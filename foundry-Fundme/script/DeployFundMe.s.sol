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

        // 🚀 Uniswap V3 addresses on Base network
        address swapRouter = 0x2626664c2603336E57B271c5C0b26F421741e481;     // Base V3 Swap Router
        address positionManager = 0x03a520b32c04bf3beEF7bF5d56831fcB7e84f141;
        // 🎯 YOUR LP POSITION DETAILS - Get from environment variables
        address picaEthPool = vm.envAddress("PICA_ETH_POOL");    // Your V3 pool address


        address weth = 0x4200000000000000000000000000000000000006;
    
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

        // 🆕 Deploy NEW FundMe with 6 parameters including Position Manager
        FundMe fundMe = new FundMe(
            priceFeedAddress,    // Chainlink ETH/USD feed
            picaTokenAddress,    // Your PICA token
            address(braboNft),   // Your NFT contract
            picaEthPool,         // Your V3 pool address
            swapRouter,          // Base V3 Swap Router
            positionManager,
            weth     
        );
        
        // Setup NFT minter
        braboNft.setMinterContract(address(fundMe));
        
        vm.stopBroadcast();
        
      
        console.log(" Contract Addresses:");
        console.log("   NftBrabo:       ", address(braboNft));
        console.log("   FundMe:         ", address(fundMe));
        console.log("");
     
        console.log("");
        console.log("  Mechanism Settings:");
        console.log("   Buyback:        80%");
        console.log("   Liquidity:      20%");
        console.log("   Price Feed:     ", priceFeedAddress);
        console.log("");
        console.log(" Next Steps:");
        console.log("   1. Fund contract with PICA tokens");
        console.log("   2. Verify contracts on BaseScan");
        console.log("   3. Test with small funding amount");
        console.log("=================================================");
          
        return (fundMe, braboNft);
    }

    function svgToImageUri(string memory svg) public pure returns (string memory) {
        string memory baseUrl = "data:image/svg+xml;base64,";
        string memory svgBase64Encoded = Base64.encode(bytes(string(abi.encodePacked(svg))));
        return string(abi.encodePacked(baseUrl, svgBase64Encoded));
    }
}