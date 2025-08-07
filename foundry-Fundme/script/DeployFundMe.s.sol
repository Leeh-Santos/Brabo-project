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
            // base
            address priceFeedAddress = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;

            address positionManager = 0x03a520b32C04BF3bEEf7BF5d7f41323c95B0Fb4; // Base V3 Position Manager
            address swapRouter = 0x2626664c2603336E57B271c5C0b26F421741e481;     // Base V3 Swap Router
            
            // 🎯 YOUR LP POSITION DETAILS - REPLACE THESE WITH YOUR ACTUAL VALUES
            address picaEthPool = vm.envAddress("PICA_ETH_POOL");    // Your V3 pool address
            uint256 positionTokenId = vm.envUint("POSITION_TOKEN_ID"); // Your position NFT ID
            int24 tickLower = int24(vm.envInt("TICK_LOWER"));         // Your position tick lower
            int24 tickUpper = int24(vm.envInt("TICK_UPPER"));         // Your position tick upper
        
        
            vm.startBroadcast(); 
            
            string memory bronzeSvg = vm.readFile("./img/bronze.svg");
            string memory silverSvg = vm.readFile("./img/silver.svg");
            string memory goldSvg = vm.readFile("./img/gold.svg");
            NftBrabo braboNft = new NftBrabo(svgToImageUri(bronzeSvg),svgToImageUri(silverSvg), svgToImageUri(goldSvg));


            FundMe fundMe = new FundMe(
                priceFeedAddress,    // Chainlink ETH/USD feed
                picaTokenAddress,    // Your PICA token
                address(braboNft),   // Your NFT contract
                picaEthPool,         // Your V3 pool address
                positionManager,     // Base V3 Position Manager
                swapRouter,          // Base V3 Swap Router
                positionTokenId,     // Your existing position ID
                tickLower,           // Your position's lower tick
                tickUpper            // Your position's upper tick
            );
            
            // Setup - only set minter, no token transfer
            braboNft.setMinterContract(address(fundMe));
            
            vm.stopBroadcast();

            
            
            // Output
            console.log("\n Deployment Complete!");
            console.log("MoodNft:", address(braboNft));
            console.log("FundMe:", address(fundMe));
          
            console.log("    FundMe address:", address(fundMe));
            
            return (fundMe, braboNft);
        }

        function svgToImageUri (string memory svg) public pure returns (string memory) {
            string memory baseUrl = "data:image/svg+xml;base64,";
            string memory svgBase64Encoded = Base64.encode(bytes(string(abi.encodePacked(svg))));

            return string(abi.encodePacked(baseUrl, svgBase64Encoded));
        }
    }