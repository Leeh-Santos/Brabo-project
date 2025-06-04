// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {NftBrabo} from "../src/NftBrabo.sol";
import {FundMe} from "../src/FundMe.sol";
import {console} from "forge-std/console.sol";

contract DeployWithoutTransfer is Script {
    function run() external {
        // Read PicaToken address from environment variable
        address picaTokenAddress = vm.envAddress("PICA_TOKEN_ADDRESS");
        
        console.log("Using existing PicaToken at:", picaTokenAddress);
        
        // Get price feed address based on network
        address priceFeedAddress = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
       
        // SVG URIs
        string memory happySvg = "data:image/svg+xml;base64,PHN2ZyB2aWV3Qm94PSIwIDAgMjAwIDIwMCIgd2lkdGg9IjQwMCIgaGVpZ2h0PSI0MDAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PGNpcmNsZSBjeD0iMTAwIiBjeT0iMTAwIiByPSI4MCIgZmlsbD0ieWVsbG93IiBzdHJva2U9ImJsYWNrIiBzdHJva2Utd2lkdGg9IjIiLz48Y2lyY2xlIGN4PSI3MCIgY3k9IjgwIiByPSIxMCIgZmlsbD0iYmxhY2siLz48Y2lyY2xlIGN4PSIxMzAiIGN5PSI4MCIgcj0iMTAiIGZpbGw9ImJsYWNrIi8+PHBhdGggZD0iTSA2MCAxMjAgUSAxMDAgMTUwIDE0MCAxMjAiIHN0cm9rZT0iYmxhY2siIHN0cm9rZS13aWR0aD0iMyIgZmlsbD0ibm9uZSIvPjwvc3ZnPg==";
        string memory sadSvg = "data:image/svg+xml;base64,PHN2ZyB2aWV3Qm94PSIwIDAgMjAwIDIwMCIgd2lkdGg9IjQwMCIgaGVpZ2h0PSI0MDAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PGNpcmNsZSBjeD0iMTAwIiBjeT0iMTAwIiByPSI4MCIgZmlsbD0ieWVsbG93IiBzdHJva2U9ImJsYWNrIiBzdHJva2Utd2lkdGg9IjIiLz48Y2lyY2xlIGN4PSI3MCIgY3k9IjgwIiByPSIxMCIgZmlsbD0iYmxhY2siLz48Y2lyY2xlIGN4PSIxMzAiIGN5PSI4MCIgcj0iMTAiIGZpbGw9ImJsYWNrIi8+PHBhdGggZD0iTSA2MCAxNDAgUSAxMDAgMTIwIDE0MCAxNDAiIHN0cm9rZT0iYmxhY2siIHN0cm9rZS13aWR0aD0iMyIgZmlsbD0ibm9uZSIvPjwvc3ZnPg==";
        
        vm.startBroadcast();
        
        // Deploy contracts
        NftBrabo braboNft = new NftBrabo(sadSvg, happySvg);
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
    }
}