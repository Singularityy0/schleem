// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Fixed-point Black-Scholes pricing for a zero-rate European call spread.
/// @dev Internal calculations use signed 18-decimal WAD arithmetic. External prices may use any
///      common scale. The approximation is intended for transparent testnet quoting, not unaudited
///      mainnet risk management.
library BlackScholes {
    int256 internal constant WAD_INT = 1e18;
    uint256 internal constant WAD = 1e18;
    uint256 internal constant YEAR = 365 days;
    int256 internal constant LN_2 = 693_147_180_559_945_309;
    int256 internal constant INV_SQRT_2PI = 398_942_280_401_432_677;

    int256 internal constant CDF_P = 231_641_900_000_000_000;
    int256 internal constant CDF_B1 = 319_381_530_000_000_000;
    int256 internal constant CDF_B2 = -356_563_782_000_000_000;
    int256 internal constant CDF_B3 = 1_781_477_937_000_000_000;
    int256 internal constant CDF_B4 = -1_821_255_978_000_000_000;
    int256 internal constant CDF_B5 = 1_330_274_429_000_000_000;

    error InvalidBlackScholesInputs();
    error SignedMathOverflow();

    /// @notice Fair value of M/(cap-strike) * (call(strike) - call(cap)).
    /// @param spot Current underlying price.
    /// @param strike Lower call strike.
    /// @param cap Upper call strike.
    /// @param maxPayout Collateral-denominated maximum ticket payout.
    /// @param volatilityBps Annualized volatility in basis points (10_000 = 100%).
    /// @param secondsToExpiry Remaining time to expiry.
    function callSpreadPrice(
        uint256 spot,
        uint256 strike,
        uint256 cap,
        uint256 maxPayout,
        uint256 volatilityBps,
        uint256 secondsToExpiry
    ) internal pure returns (uint256) {
        if (spot == 0 || strike == 0 || cap <= strike || maxPayout == 0 || volatilityBps == 0) revert InvalidBlackScholesInputs();

        if (secondsToExpiry == 0) {
            if (spot <= strike) return 0;
            if (spot >= cap) return maxPayout;
            return maxPayout * (spot - strike) / (cap - strike);
        }

        uint256 spotWad = spot * WAD / strike;
        uint256 capWad = cap * WAD / strike;
        uint256 strikeWad = WAD;
        uint256 sigmaWad = volatilityBps * 1e14;
        uint256 timeWad = secondsToExpiry * WAD / YEAR;

        uint256 lowerCall = _callPriceWad(spotWad, strikeWad, sigmaWad, timeWad);
        uint256 upperCall = _callPriceWad(spotWad, capWad, sigmaWad, timeWad);
        if (lowerCall <= upperCall) return 0;

        uint256 normalized = (lowerCall - upperCall) * WAD / (capWad - strikeWad);
        if (normalized >= WAD) return maxPayout;
        return maxPayout * normalized / WAD;
    }

    function _callPriceWad(uint256 spotWad, uint256 strikeWad, uint256 sigmaWad, uint256 timeWad)
        private
        pure
        returns (uint256)
    {
        uint256 sqrtTime = sqrt(timeWad * WAD);
        uint256 sigmaSqrtTime = sigmaWad * sqrtTime / WAD;
        if (sigmaSqrtTime == 0) {
            return spotWad > strikeWad ? spotWad - strikeWad : 0;
        }

        int256 logMoneyness = lnWad(spotWad * WAD / strikeWad);
        uint256 variance = sigmaWad * sigmaWad / WAD;
        int256 halfVarianceTime = int256(variance * timeWad / WAD / 2);
        int256 d1 = (logMoneyness + halfVarianceTime) * WAD_INT / int256(sigmaSqrtTime);
        int256 d2 = d1 - int256(sigmaSqrtTime);

        uint256 discountedSpot = spotWad * normalCdf(d1) / WAD;
        uint256 discountedStrike = strikeWad * normalCdf(d2) / WAD;
        return discountedSpot > discountedStrike ? discountedSpot - discountedStrike : 0;
    }

    /// @notice Standard normal cumulative distribution approximation in WAD.
    function normalCdf(int256 x) internal pure returns (uint256) {
        if (x <= -12 * WAD_INT) return 0;
        if (x >= 12 * WAD_INT) return WAD;

        uint256 absolute = uint256(x < 0 ? -x : x);
        int256 t = int256(WAD * WAD / uint256(WAD_INT + _mulWad(CDF_P, int256(absolute))));

        int256 polynomial = CDF_B5;
        polynomial = CDF_B4 + _mulWad(polynomial, t);
        polynomial = CDF_B3 + _mulWad(polynomial, t);
        polynomial = CDF_B2 + _mulWad(polynomial, t);
        polynomial = CDF_B1 + _mulWad(polynomial, t);
        polynomial = _mulWad(polynomial, t);

        uint256 square = absolute * absolute / WAD;
        uint256 density = uint256(_mulWad(INV_SQRT_2PI, expWad(-int256(square / 2))));
        uint256 tail = density * uint256(polynomial) / WAD;
        uint256 positiveCdf = tail >= WAD ? 0 : WAD - tail;
        return x < 0 ? WAD - positiveCdf : positiveCdf;
    }

    /// @notice Natural logarithm for a positive WAD value.
    function lnWad(uint256 x) internal pure returns (int256 result) {
        if (x == 0) revert InvalidBlackScholesInputs();

        int256 binaryExponent;
        while (x >= 2 * WAD) {
            x /= 2;
            binaryExponent++;
        }
        while (x < WAD) {
            x *= 2;
            binaryExponent--;
        }

        int256 y = int256((x - WAD) * WAD / (x + WAD));
        int256 ySquared = _mulWad(y, y);
        int256 term = y;
        int256 series = term;
        for (uint256 denominator = 3; denominator <= 39; denominator += 2) {
            term = _mulWad(term, ySquared);
            series += term / int256(denominator);
        }
        result = binaryExponent * LN_2 + 2 * series;
    }

    /// @notice Exponential of a signed WAD value.
    function expWad(int256 x) internal pure returns (int256) {
        if (x <= -60 * WAD_INT) return 0;
        if (x >= 60 * WAD_INT) revert SignedMathOverflow();

        int256 binaryExponent = x / LN_2;
        int256 remainder = x - binaryExponent * LN_2;
        int256 term = WAD_INT;
        int256 sum = WAD_INT;
        for (uint256 i = 1; i <= 24; i++) {
            term = _mulWad(term, remainder) / int256(i);
            sum += term;
        }
        if (sum < 0) revert SignedMathOverflow();

        if (binaryExponent >= 0) {
            return sum * int256(2 ** uint256(binaryExponent));
        }
        return sum / int256(2 ** uint256(-binaryExponent));
    }

    function sqrt(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) return 0;
        z = 1;
        uint256 y = x;
        if (y >= 2 ** 128) {
            y >>= 128;
            z <<= 64;
        }
        if (y >= 2 ** 64) {
            y >>= 64;
            z <<= 32;
        }
        if (y >= 2 ** 32) {
            y >>= 32;
            z <<= 16;
        }
        if (y >= 2 ** 16) {
            y >>= 16;
            z <<= 8;
        }
        if (y >= 2 ** 8) {
            y >>= 8;
            z <<= 4;
        }
        if (y >= 2 ** 4) {
            y >>= 4;
            z <<= 2;
        }
        if (y >= 2 ** 2) z <<= 1;
        for (uint256 i = 0; i < 7; i++) {
            z = (z + x / z) >> 1;
        }
        uint256 roundedDown = x / z;
        return z < roundedDown ? z : roundedDown;
    }

    function _mulWad(int256 x, int256 y) private pure returns (int256) {
        return x * y / WAD_INT;
    }
}
