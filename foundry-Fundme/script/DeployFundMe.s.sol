// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {NftBrabo} from "../src/NftBrabo.sol";
import {FundMe} from "../src/FundMe.sol";
import {console} from "forge-std/console.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

contract DeployFundme is Script {
    function run() external returns (FundMe, NftBrabo) {
        // Token and price feed addresses
        address picaTokenAddress = vm.envAddress("PICA");        
        // Base network ETH/USD price feed
        address priceFeedAddress = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;

        // 🚀 Uniswap V3 addresses on Base
        address swapRouter = 0x2626664c2603336E57B271c5C0b26F421741e481;     // Base V3 Swap Router
        
        // 🎯 YOUR LP POSITION DETAILS - Get from environment variables
        address picaEthPool = vm.envAddress("PICA_ETH_POOL");    // Your V3 pool address
    
        vm.startBroadcast(); 
        
        // Deploy NFT contract with tier images
        string memory bronzeSvg = vm.readFile("./img/bronze.svg");
        string memory silverSvg = vm.readFile("./img/silver.svg");
        string memory goldSvg = vm.readFile("./img/gold.svg");
        NftBrabo braboNft = new NftBrabo(
            svgToImageUri(bronzeSvg),
            svgToImageUri(silverSvg), 
            svgToImageUri(goldSvg)
        );

        // 🆕 Deploy NEW FundMe with 6 parameters (removed position-specific params)
        FundMe fundMe = new FundMe(
            priceFeedAddress,    // Chainlink ETH/USD feed
            picaTokenAddress,    // Your PICA token
            address(braboNft),   // Your NFT contract
            picaEthPool,         // Your V3 pool address
            swapRouter           // Base V3 Swap Router
        );
        
        // Setup NFT minter
        braboNft.setMinterContract(address(fundMe));
        
        vm.stopBroadcast();
        
    
  
        
        console.log(" Contract Addresses:");
        console.log("   NftBrabo:", address(braboNft));
        console.log("   FundMe:", address(fundMe));
        console.log("");
        console.log(" V3 Integration:");
        console.log("   PICA Token:", picaTokenAddress);
        console.log("   Pool Address:", picaEthPool);
   
        console.log("   Swap Router:", swapRouter);
      
        
        
        return (fundMe, braboNft);
    }

    function svgToImageUri(string memory svg) public pure returns (string memory) {
        string memory baseUrl = "data:image/svg+xml;base64,";
        string memory svgBase64Encoded = Base64.encode(bytes(string(abi.encodePacked(svg))));
        return string(abi.encodePacked(baseUrl, svgBase64Encoded));
    }
}