// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {console} from "forge-std/console.sol";

import {BaseScript} from "./base/BaseScript.sol";
import {RecaptureHook} from "../src/RecaptureHook.sol";
import {RecaptureMath} from "../src/RecaptureMath.sol";

/// @notice Read on-chain position state from RecaptureHook and preview recapture.
///
/// Configure via environment variables:
///   POSITION_OWNER  — address of the LP (defaults to deployer)
///   TICK_LOWER      — lower tick of the position
///   TICK_UPPER      — upper tick of the position
///
/// Usage:
///   TICK_LOWER=-887220 TICK_UPPER=887220 forge script script/05_CheckPosition.s.sol \
///     --rpc-url $UNICHAIN_RPC_URL --account eleos-deployer
contract CheckPositionScript is BaseScript {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    /////////////////////////////////////
    // --- Configure These ---
    /////////////////////////////////////

    uint24 lpFee = 3000;
    int24 tickSpacing = 60;

    /////////////////////////////////////

    function run() external view {
        // Read configuration from env (fall back to deployer and common tick range)
        address posOwner = vm.envOr("POSITION_OWNER", deployerAddress);
        int24 tickLower = int24(vm.envOr("TICK_LOWER", int256(-887220)));
        int24 tickUpper = int24(vm.envOr("TICK_UPPER", int256(887220)));

        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hookContract
        });

        PoolId poolId = poolKey.toId();

        // ── Compute position ID ─────────────────────────────────────────
        RecaptureHook hook = RecaptureHook(address(hookContract));
        bytes32 posId = hook.positionId(poolId, posOwner, tickLower, tickUpper);

        // ── Read position data ──────────────────────────────────────────
        (
            address owner,
            uint160 entrySqrtPriceX96,
            uint40 entryTimestamp,
            uint128 liquidityAdded,
            uint40 lockDuration,
            uint256 feeGrowthSnapshot,
            uint256 depositToken1
        ) = hook.positions(posId);

        // ── Current pool state ──────────────────────────────────────────
        (uint160 currentSqrtPrice,,,) = poolManager.getSlot0(poolId);

        console.log("========================================");
        console.log("  Eleos - Position Inspector");
        console.log("========================================");
        console.log("");

        if (entryTimestamp == 0) {
            console.log("Position NOT FOUND for:");
            console.log("  Owner:      ", posOwner);
            console.log("  TickLower:  ", tickLower);
            console.log("  TickUpper:  ", tickUpper);
            console.log("  PoolId:      (check that tokens, fee, tickSpacing match)");
            console.log("========================================");
            return;
        }

        console.log("Position ID:   ");
        console.logBytes32(posId);
        console.log("Owner:          ", owner);
        console.log("");

        // ── Prices ──────────────────────────────────────────────────────
        console.log("--- Prices ---");
        console.log("Entry sqrtPriceX96:  ", uint256(entrySqrtPriceX96));
        console.log("Current sqrtPriceX96:", uint256(currentSqrtPrice));
        console.log("");

        // ── Position Details ────────────────────────────────────────────
        console.log("--- Position ---");
        console.log("Liquidity:      ", uint256(liquidityAdded));
        console.log("Deposit (token1):", depositToken1);
        console.log("Entry time:      ", uint256(entryTimestamp));
        console.log("Lock duration:   ", uint256(lockDuration));
        console.log("Fee growth snap: ", feeGrowthSnapshot);
        console.log("");

        // ── Time Calculations ───────────────────────────────────────────
        uint256 timeHeld = block.timestamp - entryTimestamp;
        uint256 effectiveLock = lockDuration == 0 ? RecaptureMath.DEFAULT_LOCK_DURATION : lockDuration;

        console.log("--- Time ---");
        console.log("Time held (sec):    ", timeHeld);
        console.log("Time held (days):   ", timeHeld / 1 days);
        console.log("Effective lock (sec):", effectiveLock);
        console.log("Lock progress (%):  ", timeHeld >= effectiveLock ? 100 : (timeHeld * 100) / effectiveLock);
        console.log("");

        // ── Recapture Preview ───────────────────────────────────────────
        (
            uint256 ilPct,
            uint256 ratio,
            uint256 loyaltyMult,
            uint256 recapturedTokens,
            uint256 forfeitedTokens
        ) = hook.previewRecapture(posId, currentSqrtPrice);

        console.log("--- Recapture Preview ---");
        console.log("IL (WAD):            ", ilPct);
        console.log("IL (%):              ", ilPct * 100 / 1e18);
        console.log("Recapture ratio:     ", ratio);
        console.log("Recapture ratio (%): ", ratio * 100 / 1e18);
        console.log("Loyalty multiplier:  ", loyaltyMult);
        console.log("Loyalty mult (x):    ", loyaltyMult * 100 / 1e18);
        console.log("");
        console.log("Recaptured (tokens): ", recapturedTokens);
        console.log("Forfeited  (tokens): ", forfeitedTokens);

        // ── Vault Balance ───────────────────────────────────────────────
        console.log("");
        console.log("--- Vault ---");
        uint256 vaultBal = hook.vault().poolBalance(poolId);
        console.log("Pool vault balance:  ", vaultBal);
        bool canFullyPay = vaultBal >= recapturedTokens;
        console.log("Can fully pay:       ", canFullyPay ? "YES" : "NO");

        console.log("========================================");
    }
}
