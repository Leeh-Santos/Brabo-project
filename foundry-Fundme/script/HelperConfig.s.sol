//SPDX-License-Identifier: MIT

// deploy mocks when we are on local anvil chain # remember about the chainlink query localissue
//kee trak of cotnract across diferent chains,

//if local deploy on avil, if not grab contract from specific network

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggragator.sol";

contract HelperConfig is Script{

    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 2000e8;

    struct NetConfig{
        address PriceeFeed;
    }

    NetConfig public activeNetConfig;

    constructor(){
        if(block.chainid == 11155111){
            activeNetConfig = getSepoliaFeed();
        } else if(block.chainid == 1){
            activeNetConfig = getEthereumFeed();
        }
        else {
            activeNetConfig = getAnvilFeed();
        }
    }

    function getEthereumFeed() public pure returns(NetConfig memory){
        return NetConfig(0x72AFAECF99C9d9C8215fF44C77B94B99C28741e8);
    }

    function getSepoliaFeed() public pure returns (NetConfig memory){

        NetConfig memory sepoliaconfig = NetConfig(0x694AA1769357215DE4FAC081bf1f309aDC325306);
        return sepoliaconfig;
        //return NetConfig(0x694AA1769357215DE4FAC081bf1f309aDC325306)
    }

    function getAnvilFeed() public returns (NetConfig memory){
        if(activeNetConfig.PriceeFeed != address(0)){
            return activeNetConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator mockV3Aggregator = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
        NetConfig memory anvilConfig = NetConfig(address(mockV3Aggregator));
        vm.stopBroadcast();
        return anvilConfig;
    }  

}