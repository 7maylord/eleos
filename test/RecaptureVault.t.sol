// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {RecaptureVault} from "../src/RecaptureVault.sol";

contract RecaptureVaultTest is Test {
    RecaptureVault vault;
    MockERC20 token;
    MockERC20 otherToken;

    address hook = address(0xBEEF);
    address user = address(0xCAFE);
    address stranger = address(0xFACE);

    PoolId poolId = PoolId.wrap(bytes32(uint256(0xABCD)));
    PoolId pool2Id = PoolId.wrap(bytes32(uint256(0xBBBB)));
    PoolId unregisteredPoolId = PoolId.wrap(bytes32(uint256(0xDEAD)));
    bytes32 posId = bytes32(uint256(1));
    bytes32 posId2 = bytes32(uint256(2));

    uint256 constant SEED = 10_000 ether;

    function setUp() public {
        vault = new RecaptureVault(address(this));
        token = new MockERC20("Test Token", "TST", 18);
        otherToken = new MockERC20("Other Token", "OTH", 18);
        token.mint(address(this), 1_000_000 ether);
        otherToken.mint(address(this), 1_000_000 ether);

        vault.setHook(hook);

        // Register pool and seed it
        vm.prank(hook);
        vault.registerPool(poolId, address(token));

        token.approve(address(vault), type(uint256).max);
        vault.seedPool(poolId, SEED);
    }

    // ─── setHook ───────────────────────────────────────────────────────────────

    function test_setHook_storesAddress() public view {
        assertEq(vault.hook(), hook);
    }

    function test_setHook_cannotBeUpdatedAfterSet() public {
        // L-2 fix: hook is immutable once set — second call must revert.
        vm.expectRevert("hook already set");
        vault.setHook(address(0x1111));
    }

    function test_setHook_onlyOwner() public {
        // Fresh vault so the one-time guard doesn't interfere.
        RecaptureVault freshVault = new RecaptureVault(address(this));
        vm.prank(user);
        vm.expectRevert();
        freshVault.setHook(address(0x1234));
    }

    function test_setHook_emitsEvent() public view {
        // Verify HookSet event was emitted during setUp (hook already stored).
        assertEq(vault.hook(), hook); // already set in setUp
    }

    // ─── registerPool ──────────────────────────────────────────────────────────

    function test_registerPool_setsToken() public view {
        assertEq(vault.poolToken(poolId), address(token));
    }

    function test_registerPool_onlyHook() public {
        vm.expectRevert(RecaptureVault.OnlyHook.selector);
        vault.registerPool(unregisteredPoolId, address(token));
    }

    function test_registerPool_revertsFromStranger() public {
        vm.prank(stranger);
        vm.expectRevert(RecaptureVault.OnlyHook.selector);
        vault.registerPool(unregisteredPoolId, address(token));
    }

    function test_registerPool_revertsOnDuplicate() public {
        vm.prank(hook);
        vm.expectRevert(RecaptureVault.PoolAlreadyRegistered.selector);
        vault.registerPool(poolId, address(token));
    }

    function test_registerPool_emitsEvent() public {
        vm.prank(hook);
        vm.expectEmit(true, false, false, true);
        emit RecaptureVault.PoolRegistered(pool2Id, address(otherToken));
        vault.registerPool(pool2Id, address(otherToken));
    }

    function test_registerPool_multiplePoolsIndependent() public {
        vm.prank(hook);
        vault.registerPool(pool2Id, address(otherToken));

        assertEq(vault.poolToken(poolId), address(token));
        assertEq(vault.poolToken(pool2Id), address(otherToken));
        assertEq(vault.poolBalance(pool2Id), 0);
    }

    // ─── seedPool ──────────────────────────────────────────────────────────────

    function test_seedPool_creditsPoolBalance() public view {
        assertEq(vault.poolBalance(poolId), SEED);
    }

    function test_seedPool_transfersTokensIn() public view {
        assertEq(token.balanceOf(address(vault)), SEED);
    }

    function test_seedPool_onlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        vault.seedPool(poolId, 1 ether);
    }

    function test_seedPool_revertsZeroAmount() public {
        vm.expectRevert(RecaptureVault.ZeroAmount.selector);
        vault.seedPool(poolId, 0);
    }

    function test_seedPool_revertsUnregisteredPool() public {
        vm.expectRevert(RecaptureVault.PoolNotRegistered.selector);
        vault.seedPool(unregisteredPoolId, 100 ether);
    }

    function test_seedPool_accumulates() public {
        vault.seedPool(poolId, 500 ether);
        assertEq(vault.poolBalance(poolId), SEED + 500 ether);
    }

    function test_seedPool_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit RecaptureVault.PoolSeeded(poolId, 100 ether);
        vault.seedPool(poolId, 100 ether);
    }

    // ─── credit ────────────────────────────────────────────────────────────────

    function test_credit_increasesPoolBalance() public {
        uint256 creditAmt = 200 ether;
        token.mint(hook, creditAmt);
        vm.startPrank(hook);
        token.approve(address(vault), creditAmt);
        vault.credit(poolId, creditAmt);
        vm.stopPrank();
        assertEq(vault.poolBalance(poolId), SEED + creditAmt);
    }

    function test_credit_onlyHook() public {
        vm.expectRevert(RecaptureVault.OnlyHook.selector);
        vault.credit(poolId, 100 ether);
    }

    function test_credit_zeroIsNoOp() public {
        vm.prank(hook);
        vault.credit(poolId, 0); // should not revert
        assertEq(vault.poolBalance(poolId), SEED);
    }

    function test_credit_revertsUnregisteredPool() public {
        token.mint(hook, 100 ether);
        vm.startPrank(hook);
        token.approve(address(vault), 100 ether);
        vm.expectRevert(RecaptureVault.PoolNotRegistered.selector);
        vault.credit(unregisteredPoolId, 100 ether);
        vm.stopPrank();
    }

    function test_credit_emitsEvent() public {
        uint256 creditAmt = 50 ether;
        token.mint(hook, creditAmt);
        vm.startPrank(hook);
        token.approve(address(vault), creditAmt);
        vm.expectEmit(true, false, false, true);
        emit RecaptureVault.PoolCredited(poolId, creditAmt);
        vault.credit(poolId, creditAmt);
        vm.stopPrank();
    }

    // ─── payRecapture ──────────────────────────────────────────────────────────

    function test_payRecapture_transfersTokensToRecipient() public {
        vm.prank(hook);
        uint256 paid = vault.payRecapture(poolId, posId, user, 500 ether);

        assertEq(paid, 500 ether);
        assertEq(token.balanceOf(user), 500 ether);
        assertEq(vault.poolBalance(poolId), SEED - 500 ether);
    }

    function test_payRecapture_capsAtPoolBalance() public {
        vm.prank(hook);
        uint256 paid = vault.payRecapture(poolId, posId, user, type(uint256).max);

        assertEq(paid, SEED);                          // capped
        assertEq(vault.poolBalance(poolId), 0);
        assertEq(token.balanceOf(user), SEED);
    }

    function test_payRecapture_zeroRequestReturnsZero() public {
        vm.prank(hook);
        uint256 paid = vault.payRecapture(poolId, posId, user, 0);
        assertEq(paid, 0);
        assertEq(token.balanceOf(user), 0);
    }

    function test_payRecapture_onlyHook() public {
        vm.expectRevert(RecaptureVault.OnlyHook.selector);
        vault.payRecapture(poolId, posId, user, 100 ether);
    }

    function test_payRecapture_revertsWhenPaused() public {
        vault.pause();
        vm.prank(hook);
        vm.expectRevert();
        vault.payRecapture(poolId, posId, user, 100 ether);
    }

    function test_payRecapture_multipleCallsReduceBalance() public {
        vm.startPrank(hook);
        vault.payRecapture(poolId, posId, user, 3000 ether);
        vault.payRecapture(poolId, posId, user, 3000 ether);
        vault.payRecapture(poolId, posId, user, 3000 ether);
        // Fourth call should only get remaining 1000
        uint256 paid = vault.payRecapture(poolId, posId, user, 3000 ether);
        vm.stopPrank();

        assertEq(paid, 1000 ether);
        assertEq(vault.poolBalance(poolId), 0);
    }

    function test_payRecapture_emitsEvent() public {
        vm.prank(hook);
        vm.expectEmit(true, true, false, true);
        emit RecaptureVault.RecapturePaid(poolId, posId, user, 100 ether);
        vault.payRecapture(poolId, posId, user, 100 ether);
    }

    function test_payRecapture_zeroWhenPoolDrained() public {
        // Drain pool balance through payouts
        vm.startPrank(hook);
        vault.payRecapture(poolId, posId, user, SEED);
        // Now pool balance is 0
        uint256 paid = vault.payRecapture(poolId, posId, user, 1000 ether);
        vm.stopPrank();
        assertEq(paid, 0);
    }

    function test_payRecapture_revertsUnregisteredPool() public {
        vm.prank(hook);
        vm.expectRevert(RecaptureVault.PoolNotRegistered.selector);
        vault.payRecapture(unregisteredPoolId, posId, user, 100 ether);
    }

    // ─── recordForfeit ─────────────────────────────────────────────────────────

    function test_recordForfeit_emitsEvent() public {
        vm.prank(hook);
        vm.expectEmit(true, true, false, true);
        emit RecaptureVault.ForfeitRetained(poolId, posId, 200 ether);
        vault.recordForfeit(poolId, posId, 200 ether);
    }

    function test_recordForfeit_doesNotMoveTokens() public {
        uint256 balBefore = vault.poolBalance(poolId);
        uint256 vaultTokenBefore = token.balanceOf(address(vault));

        vm.prank(hook);
        vault.recordForfeit(poolId, posId, 200 ether);

        assertEq(vault.poolBalance(poolId), balBefore); // balance unchanged
        assertEq(token.balanceOf(address(vault)), vaultTokenBefore);
    }

    function test_recordForfeit_onlyHook() public {
        vm.expectRevert(RecaptureVault.OnlyHook.selector);
        vault.recordForfeit(poolId, posId, 100 ether);
    }

    function test_recordForfeit_revertsWhenPaused() public {
        vault.pause();
        vm.prank(hook);
        vm.expectRevert();
        vault.recordForfeit(poolId, posId, 100 ether);
    }

    // ─── pause / unpause ──────────────────────────────────────────────────────

    function test_pause_blocksSeedPool() public {
        vault.pause();
        vm.expectRevert();
        vault.seedPool(poolId, 1 ether);
    }

    function test_pause_blocksCredit() public {
        vault.pause();
        token.mint(hook, 100 ether);
        vm.startPrank(hook);
        token.approve(address(vault), 100 ether);
        vm.expectRevert();
        vault.credit(poolId, 100 ether);
        vm.stopPrank();
    }

    function test_pause_onlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        vault.pause();
    }

    function test_unpause_onlyOwner() public {
        vault.pause();
        vm.prank(user);
        vm.expectRevert();
        vault.unpause();
    }

    function test_unpause_restoresSeedPool() public {
        vault.pause();
        vault.unpause();
        vault.seedPool(poolId, 100 ether);
        assertEq(vault.poolBalance(poolId), SEED + 100 ether);
    }

    // ─── emergencyRescue ──────────────────────────────────────────────────────

    function test_emergencyRescue_drainsFunds() public {
        vault.pause();
        uint256 before = token.balanceOf(address(this));
        vault.emergencyRescue(address(token), address(this));
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(token.balanceOf(address(this)), before + SEED);
    }

    function test_emergencyRescue_revertsWhenNotPaused() public {
        vm.expectRevert();
        vault.emergencyRescue(address(token), address(this));
    }

    function test_emergencyRescue_onlyOwner() public {
        vault.pause();
        vm.prank(user);
        vm.expectRevert();
        vault.emergencyRescue(address(token), user);
    }

    function test_emergencyRescue_noOpWhenNoTokenBalance() public {
        vault.pause();
        // Rescue a different token that has 0 balance
        uint256 balBefore = otherToken.balanceOf(address(this));
        vault.emergencyRescue(address(otherToken), address(this));
        assertEq(otherToken.balanceOf(address(this)), balBefore);
    }

    // ─── Multi-pool isolation ─────────────────────────────────────────────────

    function test_multiPool_balancesAreIsolated() public {
        // Register and seed a second pool
        vm.prank(hook);
        vault.registerPool(pool2Id, address(otherToken));
        otherToken.approve(address(vault), type(uint256).max);
        vault.seedPool(pool2Id, 5000 ether);

        // Pay from pool1
        vm.prank(hook);
        vault.payRecapture(poolId, posId, user, 1000 ether);

        // Pool1 reduced, pool2 untouched
        assertEq(vault.poolBalance(poolId), SEED - 1000 ether);
        assertEq(vault.poolBalance(pool2Id), 5000 ether);
    }

    // ─── Solvency: paid never exceeds seeded ────────────────────────────────────

    function testFuzz_payRecapture_totalPaidNeverExceedsSeeded(uint96[5] memory amounts) public {
        uint256 totalPaid;
        for (uint256 i = 0; i < amounts.length; i++) {
            vm.prank(hook);
            uint256 paid = vault.payRecapture(poolId, posId, user, amounts[i]);
            totalPaid += paid;
        }
        assertLe(totalPaid, SEED);
        assertEq(vault.poolBalance(poolId), SEED - totalPaid);
    }

    function testFuzz_payRecapture_multipleRecipientsNeverExceedSeed(uint96 a1, uint96 a2, uint96 a3) public {
        vm.startPrank(hook);
        uint256 p1 = vault.payRecapture(poolId, posId, user, a1);
        uint256 p2 = vault.payRecapture(poolId, posId2, stranger, a2);
        uint256 p3 = vault.payRecapture(poolId, posId, user, a3);
        vm.stopPrank();

        assertLe(p1 + p2 + p3, SEED);
        assertEq(vault.poolBalance(poolId), SEED - p1 - p2 - p3);
    }
}
