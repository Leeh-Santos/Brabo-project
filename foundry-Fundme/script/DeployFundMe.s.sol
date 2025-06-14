    // SPDX-License-Identifier: MIT
    pragma solidity ^0.8.18;

    import {Script} from "forge-std/Script.sol";
    import {NftBrabo} from "../src/NftBrabo.sol";
    import {FundMe} from "../src/FundMe.sol";
    import {console} from "forge-std/console.sol";
    import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

    contract DeployFundme is Script {
        function run() external returns (FundMe, NftBrabo) {
            address picaTokenAddress = vm.envAddress("PICA");

        
            
        
            // sepolia
            address priceFeedAddress = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        
        
            vm.startBroadcast(); 
            
            string memory bronzeSvg = vm.readFile("./img/bronze.svg");
            string memory silverSvg = vm.readFile("./img/silver.svg");
            string memory goldSvg = vm.readFile("./img/gold.svg");
            NftBrabo braboNft = new NftBrabo(svgToImageUri(bronzeSvg),svgToImageUri(silverSvg), svgToImageUri(goldSvg));
            FundMe fundMe = new FundMe(priceFeedAddress, picaTokenAddress, address(braboNft));
            
            // Setup - only set minter, no token transfer
            braboNft.setMinterContract(address(fundMe));
            
            vm.stopBroadcast();

            
            
            // Output
            console.log("\n Deployment Complete!");
            console.log("MoodNft:", address(braboNft));
            console.log("FundMe:", address(fundMe));
            console.log("\n  IMPORTANT: You need to manually transfer PicaTokens to the FundMe contract!");
            console.log("    FundMe address:", address(fundMe));
            console.log("    Recommended amount: 100,000 PCT or more");
            console.log("\nTo transfer tokens using MetaMask:");
            console.log("1. Open MetaMask and select your account with PicaTokens");
            console.log("2. Click on the PicaToken in your assets");
            console.log("3. Click 'Send'");
            console.log("4. Paste the FundMe address:", address(fundMe));
            console.log("5. Enter the amount you want to transfer");
            console.log("6. Confirm the transaction");
            console.log("\nSave these addresses for future interactions!");
            return (fundMe, braboNft);
        }

        function svgToImageUri (string memory svg) public pure returns (string memory) {
            string memory baseUrl = "data:image/svg+xml;base64,";
            string memory svgBase64Encoded = Base64.encode(bytes(string(abi.encodePacked(svg))));

            return string(abi.encodePacked(baseUrl, svgBase64Encoded));
        }
    }