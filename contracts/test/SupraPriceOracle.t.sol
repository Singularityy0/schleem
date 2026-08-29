// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ISupraOraclePull, SupraPriceOracle } from "../src/SupraPriceOracle.sol";
import { TestBase } from "./TestBase.sol";

contract TestSupraPull is ISupraOraclePull {
    uint256[] internal pairValues;
    uint256[] internal priceValues;
    uint256[] internal timestampValues;
    uint256[] internal decimalValues;
    uint256[] internal roundValues;
    bool public rejectProof;

    error InvalidProof();

    function setData(
        uint256[] memory pairs,
        uint256[] memory prices,
        uint256[] memory timestamps,
        uint256[] memory decimals,
        uint256[] memory rounds
    ) external {
        pairValues = pairs;
        priceValues = prices;
        timestampValues = timestamps;
        decimalValues = decimals;
        roundValues = rounds;
    }

    function setRejectProof(bool reject) external {
        rejectProof = reject;
    }

    function verifyOracleProofV2(bytes calldata) external view returns (PriceInfo memory info) {
        if (rejectProof) revert InvalidProof();
        info = PriceInfo({
            pairs: pairValues,
            prices: priceValues,
            timestamp: timestampValues,
            decimal: decimalValues,
            round: roundValues
        });
    }
}

contract SupraPriceOracleTest is TestBase {
    uint256 internal constant MON_USDT = 569;
    uint256 internal constant USDT_USD = 48;
    uint256 internal constant TEST_SECONDS = 1_000_000;

    TestSupraPull internal verifier;
    SupraPriceOracle internal oracle;

    function setUp() public {
        verifier = new TestSupraPull();
        oracle = new SupraPriceOracle(address(verifier), MON_USDT, USDT_USD);
        _setValidData(TEST_SECONDS * 1_000 + 123, TEST_SECONDS * 1_000 + 456);
        vm.warp(TEST_SECONDS + 1);
    }

    function testLiveProofDerivesEightDecimalMonUsdAndStoresIt() public {
        (uint256 price, uint64 publishTime) = oracle.updateLive(hex"01");
        assertEq(price, 2_716_000, "MON/USDT times USDT/USD is normalized to 8 decimals");
        assertEq(publishTime, TEST_SECONDS, "older composite timestamp is used");

        (uint256 storedPrice, uint64 storedTime) = oracle.latest();
        assertEq(storedPrice, price, "latest verified price stored");
        assertEq(storedTime, publishTime, "latest verified timestamp stored");
    }

    function testCompositeIncludesUsdtUsdInsteadOfAssumingPeg() public {
        _setData(
            _two(MON_USDT, USDT_USD),
            _two(27_160_000_000_000_000, 99_990_000),
            _two(TEST_SECONDS * 1_000, TEST_SECONDS * 1_000),
            _two(18, 8),
            _two(1, 1)
        );
        (uint256 price,) = oracle.updateLive(hex"02");
        assertEq(price, 2_715_728, "USDT/USD deviation changes composite");
    }

    function testLatestRejectsBeforeFirstVerifiedProof() public {
        SupraPriceOracle fresh = new SupraPriceOracle(address(verifier), MON_USDT, USDT_USD);
        vm.expectRevert(SupraPriceOracle.PriceUnavailable.selector);
        fresh.latest();
    }

    function testHistoricalRequiresBothFeedTimestampsInsideWindow() public {
        _setValidData(TEST_SECONDS * 1_000, (TEST_SECONDS + 2) * 1_000 + 1);
        vm.expectRevert(SupraPriceOracle.InvalidPublishTime.selector);
        oracle.parseHistorical(hex"03", uint64(TEST_SECONDS), uint64(TEST_SECONDS + 2));

        _setValidData(TEST_SECONDS * 1_000, (TEST_SECONDS + 2) * 1_000);
        (uint256 price, uint64 publishTime) =
            oracle.parseHistorical(hex"04", uint64(TEST_SECONDS), uint64(TEST_SECONDS + 2));
        assertEq(price, 2_716_000, "valid settlement price accepted");
        assertEq(publishTime, TEST_SECONDS, "composite uses older timestamp");
    }

    function testRejectsMissingAndDuplicatePairs() public {
        _setData(
            _one(MON_USDT),
            _one(27_160_000_000_000_000),
            _one(TEST_SECONDS * 1_000),
            _one(18),
            _one(1)
        );
        vm.expectRevert(abi.encodeWithSelector(SupraPriceOracle.MissingPair.selector, USDT_USD));
        oracle.updateLive(hex"05");

        _setData(
            _three(MON_USDT, MON_USDT, USDT_USD),
            _three(27_160_000_000_000_000, 27_160_000_000_000_000, 100_000_000),
            _three(TEST_SECONDS * 1_000, TEST_SECONDS * 1_000, TEST_SECONDS * 1_000),
            _three(18, 18, 8),
            _three(1, 1, 1)
        );
        vm.expectRevert(abi.encodeWithSelector(SupraPriceOracle.DuplicatePair.selector, MON_USDT));
        oracle.updateLive(hex"06");
    }

    function testRejectsMalformedZeroAndUnverifiedProofs() public {
        _setData(
            _two(MON_USDT, USDT_USD),
            _one(27_160_000_000_000_000),
            _two(TEST_SECONDS * 1_000, TEST_SECONDS * 1_000),
            _two(18, 8),
            _two(1, 1)
        );
        vm.expectRevert(SupraPriceOracle.InvalidProofShape.selector);
        oracle.updateLive(hex"07");

        _setData(
            _two(MON_USDT, USDT_USD),
            _two(0, 100_000_000),
            _two(TEST_SECONDS * 1_000, TEST_SECONDS * 1_000),
            _two(18, 8),
            _two(1, 1)
        );
        vm.expectRevert(SupraPriceOracle.InvalidPrice.selector);
        oracle.updateLive(hex"08");

        verifier.setRejectProof(true);
        vm.expectRevert(TestSupraPull.InvalidProof.selector);
        oracle.updateLive(hex"09");
    }

    function testRejectsUnsupportedDecimalsAndFutureLiveTimestamp() public {
        _setData(
            _two(MON_USDT, USDT_USD),
            _two(27_160_000_000_000_000, 100_000_000),
            _two(TEST_SECONDS * 1_000, TEST_SECONDS * 1_000),
            _two(37, 8),
            _two(1, 1)
        );
        vm.expectRevert(SupraPriceOracle.InvalidDecimals.selector);
        oracle.updateLive(hex"0a");

        _setValidData((TEST_SECONDS + 2) * 1_000, TEST_SECONDS * 1_000);
        vm.expectRevert(SupraPriceOracle.InvalidPublishTime.selector);
        oracle.updateLive(hex"0b");
    }

    function _setValidData(uint256 monTimestamp, uint256 usdtTimestamp) internal {
        _setData(
            _two(MON_USDT, USDT_USD),
            _two(27_160_000_000_000_000, 100_000_000),
            _two(monTimestamp, usdtTimestamp),
            _two(18, 8),
            _two(1, 1)
        );
    }

    function _setData(
        uint256[] memory pairs,
        uint256[] memory prices,
        uint256[] memory timestamps,
        uint256[] memory decimals,
        uint256[] memory rounds
    ) internal {
        verifier.setData(pairs, prices, timestamps, decimals, rounds);
    }

    function _one(uint256 a) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = a;
    }

    function _two(uint256 a, uint256 b) internal pure returns (uint256[] memory values) {
        values = new uint256[](2);
        values[0] = a;
        values[1] = b;
    }

    function _three(uint256 a, uint256 b, uint256 c)
        internal
        pure
        returns (uint256[] memory values)
    {
        values = new uint256[](3);
        values[0] = a;
        values[1] = b;
        values[2] = c;
    }
}
