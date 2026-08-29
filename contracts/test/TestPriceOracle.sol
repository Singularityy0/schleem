// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IPriceOracle } from "../src/IPriceOracle.sol";

/// @dev Deterministic oracle used only by unit tests for market accounting and timing.
contract TestPriceOracle is IPriceOracle {
    uint256 public price;
    uint64 public publishTime;
    uint256 public historicalPrice;
    uint64 public historicalPublishTime;

    constructor(uint256 initialPrice, uint64 initialPublishTime) {
        price = initialPrice;
        publishTime = initialPublishTime;
        historicalPrice = initialPrice;
        historicalPublishTime = initialPublishTime;
    }

    function submitPrice(uint256 nextPrice, uint64 nextPublishTime) external {
        price = nextPrice;
        publishTime = nextPublishTime;
        historicalPrice = nextPrice;
        historicalPublishTime = nextPublishTime;
    }

    function setHistorical(uint256 nextPrice, uint64 nextPublishTime) external {
        historicalPrice = nextPrice;
        historicalPublishTime = nextPublishTime;
    }

    function latest() external view returns (uint256, uint64) {
        return (price, publishTime);
    }

    function updateLive(bytes calldata) external returns (uint256, uint64) {
        return (price, publishTime);
    }

    function parseHistorical(bytes calldata, uint64, uint64) external returns (uint256, uint64) {
        return (historicalPrice, historicalPublishTime);
    }
}
