// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {RecaptureVault} from "../src/RecaptureVault.sol";
import {RecaptureHook} from "../src/RecaptureHook.sol";

/// @notice Seeds the RecaptureVault for the deployed pool.
///         Reads all addresses from env vars — no Solidity edits needed.
///
/// Usage:
///   forge script script/06_SeedVault.s.sol \
///     --rpc-url $SEPOLIA_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --broadcast
contract SeedVaultScript is Script {
    using PoolIdLibrary for PoolKey;

    uint256 constant SEED_AMOUNT = 50_000 ether;

    function run() external {
        address token0Addr  = vm.envAddress("TOKEN0_ADDRESS");
        address token1Addr  = vm.envAddress("TOKEN1_ADDRESS");
        address hookAddr    = vm.envAddress("HOOK_ADDRESS");
        address vaultAddr   = vm.envAddress("VAULT_ADDRESS");

        RecaptureVault vault = RecaptureVault(vaultAddr);
        IERC20 token1        = IERC20(token1Addr);

        // Reconstruct the same PoolKey used in 01_CreatePoolAndAddLiquidity
        PoolKey memory poolKey = PoolKey({
            currency0:   Currency.wrap(token0Addr),
            currency1:   Currency.wrap(token1Addr),
            fee:         3000,
            tickSpacing: 60,
            hooks:       IHooks(hookAddr)
        });
        PoolId poolId = poolKey.toId();

        // Verify the pool was registered by the hook
        address registeredToken = vault.poolToken(poolId);
        require(registeredToken != address(0), "Pool not registered - did 01_ script run?");
        require(registeredToken == token1Addr,  "Unexpected pool token");

        vm.startBroadcast();
        token1.approve(vaultAddr, SEED_AMOUNT);
        vault.seedPool(poolId, SEED_AMOUNT);
        vm.stopBroadcast();

        console.log("=========================================");
        console.log("  Vault Seeded");
        console.log("=========================================");
        console.log("Pool ID:       %s", vm.toString(PoolId.unwrap(poolId)));
        console.log("Vault:         %s", vaultAddr);
        console.log("Token (token1):%s", token1Addr);
        console.log("Seeded:        %s ELOB", SEED_AMOUNT / 1e18);
        console.log("Vault balance: %s", vault.poolBalance(poolId));
    }
}
