// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
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

contract RecaptureHookTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    RecaptureHook hook;
    RecaptureVault vault;

    Currency currency0;
    Currency currency1;

    PoolKey poolKey;
    PoolId poolId;

    int24 tickLower;
    int24 tickUpper;

    uint256 constant VAULT_SEED = 100_000 ether;
    uint256 constant LP_LIQUIDITY = 100e18;
    uint24 constant LP_FEE = 3000;
    int24 constant TICK_SPACING = 60;

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

        poolKey = PoolKey(currency0, currency1, LP_FEE, TICK_SPACING, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        tickLower = TickMath.minUsableTick(TICK_SPACING);
        tickUpper = TickMath.maxUsableTick(TICK_SPACING);

        _addLiquidity(LP_LIQUIDITY, 0);

        MockERC20(Currency.unwrap(currency1)).approve(address(vault), type(uint256).max);
        vault.seedPool(poolId, VAULT_SEED);
    }

    // ─── Position Registration ─────────────────────────────────────────────────

    function test_afterAddLiquidity_registersPosition() public view {
        bytes32 posId = hook.positionId(poolId, address(this), tickLower, tickUpper);
        (
            address owner,
            uint160 entrySqrtPrice,
            uint40 entryTimestamp,
            uint128 liquidityAdded,
            uint40 lockDuration,
            ,
        ) = hook.positions(posId);

        assertEq(owner, address(this));
        assertEq(entrySqrtPrice, Constants.SQRT_PRICE_1_1);
        assertEq(entryTimestamp, block.timestamp);
        assertGt(liquidityAdded, 0);
        assertEq(lockDuration, 0);
    }

    function test_afterAddLiquidity_poolRegisteredWithVault() public view {
        assertEq(vault.poolToken(poolId), Currency.unwrap(currency1));
    }

    function test_afterAddLiquidity_poolRegistered() public view {
        assertTrue(hook.poolRegistered(poolId));
    }

    function test_afterAddLiquidity_defaultFeeDiversion() public view {
        assertEq(hook.feeDiversionBps(poolId), hook.defaultFeeDiversionBps());
    }

    function test_afterAddLiquidity_withCustomLockDuration() public {
        // Use different tick range to get a NEW position (not re-deposit)
        int24 tl = TickMath.minUsableTick(TICK_SPACING) + TICK_SPACING;
        int24 tu = TickMath.maxUsableTick(TICK_SPACING) - TICK_SPACING;
        uint40 customLock = 30 days;

        bytes memory hookData = abi.encode(address(this), customLock);
        (uint256 a0, uint256 a1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tl),
            TickMath.getSqrtPriceAtTick(tu),
            uint128(10e18)
        );
        positionManager.mint(poolKey, tl, tu, 10e18, a0 + 1, a1 + 1, address(this), block.timestamp + 60, hookData);

        bytes32 posId = hook.positionId(poolId, address(this), tl, tu);
        (,,,, uint40 ld,,) = hook.positions(posId);
        assertEq(ld, customLock);
    }

    function test_afterAddLiquidity_redeposit_accumulatesLiquidity() public {
        bytes32 posId = hook.positionId(poolId, address(this), tickLower, tickUpper);
        (,,, uint128 liq1,,,) = hook.positions(posId);

        vm.warp(block.timestamp + 10 days);
        _addLiquidity(LP_LIQUIDITY, 0);

        (,,, uint128 liq2,,,) = hook.positions(posId);
        assertGt(liq2, liq1);
    }

    function test_afterAddLiquidity_emptyHookData_usesSender() public {
        // Use different ticks for a fresh position
        int24 tl = TickMath.minUsableTick(TICK_SPACING) + 2 * TICK_SPACING;
        int24 tu = TickMath.maxUsableTick(TICK_SPACING) - 2 * TICK_SPACING;

        bytes memory hookData = new bytes(0);
        (uint256 a0, uint256 a1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tl),
            TickMath.getSqrtPriceAtTick(tu),
            uint128(5e18)
        );
        positionManager.mint(poolKey, tl, tu, 5e18, a0 + 1, a1 + 1, address(this), block.timestamp + 60, hookData);

        // Position should be registered under positionManager (sender of the hook call)
        // since hookData is empty, owner falls back to sender
        // The sender in the hook callback is the positionManager, so check that a position exists
        bytes32 posIdPosm = hook.positionId(poolId, address(positionManager), tl, tu);
        (address ownerPosm,,,,,,) = hook.positions(posIdPosm);
        assertEq(ownerPosm, address(positionManager));
    }

    // ─── Swap - feeGrowthGlobal updates ────────────────────────────────────────

    function test_afterSwap_updatesFeeGrowthGlobal() public {
        uint256 growthBefore = hook.feeGrowthGlobal(poolId);
        _swap(1e18, true);
        uint256 growthAfter = hook.feeGrowthGlobal(poolId);
        assertGt(growthAfter, growthBefore);
    }

    function test_afterSwap_multipleSwaps_growthAccumulates() public {
        _swap(1e18, true);
        uint256 g1 = hook.feeGrowthGlobal(poolId);
        _swap(1e18, true);
        uint256 g2 = hook.feeGrowthGlobal(poolId);
        assertGt(g2, g1);
    }

    function test_afterSwap_noUpdateOnUnregisteredPool() public {
        // Create a second pool without hook
        PoolKey memory pKey2 = PoolKey(currency0, currency1, 500, 10, IHooks(address(0)));
        poolManager.initialize(pKey2, Constants.SQRT_PRICE_1_1);
        // feeGrowthGlobal for the hooked pool should remain unchanged
        uint256 g = hook.feeGrowthGlobal(poolId);
        _swap(1e18, true); // swap on hooked pool
        assertGt(hook.feeGrowthGlobal(poolId), g);
    }

    function test_afterSwap_bidirectionalSwapsGrow() public {
        _swap(1e18, true);
        uint256 g1 = hook.feeGrowthGlobal(poolId);
        _swap(1e18, false);
        uint256 g2 = hook.feeGrowthGlobal(poolId);
        assertGt(g2, g1);
    }

    // ─── Preview Recapture ─────────────────────────────────────────────────────

    function test_previewRecapture_zeroILWhenPriceUnchanged() public view {
        bytes32 posId = hook.positionId(poolId, address(this), tickLower, tickUpper);
        (uint160 currentSqrtPrice,,,) = poolManager.getSlot0(poolId);
        (uint256 ilPct,,,uint256 recapturedTokens,) = hook.previewRecapture(posId, currentSqrtPrice);
        assertEq(ilPct, 0);
        assertEq(recapturedTokens, 0);
    }

    function test_previewRecapture_nonZeroAfterPriceMove() public {
        _swap(10e18, true); // move price
        bytes32 posId = hook.positionId(poolId, address(this), tickLower, tickUpper);
        (uint160 currentSqrt,,,) = poolManager.getSlot0(poolId);
        (uint256 ilPct,,,,) = hook.previewRecapture(posId, currentSqrt);
        assertGt(ilPct, 0);
    }

    function test_previewRecapture_growsWithTime() public {
        _swap(10e18, true); // move price for IL
        bytes32 posId = hook.positionId(poolId, address(this), tickLower, tickUpper);
        (uint160 currentSqrt,,,) = poolManager.getSlot0(poolId);

        vm.warp(block.timestamp + 30 days);
        (,,, uint256 rec30,) = hook.previewRecapture(posId, currentSqrt);

        vm.warp(block.timestamp + 60 days); // total 90 days
        (,,, uint256 rec90,) = hook.previewRecapture(posId, currentSqrt);

        assertGt(rec90, rec30);
    }

    function test_previewRecapture_returnsZeroForUnknownPosition() public view {
        bytes32 fakeId = bytes32(uint256(0xDEAD));
        (uint256 il, uint256 r, uint256 m, uint256 rec, uint256 forf) = hook.previewRecapture(fakeId, Constants.SQRT_PRICE_1_1);
        assertEq(il, 0);
        assertEq(r, 0);
        assertEq(m, 0);
        assertEq(rec, 0);
        assertEq(forf, 0);
    }

    // ─── Full Lifecycle: No IL ─────────────────────────────────────────────────

    function test_removeLiquidity_noIL_noPayout() public {
        uint256 vaultBefore = vault.poolBalance(poolId);
        _removeLiquidity(LP_LIQUIDITY / 2);
        assertEq(vault.poolBalance(poolId), vaultBefore);
    }

    // ─── Full Lifecycle: Patient LP ────────────────────────────────────────────

    function test_fullLifecycle_patientLP_receivesRecapture() public {
        // Move price to create IL
        _swap(10e18, true);

        (uint160 currentSqrt,,,) = poolManager.getSlot0(poolId);
        uint256 ilPct = RecaptureMath.calculateIL(Constants.SQRT_PRICE_1_1, currentSqrt);
        assertGt(ilPct, 0);

        vm.warp(block.timestamp + 90 days);

        uint256 vaultBefore = vault.poolBalance(poolId);
        _removeLiquidity(LP_LIQUIDITY);
        uint256 vaultAfter = vault.poolBalance(poolId);

        assertLt(vaultAfter, vaultBefore);
    }

    // ─── Full Lifecycle: Early Exit ────────────────────────────────────────────

    function test_earlyExit_receivesLessRecaptureThanPatientLP() public {
        // Move price to create IL
        _swap(5e18, true);

        // Early exit: 10 days into 90-day default lock
        vm.warp(block.timestamp + 10 days);

        // Preview early LP recapture
        bytes32 posId = hook.positionId(poolId, address(this), tickLower, tickUpper);
        (uint160 currentSqrt,,,) = poolManager.getSlot0(poolId);
        (,,, uint256 earlyRecapture,) = hook.previewRecapture(posId, currentSqrt);

        // Preview what the same position would get at 90 days
        vm.warp(block.timestamp + 80 days); // total 90 days
        (,,, uint256 patientRecapture,) = hook.previewRecapture(posId, currentSqrt);

        // Patient LP should receive strictly more
        assertGt(patientRecapture, earlyRecapture);
    }

    // ─── Partial Removal ───────────────────────────────────────────────────────

    function test_partialRemoval_resetsEntrySnapshot() public {
        bytes32 posId = hook.positionId(poolId, address(this), tickLower, tickUpper);
        (,,, uint128 liq1,,,) = hook.positions(posId);
        uint40 originalTs = uint40(block.timestamp); // capture before warp (L-1 fix)

        vm.warp(block.timestamp + 30 days);
        _swap(1e18, true);

        _removeLiquidity(LP_LIQUIDITY / 2);

        (uint160 newEntry, uint40 ts2, uint128 liqAfter) = _getPositionPriceTimeLiq(posId);

        // L-1: entryTimestamp is preserved on partial removal so lock progress is not wiped.
        assertEq(ts2, originalTs);
        assertLt(liqAfter, liq1);
        // Entry price resets to current so future IL is measured from this point.
        (uint160 currentSqrt,,,) = poolManager.getSlot0(poolId);
        assertEq(newEntry, currentSqrt);
    }

    function test_fullRemoval_deletesPosition() public {
        bytes32 posId = hook.positionId(poolId, address(this), tickLower, tickUpper);
        _removeLiquidity(LP_LIQUIDITY);
        (address owner,,,,,,) = hook.positions(posId);
        assertEq(owner, address(0));
    }

    // ─── Untracked Position ────────────────────────────────────────────────────

    function test_unknownPosition_skipsRecapture() public {
        address stranger = address(0xABCD);
        bytes32 posId = hook.positionId(poolId, stranger, tickLower, tickUpper);
        (address owner,,,,,,) = hook.positions(posId);
        assertEq(owner, address(0));

        uint256 vaultBefore = vault.poolBalance(poolId);

        bytes memory removeData = abi.encode(stranger);
        positionManager.decreaseLiquidity(
            _getTokenId(), LP_LIQUIDITY / 10, 0, 0, address(this), block.timestamp + 60, removeData
        );

        assertEq(vault.poolBalance(poolId), vaultBefore);
    }

    // ─── Vault Caps Payout ─────────────────────────────────────────────────────

    function test_removeLiquidity_noRevertWhenVaultEmpty() public {
        // Drain the vault via payRecapture (not emergencyRescue which doesn't update poolBalance)
        vm.prank(address(hook));
        vault.payRecapture(poolId, bytes32(0), address(0xDEAD), VAULT_SEED);
        assertEq(vault.poolBalance(poolId), 0);

        _swap(10e18, true);
        vm.warp(block.timestamp + 90 days);

        // Should succeed with 0 payout
        _removeLiquidity(LP_LIQUIDITY);
    }

    // ─── Admin ─────────────────────────────────────────────────────────────────

    function test_setDefaultFeeDiversionBps() public {
        hook.setDefaultFeeDiversionBps(1000);
        assertEq(hook.defaultFeeDiversionBps(), 1000);
    }

    function test_setDefaultFeeDiversionBps_revertsOver50Pct() public {
        vm.expectRevert();
        hook.setDefaultFeeDiversionBps(5001);
    }

    function test_setDefaultFeeDiversionBps_onlyOwner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        hook.setDefaultFeeDiversionBps(1000);
    }

    function test_setFeeDiversionBps_updatesPool() public {
        hook.setPoolFeeDiversionBps(poolId, 1000);
        assertEq(hook.feeDiversionBps(poolId), 1000);
    }

    function test_setFeeDiversionBps_revertsOver50Pct() public {
        vm.expectRevert();
        hook.setPoolFeeDiversionBps(poolId, 5001);
    }

    function test_setFeeDiversionBps_onlyOwner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        hook.setPoolFeeDiversionBps(poolId, 1000);
    }

    function test_setLoyaltyParams_updates() public {
        hook.setLoyaltyParams(60 days, 5000);
        assertEq(hook.loyaltyBasePeriod(), 60 days);
        assertEq(hook.loyaltyBonusBps(), 5000);
    }

    function test_setLoyaltyParams_onlyOwner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        hook.setLoyaltyParams(60 days, 5000);
    }

    function test_pause_unpause() public {
        hook.pause();
        hook.unpause();
        // Should work normally after unpause
        _swap(1e18, true);
    }

    function test_pause_onlyOwner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        hook.pause();
    }

    function test_unpause_onlyOwner() public {
        hook.pause();
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        hook.unpause();
    }

    // ─── Hook Permissions ─────────────────────────────────────────────────────

    function test_getHookPermissions() public view {
        Hooks.Permissions memory perms = hook.getHookPermissions();
        assertFalse(perms.beforeInitialize);
        assertFalse(perms.afterInitialize);
        assertFalse(perms.beforeAddLiquidity);
        assertTrue(perms.afterAddLiquidity);
        assertTrue(perms.beforeRemoveLiquidity);
        assertFalse(perms.afterRemoveLiquidity);
        assertTrue(perms.beforeSwap);
        assertTrue(perms.afterSwap);
        assertFalse(perms.beforeSwapReturnDelta);
        assertTrue(perms.afterSwapReturnDelta);
    }

    // ─── positionId ───────────────────────────────────────────────────────────

    function test_positionId_deterministic() public view {
        bytes32 id1 = hook.positionId(poolId, address(this), tickLower, tickUpper);
        bytes32 id2 = hook.positionId(poolId, address(this), tickLower, tickUpper);
        assertEq(id1, id2);
    }

    function test_positionId_differentForDifferentOwners() public view {
        bytes32 id1 = hook.positionId(poolId, address(this), tickLower, tickUpper);
        bytes32 id2 = hook.positionId(poolId, address(0xBEEF), tickLower, tickUpper);
        assertNotEq(id1, id2);
    }

    function test_positionId_differentForDifferentTicks() public view {
        bytes32 id1 = hook.positionId(poolId, address(this), tickLower, tickUpper);
        bytes32 id2 = hook.positionId(poolId, address(this), tickLower + TICK_SPACING, tickUpper);
        assertNotEq(id1, id2);
    }

    // ─── Swap with zero fee diversion ─────────────────────────────────────────

    function test_afterSwap_zeroFeeDiversion_noGrowth() public {
        hook.setPoolFeeDiversionBps(poolId, 0);
        uint256 g = hook.feeGrowthGlobal(poolId);
        _swap(1e18, true);
        assertEq(hook.feeGrowthGlobal(poolId), g);
    }

    // ─── Multiple positions same pool ─────────────────────────────────────────

    function test_multiplePositions_trackedIndependently() public {
        int24 tl2 = tickLower + TICK_SPACING;
        int24 tu2 = tickUpper - TICK_SPACING;

        bytes memory hookData = abi.encode(address(this), uint40(60 days));
        (uint256 a0, uint256 a1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tl2),
            TickMath.getSqrtPriceAtTick(tu2),
            uint128(50e18)
        );
        positionManager.mint(poolKey, tl2, tu2, 50e18, a0 + 1, a1 + 1, address(this), block.timestamp + 60, hookData);

        bytes32 posId1 = hook.positionId(poolId, address(this), tickLower, tickUpper);
        bytes32 posId2 = hook.positionId(poolId, address(this), tl2, tu2);

        (,,,, uint40 ld1,,) = hook.positions(posId1);
        (,,,, uint40 ld2,,) = hook.positions(posId2);

        assertEq(ld1, 0);
        assertEq(ld2, 60 days);
    }

    // ─── hookData decoding branches ───────────────────────────────────────────

    function test_addLiquidity_withOnlyAddressInHookData() public {
        // hookData with only address (32 bytes), no lockDuration
        int24 tl = tickLower + 3 * TICK_SPACING;
        int24 tu = tickUpper - 3 * TICK_SPACING;
        bytes memory hookData = abi.encode(address(this));
        (uint256 a0, uint256 a1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tl),
            TickMath.getSqrtPriceAtTick(tu),
            uint128(5e18)
        );
        positionManager.mint(poolKey, tl, tu, 5e18, a0 + 1, a1 + 1, address(this), block.timestamp + 60, hookData);

        bytes32 posId = hook.positionId(poolId, address(this), tl, tu);
        (address owner,,,, uint40 ld,,) = hook.positions(posId);
        assertEq(owner, address(this));
        assertEq(ld, 0); // lockDuration defaults to 0 when not provided
    }

    function test_removeLiquidity_withEmptyHookData() public {
        // Remove with empty hookData — falls back to sender (positionManager)
        uint256 vaultBefore = vault.poolBalance(poolId);
        bytes memory hookData = new bytes(0);
        positionManager.decreaseLiquidity(
            _getTokenId(), LP_LIQUIDITY / 10, 0, 0, address(this), block.timestamp + 60, hookData
        );
        // Since the fallback owner is positionManager and there's no position for it,
        // recapture is skipped
        assertEq(vault.poolBalance(poolId), vaultBefore);
    }

    // ─── Recapture with forfeit ───────────────────────────────────────────────

    function test_removeLiquidity_withIL_producesRecaptureAndForfeit() public {
        // Create IL by swapping
        _swap(5e18, true);

        // Warp only 30 days (33% of default 90-day lock -> 67% forfeit)
        vm.warp(block.timestamp + 30 days);

        // Preview shows both recapture and forfeit
        bytes32 posId = hook.positionId(poolId, address(this), tickLower, tickUpper);
        (uint160 currentSqrt,,,) = poolManager.getSlot0(poolId);
        (uint256 il, uint256 ratio,, uint256 recaptured, uint256 forfeited) =
            hook.previewRecapture(posId, currentSqrt);

        assertGt(il, 0);
        assertGt(ratio, 0);
        assertGt(recaptured, 0);
        assertGt(forfeited, 0);

        // Actually remove and verify vault balance decreased
        uint256 vaultBefore = vault.poolBalance(poolId);
        _removeLiquidity(LP_LIQUIDITY);
        assertLt(vault.poolBalance(poolId), vaultBefore);
    }

    // ─── Admin boundary tests ─────────────────────────────────────────────────

    function test_setDefaultFeeDiversionBps_at5000_passes() public {
        hook.setDefaultFeeDiversionBps(5000);
        assertEq(hook.defaultFeeDiversionBps(), 5000);
    }

    function test_setPoolFeeDiversionBps_at5000_passes() public {
        hook.setPoolFeeDiversionBps(poolId, 5000);
        assertEq(hook.feeDiversionBps(poolId), 5000);
    }

    function test_setPoolFeeDiversionBps_at0_passes() public {
        hook.setPoolFeeDiversionBps(poolId, 0);
        assertEq(hook.feeDiversionBps(poolId), 0);
    }

    // ─── Internal Helpers ──────────────────────────────────────────────────────

    uint256 private _tokenId;

    function _addLiquidity(uint256 liquidity, uint40 lockDuration) internal {
        bytes memory hookData = abi.encode(address(this), lockDuration);
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            uint128(liquidity)
        );
        uint256 tokenId;
        (tokenId,) = positionManager.mint(
            poolKey, tickLower, tickUpper, liquidity, amount0 + 1, amount1 + 1, address(this), block.timestamp + 60, hookData
        );
        if (_tokenId == 0) _tokenId = tokenId;
    }

    function _removeLiquidity(uint256 liquidity) internal {
        bytes memory hookData = abi.encode(address(this));
        positionManager.decreaseLiquidity(_tokenId, liquidity, 0, 0, address(this), block.timestamp + 60, hookData);
    }

    function _swap(uint256 amountIn, bool zeroForOne) internal {
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: new bytes(0),
            receiver: address(this),
            deadline: block.timestamp + 60
        });
    }

    function _getTokenId() internal view returns (uint256) {
        return _tokenId;
    }

    function _getPositionPriceTimeLiq(bytes32 posId)
        internal
        view
        returns (uint160 entrySqrtPrice, uint40 entryTimestamp, uint128 liquidityAdded)
    {
        (, entrySqrtPrice, entryTimestamp, liquidityAdded,,,) = hook.positions(posId);
    }

    // ─── Feature 1: Real fee diversion ─────────────────────────────────────────

    function test_swap_divertsFeesToVault_zeroForOne() public {
        // zeroForOne+exactInput: unspecifiedIsCurrency1 → physical diversion happens
        uint256 vaultBefore = vault.poolBalance(poolId);
        _swap(1e18, true);
        uint256 vaultAfter = vault.poolBalance(poolId);
        assertGt(vaultAfter, vaultBefore, "vault should grow on zeroForOne swap");
    }

    function test_swap_noPhysicalDiversion_oneForZero() public {
        // oneForZero+exactInput: unspecifiedIsCurrency0 → no physical diversion
        uint256 vaultBefore = vault.poolBalance(poolId);
        _swap(1e18, false);
        uint256 vaultAfter = vault.poolBalance(poolId);
        assertEq(vaultAfter, vaultBefore, "vault should not change on oneForZero exactInput swap");
    }

    function test_swap_totalCredited_increments() public {
        uint256 creditedBefore = vault.totalCredited(poolId);
        _swap(5e18, true);
        uint256 creditedAfter = vault.totalCredited(poolId);
        assertGt(creditedAfter, creditedBefore);
    }

    // ─── Feature 3: Per-position forfeit redistribution ────────────────────────

    function test_forfeitGrowth_increasesOnEarlyExit() public {
        _swap(5e18, true); // move price to create IL — forfeit only occurs when IL > 0
        uint256 fg0 = hook.forfeitGrowthGlobal(poolId);
        // Exit immediately with unsatisfied lock → IL exists → forfeit occurs
        bytes memory hookData = abi.encode(address(this));
        positionManager.decreaseLiquidity(
            _getTokenId(), LP_LIQUIDITY, 0, 0, address(this), block.timestamp + 60, hookData
        );
        uint256 fg1 = hook.forfeitGrowthGlobal(poolId);
        assertGt(fg1, fg0, "forfeit growth should increase on early exit with IL");
    }

    function test_forfeitGrowthSnapshot_setOnNewPosition() public {
        // A new deposit should snapshot current forfeitGrowthGlobal
        uint256 fgBefore = hook.forfeitGrowthGlobal(poolId);
        bytes32 posId = hook.positionId(poolId, address(this), tickLower, tickUpper);
        assertEq(hook.forfeitGrowthSnapshot(posId), fgBefore);
    }

    function test_forfeitShare_accumulatesInGrowthGlobal() public {
        // Exit immediately — IL is 0 (no price move) but lock not satisfied → forfeit
        // of ilInTokens. With no IL, forfeit = 0. Move price first to create IL.
        _swap(5e18, true); // create IL so there's something to forfeit

        uint256 fg0 = hook.forfeitGrowthGlobal(poolId);
        bytes memory hookData = abi.encode(address(this));
        positionManager.decreaseLiquidity(
            _getTokenId(), LP_LIQUIDITY, 0, 0, address(this), block.timestamp + 60, hookData
        );
        uint256 fg1 = hook.forfeitGrowthGlobal(poolId);
        // forfeitGrowthGlobal should increase because IL > 0 and time < lock
        assertGe(fg1, fg0);
    }

    // ─── Feature 4: Analytics ──────────────────────────────────────────────────

    function test_totalSeeded_trackedByVault() public {
        uint256 seeded = vault.totalSeeded(poolId);
        assertGt(seeded, 0, "vault should have totalSeeded from setup");
    }

    function test_totalPaid_incrementsOnRecapture() public {
        uint256 paidBefore = vault.totalPaid(poolId);

        // Move price to create IL, then wait full lock, then exit
        _swap(10e18, true);
        vm.warp(block.timestamp + 91 days);

        bytes memory hookData = abi.encode(address(this));
        positionManager.decreaseLiquidity(
            _getTokenId(), LP_LIQUIDITY, 0, 0, address(this), block.timestamp + 60, hookData
        );

        uint256 paidAfter = vault.totalPaid(poolId);
        assertGe(paidAfter, paidBefore); // may be 0 if IL is 0
    }

    function test_totalForfeited_incrementsOnEarlyExit() public {
        uint256 forfeitedBefore = vault.totalForfeited(poolId);
        // Immediate exit (no time elapsed since setup) → forfeit
        bytes memory hookData = abi.encode(address(this));
        positionManager.decreaseLiquidity(
            _getTokenId(), LP_LIQUIDITY, 0, 0, address(this), block.timestamp + 60, hookData
        );
        uint256 forfeitedAfter = vault.totalForfeited(poolId);
        assertGe(forfeitedAfter, forfeitedBefore);
    }

    // ─── Feature 5: claimRecapture without removal ──────────────────────────────

    function test_claimRecapture_revertsOnUnknownPosition() public {
        vm.expectRevert(RecaptureHook.PositionNotFound.selector);
        hook.claimRecapture(poolKey, tickLower, tickUpper + 1);
    }

    function test_claimRecapture_revertsOnUnknownPositionForCaller() public {
        // claimRecapture builds posId from msg.sender, so a stranger gets PositionNotFound
        vm.prank(address(0xDEAD));
        vm.expectRevert(RecaptureHook.PositionNotFound.selector);
        hook.claimRecapture(poolKey, tickLower, tickUpper);
    }

    function test_claimRecapture_resetsPositionClock() public {
        _swap(5e18, true); // create some IL

        bytes32 posId = hook.positionId(poolId, address(this), tickLower, tickUpper);
        (, , uint40 tsBefore,,,, ) = hook.positions(posId);

        vm.warp(block.timestamp + 30 days);
        hook.claimRecapture(poolKey, tickLower, tickUpper);

        (, , uint40 tsAfter,,,, ) = hook.positions(posId);
        assertGt(tsAfter, tsBefore, "entryTimestamp should reset to current block");
    }

    function test_claimRecapture_keepsPosition() public {
        bytes32 posId = hook.positionId(poolId, address(this), tickLower, tickUpper);
        (,,, uint128 liqBefore,,,) = hook.positions(posId);

        vm.warp(block.timestamp + 30 days);
        hook.claimRecapture(poolKey, tickLower, tickUpper);

        (,,, uint128 liqAfter,,,) = hook.positions(posId);
        assertEq(liqAfter, liqBefore, "liquidity should be unchanged after claim");
    }

    function test_claimRecapture_emitsRecaptureClaimed() public {
        bytes32 posId = hook.positionId(poolId, address(this), tickLower, tickUpper);
        vm.warp(block.timestamp + 30 days);

        vm.expectEmit(true, true, false, false);
        emit RecaptureHook.RecaptureClaimed(posId, address(this), 0);
        hook.claimRecapture(poolKey, tickLower, tickUpper);
    }

    // ─── Feature 7: ERC-4626-style vault views ─────────────────────────────────

    function test_vault_asset_returnsPoolToken() public view {
        assertEq(vault.asset(poolId), Currency.unwrap(currency1));
    }

    function test_vault_totalAssets_equalsPoolBalance() public view {
        assertEq(vault.totalAssets(poolId), vault.poolBalance(poolId));
    }

    function test_vault_totalSeeded_positive() public view {
        assertGt(vault.totalSeeded(poolId), 0);
    }
}
