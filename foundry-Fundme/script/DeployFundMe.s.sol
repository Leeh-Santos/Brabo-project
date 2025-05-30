// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {FundMe} from "../src/FundMe.sol";

contract DeployFundMe is Script {

    function run() external returns (FundMe) {

        HelperConfig helperConfig = new HelperConfig();
        //NetConfig memory config = helperConfig.activeNetConfig();
        //address ethPrice = config.PriceeFeed;
        address ethPrice = helperConfig.activeNetConfig(); // just like(, uint256, string)

        vm.startBroadcast(); //now gas stats to count
        //FundMe fundMe = new FundMe(helperConfig.activeNetConfig()); // so this can be done
        FundMe fundMe = new FundMe(ethPrice);
        vm.stopBroadcast();
        console.log("Deployed FundMe at address: ", address(fundMe));
        return fundMe;
    }
}

