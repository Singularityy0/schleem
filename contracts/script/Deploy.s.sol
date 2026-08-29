// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { SupraPriceOracle } from "../src/SupraPriceOracle.sol";
import { SchmecklesMarket } from "../src/SchmecklesMarket.sol";
import { TestUSDC } from "../src/TestUSDC.sol";

interface VmScript {
    function envUint(string calldata name) external view returns (uint256);
    function addr(uint256 privateKey) external returns (address);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

contract Deploy {
    VmScript internal constant vm =
        VmScript(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant INITIAL_COLLATERAL = 10_000e6;
    address internal constant SUPRA_PULL_MONAD_TESTNET = 0xF8522B7fcE37439b98A2be282d413A44269028bE;
    uint256 internal constant MON_USDT_PAIR_ID = 569;
    uint256 internal constant USDT_USD_PAIR_ID = 48;

    function run()
        external
        returns (TestUSDC token, SupraPriceOracle oracle, SchmecklesMarket market)
    {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        token = new TestUSDC(deployer);
        oracle = new SupraPriceOracle(SUPRA_PULL_MONAD_TESTNET, MON_USDT_PAIR_ID, USDT_USD_PAIR_ID);
        market = new SchmecklesMarket(address(token), address(oracle), deployer, deployer);
        token.mint(deployer, INITIAL_COLLATERAL);
        token.approve(address(market), INITIAL_COLLATERAL);
        market.depositCollateral(INITIAL_COLLATERAL);
        vm.stopBroadcast();
    }
}
