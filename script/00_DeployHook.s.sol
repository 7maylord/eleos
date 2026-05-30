// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {console} from "forge-std/console.sol";

import {BaseScript} from "./base/BaseScript.sol";

import {RecaptureHook} from "../src/RecaptureHook.sol";
import {RecaptureVault} from "../src/RecaptureVault.sol";

/// @notice Deploys RecaptureVault then RecaptureHook (salt-mined to the correct flag address).
///         After deployment, wires the vault to point at the hook.
///
/// Usage:
///   forge script script/00_DeployHook.s.sol \
///     --rpc-url $UNICHAIN_RPC_URL --account eleos-deployer --broadcast
contract DeployHookScript is BaseScript {
    function run() public {
        // ── Hook Flags ──────────────────────────────────────────────────────
        // AFTER_ADD_LIQUIDITY      (1 << 10)
        // BEFORE_REMOVE_LIQUIDITY  (1 << 9)
        // BEFORE_SWAP              (1 << 7)
        // AFTER_SWAP               (1 << 6)
        // AFTER_SWAP_RETURNS_DELTA (1 << 2)
        uint160 flags = uint160(
            Hooks.AFTER_ADD_LIQUIDITY_FLAG
                | Hooks.BEFORE_SWAP_FLAG
                | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
                | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );

        vm.startBroadcast();

        // 1. Deploy RecaptureVault (owner = deployer)
        RecaptureVault vault = new RecaptureVault(deployerAddress);
        console.log("RecaptureVault deployed at:", address(vault));

        // 2. Mine a salt that produces a hook address encoding the correct flags
        bytes memory constructorArgs = abi.encode(poolManager, vault, deployerAddress);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(RecaptureHook).creationCode, constructorArgs);
        console.log("Mined hook address:        ", hookAddress);

        // 3. Deploy RecaptureHook via CREATE2 with the mined salt
        RecaptureHook hook = new RecaptureHook{salt: salt}(poolManager, vault, deployerAddress);
        require(address(hook) == hookAddress, "DeployHookScript: Hook Address Mismatch");

        // 4. Wire the vault to accept calls from the hook
        vault.setHook(address(hook));

        vm.stopBroadcast();

        // ── Summary ─────────────────────────────────────────────────────────
        console.log("========================================");
        console.log("  Eleos - RecaptureHook Deployment");
        console.log("========================================");
        console.log("RecaptureVault: ", address(vault));
        console.log("RecaptureHook:  ", address(hook));
        console.log("PoolManager:    ", address(poolManager));
        console.log("Owner:          ", deployerAddress);
        console.log("Flags:          ", uint256(flags));
        console.log("========================================");
        console.log("");
        console.log("NEXT STEPS:");
        console.log("  1. Update BaseScript.sol hookContract to the RecaptureHook address above.");
        console.log("  2. Run 01_CreatePoolAndAddLiquidity.s.sol to create a pool.");
        console.log("  3. Seed the vault via vault.seedPool(poolId, amount).");
    }
}
