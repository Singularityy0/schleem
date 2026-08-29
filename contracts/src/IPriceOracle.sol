// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Oracle surface consumed by the market.
/// @dev Both live and settlement observations are authenticated from a supplied proof.
interface IPriceOracle {
    function latest() external view returns (uint256 price, uint64 publishTime);

    function updateLive(bytes calldata proof) external returns (uint256 price, uint64 publishTime);

    function parseHistorical(bytes calldata proof, uint64 minPublishTime, uint64 maxPublishTime)
        external
        returns (uint256 price, uint64 publishTime);
}
