// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./PriceConverter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NftBrabo} from "./NftBrabo.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

error FundMe__NotOwner();
error FundMe__InsufficientTokenBalance();
error FundMe__TokenTransferFailed();
error FundMe__BuybackFailed();

contract FundMe {
    using PriceConverter for uint256;

    mapping(address => uint256) private addressToAmountFunded;
    mapping(address => uint256) private addressToAmountFundedInUsd;
    mapping(address => bool) private alreadyReceivedNft;
    mapping(address => bool) private hasFunded;
    address[] private funders;
    uint256 public totalFunders;
    uint256 public totalEthFunded;
    
    address private immutable i_owner;
    uint256 public constant MINIMUM_USD = 1 * 10 ** 18;
    
    AggregatorV3Interface internal priceFeed;
    IERC20 public immutable picaToken;
    NftBrabo public immutable braboNft;

    // Uniswap V3 specific variables
    IUniswapV3Pool public immutable picaEthPool;
    INonfungiblePositionManager public immutable positionManager;
    ISwapRouter public immutable swapRouter;
    
   
    uint256 public constant BUYBACK_PERCENTAGE = 100; 
    
    //  NFT Tier Bonuses
    uint256 public constant BRONZE_BONUS = 2; // 2% bonus
    uint256 public constant SILVER_BONUS = 5; // 5% bonus  
    uint256 public constant GOLD_BONUS = 10;  // 10% bonus
    
    // V3 specific variables (kept for compatibility)
    uint256 public positionTokenId;
    int24 public tickLower;
    int24 public tickUpper;

    // 📊 Buyback tracking
    uint256 public totalTokensBought;
    uint256 public totalEthUsedForBuyback;

    event Funded(address indexed funder, uint256 ethAmount, uint256 picaTokensAwarded, uint256 bonusPercentage);
    event NftMinted(address indexed recipient);
    event TierUpgraded(address indexed user, uint256 totalFundingUsd);
    event TokensBought(uint256 ethSpent, uint256 picaTokensBought, uint256 newPrice);

    constructor(
        address _priceFeed, 
        address _picaToken,
        address _moodNft,
        address _picaEthPool,
        address _positionManager,
        address _swapRouter
    ) {
        i_owner = msg.sender;
        priceFeed = AggregatorV3Interface(_priceFeed);
        picaToken = IERC20(_picaToken);
        braboNft = NftBrabo(_moodNft);
        
        picaEthPool = IUniswapV3Pool(_picaEthPool);
        positionManager = INonfungiblePositionManager(_positionManager);
        swapRouter = ISwapRouter(_swapRouter);
        
        // Set wide tick range for maximum liquidity coverage (for compatibility)
        int24 tickSpacing = picaEthPool.tickSpacing();
        (, int24 currentTick,,,,,) = picaEthPool.slot0();
        tickLower = currentTick - (tickSpacing * 100);
        tickUpper = currentTick + (tickSpacing * 100);
    }

    function fund() public payable {
        require(msg.value.getConversionRate(priceFeed) >= MINIMUM_USD, "You need to spend more ETH!");
        
        uint256 ethValueInUsd = msg.value.getConversionRate(priceFeed);
        
        uint256 tokensBought = buyTokensFromLP(msg.value);
        
        // 🎯 STEP 2: Calculate NFT tier bonus
        uint256 bonusPercentage = getNFTTierBonus(msg.sender);
        uint256 bonusTokens = (tokensBought * bonusPercentage) / 100;
        uint256 totalUserTokens = tokensBought + bonusTokens;
        
        // 🎁 STEP 3: Transfer tokens to user (bought tokens + bonus)
        uint256 contractBalance = picaToken.balanceOf(address(this));
        if (contractBalance < totalUserTokens) {
            revert FundMe__InsufficientTokenBalance();
        }
        
        bool success = picaToken.transfer(msg.sender, totalUserTokens);
        if (!success) {
            revert FundMe__TokenTransferFailed();
        }

       
        if (addressToAmountFundedInUsd[msg.sender] + ethValueInUsd >= 10 * 10 ** 18 && !alreadyReceivedNft[msg.sender]) {
            alreadyReceivedNft[msg.sender] = true;
            braboNft.mintNftTo(msg.sender);
            emit NftMinted(msg.sender);
        }
       
      
        addressToAmountFunded[msg.sender] += msg.value;
        totalEthFunded += msg.value;
        addressToAmountFundedInUsd[msg.sender] += ethValueInUsd;

        
        if (alreadyReceivedNft[msg.sender]) {
            braboNft.upgradeTierBasedOnFunding(msg.sender, addressToAmountFundedInUsd[msg.sender]);
            emit TierUpgraded(msg.sender, addressToAmountFundedInUsd[msg.sender]);
        }

       
        if (!hasFunded[msg.sender]) {
            funders.push(msg.sender);       
            hasFunded[msg.sender] = true;
            totalFunders++;
        }

        emit Funded(msg.sender, msg.value, totalUserTokens, bonusPercentage);
    }


    function buyTokensFromLP(uint256 ethAmount) internal returns (uint256 tokensBought) {
        if (ethAmount == 0) return 0;
        
        
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(0), // ETH (automatically wrapped to WETH)
            tokenOut: address(picaToken),
            fee: picaEthPool.fee(),
            recipient: address(this), // Contract receives the PICA tokens
            deadline: block.timestamp + 300,
            amountIn: ethAmount,
            amountOutMinimum: 0, // Accept any amount of tokens out
            sqrtPriceLimitX96: 0 // No price limit
        });
        
        try swapRouter.exactInputSingle{value: ethAmount}(params) 
            returns (uint256 amountOut) {
            
            // Update buyback statistics
            totalTokensBought += amountOut;
            totalEthUsedForBuyback += ethAmount;
            
            // Get new price after buyback
            uint256 newPrice = getPicaPriceFromLP();
            
            emit TokensBought(ethAmount, amountOut, newPrice);
            
            return amountOut;
            
        } catch {
            revert FundMe__BuybackFailed();
        }
    }

    // 🎯 Get NFT tier bonus percentage
    function getNFTTierBonus(address user) internal view returns (uint256) {
        if (!alreadyReceivedNft[user]) {
            return 0; // No NFT, no bonus
        }
        
        // Get user's NFT tier from NftBrabo contract
        try braboNft.getUserTier(user) returns (uint256 tier) {
            if (tier == 0) return BRONZE_BONUS; // Bronze = 2%
            if (tier == 1) return SILVER_BONUS; // Silver = 5%
            if (tier == 2) return GOLD_BONUS;   // Gold = 10%
            return 0; // Unknown tier
        } catch {
            return 0; // Error getting tier
        }
    }

    // 🔍 Get current PICA price from LP
    function getPicaPriceFromLP() internal view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,) = picaEthPool.slot0();
        
        // Convert sqrtPriceX96 to actual price
        uint256 price = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) / (2**192);
        
        // Adjust for token decimals and determine which token is token0
        address token0 = picaEthPool.token0();
        uint256 ethPriceInUsd = uint256(1 * 10**18).getConversionRate(priceFeed);
        
        if (token0 == address(picaToken)) {
            // PICA is token0, ETH is token1
            return price == 0 ? 1e18 : (ethPriceInUsd * (2**192)) / (uint256(sqrtPriceX96) * uint256(sqrtPriceX96));
        } else {
            // ETH is token0, PICA is token1
            return price == 0 ? 1e18 : (ethPriceInUsd) / price;
        }
    }

    // 🔧 Function to set initial position (kept for compatibility)
    function setPositionTokenId(uint256 _tokenId, int24 _tickLower, int24 _tickUpper) external onlyOwner {
        positionTokenId = _tokenId;
        tickLower = _tickLower;
        tickUpper = _tickUpper;
    }

    function upgradeTierForUser(address user) external onlyOwner {
        require(alreadyReceivedNft[user], "User doesn't have an NFT");
        braboNft.upgradeTierBasedOnFunding(user, addressToAmountFundedInUsd[user]);
        emit TierUpgraded(user, addressToAmountFundedInUsd[user]);
    }

    function getVersion() public view returns (uint256) {
        return priceFeed.version();
    }

    modifier onlyOwner() {
        if (msg.sender != i_owner) revert FundMe__NotOwner();
        _;
    }

    function withdraw() public onlyOwner {
        (bool callSuccess,) = payable(msg.sender).call{value: address(this).balance}("");
        require(callSuccess, "Call failed");
    }
    
    function withdrawPicaTokens() public onlyOwner {
        uint256 balance = picaToken.balanceOf(address(this));
        bool success = picaToken.transfer(i_owner, balance);
        require(success, "Token withdrawal failed");
    }
    
    function depositPicaTokens(uint256 amount) public onlyOwner {
        bool success = picaToken.transferFrom(msg.sender, address(this), amount);
        require(success, "Token deposit failed");
    }

    fallback() external payable {
        fund();
    }

    receive() external payable {
        fund();
    }

    // 📊 View functions
    function getHowMuchDudeFunded(address _address) external view returns (uint256) {
        return addressToAmountFunded[_address];
    }

    function getHowMuchDudeFundedInUsdActual(address _address) external view returns (uint256) {
        return addressToAmountFundedInUsd[_address] / 1e18;
    }

    function getHowMuchDudeFundedInUsd(address _address) external view returns (uint256) {
        return addressToAmountFundedInUsd[_address];
    }

    function getFunders(uint256 _idx) external view returns (address) {
        return funders[_idx];
    }

    function getOwner() external view returns (address) {
        return i_owner;
    }
    
    function getPicaTokenBalance() external view returns (uint256) {
        return picaToken.balanceOf(address(this));
    }
    
    // 🎯 NEW: Calculate user rewards with NFT bonus
    function calculateUserReward(address user, uint256 ethAmount) external view returns (uint256 baseTokens, uint256 bonusTokens, uint256 totalTokens) {
        // Simulate buying tokens (without actually buying)
        uint256 ethValueInUsd = ethAmount.getConversionRate(priceFeed);
        uint256 currentPicaPrice = getPicaPriceFromLP();
        baseTokens = ethValueInUsd / currentPicaPrice;
        
        // Calculate bonus
        uint256 bonusPercentage = getNFTTierBonus(user);
        bonusTokens = (baseTokens * bonusPercentage) / 100;
        totalTokens = baseTokens + bonusTokens;
        
        return (baseTokens, bonusTokens, totalTokens);
    }

    function getTotalEthFundedInEth() public view returns (uint256) {
        return totalEthFunded / 1e18;
    }
    
    function getCurrentPicaPrice() external view returns (uint256) {
        return getPicaPriceFromLP();
    }
    
    function getPositionInfo() external view returns (uint256, int24, int24) {
        return (positionTokenId, tickLower, tickUpper);
    }
    
    // 📊 NEW: Get buyback statistics
    function getBuybackStats() external view returns (
        uint256 totalBought,
        uint256 totalEthSpent,
        uint256 averagePricePerToken
    ) {
        return (
            totalTokensBought,
            totalEthUsedForBuyback,
            totalTokensBought > 0 ? (totalEthUsedForBuyback * 1e18) / totalTokensBought : 0
        );
    }
    
    // 🎯 NEW: Get user's NFT tier bonus
    function getUserTierBonus(address user) external view returns (uint256 bonusPercentage, string memory tierName) {
        bonusPercentage = getNFTTierBonus(user);
        
        if (bonusPercentage == BRONZE_BONUS) return (bonusPercentage, "Bronze");
        if (bonusPercentage == SILVER_BONUS) return (bonusPercentage, "Silver");
        if (bonusPercentage == GOLD_BONUS) return (bonusPercentage, "Gold");
        return (0, "No NFT");
    }
}