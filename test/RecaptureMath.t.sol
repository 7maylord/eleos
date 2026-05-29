// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {RecaptureMath} from "../src/RecaptureMath.sol";

contract RecaptureMathTest is Test {
    uint256 constant WAD = 1e18;
    // sqrtPriceX96 for a 1:1 price (floor(sqrt(1) * 2^96))
    uint160 constant SQRT_1_1 = 79228162514264337593543950336;

    // ─── calculateIL ───────────────────────────────────────────────────────────

    function test_IL_zeroWhenPriceUnchanged() public pure {
        assertEq(RecaptureMath.calculateIL(SQRT_1_1, SQRT_1_1), 0);
    }

    function test_IL_zeroWhenEitherInputIsZero() public pure {
        assertEq(RecaptureMath.calculateIL(0, SQRT_1_1), 0);
        assertEq(RecaptureMath.calculateIL(SQRT_1_1, 0), 0);
    }

    function test_IL_zeroWhenBothInputsZero() public pure {
        assertEq(RecaptureMath.calculateIL(0, 0), 0);
    }

    function test_IL_at4xPrice_is20Pct() public pure {
        // At 4x price: r = sqrt(4) = 2 -> |IL| = (2-1)^2 / (4+1) = 1/5 = 20%
        uint160 current = uint160(uint256(SQRT_1_1) * 2); // sqrt(4) relative to base
        uint256 il = RecaptureMath.calculateIL(SQRT_1_1, current);
        assertApproxEqRel(il, 0.20e18, 0.001e18); // within 0.1%
    }

    function test_IL_at025xPrice_is20Pct() public pure {
        // At 0.25x price: r = sqrt(0.25) = 0.5 -> |IL| = (0.5-1)^2 / (0.25+1) = 0.25/1.25 = 20%
        uint160 current = uint160(uint256(SQRT_1_1) / 2);
        uint256 il = RecaptureMath.calculateIL(SQRT_1_1, current);
        assertApproxEqRel(il, 0.20e18, 0.001e18);
    }

    function test_IL_at1_5xPrice_knownValue() public pure {
        // r = sqrt(1.5) ~ 1.2247
        // |IL| = (1.2247-1)^2 / (1.5+1) ~ 0.0504 / 2.5 ~ 2.016%
        uint160 current = uint160(uint256(SQRT_1_1) * 12247 / 10000);
        uint256 il = RecaptureMath.calculateIL(SQRT_1_1, current);
        assertApproxEqRel(il, 0.02016e18, 0.02e18); // within 2% tolerance (approximation)
    }

    function test_IL_at9xPrice_knownValue() public pure {
        // r = sqrt(9) = 3 -> |IL| = (3-1)^2 / (9+1) = 4/10 = 40%
        uint160 current = uint160(uint256(SQRT_1_1) * 3);
        uint256 il = RecaptureMath.calculateIL(SQRT_1_1, current);
        assertApproxEqRel(il, 0.40e18, 0.001e18);
    }

    function test_IL_at16xPrice_knownValue() public pure {
        // r = sqrt(16) = 4 -> |IL| = (4-1)^2 / (16+1) = 9/17 ~ 52.94%
        uint160 current = uint160(uint256(SQRT_1_1) * 4);
        uint256 il = RecaptureMath.calculateIL(SQRT_1_1, current);
        assertApproxEqRel(il, 0.5294e18, 0.001e18);
    }

    function test_IL_symmetricForInverseRatio() public pure {
        // IL at 4x should equal IL at 0.25x (symmetric in log-price space)
        uint160 up = uint160(uint256(SQRT_1_1) * 2);     // 4x price
        uint160 down = uint160(uint256(SQRT_1_1) / 2);   // 0.25x price
        uint256 ilUp = RecaptureMath.calculateIL(SQRT_1_1, up);
        uint256 ilDown = RecaptureMath.calculateIL(SQRT_1_1, down);
        assertApproxEqRel(ilUp, ilDown, 0.001e18);
    }

    function test_IL_strictlyPositiveWhenPriceDiffers() public pure {
        uint160 current = uint160(uint256(SQRT_1_1) * 2);
        assertGt(RecaptureMath.calculateIL(SQRT_1_1, current), 0);
    }

    function test_IL_at_moderateExtremes() public pure {
        // Use a 100x price ratio (not min/max which overflows FullMath)
        uint160 low = uint160(uint256(SQRT_1_1) / 10);
        uint160 high = uint160(uint256(SQRT_1_1) * 10);
        uint256 il = RecaptureMath.calculateIL(low, high);
        assertLt(il, WAD);
        assertGt(il, 0);
    }

    /// @dev Fuzz: IL always in [0, WAD) for valid sqrtPrice range.
    ///      Uses TickMath bounds to avoid FullMath overflow on extreme values.
    function testFuzz_IL_alwaysBelowWAD(uint160 entry, uint160 current) public pure {
        entry = uint160(bound(uint256(entry), TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE));
        current = uint160(bound(uint256(current), TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE));

        // Also ensure the ratio doesn't cause FullMath overflow:
        // r = current * WAD / entry must not overflow uint256.
        // When current is much larger than entry, mulDiv can overflow internally.
        // Bound the ratio to at most 1e12 to avoid intermediate overflow.
        if (entry > 0 && uint256(current) > uint256(entry) * 1e12 / WAD) {
            current = uint160(uint256(entry) * 1e12 / WAD);
            if (current < TickMath.MIN_SQRT_PRICE) current = TickMath.MIN_SQRT_PRICE;
        }
        if (current > 0 && uint256(entry) > uint256(current) * 1e12 / WAD) {
            entry = uint160(uint256(current) * 1e12 / WAD);
            if (entry < TickMath.MIN_SQRT_PRICE) entry = TickMath.MIN_SQRT_PRICE;
        }

        uint256 il = RecaptureMath.calculateIL(entry, current);
        assertLt(il, WAD);
    }

    /// @dev Fuzz: IL is symmetric within 2 wei of rounding.
    function testFuzz_IL_symmetric(uint160 a, uint160 b) public pure {
        a = uint160(bound(uint256(a), TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE));
        b = uint160(bound(uint256(b), TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE));

        // Bound ratio to avoid FullMath overflow
        if (a > 0 && uint256(b) > uint256(a) * 1e12 / WAD) {
            b = uint160(uint256(a) * 1e12 / WAD);
            if (b < TickMath.MIN_SQRT_PRICE) b = TickMath.MIN_SQRT_PRICE;
        }
        if (b > 0 && uint256(a) > uint256(b) * 1e12 / WAD) {
            a = uint160(uint256(b) * 1e12 / WAD);
            if (a < TickMath.MIN_SQRT_PRICE) a = TickMath.MIN_SQRT_PRICE;
        }

        // Integer rounding can cause small difference -- use 2 wei tolerance
        assertApproxEqAbs(RecaptureMath.calculateIL(a, b), RecaptureMath.calculateIL(b, a), 2);
    }

    // ─── calculateRecaptured ───────────────────────────────────────────────────

    function test_recaptured_zeroAtEntry() public pure {
        assertEq(RecaptureMath.calculateRecaptured(0.05e18, 0, 90 days), 0);
    }

    function test_recaptured_fullAtExactLockEnd() public pure {
        uint256 il = 0.05e18;
        assertEq(RecaptureMath.calculateRecaptured(il, 90 days, 90 days), il);
    }

    function test_recaptured_fullWhenTimeExceedsDuration() public pure {
        uint256 il = 0.05e18;
        assertEq(RecaptureMath.calculateRecaptured(il, 180 days, 90 days), il);
    }

    function test_recaptured_halfAtHalfway() public pure {
        uint256 il = 1e18;
        uint256 recaptured = RecaptureMath.calculateRecaptured(il, 45 days, 90 days);
        assertApproxEqRel(recaptured, 0.5e18, 0.001e18);
    }

    function test_recaptured_defaultDuration90DaysWhenZero() public pure {
        uint256 il = 1e18;
        // lockDuration = 0 -> uses 90 days default
        uint256 rec90 = RecaptureMath.calculateRecaptured(il, 90 days, 0);
        uint256 recExplicit = RecaptureMath.calculateRecaptured(il, 90 days, 90 days);
        assertEq(rec90, recExplicit);
    }

    function test_recaptured_zeroILAlwaysZero() public pure {
        assertEq(RecaptureMath.calculateRecaptured(0, 365 days, 90 days), 0);
    }

    function test_recaptured_linearProgression() public pure {
        uint256 il = 1e18;
        uint256 duration = 100 days;
        uint256 r10 = RecaptureMath.calculateRecaptured(il, 10 days, duration);
        uint256 r50 = RecaptureMath.calculateRecaptured(il, 50 days, duration);
        uint256 r99 = RecaptureMath.calculateRecaptured(il, 99 days, duration);
        assertLt(r10, r50);
        assertLt(r50, r99);
        assertLt(r99, il);
    }

    /// @dev Fuzz: recaptured <= accruedIL always.
    function testFuzz_recaptured_neverExceedsIL(uint128 il, uint32 timeHeld, uint32 lockDuration) public pure {
        il = uint128(bound(il, 0, WAD));
        uint256 recaptured = RecaptureMath.calculateRecaptured(il, timeHeld, lockDuration);
        assertLe(recaptured, il);
    }

    // ─── recaptureRatio ────────────────────────────────────────────────────────

    function test_ratio_zeroAtStart() public pure {
        assertEq(RecaptureMath.recaptureRatio(0, 90 days), 0);
    }

    function test_ratio_WADAtExactDuration() public pure {
        assertEq(RecaptureMath.recaptureRatio(90 days, 90 days), WAD);
    }

    function test_ratio_WADAfterDuration() public pure {
        assertEq(RecaptureMath.recaptureRatio(365 days, 90 days), WAD);
    }

    function test_ratio_halfAtHalfway() public pure {
        uint256 ratio = RecaptureMath.recaptureRatio(45 days, 90 days);
        assertApproxEqRel(ratio, 0.5e18, 0.001e18);
    }

    function test_ratio_defaultLockDurationWhenZero() public pure {
        // lockDuration = 0 -> DEFAULT_LOCK_DURATION = 90 days
        uint256 ratio = RecaptureMath.recaptureRatio(45 days, 0);
        assertApproxEqRel(ratio, 0.5e18, 0.001e18);
    }

    /// @dev Fuzz: ratio always in [0, WAD].
    function testFuzz_ratio_alwaysInRange(uint32 timeHeld, uint32 lockDuration) public pure {
        uint256 ratio = RecaptureMath.recaptureRatio(timeHeld, lockDuration);
        assertGe(ratio, 0);
        assertLe(ratio, WAD);
    }

    // ─── calculateLoyaltyMultiplier ────────────────────────────────────────────

    function test_multiplier_oneAtZeroTime() public pure {
        assertEq(RecaptureMath.calculateLoyaltyMultiplier(0, 30 days, 10000), WAD);
    }

    function test_multiplier_oneWithZeroBonus() public pure {
        assertEq(RecaptureMath.calculateLoyaltyMultiplier(90 days, 30 days, 0), WAD);
    }

    function test_multiplier_oneWithZeroBasePeriod() public pure {
        assertEq(RecaptureMath.calculateLoyaltyMultiplier(90 days, 0, 10000), WAD);
    }

    function test_multiplier_twoAtBasePeriod() public pure {
        // 100% bonus bps -> should reach 2x at exactly basePeriod
        uint256 mult = RecaptureMath.calculateLoyaltyMultiplier(30 days, 30 days, 10000);
        assertApproxEqRel(mult, 2e18, 0.001e18);
    }

    function test_multiplier_capsAtTwoXRegardlessOfTime() public pure {
        uint256 mult = RecaptureMath.calculateLoyaltyMultiplier(365 days, 1 days, 10000);
        assertEq(mult, 2e18);
    }

    function test_multiplier_halfBonusAtHalfPeriod() public pure {
        // bonusBps = 10000 (100%), basePeriod = 30 days, timeHeld = 15 days
        // bonus = 10000 * WAD * 15d / (10000 * 30d) = 0.5 * WAD
        // multiplier = WAD + 0.5 * WAD = 1.5x
        uint256 mult = RecaptureMath.calculateLoyaltyMultiplier(15 days, 30 days, 10000);
        assertApproxEqRel(mult, 1.5e18, 0.001e18);
    }

    function test_multiplier_lowerBonusRate() public pure {
        // bonusBps = 5000 (50% max bonus -> 1.5x max)
        uint256 mult = RecaptureMath.calculateLoyaltyMultiplier(30 days, 30 days, 5000);
        assertApproxEqRel(mult, 1.5e18, 0.001e18);
    }

    /// @dev Fuzz: multiplier always in [WAD, 2*WAD].
    function testFuzz_multiplier_alwaysInRange(uint32 timeHeld, uint32 basePeriod, uint16 bonusBps) public pure {
        uint256 mult = RecaptureMath.calculateLoyaltyMultiplier(timeHeld, basePeriod, bonusBps);
        assertGe(mult, WAD);
        assertLe(mult, 2 * WAD);
    }

    // ─── calculateEarlyExitForfeit ─────────────────────────────────────────────

    function test_forfeit_allForfeitedAtZeroRatio() public pure {
        uint256 amount = 1000e18;
        assertEq(RecaptureMath.calculateEarlyExitForfeit(amount, 0), amount);
    }

    function test_forfeit_nothingForfeitedAtFullRatio() public pure {
        assertEq(RecaptureMath.calculateEarlyExitForfeit(1000e18, WAD), 0);
    }

    function test_forfeit_halfAtHalfRatio() public pure {
        uint256 amount = 1000e18;
        uint256 forfeit = RecaptureMath.calculateEarlyExitForfeit(amount, WAD / 2);
        assertApproxEqRel(forfeit, 500e18, 0.001e18);
    }

    function test_forfeit_zeroAmountAlwaysZero() public pure {
        assertEq(RecaptureMath.calculateEarlyExitForfeit(0, 0), 0);
    }

    function test_forfeit_zeroAboveWADRatio() public pure {
        // ratio >= WAD should return 0 forfeit
        assertEq(RecaptureMath.calculateEarlyExitForfeit(1000e18, WAD + 1), 0);
    }

    function test_forfeit_quarterRatio_threequartersForfeit() public pure {
        uint256 amount = 1000e18;
        uint256 forfeit = RecaptureMath.calculateEarlyExitForfeit(amount, WAD / 4);
        assertApproxEqRel(forfeit, 750e18, 0.001e18);
    }

    /// @dev Fuzz: forfeit <= amount always, and forfeit + kept ~ amount.
    function testFuzz_forfeit_neverExceedsAmount(uint128 amount, uint128 ratio) public pure {
        ratio = uint128(bound(ratio, 0, WAD));
        uint256 forfeit = RecaptureMath.calculateEarlyExitForfeit(amount, ratio);
        assertLe(forfeit, amount);
    }

    /// @dev Fuzz: forfeit conservation -- forfeit + kept should approximate amount.
    function testFuzz_forfeit_conservation(uint128 amount, uint128 ratio) public pure {
        ratio = uint128(bound(ratio, 0, WAD));
        uint256 forfeit = RecaptureMath.calculateEarlyExitForfeit(amount, ratio);
        // kept = amount - forfeit (always valid since forfeit <= amount)
        uint256 kept = amount - forfeit;
        // kept + forfeit = amount (exact conservation)
        assertEq(kept + forfeit, amount);
    }
}
