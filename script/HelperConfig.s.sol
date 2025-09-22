// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 4923e8;
    uint256 public constant DEFAULT_PREMIUM_USD_BASE = 1;
    uint256 public constant DEFAULT_PLUS_PRICE_USD_BASE = 10;

    struct NetworkConfig {
        address ethUsdPriceFeed;
        uint256 deployerKey;
        uint256 premiumUsdBase;
        address deployerAddress;
        uint256 plusPriceUsdBase;
    }

    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 84532) {
            activeNetworkConfig = getBaseSepoliaEthConfig();
        } else if (block.chainid == 8453) {
            activeNetworkConfig = getBaseEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getBaseSepoliaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerKey);

        sepoliaNetworkConfig = NetworkConfig({
            ethUsdPriceFeed: 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1,
            deployerKey: deployerKey,
            premiumUsdBase: DEFAULT_PREMIUM_USD_BASE,
            deployerAddress: deployerAddress,
            plusPriceUsdBase: DEFAULT_PLUS_PRICE_USD_BASE
        });
    }

    function getBaseEthConfig() public view returns (NetworkConfig memory baseNetworkConfig) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerKey);
        baseNetworkConfig = NetworkConfig({
            ethUsdPriceFeed: 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70,
            deployerKey: deployerKey,
            premiumUsdBase: DEFAULT_PREMIUM_USD_BASE,
            deployerAddress: deployerAddress,
            plusPriceUsdBase: DEFAULT_PLUS_PRICE_USD_BASE
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        if (activeNetworkConfig.ethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        address deployerAddress = vm.addr(DEFAULT_ANVIL_PRIVATE_KEY);

        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            ethUsdPriceFeed: address(ethUsdPriceFeed), // ETH/USD mock for Anvil
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY,
            premiumUsdBase: DEFAULT_PREMIUM_USD_BASE,
            deployerAddress: deployerAddress,
            plusPriceUsdBase: DEFAULT_PLUS_PRICE_USD_BASE
        });
    }
}
