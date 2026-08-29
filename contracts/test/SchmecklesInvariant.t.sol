// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { TestUSDC } from "../src/TestUSDC.sol";
import { SchmecklesMarket } from "../src/SchmecklesMarket.sol";
import { TestBase } from "./TestBase.sol";
import { TestPriceOracle } from "./TestPriceOracle.sol";

contract SchmecklesAccountingInvariantTest is TestBase {
    address internal constant BUYER_A = address(0xA11CE);
    address internal constant BUYER_B = address(0xB0B);

    function testAccountingInvariantAcrossMultipleBuyersSettlementAndClaims() public {
        TestUSDC token = new TestUSDC(address(this));
        TestPriceOracle oracle = new TestPriceOracle(400e8, uint64(block.timestamp));
        SchmecklesMarket market =
            new SchmecklesMarket(address(token), address(oracle), address(this), address(this));

        token.mint(address(this), 500e6);
        token.approve(address(market), 500e6);
        market.depositCollateral(500e6);
        _fundAndApprove(token, market, BUYER_A);
        _fundAndApprove(token, market, BUYER_B);

        SchmecklesMarket.OpenParams memory params = SchmecklesMarket.OpenParams({
            capBps: 100,
            maxPayout: 10e6,
            pricingVolBps: 12_000,
            jumpSizeBps: 75,
            jumpWeightBps: 1_000,
            feeBps: 100
        });
        uint256 epochId = market.openEpoch(params);
        (, uint256 paymentA,) = market.quote(epochId, 2);
        (, uint256 paymentB,) = market.quote(epochId, 3);

        vm.prank(BUYER_A);
        market.buy(epochId, 2, paymentA);
        _assertAccounting(token, market);
        vm.prank(BUYER_B);
        market.buy(epochId, 3, paymentB);
        _assertAccounting(token, market);

        uint256 expiry = block.timestamp + market.EPOCH_DURATION();
        vm.warp(expiry);
        oracle.submitPrice(402e8, uint64(expiry));
        market.settle(epochId, "");
        _assertAccounting(token, market);

        vm.prank(BUYER_A);
        market.claim(epochId);
        _assertAccounting(token, market);
        vm.prank(BUYER_B);
        market.claim(epochId);
        _assertAccounting(token, market);
    }

    function _fundAndApprove(TestUSDC token, SchmecklesMarket market, address user) internal {
        token.mint(user, 100e6);
        vm.prank(user);
        token.approve(address(market), type(uint256).max);
    }

    function _assertAccounting(TestUSDC token, SchmecklesMarket market) internal view {
        uint256 balance = token.balanceOf(address(market));
        uint256 protected = market.reservedLiability() + market.claimableLiability()
            + market.refundableEscrow() + market.accruedProtocolFees();
        assertTrue(balance >= protected, "C >= R + L + E + F");
        assertTrue(market.isSolvent(), "reported solvent");
        assertEq(market.freeCollateral(), balance - protected, "free collateral identity");
    }
}
