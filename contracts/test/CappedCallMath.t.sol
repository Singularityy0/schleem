// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { CappedCallMath } from "../src/CappedCallMath.sol";
import { TestBase } from "./TestBase.sol";

contract CappedCallMathHarness {
    function payoff(uint256 settlement, uint256 strike, uint256 cap, uint256 maxPayout)
        external
        pure
        returns (uint256)
    {
        return CappedCallMath.payoff(settlement, strike, cap, maxPayout);
    }

    function quote(
        uint256 baseReference,
        uint256 maxPayout,
        uint256 spot,
        uint256 strike,
        uint256 cap,
        uint256 jumpSizeBps,
        uint256 jumpWeightBps,
        uint256 feeBps
    ) external pure returns (CappedCallMath.Quote memory) {
        return CappedCallMath.quote(
            baseReference, maxPayout, spot, strike, cap, jumpSizeBps, jumpWeightBps, feeBps
        );
    }
}

contract CappedCallMathTest is TestBase {
    CappedCallMathHarness internal math;

    function setUp() public {
        math = new CappedCallMathHarness();
    }

    function testPayoffRegionsAndBoundaries() public view {
        uint256 strike = 400e8;
        uint256 cap = 404e8;
        uint256 maximum = 10e6;

        assertEq(math.payoff(399e8, strike, cap, maximum), 0, "below strike");
        assertEq(math.payoff(strike, strike, cap, maximum), 0, "at strike");
        assertEq(math.payoff(402e8, strike, cap, maximum), 5e6, "linear midpoint");
        assertEq(math.payoff(cap, strike, cap, maximum), maximum, "at cap");
        assertEq(math.payoff(500e8, strike, cap, maximum), maximum, "above cap");
    }

    function testJumpGuardIsBoundedConvexCombination() public view {
        CappedCallMath.Quote memory result =
            math.quote(250_000, 10e6, 400e8, 400e8, 404e8, 75, 1_000, 100);

        assertEq(result.stressedPayoff, 7_500_000, "stress payoff");
        assertEq(result.jumpGuard, 725_000, "10 percent stress loading");
        assertEq(result.riskAdjusted, 975_000, "adjusted price");
        assertEq(result.protocolFee, 9_750, "one percent fee");
        assertEq(result.allIn, 984_750, "all-in premium");
        assertTrue(result.riskAdjusted <= 10e6, "adjusted price bounded by maximum");
    }

    function testZeroJumpWeightReturnsBase() public view {
        CappedCallMath.Quote memory result =
            math.quote(250_000, 10e6, 400e8, 400e8, 404e8, 75, 0, 0);
        assertEq(result.riskAdjusted, result.baseReference, "zero weight must return base");
    }

    function testFuzzPayoffIsBoundedAndMonotone(uint96 randomA, uint96 randomB) public view {
        uint256 strike = 400e8;
        uint256 cap = 404e8;
        uint256 maximum = 10e6;
        uint256 a = uint256(randomA) % 1_000e8;
        uint256 b = uint256(randomB) % 1_000e8;
        if (a > b) (a, b) = (b, a);

        uint256 payoutA = math.payoff(a, strike, cap, maximum);
        uint256 payoutB = math.payoff(b, strike, cap, maximum);
        assertTrue(payoutA <= maximum, "first payout bounded");
        assertTrue(payoutB <= maximum, "second payout bounded");
        assertTrue(payoutA <= payoutB, "payoff monotone");
    }

    function testInvalidTermsRevert() public {
        vm.expectRevert(CappedCallMath.InvalidTerms.selector);
        math.payoff(100, 100, 100, 10e6);
    }
}

