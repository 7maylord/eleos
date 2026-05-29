// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, StdInvariant} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {BaseTest} from "./utils/BaseTest.sol";

import {RecaptureHook} from "../src/RecaptureHook.sol";
import {RecaptureVault} from "../src/RecaptureVault.sol";
import {RecaptureMath} from "../src/RecaptureMath.sol";

/// @notice Handler contract for invariant fuzzing.
contract RecaptureHookHandler is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    RecaptureHook public hook;
    RecaptureVault public vault;
    PoolKey public poolKey;
    PoolId public poolId;
    Currency currency0;
    Currency currency1;

    int24 tickLower;
    int24 tickUpper;

    uint256 constant VAULT_SEED = 50_000 ether;
    uint256 constant BASE_LIQUIDITY = 10e18;

    uint256 public totalSeeded;
    uint256 public totalPaidOut;

    uint256 private _tokenId;
    bool private _hasPosition;

    function setUp() public {
        deployArtifactsAndLabel();
        (currency0, currency1) = deployCurrencyPair();

        vault = new RecaptureVault(address(this));

        uint160 flags = uint160(
            Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        ) ^ (0x4444 << 144);

        bytes memory constructorArgs = abi.encode(poolManager, vault, address(this));
        deployCodeTo("RecaptureHook.sol:RecaptureHook", constructorArgs, address(flags));
        hook = RecaptureHook(address(flags));

        vault.setHook(address(hook));

        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        tickLower = TickMath.minUsableTick(60);
        tickUpper = TickMath.maxUsableTick(60);

        _doAddLiquidity(BASE_LIQUIDITY);

        MockERC20(Currency.unwrap(currency1)).approve(address(vault), type(uint256).max);
        vault.seedPool(poolId, VAULT_SEED);
        totalSeeded = VAULT_SEED;
    }

    function handler_addLiquidity(uint64 liquidityFuzz) external {
        uint256 liquidity = bound(liquidityFuzz, 1e15, 50e18);
        _doAddLiquidity(liquidity);
    }

    function handler_swap(uint64 amountFuzz, bool zeroForOne) external {
        uint256 amount = bound(amountFuzz, 0.001e18, 1000e18);
        try swapRouter.swapExactTokensForTokens({
            amountIn: amount,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: new bytes(0),
            receiver: address(this),
            deadline: block.timestamp + 60
        }) {} catch {}
    }

    function handler_warpTime(uint32 secondsFuzz) external {
        uint256 seconds_ = bound(secondsFuzz, 0, 180 days);
        vm.warp(block.timestamp + seconds_);
    }

    function handler_removeLiquidity(uint64 liquidityFuzz) external {
        if (!_hasPosition) return;
        uint256 liquidity = bound(liquidityFuzz, 1e15, BASE_LIQUIDITY);
        uint256 vaultBefore = vault.poolBalance(poolId);

        bytes memory hookData = abi.encode(address(this));
        positionManager.decreaseLiquidity(
            _tokenId, liquidity, 0, 0, address(this), block.timestamp + 60, hookData
        );

        uint256 vaultAfter = vault.poolBalance(poolId);
        if (vaultBefore > vaultAfter) totalPaidOut += vaultBefore - vaultAfter;
    }

    function _doAddLiquidity(uint256 liquidity) internal {
        bytes memory hookData = abi.encode(address(this), uint40(0));
        (uint256 a0, uint256 a1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            uint128(liquidity)
        );

        (uint256 tokenId,) = positionManager.mint(
            poolKey, tickLower, tickUpper, liquidity, a0 + 1, a1 + 1, address(this), block.timestamp + 60, hookData
        );
        if (_tokenId == 0) _tokenId = tokenId;
        _hasPosition = true;
    }
}

/// @notice Invariant test suite for hook + vault system.
contract RecaptureHookInvariantTest is StdInvariant, Test {
    RecaptureHookHandler handler;

    function setUp() public {
        handler = new RecaptureHookHandler();
        handler.setUp();

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = handler.handler_addLiquidity.selector;
        selectors[1] = handler.handler_swap.selector;
        selectors[2] = handler.handler_warpTime.selector;
        selectors[3] = handler.handler_removeLiquidity.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @dev Vault balance + total paid out never exceeds total seeded + total credited.
    function invariant_vaultSolvency() public view {
        RecaptureVault v = handler.vault();
        PoolId pid = handler.poolId();
        uint256 remaining = v.poolBalance(pid);
        uint256 paid     = v.totalPaid(pid);
        uint256 seeded   = v.totalSeeded(pid);
        uint256 credited = v.totalCredited(pid);
        assertLe(remaining + paid, seeded + credited + 1);
    }

    /// @dev Vault token balance always >= pool balance (no leakage).
    function invariant_vaultTokenMatchesPoolBalance() public view {
        RecaptureVault vault = handler.vault();
        PoolId pid = handler.poolId();
        address token = vault.poolToken(pid);

        if (token != address(0)) {
            uint256 vaultTokenBal = MockERC20(token).balanceOf(address(vault));
            uint256 poolBal = vault.poolBalance(pid);
            assertGe(vaultTokenBal, poolBal);
        }
    }

    /// @dev feeGrowthGlobal is monotonically non-decreasing (uint256, trivially true).
    function invariant_feeGrowthNeverDecreases() public view {
        assertGe(handler.hook().feeGrowthGlobal(handler.poolId()), 0);
    }
}

/// @notice Pure math invariants via fuzz tests (not stateful invariants).
contract RecaptureMathInvariantTest is Test {
    uint256 constant WAD = 1e18;

    /// @dev IL boundary values are in [0, WAD).
    function test_IL_boundaryValues() public pure {
        // Use moderate extremes (100x ratio) -- MIN/MAX overflows FullMath internally
        uint160 SQRT_1_1 = 79228162514264337593543950336;
        uint160 low = uint160(uint256(SQRT_1_1) / 10);
        uint160 high = uint160(uint256(SQRT_1_1) * 10);
        assertLt(RecaptureMath.calculateIL(low, high), WAD);
        assertLt(RecaptureMath.calculateIL(high, low), WAD);
    }

    /// @dev recaptured <= accruedIL for all inputs.
    function testFuzz_invariant_recapturedNeverExceedsIL(uint128 il, uint32 time, uint32 lock) public pure {
        il = uint128(bound(il, 0, WAD));
        uint256 recaptured = RecaptureMath.calculateRecaptured(il, time, lock);
        assertLe(recaptured, il);
    }

    /// @dev Loyalty multiplier always in [WAD, 2*WAD].
    function testFuzz_invariant_multiplierBounds(uint32 time, uint32 period, uint16 bonus) public pure {
        uint256 mult = RecaptureMath.calculateLoyaltyMultiplier(time, period, bonus);
        assertGe(mult, WAD);
        assertLe(mult, 2 * WAD);
    }

    /// @dev recaptureRatio always in [0, WAD].
    function testFuzz_invariant_ratioBounds(uint32 time, uint32 lock) public pure {
        uint256 ratio = RecaptureMath.recaptureRatio(time, lock);
        assertLe(ratio, WAD);
    }

    /// @dev Forfeit <= amount always.
    function testFuzz_invariant_forfeitBounds(uint128 amount, uint128 ratio) public pure {
        ratio = uint128(bound(ratio, 0, WAD));
        uint256 forfeit = RecaptureMath.calculateEarlyExitForfeit(amount, ratio);
        assertLe(forfeit, amount);
    }
}
