//SPDX-License-identifier: MIT

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {DevOpsTools} from "../lib/foundry-devops/src/DevOpsTools.sol";
import {FundMe} from "../src/FundMe.sol";
//import {DeployFundMe} from "../../script/DeployFundMe.s.sol";

//TWO CONTRACTS INTERACTION HERE
contract FundFundme is Script {

    uint256 constant private SEND_VALUE = 0.1 ether;

    function fundFundme(address recentDeploy) public {
        
        FundMe(payable(address(recentDeploy))).fund{value: SEND_VALUE}();

    }

    function run() external{
        vm.startBroadcast();
         // NEXT line WILL BE SENT/called BY USER

        address mostRecentDeploy = DevOpsTools.get_most_recent_deployment("FundeMe", block.chainid);
        fundFundme(mostRecentDeploy);

        vm.stopBroadcast();
    }
}

contract WithdrawFundme is Script{

    
    uint256 constant private SEND_VALUE = 0.1 ether;

    function withdrawFundme(address recentDeploy) public {
        vm.startBroadcast();
        FundMe(payable(recentDeploy)).withdraw();
         vm.stopBroadcast();

    }

    function run() external{
         // NEXT line WILL BE SENT/called BY USER
        address mostRecentDeploy = DevOpsTools.get_most_recent_deployment("FundeMe", block.chainid);
        withdrawFundme(mostRecentDeploy);
    }

}