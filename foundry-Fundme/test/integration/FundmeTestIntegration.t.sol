// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

//import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../../src/FundMe.sol";
import {DeployFundMe} from "../../script/DeployFundMe.s.sol";
import {FundFundme, WithdrawFundme} from "../../script/Interactions.s.sol";

contract InteractionTest is Test{

    FundMe fundMe;
    uint256 constant private SEND_VALUE = 0.01 ether;
    uint256 constant private INITIAL_BUDGED = 10 ether;
    uint256 constant private GAS_PRICE = 1;


    address USER = makeAddr("lele"); // user to make fake call


    function setUp() external{
        DeployFundMe deploy = new DeployFundMe();
        fundMe = deploy.run();
        vm.deal(USER, INITIAL_BUDGED); // give money
    }

    //function testUsercanFund() public{ // call as a user 
    //   FundFundme fundFundme = new FundFundme();
    //    vm.prank(USER);
    //    vm.deal(USER, INITIAL_BUDGED);
//
    //   fundFundme.fundFundme(address(fundMe));
//
    //   address funder = fundMe.getFunders(0);
    //   assertEq(funder, USER);
    //}

    function testUsercanwithdraw() public{ // call as a user 
       FundFundme fundFundme = new FundFundme();
       vm.prank(USER);
        vm.deal(USER, INITIAL_BUDGED);
       fundFundme.fundFundme(address(fundMe));




        WithdrawFundme withdrawFundme = new WithdrawFundme();
        withdrawFundme.withdrawFundme(address(fundMe));

    
       assert(address(fundMe).balance == 0);
    }

       
   
}