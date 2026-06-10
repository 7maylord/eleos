// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {BaseScript} from "./base/BaseScript.sol";

// Minimal vault interface — only what the script needs
interface IVaultView {
    function poolBalance(bytes32 poolId)    external view returns (uint256);
    function totalSeeded(bytes32 poolId)    external view returns (uint256);
    function totalCredited(bytes32 poolId)  external view returns (uint256);
}

/**
 * Run a batch of swaps through the Eleos RecaptureHook pool.
 *
 * Purpose:
 *   • Generate fee diversions so the vault balance grows
 *   • Move the pool price to create measurable IL on LP positions
 *
 * Usage:
 *   source .env   # loads UNICHAIN_RPC_URL, DEPLOYER_PRIVATE_KEY, VAULT_ADDRESS, etc.
 *   forge script script/07_RunSwaps.s.sol \
 *     --rpc-url $UNICHAIN_RPC_URL \
 *     --private-key $DEPLOYER_PRIVATE_KEY \
 *     --broadcast -vvv
 *
 * Optional env vars (set before sourcing, or export manually):
 *   SWAP_COUNT      Number of swaps to execute          (default: 5)
 *   SWAP_AMOUNT     Tokens per swap, no decimals         (default: 1000)
 *   DIRECTION       0 = ELOB→ELOA, 1 = ELOA→ELOB,
 *                   2 = alternating                      (default: 2)
 *   VAULT_ADDRESS   RecaptureVault to read stats from    (already in .env)
 */
contract RunSwapsScript is BaseScript {
    using PoolIdLibrary for PoolKey;

    function run() external {
        // ── Config from env ───────────────────────────────────────────────────
        uint256 swapCount  = vm.envOr("SWAP_COUNT",  uint256(5));
        uint256 swapAmount = vm.envOr("SWAP_AMOUNT", uint256(1_000)) * 1e18;
        uint256 direction  = vm.envOr("DIRECTION",   uint256(2));  // 2 = alternating
        address vaultAddr  = vm.envOr("VAULT_ADDRESS", address(0));

        PoolKey memory poolKey = PoolKey({
            currency0:   currency0,
            currency1:   currency1,
            fee:         3000,
            tickSpacing: 60,
            hooks:       hookContract
        });

        bytes32 poolId = PoolId.unwrap(poolKey.toId());

        // ── Balances / vault state before ─────────────────────────────────────
        console.log("=== BEFORE ===");
        console.log("Deployer ELOB balance:", token0.balanceOf(deployerAddress) / 1e18);
        console.log("Deployer ELOA balance:", token1.balanceOf(deployerAddress) / 1e18);
        if (vaultAddr != address(0)) {
            IVaultView vault = IVaultView(vaultAddr);
            console.log("Vault pool balance (ELOA):", vault.poolBalance(poolId) / 1e18);
            console.log("Vault total credited:     ", vault.totalCredited(poolId) / 1e18);
        }
        console.log("---");
        console.log(string.concat(
            "Running ", vm.toString(swapCount),
            " swaps of ", vm.toString(swapAmount / 1e18), " tokens each"
        ));
        console.log(string.concat(
            "Direction: ",
            direction == 0 ? "ELOB->ELOA" : direction == 1 ? "ELOA->ELOB" : "alternating"
        ));
        console.log("---");

        // ── Approve routers ───────────────────────────────────────────────────
        vm.startBroadcast();

        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);

        // ── Execute swaps ─────────────────────────────────────────────────────
        bytes memory hookData = new bytes(0);

        for (uint256 i = 0; i < swapCount; i++) {
            bool zeroForOne;
            if (direction == 0) {
                zeroForOne = true;
            } else if (direction == 1) {
                zeroForOne = false;
            } else {
                zeroForOne = (i % 2 == 0);  // alternating
            }

            BalanceDelta delta = swapRouter.swapExactTokensForTokens({
                amountIn:    swapAmount,
                amountOutMin: 0,  // no slippage protection — test only
                zeroForOne:  zeroForOne,
                poolKey:     poolKey,
                hookData:    hookData,
                receiver:    deployerAddress,
                deadline:    block.timestamp + 60
            });

            console.log(
                string.concat(
                    "Swap ", vm.toString(i + 1), "/", vm.toString(swapCount),
                    " (", zeroForOne ? "ELOB->ELOA" : "ELOA->ELOB", ")",
                    "  in=", vm.toString(swapAmount / 1e18),
                    "  out=", vm.toString(
                        uint256(int256(zeroForOne ? delta.amount1() : delta.amount0())) / 1e18
                    )
                )
            );
        }

        vm.stopBroadcast();

        // ── Balances / vault state after ──────────────────────────────────────
        console.log("---");
        console.log("=== AFTER ===");
        console.log("Deployer ELOB balance:", token0.balanceOf(deployerAddress) / 1e18);
        console.log("Deployer ELOA balance:", token1.balanceOf(deployerAddress) / 1e18);
        if (vaultAddr != address(0)) {
            IVaultView vault = IVaultView(vaultAddr);
            uint256 newBalance  = vault.poolBalance(poolId);
            uint256 newCredited = vault.totalCredited(poolId);
            console.log("Vault pool balance (ELOA):", newBalance / 1e18);
            console.log("Vault total credited:     ", newCredited / 1e18);
            if (newCredited > 0) {
                console.log("  >> Fee diversions this session: ~", newCredited / 1e15, "mELOA");
            }
        }
    }
}
