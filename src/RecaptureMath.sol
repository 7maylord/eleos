// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

/// @title RecaptureMath
/// @notice Pure math library for IL calculation, recapture curves, and loyalty multipliers.
/// All values are WAD-scaled (1e18 = 100%) unless noted otherwise.
library RecaptureMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant MAX_MULTIPLIER = 2e18;
    uint256 internal constant DEFAULT_LOCK_DURATION = 90 days;

    // H-1: FullMath overflow guard for calculateIL.
    // rDiffSq = mulDiv(rDiff, rDiff, WAD) overflows uint256 when rDiff >= sqrt(uint256.max * WAD).
    // sqrt(uint256.max * WAD) ≈ 2^128 * 1e9. At that ratio IL is already indistinguishable from 100%.
    uint256 internal constant IL_OVERFLOW_GUARD = type(uint128).max * uint256(1e9);

    // ─── IL Calculation ────────────────────────────────────────────────────────

    /// @notice Computes IL as a WAD-scaled absolute value.
    /// @dev Uses the identity: IL = (r-1)^2 / (r^2+1) where r = currentSqrt/entrySqrt.
    ///      Derivation: standard IL = 2√k/(1+k) - 1, k = (currentSqrt/entrySqrt)^2 = r^2.
    ///      Absolute value: |IL| = 1 - 2r/(1+r^2) = (r-1)^2 / (r^2+1).
    ///      Returns a value in [0, WAD). IL is 0 when price is unchanged.
    function calculateIL(uint160 entrySqrtPrice, uint160 currentSqrtPrice)
        internal
        pure
        returns (uint256 il)
    {
        if (entrySqrtPrice == 0 || currentSqrtPrice == 0) return 0;
        if (entrySqrtPrice == currentSqrtPrice) return 0;

        // r = currentSqrtPrice * WAD / entrySqrtPrice  (WAD-scaled ratio)
        uint256 r = FullMath.mulDiv(uint256(currentSqrtPrice), WAD, uint256(entrySqrtPrice));

        // |r - WAD| then squared (divided by WAD to keep scale)
        uint256 rDiff = r > WAD ? r - WAD : WAD - r;

        // H-1 guard: if rDiff is large enough that rDiff² / WAD would overflow uint256,
        // the price ratio is extreme and IL is effectively 100%. Return WAD-1 to stay bounded.
        if (rDiff >= IL_OVERFLOW_GUARD) return WAD - 1;

        uint256 rDiffSq = FullMath.mulDiv(rDiff, rDiff, WAD);

        // r^2 / WAD
        uint256 rSq = FullMath.mulDiv(r, r, WAD);

        // IL = (r-1)^2 / (r^2 + 1)  →  rDiffSq * WAD / (rSq + WAD)
        il = FullMath.mulDiv(rDiffSq, WAD, rSq + WAD);
    }

    // ─── Recapture Curve ───────────────────────────────────────────────────────

    /// @notice Linear recapture: recaptured = accruedIL * min(timeHeld / duration, 1).
    /// @dev Phase 1 uses linear. Phase 2 replaces with exponential decay.
    function calculateRecaptured(uint256 accruedIL, uint256 timeHeld, uint256 lockDuration)
        internal
        pure
        returns (uint256 recaptured)
    {
        if (accruedIL == 0) return 0;
        uint256 duration = lockDuration == 0 ? DEFAULT_LOCK_DURATION : lockDuration;
        if (timeHeld >= duration) return accruedIL;
        recaptured = FullMath.mulDiv(accruedIL, timeHeld, duration);
    }

    /// @notice WAD-scaled ratio of time elapsed vs effective lock duration [0, WAD].
    function recaptureRatio(uint256 timeHeld, uint256 lockDuration)
        internal
        pure
        returns (uint256 ratio)
    {
        uint256 duration = lockDuration == 0 ? DEFAULT_LOCK_DURATION : lockDuration;
        if (timeHeld >= duration) return WAD;
        ratio = FullMath.mulDiv(timeHeld, WAD, duration);
    }

    // ─── Loyalty Multiplier ────────────────────────────────────────────────────

    /// @notice Loyalty multiplier in WAD. Increases linearly from 1x to 2x over basePeriod.
    /// @param timeHeld     Seconds the position has been open.
    /// @param basePeriod   Seconds at which the maximum bonus is reached.
    /// @param bonusBps     Max bonus in basis points (10000 = 100% extra → 2x at basePeriod).
    /// @return multiplier  WAD-scaled value in [WAD, 2*WAD].
    function calculateLoyaltyMultiplier(uint256 timeHeld, uint256 basePeriod, uint256 bonusBps)
        internal
        pure
        returns (uint256 multiplier)
    {
        if (timeHeld == 0 || basePeriod == 0 || bonusBps == 0) return WAD;
        // bonus (WAD) = bonusBps * WAD * timeHeld / (10000 * basePeriod)
        uint256 bonus = FullMath.mulDiv(bonusBps * WAD, timeHeld, 10000 * basePeriod);
        multiplier = WAD + bonus;
        if (multiplier > MAX_MULTIPLIER) multiplier = MAX_MULTIPLIER;
    }

    // ─── Early Exit ────────────────────────────────────────────────────────────

    /// @notice Tokens forfeited on early exit: forfeit = amount * (WAD - ratio) / WAD.
    /// @dev    Patient LPs implicitly benefit as vault balance is preserved for them.
    function calculateEarlyExitForfeit(uint256 amount, uint256 ratio)
        internal
        pure
        returns (uint256 forfeit)
    {
        if (ratio >= WAD) return 0;
        forfeit = FullMath.mulDiv(amount, WAD - ratio, WAD);
    }
}
