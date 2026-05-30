// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

/// @notice Deploys two MockERC20 tokens on Unichain and mints to the deployer.
///         Run this FIRST, then add the printed addresses to .env as:
///           TOKEN0_ADDRESS=<lower address>
///           TOKEN1_ADDRESS=<higher address>
///
/// Usage:
///   forge script script/DeployTestTokens.s.sol \
///     --rpc-url $UNICHAIN_RPC_URL --account eleos-deployer --broadcast
contract DeployTestTokens is Script {
    uint256 constant MINT_AMOUNT = 10_000_000 ether;

    function run() public {
        address deployer = msg.sender;
        vm.startBroadcast();

        MockERC20 tokenA = new MockERC20("Eleos Token A", "ELOA", 18);
        MockERC20 tokenB = new MockERC20("Eleos Token B", "ELOB", 18);

        tokenA.mint(deployer, MINT_AMOUNT);
        tokenB.mint(deployer, MINT_AMOUNT);

        vm.stopBroadcast();

        // Uniswap v4 requires currency0 < currency1 by address.
        // Print them pre-sorted so TOKEN0/TOKEN1 env vars are correct.
        (address t0, address t1) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));

        console.log("========================================");
        console.log("  Test Token Deployment");
        console.log("========================================");
        console.log("Token A (ELOA):", address(tokenA));
        console.log("Token B (ELOB):", address(tokenB));
        console.log("");
        console.log("Add to .env (already sorted currency0 < currency1):");
        console.log("  TOKEN0_ADDRESS=%s", t0);
        console.log("  TOKEN1_ADDRESS=%s", t1);
        console.log("");
        console.log("Minted %s of each to deployer: %s", MINT_AMOUNT, deployer);
    }
}
