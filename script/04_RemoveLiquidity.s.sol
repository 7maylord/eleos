// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {console} from "forge-std/console.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {BaseScript} from "./base/BaseScript.sol";
import {RecaptureHook} from "../src/RecaptureHook.sol";

/// @notice Remove liquidity from a RecaptureHook pool, triggering recapture settlement.
///
/// Configure:
///   TOKEN_ID        — the ERC-721 position token id (from PositionManager)
///   LIQUIDITY       — amount of liquidity units to remove (set to type(uint128).max for full removal)
///
/// Usage:
///   TOKEN_ID=1 LIQUIDITY=0 forge script script/04_RemoveLiquidity.s.sol \
///     --rpc-url $UNICHAIN_RPC_URL --account eleos-deployer --broadcast
contract RemoveLiquidityScript is BaseScript {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    /////////////////////////////////////
    // --- Configure These ---
    /////////////////////////////////////

    uint24 lpFee = 3000;
    int24 tickSpacing = 60;

    /////////////////////////////////////

    function run() external {
        // Read configuration from environment
        uint256 tokenId = vm.envOr("TOKEN_ID", uint256(1));
        uint128 liquidityToRemove = uint128(vm.envOr("LIQUIDITY", uint256(0)));

        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hookContract
        });

        PoolId poolId = poolKey.toId();

        // ── Pre-removal info ────────────────────────────────────────────
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

        // Build hookData: encode the deployer as the position owner
        bytes memory hookData = abi.encode(deployerAddress);

        // ── Build actions ───────────────────────────────────────────────
        // DECREASE_LIQUIDITY → TAKE_PAIR (send both tokens to deployer)
        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY),
            uint8(Actions.TAKE_PAIR)
        );

        bytes[] memory params = new bytes[](2);
        // DECREASE_LIQUIDITY params: (tokenId, liquidity, amount0Min, amount1Min, hookData)
        params[0] = abi.encode(tokenId, uint256(liquidityToRemove), uint128(0), uint128(0), hookData);
        // TAKE_PAIR params: (currency0, currency1, recipient)
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1, deployerAddress);

        bytes[] memory multicallParams = new bytes[](1);
        multicallParams[0] = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector,
            abi.encode(actions, params),
            block.timestamp + 3600
        );

        console.log("========================================");
        console.log("  Remove Liquidity - RecaptureHook");
        console.log("========================================");
        console.log("Token ID:       ", tokenId);
        console.log("Liquidity:      ", uint256(liquidityToRemove));
        console.log("Current sqrtP:  ", uint256(sqrtPriceX96));
        console.log("Pool fee:       ", uint256(lpFee));

        vm.startBroadcast();
        positionManager.multicall(multicallParams);
        vm.stopBroadcast();

        console.log("========================================");
        console.log("Liquidity removed successfully.");
        console.log("Check RecaptureSettled event in tx logs for IL / recapture / penalty details.");
        console.log("========================================");
    }
}
