// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { CappedCallMath } from "../src/CappedCallMath.sol";
import { TestUSDC } from "../src/TestUSDC.sol";
import { SchmecklesMarket } from "../src/SchmecklesMarket.sol";
import { TestBase } from "./TestBase.sol";
import { TestPriceOracle } from "./TestPriceOracle.sol";

contract SchmecklesMarketTest is TestBase {
    uint256 internal constant PRICE = 400e8;
    uint256 internal constant SEED = 1_000e6;
    address internal constant BUYER = address(0xBEEF);

    TestUSDC internal token;
    TestPriceOracle internal oracle;
    SchmecklesMarket internal market;

    function setUp() public {
        token = new TestUSDC(address(this));
        oracle = new TestPriceOracle(PRICE, uint64(block.timestamp));
        market = new SchmecklesMarket(address(token), address(oracle), address(this), address(this));

        token.mint(address(this), SEED);
        token.approve(address(market), SEED);
        market.depositCollateral(SEED);

        token.mint(BUYER, 1_000e6);
        vm.prank(BUYER);
        token.approve(address(market), type(uint256).max);
    }

    function testBuyReservesMaximumBeforeAcceptingPayment() public {
        uint256 epochId = _openEpoch();
        (, uint256 payment,) = market.quote(epochId, 2);

        vm.prank(BUYER);
        market.buy(epochId, 2, payment);

        assertEq(market.reservedLiability(), 20e6, "two exact maximum payouts reserved");
        assertEq(market.refundableEscrow(), payment, "entire payment escrowed");
        assertEq(token.balanceOf(address(market)), SEED + payment, "payment received");
        assertEq(market.freeCollateral(), SEED - 20e6, "incoming payment is not free collateral");
        assertTrue(market.isSolvent(), "market remains solvent");
    }

    function testIncomingPremiumCannotFundItsOwnReserve() public {
        TestPriceOracle secondOracle = new TestPriceOracle(PRICE, uint64(block.timestamp));
        SchmecklesMarket emptyMarket = new SchmecklesMarket(
            address(token), address(secondOracle), address(this), address(this)
        );
        SchmecklesMarket.OpenParams memory params = _params();
        uint256 epochId = emptyMarket.openEpoch(params);
        (, uint256 payment,) = emptyMarket.quote(epochId, 1);

        vm.prank(BUYER);
        token.approve(address(emptyMarket), payment);
        vm.prank(BUYER);
        vm.expectRevert(SchmecklesMarket.InsufficientFreeCollateral.selector);
        emptyMarket.buy(epochId, 1, payment);
    }

    function testSettlementConvertsReserveToExactClaimLiability() public {
        uint256 epochId = _openEpoch();
        (CappedCallMath.Quote memory perTicket, uint256 payment,) = market.quote(epochId, 2);
        vm.prank(BUYER);
        market.buy(epochId, 2, payment);

        uint256 buyerBeforeClaim = token.balanceOf(BUYER);
        uint256 expiry = block.timestamp + market.EPOCH_DURATION();
        vm.warp(expiry);
        oracle.submitPrice(404e8, uint64(expiry));
        market.settle(epochId, "");

        assertEq(market.reservedLiability(), 0, "maximum reserve released");
        assertEq(market.refundableEscrow(), 0, "payment escrow resolved");
        assertEq(market.claimableLiability(), 20e6, "full capped payout protected");
        assertEq(
            market.accruedProtocolFees(), perTicket.protocolFee * 2, "fees recognized only now"
        );

        vm.prank(BUYER);
        uint256 claimed = market.claim(epochId);
        assertEq(claimed, 20e6, "buyer claim");
        assertEq(market.claimableLiability(), 0, "claim liability cleared");
        assertEq(token.balanceOf(BUYER), buyerBeforeClaim + 20e6, "claim transferred");
        assertTrue(market.isSolvent(), "market remains solvent after claim");
    }

    function testCancellationReleasesReserveAndRefundsFullPayment() public {
        uint256 epochId = _openEpoch();
        (, uint256 payment,) = market.quote(epochId, 3);
        uint256 buyerStart = token.balanceOf(BUYER);
        vm.prank(BUYER);
        market.buy(epochId, 3, payment);

        uint256 deadline = block.timestamp + market.EPOCH_DURATION() + market.SETTLEMENT_TIMEOUT();
        vm.warp(deadline + 1);
        market.cancel(epochId);

        assertEq(market.reservedLiability(), 0, "reserve released on cancellation");
        assertEq(market.refundableEscrow(), payment, "payment stays refundable");
        assertEq(market.accruedProtocolFees(), 0, "no fee earned on cancellation");

        vm.prank(BUYER);
        uint256 refunded = market.refund(epochId);
        assertEq(refunded, payment, "full payment refunded");
        assertEq(token.balanceOf(BUYER), buyerStart, "buyer made whole");
        assertEq(market.refundableEscrow(), 0, "refund liability cleared");
    }

    function testOwnerCannotWithdrawProtectedLiabilities() public {
        uint256 epochId = _openEpoch();
        (, uint256 payment,) = market.quote(epochId, 2);
        vm.prank(BUYER);
        market.buy(epochId, 2, payment);

        uint256 free = market.freeCollateral();
        market.withdrawFreeCollateral(address(this), free);
        assertTrue(market.isSolvent(), "exact protected balance remains");
        vm.expectRevert(SchmecklesMarket.InsufficientFreeCollateral.selector);
        market.withdrawFreeCollateral(address(this), 1);
    }

    function testTradingClosesThirtySecondsBeforeExpiry() public {
        uint256 epochId = _openEpoch();
        vm.warp(block.timestamp + market.EPOCH_DURATION() - market.TRADING_CLOSE_BUFFER());
        assertEq(
            uint256(market.epochStatus(epochId)),
            uint256(SchmecklesMarket.EpochStatus.Locked),
            "market locked"
        );
        vm.prank(BUYER);
        vm.expectRevert(SchmecklesMarket.InvalidEpochState.selector);
        market.buy(epochId, 1, 10e6);
    }

    function testSettlementRejectsReportOutsideExpiryWindow() public {
        uint256 epochId = _openEpoch();
        uint256 expiry = block.timestamp + market.EPOCH_DURATION();
        uint256 outsideWindow = expiry + market.SETTLEMENT_OBSERVATION_WINDOW() + 1;
        vm.warp(outsideWindow);
        oracle.submitPrice(404e8, uint64(outsideWindow));
        vm.expectRevert(SchmecklesMarket.InvalidSettlementObservation.selector);
        market.settle(epochId, "");
    }

    function testSettlementAcceptsReportAtWindowUpperBound() public {
        uint256 epochId = _openEpoch();
        uint256 expiry = block.timestamp + market.EPOCH_DURATION();
        uint256 upperBound = expiry + market.SETTLEMENT_OBSERVATION_WINDOW();
        vm.warp(upperBound);
        oracle.submitPrice(404e8, uint64(upperBound));

        market.settle(epochId, "");

        assertEq(
            uint256(market.epochStatus(epochId)),
            uint256(SchmecklesMarket.EpochStatus.Settled),
            "upper-bound observation settles"
        );
    }

    function testOpenRejectsStaleAndFutureLivePrices() public {
        vm.warp(1_000);
        oracle.submitPrice(PRICE, 939);
        vm.expectRevert(SchmecklesMarket.StalePrice.selector);
        market.openEpoch(_params());

        oracle.submitPrice(PRICE, 1_001);
        vm.expectRevert(SchmecklesMarket.FuturePrice.selector);
        market.openEpoch(_params());
    }

    function testSettlementRequiresKeeper() public {
        uint256 epochId = _openEpoch();
        uint256 expiry = block.timestamp + market.EPOCH_DURATION();
        vm.warp(expiry);
        oracle.submitPrice(404e8, uint64(expiry));

        vm.prank(BUYER);
        vm.expectRevert(SchmecklesMarket.Unauthorized.selector);
        market.settle(epochId, "");

        market.settle(epochId, "");
        assertEq(
            uint256(market.epochStatus(epochId)),
            uint256(SchmecklesMarket.EpochStatus.Settled),
            "verified proof path settles"
        );
    }

    function _openEpoch() internal returns (uint256) {
        oracle.submitPrice(PRICE, uint64(block.timestamp));
        return market.openEpoch(_params());
    }

    function _params() internal pure returns (SchmecklesMarket.OpenParams memory) {
        return SchmecklesMarket.OpenParams({
            capBps: 100,
            maxPayout: 10e6,
            pricingVolBps: 12_000,
            jumpSizeBps: 75,
            jumpWeightBps: 1_000,
            feeBps: 100
        });
    }
}
