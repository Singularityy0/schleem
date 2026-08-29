// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { CappedCallMath } from "./CappedCallMath.sol";
import { IPriceOracle } from "./IPriceOracle.sol";

interface ISupraOraclePull {
    struct PriceInfo {
        uint256[] pairs;
        uint256[] prices;
        uint256[] timestamp;
        uint256[] decimal;
        uint256[] round;
    }

    function verifyOracleProofV2(bytes calldata proof) external returns (PriceInfo memory priceInfo);
}

/// @notice Verifies Supra Pull proofs and derives MON/USD from MON/USDT x USDT/USD.
/// @dev Supra timestamps are milliseconds. The market consumes an 8-decimal composite price.
contract SupraPriceOracle is IPriceOracle {
    uint256 public constant PRICE_SCALE = 1e8;
    uint256 public constant WAD = 1e18;
    uint256 public constant MILLISECONDS_PER_SECOND = 1_000;
    uint256 public constant MAX_DECIMALS = 36;

    ISupraOraclePull public immutable supraPull;
    uint256 public immutable monUsdtPairId;
    uint256 public immutable usdtUsdPairId;

    uint256 private latestPrice;
    uint64 private latestPublishTime;

    error ZeroAddress();
    error InvalidPairId();
    error InvalidProofShape();
    error MissingPair(uint256 pairId);
    error DuplicatePair(uint256 pairId);
    error InvalidPrice();
    error InvalidDecimals();
    error InvalidPublishTime();
    error PriceUnavailable();

    event PriceVerified(
        uint256 indexed monUsdtPairId,
        uint256 indexed usdtUsdPairId,
        uint256 price,
        uint64 publishTime
    );

    constructor(address supraPull_, uint256 monUsdtPairId_, uint256 usdtUsdPairId_) {
        if (supraPull_ == address(0)) revert ZeroAddress();
        if (monUsdtPairId_ == 0 || usdtUsdPairId_ == 0 || monUsdtPairId_ == usdtUsdPairId_) {
            revert InvalidPairId();
        }
        supraPull = ISupraOraclePull(supraPull_);
        monUsdtPairId = monUsdtPairId_;
        usdtUsdPairId = usdtUsdPairId_;
    }

    function latest() external view returns (uint256 price, uint64 publishTime) {
        price = latestPrice;
        publishTime = latestPublishTime;
        if (price == 0 || publishTime == 0) revert PriceUnavailable();
    }

    function updateLive(bytes calldata proof) external returns (uint256 price, uint64 publishTime) {
        uint256 monTimestampMillis;
        uint256 usdtTimestampMillis;
        (price, monTimestampMillis, usdtTimestampMillis) = _verify(proof);
        uint64 monPublishTime = _toSeconds(monTimestampMillis);
        uint64 usdtPublishTime = _toSeconds(usdtTimestampMillis);
        if (monPublishTime > block.timestamp || usdtPublishTime > block.timestamp) {
            revert InvalidPublishTime();
        }
        publishTime = monPublishTime < usdtPublishTime ? monPublishTime : usdtPublishTime;
        latestPrice = price;
        latestPublishTime = publishTime;
        emit PriceVerified(monUsdtPairId, usdtUsdPairId, price, publishTime);
    }

    function parseHistorical(bytes calldata proof, uint64 minPublishTime, uint64 maxPublishTime)
        external
        returns (uint256 price, uint64 publishTime)
    {
        if (minPublishTime > maxPublishTime) revert InvalidPublishTime();
        uint256 monTimestampMillis;
        uint256 usdtTimestampMillis;
        (price, monTimestampMillis, usdtTimestampMillis) = _verify(proof);
        uint256 minTimestampMillis = uint256(minPublishTime) * MILLISECONDS_PER_SECOND;
        uint256 maxTimestampMillis = uint256(maxPublishTime) * MILLISECONDS_PER_SECOND;
        if (
            monTimestampMillis < minTimestampMillis || monTimestampMillis > maxTimestampMillis
                || usdtTimestampMillis < minTimestampMillis
                || usdtTimestampMillis > maxTimestampMillis
        ) revert InvalidPublishTime();
        uint64 monPublishTime = _toSeconds(monTimestampMillis);
        uint64 usdtPublishTime = _toSeconds(usdtTimestampMillis);
        publishTime = monPublishTime < usdtPublishTime ? monPublishTime : usdtPublishTime;
    }

    function _verify(bytes calldata proof)
        internal
        returns (uint256 price, uint256 monTimestampMillis, uint256 usdtTimestampMillis)
    {
        ISupraOraclePull.PriceInfo memory info = supraPull.verifyOracleProofV2(proof);
        uint256 length = info.pairs.length;
        if (
            length == 0 || info.prices.length != length || info.timestamp.length != length
                || info.decimal.length != length || info.round.length != length
        ) revert InvalidProofShape();

        bool foundMon;
        bool foundUsdt;
        uint256 monPrice;
        uint256 usdtPrice;
        uint256 monDecimals;
        uint256 usdtDecimals;

        for (uint256 i; i < length; ++i) {
            if (info.pairs[i] == monUsdtPairId) {
                if (foundMon) revert DuplicatePair(monUsdtPairId);
                foundMon = true;
                monPrice = info.prices[i];
                monDecimals = info.decimal[i];
                monTimestampMillis = info.timestamp[i];
            } else if (info.pairs[i] == usdtUsdPairId) {
                if (foundUsdt) revert DuplicatePair(usdtUsdPairId);
                foundUsdt = true;
                usdtPrice = info.prices[i];
                usdtDecimals = info.decimal[i];
                usdtTimestampMillis = info.timestamp[i];
            }
        }

        if (!foundMon) revert MissingPair(monUsdtPairId);
        if (!foundUsdt) revert MissingPair(usdtUsdPairId);
        if (monPrice == 0 || usdtPrice == 0) revert InvalidPrice();

        uint256 monWad = _toWad(monPrice, monDecimals);
        uint256 usdtWad = _toWad(usdtPrice, usdtDecimals);
        price = CappedCallMath.mulDiv(monWad, usdtWad, 1e28);
        if (price == 0) revert InvalidPrice();
    }

    function _toWad(uint256 value, uint256 decimals) internal pure returns (uint256) {
        if (decimals > MAX_DECIMALS) revert InvalidDecimals();
        if (decimals <= 18) return value * (10 ** (18 - decimals));
        return value / (10 ** (decimals - 18));
    }

    function _toSeconds(uint256 milliseconds) internal pure returns (uint64 seconds_) {
        uint256 secondsValue = milliseconds / MILLISECONDS_PER_SECOND;
        if (secondsValue == 0 || secondsValue > type(uint64).max) revert InvalidPublishTime();
        seconds_ = uint64(secondsValue);
    }
}
