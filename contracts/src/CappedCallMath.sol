// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Bounded capped-call payoff and disclosed risk-adjusted quote.
/// @dev Prices share any consistent decimal scale. Payouts use collateral decimals (mUSDC = 6).
library CappedCallMath {
    uint256 internal constant BPS = 10_000;

    error InvalidTerms();
    error MulDivOverflow();
    error QuoteAboveMaximumPayout();

    struct Quote {
        uint256 baseReference;
        uint256 jumpGuard;
        uint256 riskAdjusted;
        uint256 protocolFee;
        uint256 allIn;
        uint256 stressedPayoff;
    }

    function payoff(uint256 settlementPrice, uint256 strike, uint256 cap, uint256 maxPayout)
        internal
        pure
        returns (uint256)
    {
        if (strike == 0 || cap <= strike || maxPayout == 0) revert InvalidTerms();
        if (settlementPrice <= strike) return 0;
        if (settlementPrice >= cap) return maxPayout;
        return mulDiv(maxPayout, settlementPrice - strike, cap - strike);
    }

    /// @dev Jump Guard remains bounded because riskAdjusted is a convex combination of the
    /// Black-Scholes base reference and stressed payoff.
    function quote(
        uint256 baseReference,
        uint256 maxPayout,
        uint256 spot,
        uint256 strike,
        uint256 cap,
        uint256 jumpSizeBps,
        uint256 jumpWeightBps,
        uint256 feeBps
    ) internal pure returns (Quote memory result) {
        if (
            baseReference > maxPayout || jumpWeightBps > BPS || feeBps > BPS
                || jumpSizeBps > type(uint32).max
        ) revert InvalidTerms();

        uint256 stressedSpot = mulDiv(spot, BPS + jumpSizeBps, BPS);
        uint256 stressedPayoff = payoff(stressedSpot, strike, cap, maxPayout);
        uint256 guard;

        if (stressedPayoff > baseReference) {
            guard = mulDiv(stressedPayoff - baseReference, jumpWeightBps, BPS);
        }

        uint256 adjusted = baseReference + guard;
        uint256 fee = mulDivUp(adjusted, feeBps, BPS);
        if (fee > maxPayout - adjusted) fee = maxPayout - adjusted;
        uint256 allIn = adjusted + fee;

        result = Quote({
            baseReference: baseReference,
            jumpGuard: guard,
            riskAdjusted: adjusted,
            protocolFee: fee,
            allIn: allIn,
            stressedPayoff: stressedPayoff
        });
    }

    function mulDivUp(uint256 x, uint256 y, uint256 denominator)
        internal
        pure
        returns (uint256 result)
    {
        result = mulDiv(x, y, denominator);
        if (mulmod(x, y, denominator) != 0) {
            if (result == type(uint256).max) revert MulDivOverflow();
            result++;
        }
    }

    /// @dev Full-precision floor(x * y / denominator), based on Remco Bloemen's algorithm.
    function mulDiv(uint256 x, uint256 y, uint256 denominator)
        internal
        pure
        returns (uint256 result)
    {
        unchecked {
            uint256 prod0;
            uint256 prod1;
            assembly ("memory-safe") {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            if (prod1 == 0) {
                if (denominator == 0) revert MulDivOverflow();
                return prod0 / denominator;
            }
            if (denominator <= prod1) revert MulDivOverflow();

            uint256 remainder;
            assembly ("memory-safe") {
                remainder := mulmod(x, y, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            uint256 twos = denominator & (0 - denominator);
            assembly ("memory-safe") {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }
            prod0 |= prod1 * twos;

            uint256 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            result = prod0 * inverse;
        }
    }
}
