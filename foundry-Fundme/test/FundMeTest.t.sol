// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../src/FundMe.sol";
import {DeployFundMe} from "../script/DeployFundMe.s.sol";

contract FundMeTest is Test{
    
    FundMe fundMe;
    
    uint256 constant private SEND_VALUE = 0.1 ether;
    uint256 constant private INITIAL_BUDGED = 10 ether;
    uint256 constant private GAS_PRICE = 1;
    address USER = makeAddr("lele"); // user to make fake calls

    function setUp() external{
        DeployFundMe deployFundMe = new DeployFundMe();
        fundMe = deployFundMe.run();
        vm.deal(USER, INITIAL_BUDGED); // give money
        console.log("FundMe contract address: ", address(fundMe));
    }

    function testMinimun() view public{
       assertEq(fundMe.getOwner(), msg.sender);
       console.log("FundMe contract address: ", address(fundMe));
    }

    function testversion() view public{
        uint256 version = fundMe.getVersion();
        assertEq(fundMe.getVersion(), version);
    }

    function testFundfail()  public{
        vm.expectRevert();
        fundMe.fund(); // this should fail due to experted revert
    }

    function testFundUpdatesDataStruct() public{
        vm.prank(USER); // NEXT CALL WILL BE SENT BY USER
        fundMe.fund{value: SEND_VALUE}();
        
        uint256 amountFunded = fundMe.getHowMuchDudeFunded(USER);
        assertEq(amountFunded, SEND_VALUE);
    }

    function testFundersBeingUpdated() public{ 
        vm.prank(USER); // NEXT line WILL BE SENT/called BY USER
        fundMe.fund{value: SEND_VALUE}();
        address funder = fundMe.getFunders(0);
        assertEq(funder, USER);
    }

    function testOnlyOwner() public fundFakeUser {
    
        vm.expectRevert();
        vm.prank(USER); //// user is not the contract owner
        fundMe.withdraw();
    }

    modifier fundFakeUser() { //since resets apparantly
        vm.prank(USER); // NEXT line WILL BE SENT/called BY USER
        fundMe.fund{value: SEND_VALUE}();
        _;
    }

    function testWithdraw() public fundFakeUser{
        uint256 startOwnBalance = fundMe.getOwner().balance;
        uint256 startContractBalance = address(fundMe).balance;

        uint256 gasStart = gasleft();
        console.log("Gas start: ", gasStart);
        vm.txGasPrice(GAS_PRICE); //this make gas work in anvil
        vm.prank(fundMe.getOwner()); // NEXT line WILL BE SENT/called BY OWNER
        fundMe.withdraw();

        uint256 gasEnd = gasleft();
        console.log("Gas end: ", gasEnd);
        uint256 gasUsed = (gasStart - gasEnd) * tx.gasprice; // se how much withdarw cost

        console.log("Gas used: ", gasUsed);

        uint256 endOwnBalance = fundMe.getOwner().balance;
        uint256 endContractBalance = address(fundMe).balance;

        assertEq(endContractBalance, 0);
        assertEq(endOwnBalance, startOwnBalance + startContractBalance);    

    }

    function testWithdrawMuiltipleDonators() public fundFakeUser {

        for(uint160 i = 1; i < 10; i++){ // since we already donated once with funcFake user 
            hoax(address(i), SEND_VALUE); // creates fake users and add balance to them and does vm.prank
            fundMe.fund{value: SEND_VALUE}();
        }

        uint256 startOwnBalance = fundMe.getOwner().balance;
        uint256 startContractBalance = address(fundMe).balance;

        vm.prank(fundMe.getOwner()); // NEXT line WILL BE SENT/called BY OWNER
        FundMe(fundMe).withdraw();

        assertEq(address(fundMe).balance, 0);
        assertEq(fundMe.getOwner().balance, startOwnBalance + startContractBalance);

    }

}  