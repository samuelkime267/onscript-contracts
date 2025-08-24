// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {OnscriptUserManagement} from "../src/OnscriptUserManagement.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployOnScriptUserManagement is Script {
    function run() external returns (OnscriptUserManagement, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address ethUsdPriceFeed, uint256 deployerKey, uint256 premiumUsdBase, address deployerAddress) =
            helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        OnscriptUserManagement onscriptUserManagement =
            new OnscriptUserManagement(deployerAddress, premiumUsdBase, ethUsdPriceFeed);
        vm.stopBroadcast();

        return (onscriptUserManagement, helperConfig);
    }
}
