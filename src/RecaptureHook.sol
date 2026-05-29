// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

import {RecaptureMath} from "./RecaptureMath.sol";
import {RecaptureVault} from "./RecaptureVault.sol";

/// @title RecaptureHook
/// @notice Uniswap v4 hook that recaptures Impermanent Loss over time for patient LPs.
///
/// Core idea: "IL is not lost — it is only deferred."
///
/// How it works:
///   1. On addLiquidity:  snapshot entry price and timestamp for each position.
///   2. On swap:          physically divert feeDiversionBps of LP fee to vault (Phase 2).
///                        Update feeGrowthGlobal and forfeitGrowthGlobal per unit liquidity.
///   3. On removeLiquidity:
///        a. Compute current IL from entry vs current sqrtPrice.
///        b. Apply linear recapture curve based on time held.
///        c. Apply loyalty multiplier (longer holds earn up to 2x recapture).
///        d. Add proportional share of accumulated forfeits (forfeitGrowthGlobal delta).
///        e. Pay recaptured IL from the vault.
///        f. Record early-exit forfeit if lock not satisfied.
///   4. claimRecapture:   LP claims recapture without removing liquidity (after lock expires).
///
/// hookData encoding:
///   addLiquidity:    abi.encode(address owner, uint40 lockDuration)
///   removeLiquidity: abi.encode(address owner)
///   If hookData is empty or malformed, sender is used as owner and lockDuration defaults to 0.
contract RecaptureHook is BaseHook, Ownable, Pausable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;

    // ─── Data Structures ───────────────────────────────────────────────────────

    struct PositionInfo {
        address owner;
        uint160 entrySqrtPriceX96;
        uint40 entryTimestamp;
        uint128 liquidityAdded;
        uint40 lockDuration;
        uint256 feeGrowthSnapshot;  // snapshot of feeGrowthGlobal[poolId] at entry
        uint256 depositValue;       // token1 value proxy at entry (or token0 for out-of-range)
    }

    // ─── State ─────────────────────────────────────────────────────────────────

    RecaptureVault public immutable vault;

    /// @notice positionId → position data. positionId = keccak256(poolId, owner, tickLower, tickUpper).
    mapping(bytes32 => PositionInfo) public positions;

    /// @notice positionId → pool it belongs to (for forfeit growth lookup in previewRecapture).
    mapping(bytes32 => PoolId) public positionPool;

    /// @notice Cumulative diverted fee per unit of active liquidity (WAD-scaled).
    ///         Phase 2: updated with real token movement. Phase 1: virtual only.
    mapping(PoolId => uint256) public feeGrowthGlobal;

    /// @notice Cumulative forfeit per unit of active liquidity (WAD-scaled).
    ///         When an LP exits early, their forfeited portion is redistributed here.
    mapping(PoolId => uint256) public forfeitGrowthGlobal;

    /// @notice Per-position snapshot of forfeitGrowthGlobal at entry (kept separate to
    ///         avoid expanding the PositionInfo tuple and breaking existing callers).
    mapping(bytes32 => uint256) public forfeitGrowthSnapshot;

    /// @notice Fee diversion rate in basis points per pool (default: 2000 = 20% of LP fee).
    mapping(PoolId => uint24) public feeDiversionBps;

    /// @notice Whether a pool has been registered (first addLiquidity).
    mapping(PoolId => bool) public poolRegistered;

    /// Default fee diversion applied to new pools.
    uint24 public defaultFeeDiversionBps = 2000;

    /// Loyalty params: after basePeriod seconds, the multiplier reaches its max.
    uint256 public loyaltyBasePeriod = 30 days;
    uint256 public loyaltyBonusBps = 10000; // 100% bonus → 2x multiplier at basePeriod

    // ─── Events ────────────────────────────────────────────────────────────────

    event PositionRegistered(
        bytes32 indexed positionId,
        address indexed owner,
        PoolId indexed poolId,
        uint160 entrySqrtPrice,
        uint40 lockDuration
    );

    event PositionUpdated(bytes32 indexed positionId, uint160 newEntrySqrtPrice, uint128 newLiquidity);

    event SwapFeeDiverted(PoolId indexed poolId, uint256 amount, uint256 newFeeGrowth);

    event RecaptureSettled(
        bytes32 indexed positionId,
        address indexed owner,
        uint256 ilPct,
        uint256 recaptureRatio,
        uint256 loyaltyMult,
        uint256 recapturedTokens,
        uint256 forfeitedTokens
    );

    event ForfeitRedistributed(PoolId indexed poolId, uint256 amount, uint256 newForfeitGrowth);

    event RecaptureClaimed(bytes32 indexed positionId, address indexed owner, uint256 recapturedTokens);

    // ─── Errors ────────────────────────────────────────────────────────────────

    error PositionNotFound();
    error InvalidHookData();
    error CallerNotOwner();
    error LockNotExpired();

    // ─── Constructor ───────────────────────────────────────────────────────────

    constructor(IPoolManager _poolManager, RecaptureVault _vault, address _owner)
        BaseHook(_poolManager)
        Ownable(_owner)
    {
        vault = _vault;
    }

    // ─── Hook Permissions ──────────────────────────────────────────────────────

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,       // snapshot entry price + register position
            beforeRemoveLiquidity: true,   // settle recapture before tokens leave
            afterRemoveLiquidity: false,
            beforeSwap: true,              // read fee params for diversion accounting
            afterSwap: true,               // update feeGrowthGlobal + real fee diversion
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,    // physically divert fees to vault
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ─── afterAddLiquidity ─────────────────────────────────────────────────────

    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata hookData
    ) internal override whenNotPaused returns (bytes4, BalanceDelta) {
        (address owner, uint40 lockDuration) = _decodeAddHookData(hookData, sender);

        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

        if (!poolRegistered[poolId]) {
            poolRegistered[poolId] = true;
            feeDiversionBps[poolId] = defaultFeeDiversionBps;
            vault.registerPool(poolId, Currency.unwrap(key.currency1));
        }

        bytes32 posId = _positionId(poolId, owner, params.tickLower, params.tickUpper);
        PositionInfo storage pos = positions[posId];

        uint256 dep1 = delta.amount1() < 0 ? uint256(-int256(delta.amount1())) : 0;
        uint256 dep0 = delta.amount0() < 0 ? uint256(-int256(delta.amount0())) : 0;
        uint256 depositValue = dep1 > 0 ? dep1 : dep0;

        if (pos.entryTimestamp == 0) {
            positions[posId] = PositionInfo({
                owner: owner,
                entrySqrtPriceX96: sqrtPriceX96,
                entryTimestamp: uint40(block.timestamp),
                liquidityAdded: uint128(uint256(params.liquidityDelta)),
                lockDuration: lockDuration,
                feeGrowthSnapshot: feeGrowthGlobal[poolId],
                depositValue: depositValue
            });
            positionPool[posId] = poolId;
            forfeitGrowthSnapshot[posId] = forfeitGrowthGlobal[poolId];
            emit PositionRegistered(posId, owner, poolId, sqrtPriceX96, lockDuration);
        } else {
            uint256 prevLiq = pos.liquidityAdded;
            uint256 newLiq = uint256(params.liquidityDelta);
            uint256 totalLiq = prevLiq + newLiq;
            uint160 avgSqrt = uint160(
                FullMath.mulDiv(pos.entrySqrtPriceX96, prevLiq, totalLiq)
                    + FullMath.mulDiv(sqrtPriceX96, newLiq, totalLiq)
            );
            pos.entrySqrtPriceX96 = avgSqrt;
            require(totalLiq <= type(uint128).max, "liquidity overflow"); // L-3
            pos.liquidityAdded = uint128(totalLiq);
            pos.depositValue += depositValue;
            // M-2: feeGrowthSnapshot intentionally NOT reset on re-deposit.
            emit PositionUpdated(posId, avgSqrt, uint128(totalLiq));
        }

        return (BaseHook.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    // ─── beforeSwap ────────────────────────────────────────────────────────────

    function _beforeSwap(
        address,
        PoolKey calldata,
        SwapParams calldata,
        bytes calldata
    ) internal view override whenNotPaused returns (bytes4, BeforeSwapDelta, uint24) {
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    // ─── afterSwap ─────────────────────────────────────────────────────────────

    /// @dev Phase 2: physically diverts a fraction of swap fees to the vault.
    ///      feeGrowthGlobal is updated for ALL swaps (virtual accounting for LP attribution).
    ///      Physical token diversion only applies when the unspecified currency is currency1
    ///      (zeroForOne+exactInput or oneForZero+exactOutput), so the vault token is available.
    ///      The swapper receives slightly less currency1; LP fees are unchanged.
    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta swapDelta,
        bytes calldata
    ) internal override whenNotPaused returns (bytes4, int128) {
        PoolId poolId = key.toId();
        if (!poolRegistered[poolId]) return (BaseHook.afterSwap.selector, 0);

        uint24 divBps = feeDiversionBps[poolId];
        if (divBps == 0) return (BaseHook.afterSwap.selector, 0);

        // ── Update feeGrowthGlobal for all swap directions (virtual tracking) ──
        uint256 swapAmount = params.amountSpecified < 0
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);
        uint256 virtualDiverted = FullMath.mulDiv(
            FullMath.mulDiv(swapAmount, key.fee, 1_000_000), divBps, 10_000
        );
        if (virtualDiverted > 0) {
            uint128 activeLiquidity = poolManager.getLiquidity(poolId);
            if (activeLiquidity > 0) {
                feeGrowthGlobal[poolId] += FullMath.mulDiv(virtualDiverted, RecaptureMath.WAD, activeLiquidity);
            }
        }

        // ── Physical diversion: only when unspecified currency is currency1 ──
        // Condition: zeroForOne == exactInput.
        // (zeroForOne+exactInput: unspecified=currency1; oneForZero+exactOutput: also unspecified=currency1)
        bool zeroForOne = params.zeroForOne;
        bool exactInput = params.amountSpecified < 0;
        if (zeroForOne != exactInput) {
            if (virtualDiverted > 0) emit SwapFeeDiverted(poolId, 0, feeGrowthGlobal[poolId]);
            return (BaseHook.afterSwap.selector, 0);
        }

        // amount1 is positive when the pool owes the swapper currency1 (their output).
        int256 amount1 = swapDelta.amount1();
        if (amount1 <= 0) return (BaseHook.afterSwap.selector, 0);

        uint256 outputAmount = uint256(amount1);
        uint256 estimatedFee = FullMath.mulDiv(outputAmount, key.fee, 1_000_000);
        uint256 diverted = FullMath.mulDiv(estimatedFee, divBps, 10_000);

        if (diverted == 0) return (BaseHook.afterSwap.selector, 0);

        emit SwapFeeDiverted(poolId, diverted, feeGrowthGlobal[poolId]);

        // Physically move diverted tokens: pool → vault (within unlock context).
        // take() gives hook a -diverted delta; returning +diverted as hookDelta credits
        // the hook +diverted, netting to zero. The caller (swapper) receives output - diverted.
        poolManager.take(key.currency1, address(vault), diverted);
        vault.credit(poolId, diverted);

        return (BaseHook.afterSwap.selector, int128(uint128(diverted)));
    }

    // ─── beforeRemoveLiquidity ─────────────────────────────────────────────────

    function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override nonReentrant whenNotPaused returns (bytes4) {
        address owner = _decodeOwner(hookData, sender);
        PoolId poolId = key.toId();
        bytes32 posId = _positionId(poolId, owner, params.tickLower, params.tickUpper);

        PositionInfo memory pos = positions[posId];
        if (pos.entryTimestamp == 0) {
            return BaseHook.beforeRemoveLiquidity.selector;
        }

        if (pos.owner != owner) revert CallerNotOwner();

        (uint160 currentSqrtPrice,,,) = poolManager.getSlot0(poolId);

        (uint256 recapturedTokens, uint256 forfeitedTokens, uint256 ilPct, uint256 ratio, uint256 loyaltyMult) =
            _computeRecapture(posId, pos, currentSqrtPrice);

        if (recapturedTokens > 0) {
            try vault.payRecapture(poolId, posId, pos.owner, recapturedTokens) {} catch {}
        }
        if (forfeitedTokens > 0) {
            _updateForfeitGrowth(poolId, forfeitedTokens);
            try vault.recordForfeit(poolId, posId, forfeitedTokens) {} catch {}
        }

        uint128 liquidityRemoved = uint128(uint256(-params.liquidityDelta));
        if (liquidityRemoved >= pos.liquidityAdded) {
            delete positions[posId];
            positionPool[posId] = PoolId.wrap(bytes32(0));
            delete forfeitGrowthSnapshot[posId];
        } else {
            // L-1: preserve entryTimestamp so lock progress survives partial exits.
            positions[posId].liquidityAdded -= liquidityRemoved;
            positions[posId].depositValue = FullMath.mulDiv(
                pos.depositValue, pos.liquidityAdded - liquidityRemoved, pos.liquidityAdded
            );
            positions[posId].entrySqrtPriceX96 = currentSqrtPrice;
            positions[posId].feeGrowthSnapshot = feeGrowthGlobal[poolId];
            forfeitGrowthSnapshot[posId] = forfeitGrowthGlobal[poolId];
        }

        emit RecaptureSettled(posId, owner, ilPct, ratio, loyaltyMult, recapturedTokens, forfeitedTokens);

        return BaseHook.beforeRemoveLiquidity.selector;
    }

    // ─── claimRecapture (Feature 5) ────────────────────────────────────────────

    /// @notice Claim accrued IL recapture without removing liquidity.
    ///         Resets the position's price and time snapshot so the LP starts fresh.
    ///         Can be called at any time — early claims apply the same time-based
    ///         recapture ratio and loyalty multiplier as removal would.
    function claimRecapture(PoolKey calldata key, int24 tickLower, int24 tickUpper)
        external
        nonReentrant
        whenNotPaused
    {
        PoolId poolId = key.toId();
        bytes32 posId = _positionId(poolId, msg.sender, tickLower, tickUpper);

        PositionInfo memory pos = positions[posId];
        if (pos.entryTimestamp == 0) revert PositionNotFound();
        if (pos.owner != msg.sender) revert CallerNotOwner();

        (uint160 currentSqrtPrice,,,) = poolManager.getSlot0(poolId);

        (uint256 recapturedTokens, uint256 forfeitedTokens, uint256 ilPct, uint256 ratio, uint256 loyaltyMult) =
            _computeRecapture(posId, pos, currentSqrtPrice);

        if (recapturedTokens > 0) {
            try vault.payRecapture(poolId, posId, pos.owner, recapturedTokens) {} catch {}
        }
        if (forfeitedTokens > 0) {
            _updateForfeitGrowth(poolId, forfeitedTokens);
            try vault.recordForfeit(poolId, posId, forfeitedTokens) {} catch {}
        }

        // Reset clock and price snapshot; keep liquidity and lockDuration intact.
        positions[posId].entrySqrtPriceX96 = currentSqrtPrice;
        positions[posId].entryTimestamp = uint40(block.timestamp);
        positions[posId].feeGrowthSnapshot = feeGrowthGlobal[poolId];
        forfeitGrowthSnapshot[posId] = forfeitGrowthGlobal[poolId];

        emit RecaptureSettled(posId, msg.sender, ilPct, ratio, loyaltyMult, recapturedTokens, forfeitedTokens);
        emit RecaptureClaimed(posId, msg.sender, recapturedTokens);
    }

    // ─── Admin ─────────────────────────────────────────────────────────────────

    function setDefaultFeeDiversionBps(uint24 bps) external onlyOwner {
        require(bps <= 5000, "max 50%");
        defaultFeeDiversionBps = bps;
    }

    function setPoolFeeDiversionBps(PoolId poolId, uint24 bps) external onlyOwner {
        require(bps <= 5000, "max 50%");
        feeDiversionBps[poolId] = bps;
    }

    function setLoyaltyParams(uint256 basePeriod, uint256 bonusBps) external onlyOwner {
        loyaltyBasePeriod = basePeriod;
        loyaltyBonusBps = bonusBps;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ─── View Helpers ──────────────────────────────────────────────────────────

    /// @notice Preview recapture for a position without removing liquidity.
    function previewRecapture(bytes32 posId, uint160 currentSqrtPrice)
        external
        view
        returns (
            uint256 ilPct,
            uint256 ratio,
            uint256 loyaltyMult,
            uint256 recapturedTokens,
            uint256 forfeitedTokens
        )
    {
        PositionInfo memory pos = positions[posId];
        if (pos.entryTimestamp == 0) return (0, 0, 0, 0, 0);
        (recapturedTokens, forfeitedTokens, ilPct, ratio, loyaltyMult) =
            _computeRecapture(posId, pos, currentSqrtPrice);
    }

    /// @notice Compute the canonical positionId used for tracking.
    function positionId(PoolId poolId, address owner, int24 tickLower, int24 tickUpper)
        external
        pure
        returns (bytes32)
    {
        return _positionId(poolId, owner, tickLower, tickUpper);
    }

    // ─── Internal Helpers ──────────────────────────────────────────────────────

    /// @dev Core recapture math. Includes forfeit-growth share earned by this position.
    function _computeRecapture(bytes32 posId, PositionInfo memory pos, uint160 currentSqrtPrice)
        internal
        view
        returns (
            uint256 recapturedTokens,
            uint256 forfeitedTokens,
            uint256 ilPct,
            uint256 ratio,
            uint256 loyaltyMult
        )
    {
        uint256 timeHeld = block.timestamp - pos.entryTimestamp;
        ilPct = RecaptureMath.calculateIL(pos.entrySqrtPriceX96, currentSqrtPrice);
        ratio = RecaptureMath.recaptureRatio(timeHeld, pos.lockDuration);
        loyaltyMult = RecaptureMath.calculateLoyaltyMultiplier(timeHeld, loyaltyBasePeriod, loyaltyBonusBps);

        uint256 ilInTokens = FullMath.mulDiv(ilPct, pos.depositValue, RecaptureMath.WAD);
        recapturedTokens = FullMath.mulDiv(
            FullMath.mulDiv(ilInTokens, ratio, RecaptureMath.WAD), loyaltyMult, RecaptureMath.WAD
        );
        forfeitedTokens = recapturedTokens < ilInTokens ? ilInTokens - recapturedTokens : 0;

        // Add this LP's proportional share of accumulated pool forfeits (Feature 3).
        PoolId poolId = positionPool[posId];
        uint256 fgGlobal = forfeitGrowthGlobal[poolId];
        uint256 fgSnapshot = forfeitGrowthSnapshot[posId];
        if (fgGlobal > fgSnapshot) {
            uint256 forfeitShare = FullMath.mulDiv(
                fgGlobal - fgSnapshot, pos.liquidityAdded, RecaptureMath.WAD
            );
            recapturedTokens += forfeitShare;
        }
    }

    function _updateForfeitGrowth(PoolId poolId, uint256 forfeitedTokens) internal {
        uint128 activeLiq = poolManager.getLiquidity(poolId);
        if (activeLiq > 0) {
            uint256 growth = FullMath.mulDiv(forfeitedTokens, RecaptureMath.WAD, activeLiq);
            forfeitGrowthGlobal[poolId] += growth;
            emit ForfeitRedistributed(poolId, forfeitedTokens, forfeitGrowthGlobal[poolId]);
        }
    }

    function _positionId(PoolId poolId, address owner, int24 tickLower, int24 tickUpper)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(poolId, owner, tickLower, tickUpper));
    }

    function _decodeAddHookData(bytes calldata hookData, address fallbackOwner)
        internal
        pure
        returns (address owner, uint40 lockDuration)
    {
        if (hookData.length >= 64) {
            (owner, lockDuration) = abi.decode(hookData, (address, uint40));
        } else if (hookData.length >= 32) {
            owner = abi.decode(hookData, (address));
            lockDuration = 0;
        } else {
            owner = fallbackOwner;
            lockDuration = 0;
        }
    }

    function _decodeOwner(bytes calldata hookData, address fallbackOwner)
        internal
        pure
        returns (address owner)
    {
        if (hookData.length >= 32) {
            owner = abi.decode(hookData, (address));
        } else {
            owner = fallbackOwner;
        }
    }
}
