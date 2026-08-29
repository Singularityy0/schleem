// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { TestUSDC } from "../src/TestUSDC.sol";
import { TestBase } from "./TestBase.sol";

contract TestUSDCFaucetTest is TestBase {
    address internal constant USER = address(0xCAFE);
    TestUSDC internal token;

    function setUp() public {
        token = new TestUSDC(address(this));
        vm.warp(1_000_000);
    }

    function testFaucetMintsExactlyFiveHundredEveryTwentyFourHours() public {
        vm.prank(USER);
        token.faucet();
        assertEq(token.balanceOf(USER), 500e6, "first claim is 500 mUSDC");
        assertEq(token.nextFaucetAt(USER), 1_000_000 + 24 hours, "rolling unlock time");

        vm.warp(1_000_000 + 24 hours);
        vm.prank(USER);
        token.faucet();
        assertEq(token.balanceOf(USER), 1_000e6, "second daily claim accumulates");
    }

    function testFaucetRejectsEarlyRepeat() public {
        vm.prank(USER);
        token.faucet();

        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(TestUSDC.FaucetCooldown.selector, uint64(1_000_000 + 24 hours))
        );
        token.faucet();
    }
}
