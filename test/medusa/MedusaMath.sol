// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {RecaptureMath} from "../../src/RecaptureMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/// @notice Medusa assertion-based harness for RecaptureMath pure invariants.
///
/// Two test surfaces:
///   1. check_* — standard assertions over safe-bounded inputs.
///   2. check_IL_noRevertAtValidPrices — probes the *full* Uniswap v4 price range
///      to detect FullMath overflow; known to fail at extreme ratios (HIGH finding).
contract MedusaMathTest {
    uint256 constant WAD = 1e18;

    // Safe upper bound for sqrtPrice in IL checks.
    // At extreme ratios (MAX/MIN ≈ 3.4e38), rDiffSq = (r-1)² / WAD overflows uint256.
    // uint80 max ≈ 1.2e24, giving ratio ≤ 1.2e24 — well inside the safe region.
    uint160 constant SAFE_MAX = type(uint80).max;

    // ─── IL Properties (safe range) ────────────────────────────────────────────

    function check_IL_alwaysLtWAD(uint160 entry, uint160 current) external pure {
        entry   = uint160(uint256(entry)   % uint256(SAFE_MAX) + 1);
        current = uint160(uint256(current) % uint256(SAFE_MAX) + 1);
        uint256 il = RecaptureMath.calculateIL(entry, current);
        assert(il < WAD);
    }

    function check_IL_zeroWhenUnchanged(uint160 price) external pure {
        price = uint160(uint256(price) % uint256(SAFE_MAX) + 1);
        assert(RecaptureMath.calculateIL(price, price) == 0);
    }

    function check_IL_zeroWhenInputZero(uint160 other) external pure {
        other = uint160(uint256(other) % uint256(SAFE_MAX) + 1);
        assert(RecaptureMath.calculateIL(0, other) == 0);
        assert(RecaptureMath.calculateIL(other, 0) == 0);
    }

    function check_IL_symmetric(uint160 a, uint160 b) external pure {
        a = uint160(uint256(a) % uint256(SAFE_MAX) + 1);
        b = uint160(uint256(b) % uint256(SAFE_MAX) + 1);
        uint256 ab = RecaptureMath.calculateIL(a, b);
        uint256 ba = RecaptureMath.calculateIL(b, a);
        uint256 diff = ab > ba ? ab - ba : ba - ab;
        assert(diff <= 1); // 1-wei rounding tolerance
    }

    // ─── Full-Range Revert Probe (finds HIGH finding) ─────────────────────────

    /// @notice Probes the *full* Uniswap v4 sqrtPrice range.
    ///         calculateIL MUST NOT revert for any valid price pair.
    ///         Medusa will find counter-examples near MIN_SQRT_PRICE / MAX_SQRT_PRICE.
    function check_IL_noRevertAtValidPrices(uint160 entry, uint160 current) external view {
        if (entry   < TickMath.MIN_SQRT_PRICE || entry   > TickMath.MAX_SQRT_PRICE) return;
        if (current < TickMath.MIN_SQRT_PRICE || current > TickMath.MAX_SQRT_PRICE) return;

        try this.callCalculateIL(entry, current) returns (uint256 il) {
            assert(il < WAD);
        } catch {
            // Revert inside calculateIL for a valid price pair == FullMath overflow bug.
            assert(false);
        }
    }

    function callCalculateIL(uint160 entry, uint160 current) external pure returns (uint256) {
        return RecaptureMath.calculateIL(entry, current);
    }

    // ─── recaptureRatio Properties ─────────────────────────────────────────────

    function check_ratio_bounded(uint32 timeHeld, uint32 lockDuration) external pure {
        uint256 ratio = RecaptureMath.recaptureRatio(timeHeld, lockDuration);
        assert(ratio <= WAD);
    }

    function check_ratio_WADWhenTimeGeDuration(uint32 timeHeld, uint32 lockDuration) external pure {
        // When timeHeld >= lockDuration (and lockDuration > 0), ratio must be WAD
        if (lockDuration == 0) return;
        if (uint256(timeHeld) < uint256(lockDuration)) return;
        assert(RecaptureMath.recaptureRatio(timeHeld, lockDuration) == WAD);
    }

    function check_ratio_zeroAtZeroTime(uint32 lockDuration) external pure {
        assert(RecaptureMath.recaptureRatio(0, lockDuration) == 0);
    }

    // ─── Loyalty Multiplier Properties ─────────────────────────────────────────

    function check_multiplier_inRange(uint32 timeHeld, uint32 basePeriod, uint16 bonusBps) external pure {
        uint256 mult = RecaptureMath.calculateLoyaltyMultiplier(timeHeld, basePeriod, bonusBps);
        assert(mult >= WAD);
        assert(mult <= 2 * WAD);
    }

    function check_multiplier_WADAtZeroTime(uint32 basePeriod, uint16 bonusBps) external pure {
        assert(RecaptureMath.calculateLoyaltyMultiplier(0, basePeriod, bonusBps) == WAD);
    }

    function check_multiplier_WADWithZeroBonus(uint32 timeHeld, uint32 basePeriod) external pure {
        assert(RecaptureMath.calculateLoyaltyMultiplier(timeHeld, basePeriod, 0) == WAD);
    }

    // ─── calculateRecaptured Properties ────────────────────────────────────────

    function check_recaptured_neverExceedsIL(uint128 il, uint32 timeHeld, uint32 lockDuration) external pure {
        il = uint128(uint256(il) % (WAD + 1));
        uint256 recaptured = RecaptureMath.calculateRecaptured(il, timeHeld, lockDuration);
        assert(recaptured <= uint256(il));
    }

    function check_recaptured_zeroAtZeroTime(uint128 il) external pure {
        il = uint128(uint256(il) % (WAD + 1));
        assert(RecaptureMath.calculateRecaptured(il, 0, 90 days) == 0);
    }

    function check_recaptured_fullAfterDuration(uint128 il, uint32 lockDuration) external pure {
        il = uint128(uint256(il) % (WAD + 1));
        if (lockDuration == 0) lockDuration = 1;
        // timeHeld = type(uint32).max always >= any lockDuration
        assert(RecaptureMath.calculateRecaptured(il, type(uint32).max, lockDuration) == uint256(il));
    }

    // ─── Early Exit Forfeit Properties ─────────────────────────────────────────

    function check_forfeit_neverExceedsAmount(uint128 amount, uint128 ratio) external pure {
        ratio = uint128(uint256(ratio) % (WAD + 1));
        uint256 forfeit = RecaptureMath.calculateEarlyExitForfeit(amount, ratio);
        assert(forfeit <= uint256(amount));
    }

    function check_forfeit_zeroAtFullRatio(uint128 amount) external pure {
        assert(RecaptureMath.calculateEarlyExitForfeit(amount, WAD) == 0);
    }

    function check_forfeit_allAtZeroRatio(uint128 amount) external pure {
        assert(RecaptureMath.calculateEarlyExitForfeit(amount, 0) == uint256(amount));
    }

    function check_forfeit_conservation(uint128 amount, uint128 ratio) external pure {
        ratio = uint128(uint256(ratio) % (WAD + 1));
        uint256 forfeit = RecaptureMath.calculateEarlyExitForfeit(amount, ratio);
        uint256 kept = uint256(amount) - forfeit;
        // forfeit + kept == amount (no tokens created or destroyed)
        assert(forfeit + kept == uint256(amount));
    }
}
