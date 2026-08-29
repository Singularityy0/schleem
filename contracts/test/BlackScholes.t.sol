// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BlackScholes } from "../src/BlackScholes.sol";
import { TestBase } from "./TestBase.sol";

contract BlackScholesHarness {
    function callSpread(
        uint256 spot,
        uint256 strike,
        uint256 cap,
        uint256 maxPayout,
        uint256 volatilityBps,
        uint256 secondsToExpiry
    ) external pure returns (uint256) {
        return BlackScholes.callSpreadPrice(
            spot, strike, cap, maxPayout, volatilityBps, secondsToExpiry
        );
    }

    function cdf(int256 x) external pure returns (uint256) {
        return BlackScholes.normalCdf(x);
    }

    function ln(uint256 x) external pure returns (int256) {
        return BlackScholes.lnWad(x);
    }
}

contract BlackScholesTest is TestBase {
    BlackScholesHarness internal pricing;

    function setUp() public {
        pricing = new BlackScholesHarness();
    }

    /// @dev Reference values generated independently with IEEE-754 Math.log/Math.exp and the
    /// same documented Abramowitz-Stegun CDF approximation, rounded to 6 collateral decimals.
    function testReferenceVectors() public view {
        assertApproxEqAbs(
            pricing.callSpread(4e8, 4e8, 404e6, 10e6, 12_000, 300),
            1_472_467,
            2_500,
            "ATM five-minute 120% vol vector"
        );
        assertApproxEqAbs(
            pricing.callSpread(402e6, 4e8, 404e6, 10e6, 12_000, 240),
            4_997_865,
            2_500,
            "mid-spread four-minute vector"
        );
        assertApproxEqAbs(
            pricing.callSpread(398e6, 4e8, 404e6, 10e6, 8_000, 300),
            19_200,
            1_000,
            "out-of-money low-vol vector"
        );
        assertApproxEqAbs(
            pricing.callSpread(404e6, 4e8, 404e6, 10e6, 15_000, 60),
            9_166_322,
            2_500,
            "at-cap one-minute vector"
        );
        assertApproxEqAbs(
            pricing.callSpread(100e8, 100e8, 101e8, 10e6, 5_000, 1 days),
            4_198_526,
            2_500,
            "one-day scale-invariance vector"
        );
    }

    function testExpiryConvergesToCappedIntrinsicPayoff() public view {
        assertEq(pricing.callSpread(399e6, 4e8, 404e6, 10e6, 12_000, 0), 0, "below");
        assertEq(pricing.callSpread(402e6, 4e8, 404e6, 10e6, 12_000, 0), 5e6, "mid");
        assertEq(pricing.callSpread(405e6, 4e8, 404e6, 10e6, 12_000, 0), 10e6, "cap");
    }

    function testNormalCdfAndLogReferencePoints() public view {
        assertApproxEqAbs(pricing.cdf(0), 500_000_000_000_000_000, 100_000_000_000, "N(0)");
        assertApproxEqAbs(pricing.cdf(1e18), 841_344_740_000_000_000, 100_000_000_000, "N(1)");
        uint256 lnTwo = uint256(pricing.ln(2e18));
        assertApproxEqAbs(lnTwo, 693_147_180_559_945_309, 100, "ln(2)");
    }
}
