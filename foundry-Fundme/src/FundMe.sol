// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./PriceConverter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NftBrabo} from "./NftBrabo.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

error FundMe__NotOwner();
error FundMe__InsufficientTokenBalance();
error FundMe__TokenTransferFailed();
error FundMe__BuybackFailed();
error FundMe__LiquidityAdditionFailed();

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
    uint256 public constant MINIMUM_USD = 2 * 10 ** 17;
    
    AggregatorV3Interface internal priceFeed;
    IERC20 public immutable picaToken;
    NftBrabo public immutable braboNft;

    // Uniswap V3 specific variables
    IUniswapV3Pool public immutable picaEthPool;
    ISwapRouter public immutable swapRouter;
    INonfungiblePositionManager public immutable positionManager;
    
    // 📊 NEW: Split percentages
    uint256 public constant BUYBACK_PERCENTAGE = 80; // 80% for buybacks
    uint256 public constant LIQUIDITY_PERCENTAGE = 20; // 20% for liquidity addition
    
    //  NFT Tier Bonuses
    uint256 public constant BRONZE_BONUS = 2; // 2% bonus
    uint256 public constant SILVER_BONUS = 5; // 5% bonus  
    uint256 public constant GOLD_BONUS = 10;  // 10% bonus
    
    // 📊 Tracking variables
    uint256 public totalTokensBought;
    uint256 public totalEthUsedForBuyback;
    uint256 public totalEthUsedForLiquidity;
    uint256 public totalTokensAddedToLiquidity;

    event Funded(address indexed funder, uint256 ethAmount, uint256 picaTokensAwarded, uint256 bonusPercentage);
    event NftMinted(address indexed recipient);
    event TierUpgraded(address indexed user, uint256 totalFundingUsd);
    event TokensBought(uint256 ethSpent, uint256 picaTokensBought, uint256 newPrice);
    event LiquidityAdded(uint256 ethAmount, uint256 picaAmount, uint256 tokenId);

    constructor(
        address _priceFeed, 
        address _picaToken,
        address _moodNft,
        address _picaEthPool,
        address _swapRouter,
        address _positionManager
    ) {
        i_owner = msg.sender;
        priceFeed = AggregatorV3Interface(_priceFeed);
        picaToken = IERC20(_picaToken);
        braboNft = NftBrabo(_moodNft);
        picaEthPool = IUniswapV3Pool(_picaEthPool);
        swapRouter = ISwapRouter(_swapRouter);
        positionManager = INonfungiblePositionManager(_positionManager);
    }

    function fund() public payable {
        require(msg.value.getConversionRate(priceFeed) >= MINIMUM_USD, "You need to spend more ETH!");
        
        uint256 ethValueInUsd = msg.value.getConversionRate(priceFeed);
        
        // 📊 STEP 1: Split ETH between buyback and liquidity
        uint256 buybackEth = (msg.value * BUYBACK_PERCENTAGE) / 100;
        uint256 liquidityEth = (msg.value * LIQUIDITY_PERCENTAGE) / 100;
        
        // 🎯 STEP 2: Execute buyback with 80% of ETH
        uint256 tokensBought = buyTokensFromLP(buybackEth);
        
        // 💧 STEP 3: Add liquidity with 20% of ETH
        addLiquidityToPool(liquidityEth);
        
        // 🎯 STEP 4: Calculate NFT tier bonus
        uint256 bonusPercentage = getNFTTierBonus(msg.sender);
        uint256 bonusTokens = (tokensBought * bonusPercentage) / 100;
        uint256 totalUserTokens = tokensBought + bonusTokens;
        
        // 🎁 STEP 5: Transfer tokens to user (bought tokens + bonus)
        uint256 contractBalance = picaToken.balanceOf(address(this));
        if (contractBalance < totalUserTokens) {
            revert FundMe__InsufficientTokenBalance();
        }
        
        bool success = picaToken.transfer(msg.sender, totalUserTokens);
        if (!success) {
            revert FundMe__TokenTransferFailed();
        }

        // NFT minting logic
        if (addressToAmountFundedInUsd[msg.sender] + ethValueInUsd >= 3 * 10 ** 17 && !alreadyReceivedNft[msg.sender]) {
            alreadyReceivedNft[msg.sender] = true;
            braboNft.mintNftTo(msg.sender);
            emit NftMinted(msg.sender);
        }
       
        // Update funding records
        addressToAmountFunded[msg.sender] += msg.value;
        totalEthFunded += msg.value;
        addressToAmountFundedInUsd[msg.sender] += ethValueInUsd;

        // Tier upgrade logic
        if (alreadyReceivedNft[msg.sender]) {
            braboNft.upgradeTierBasedOnFunding(msg.sender, addressToAmountFundedInUsd[msg.sender]);
            emit TierUpgraded(msg.sender, addressToAmountFundedInUsd[msg.sender]);
        }

        // Track new funders
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

    // 💧 NEW: Add liquidity to the pool
    function addLiquidityToPool(uint256 ethAmount) internal {
        if (ethAmount == 0) return;
        
        // Calculate how many PICA tokens we need for liquidity
        uint256 currentPrice = getPicaPriceFromLP();
        uint256 ethValueInUsd = ethAmount.getConversionRate(priceFeed);
        uint256 picaTokensNeeded = ethValueInUsd / currentPrice;
        
        // Check if contract has enough PICA tokens for liquidity
        uint256 contractBalance = picaToken.balanceOf(address(this));
        if (contractBalance < picaTokensNeeded) {
            // If not enough PICA tokens, use all available balance
            picaTokensNeeded = contractBalance;
        }
        
        if (picaTokensNeeded == 0) return;
        
        // Approve position manager to spend PICA tokens
        picaToken.approve(address(positionManager), picaTokensNeeded);
        
        // Determine token order (token0 and token1)
        address token0 = picaEthPool.token0();
        address token1 = picaEthPool.token1();
        
        uint256 amount0Desired;
        uint256 amount1Desired;
        
        if (token0 == address(picaToken)) {
            // PICA is token0, ETH is token1
            amount0Desired = picaTokensNeeded;
            amount1Desired = ethAmount;
        } else {
            // ETH is token0, PICA is token1
            amount0Desired = ethAmount;
            amount1Desired = picaTokensNeeded;
        }
        
        // Get pool tick spacing and current tick
        int24 tickSpacing = picaEthPool.tickSpacing();
        (, int24 currentTick,,,,,) = picaEthPool.slot0();
        
        // Set tick range (you can adjust this range based on your strategy)
        int24 tickLower = (currentTick / tickSpacing - 100) * tickSpacing;
        int24 tickUpper = (currentTick / tickSpacing + 100) * tickSpacing;
        
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: picaEthPool.fee(),
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0, // Accept any amount
            amount1Min: 0, // Accept any amount
            recipient: address(this), // Contract owns the LP position
            deadline: block.timestamp + 300
        });
        
        try positionManager.mint{value: ethAmount}(params) 
            returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
            
            // Update liquidity statistics
            totalEthUsedForLiquidity += ethAmount;
            totalTokensAddedToLiquidity += picaTokensNeeded;
            
            emit LiquidityAdded(ethAmount, picaTokensNeeded, tokenId);
            
        } catch {
            revert FundMe__LiquidityAdditionFailed();
        }
    }
    
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
    
    // 🎯 Calculate user rewards with NFT bonus
    function calculateUserReward(address user, uint256 ethAmount) external view returns (uint256 baseTokens, uint256 bonusTokens, uint256 totalTokens) {
        // Only 80% of ETH is used for buyback
        uint256 buybackEth = (ethAmount * BUYBACK_PERCENTAGE) / 100;
        uint256 ethValueInUsd = buybackEth.getConversionRate(priceFeed);
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
    
    // 📊 NEW: Enhanced statistics with liquidity tracking
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
    
    function getLiquidityStats() external view returns (
        uint256 totalEthAddedToLP,
        uint256 totalTokensAddedToLP,
        uint256 liquidityPercentage
    ) {
        return (
            totalEthUsedForLiquidity,
            totalTokensAddedToLiquidity,
            LIQUIDITY_PERCENTAGE
        );
    }
    
    function getSystemStats() external view returns (
        uint256 buybackEthTotal,
        uint256 liquidityEthTotal,
        uint256 buybackPercentage,
        uint256 liquidityPercentage
    ) {
        return (
            totalEthUsedForBuyback,
            totalEthUsedForLiquidity,
            BUYBACK_PERCENTAGE,
            LIQUIDITY_PERCENTAGE
        );
    }
    
    // 🎯 Get user's NFT tier bonus
    function getUserTierBonus(address user) external view returns (uint256 bonusPercentage, string memory tierName) {
        bonusPercentage = getNFTTierBonus(user);
        
        if (bonusPercentage == BRONZE_BONUS) return (bonusPercentage, "Bronze");
        if (bonusPercentage == SILVER_BONUS) return (bonusPercentage, "Silver");
        if (bonusPercentage == GOLD_BONUS) return (bonusPercentage, "Gold");
        return (0, "No NFT");
    }
}