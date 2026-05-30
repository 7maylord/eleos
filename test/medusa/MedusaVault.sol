// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {RecaptureVault} from "../../src/RecaptureVault.sol";

/// @notice Medusa stateful fuzzing harness for RecaptureVault.
///
/// This contract acts as both owner and hook so it can exercise all vault paths.
/// Key solvency invariants checked:
///   property_solvency           — remaining + paid ≤ seeded
///   property_tokenMatchesPool   — ERC20 balance ≥ poolBalance (no leakage)
///   property_recipientsBalance  — paid tokens fully accounted across recipients
contract MedusaVaultTest {
    RecaptureVault public vault;
    MockERC20 public token;

    PoolId poolId  = PoolId.wrap(bytes32(uint256(1)));
    PoolId poolId2 = PoolId.wrap(bytes32(uint256(2)));
    bytes32 posId  = bytes32(uint256(0xBEEF));

    address recipient1 = address(0x1001);
    address recipient2 = address(0x1002);

    uint256 public totalSeeded;
    uint256 public totalPaid;
    uint256 public totalCredited;

    uint256 constant MAX_SUPPLY = type(uint128).max;

    constructor() {
        vault = new RecaptureVault(address(this));
        token = new MockERC20("Test", "TST", 18);

        token.mint(address(this), MAX_SUPPLY);
        token.approve(address(vault), type(uint256).max);

        // This contract acts as the hook
        vault.setHook(address(this));
        vault.registerPool(poolId, address(token));
    }

    // ─── Handlers ──────────────────────────────────────────────────────────────

    function handler_seed(uint96 amount) external {
        if (amount == 0) return;
        if (totalSeeded + amount > MAX_SUPPLY) return;
        vault.seedPool(poolId, amount);
        totalSeeded += amount;
    }

    function handler_payRecipient1(uint96 amount) external {
        if (amount == 0) return;
        uint256 paid = vault.payRecapture(poolId, posId, recipient1, amount);
        totalPaid += paid;
    }

    function handler_payRecipient2(uint96 amount) external {
        if (amount == 0) return;
        uint256 paid = vault.payRecapture(poolId, posId, recipient2, amount);
        totalPaid += paid;
    }

    function handler_credit(uint96 amount) external {
        if (amount == 0) return;
        // Phase 2: hook is responsible for having tokens already in the vault
        // (via poolManager.take). Simulate by minting directly to vault.
        token.mint(address(vault), amount);
        totalCredited += amount;
        vault.credit(poolId, amount);
    }

    function handler_recordForfeit(uint96 amount) external {
        // No token movement; just event emission
        vault.recordForfeit(poolId, posId, amount);
    }

    function handler_payZero() external {
        uint256 paid = vault.payRecapture(poolId, posId, recipient1, 0);
        assert(paid == 0);
    }

    function handler_creditZero() external {
        // credit(0) is a no-op
        vault.credit(poolId, 0);
    }

    // ─── Properties ────────────────────────────────────────────────────────────

    /// @dev Core solvency: remaining + paid ≤ seeded + credited.
    ///      Uses vault's own analytics (totalSeeded, totalCredited, totalPaid).
    function property_solvency() external view returns (bool) {
        uint256 remaining = vault.poolBalance(poolId);
        uint256 paid      = vault.totalPaid(poolId);
        uint256 seeded    = vault.totalSeeded(poolId);
        uint256 credited  = vault.totalCredited(poolId);
        // 1-wei rounding tolerance from mulDiv in payRecapture
        return remaining + paid <= seeded + credited + 1;
    }

    /// @dev ERC20 balance of vault always ≥ its accounting (no leakage out).
    function property_tokenMatchesPool() external view returns (bool) {
        uint256 erc20Bal = token.balanceOf(address(vault));
        uint256 poolBal  = vault.poolBalance(poolId);
        return erc20Bal >= poolBal;
    }

    /// @dev Tokens sent to recipients exactly equal totalPaid (accounting identity).
    function property_recipientsBalance() external view returns (bool) {
        uint256 r1 = token.balanceOf(recipient1);
        uint256 r2 = token.balanceOf(recipient2);
        return r1 + r2 == vault.totalPaid(poolId);
    }

    /// @dev Pool balance never exceeds what was put in.
    function property_poolBalanceBounded() external view returns (bool) {
        return vault.poolBalance(poolId) <= vault.totalSeeded(poolId) + vault.totalCredited(poolId);
    }

    /// @dev Unregistered pool always has zero balance and no token.
    function property_unregisteredPoolClean() external view returns (bool) {
        return vault.poolBalance(poolId2) == 0 && vault.poolToken(poolId2) == address(0);
    }
}
