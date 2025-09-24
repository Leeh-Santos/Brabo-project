// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./PriceConverter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NftBrabo} from "./NftBrabo.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IWETH} from "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";

error FundMe__NotOwner();
error FundMe__InsufficientTokenBalance();
error FundMe__TokenTransferFailed();
error FundMe__BuybackFailed();
error FundMe__LiquidityAdditionFailed();
error FundMe__SlippageExceeded();
        
contract FundMe {
    using PriceConverter for uint256;

    // Base network WETH address
    address constant WETH = 0x4200000000000000000000000000000000000006;

    mapping(address => uint256) private addressToAmountFunded;
    mapping(address => uint256) private addressToAmountFundedInUsd;
    mapping(address => bool) private alreadyReceivedNft;
    mapping(address => bool) private hasFunded;
    uint256[] public liquidityPositionIds;
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
    
    // Split percentages
    uint256 public constant BUYBACK_PERCENTAGE = 80; // 80% for buybacks
    uint256 public constant LIQUIDITY_PERCENTAGE = 20; // 20% for liquidity addition
    uint256 public constant MAX_SLIPPAGE = 500; // 5% max slippage (500 basis points)
    
    // NFT Tier Bonuses
    uint256 public constant BRONZE_BONUS = 2; // 2% bonus
    uint256 public constant SILVER_BONUS = 5; // 5% bonus  
    uint256 public constant GOLD_BONUS = 10;  // 10% bonus
    
    // Tracking variables
    uint256 public totalTokensBought;
    uint256 public totalEthUsedForBuyback;
    uint256 public totalEthUsedForLiquidity;
    uint256 public totalTokensAddedToLiquidity;

    // Emergency pause mechanism
    bool public paused = false;

    event Funded(address indexed funder, uint256 ethAmount, uint256 picaTokensAwarded, uint256 bonusPercentage, uint256 liquidityCompensation);
    event NftMinted(address indexed recipient);
    event TierUpgraded(address indexed user, uint256 totalFundingUsd);
    event TokensBought(uint256 ethSpent, uint256 picaTokensBought, uint256 newPrice);
    event LiquidityAdded(uint256 ethAmount, uint256 picaAmount, uint256 tokenId);
    event SwapFailed(address indexed user, uint256 ethAmount, string reason);
    event BuybackFailed(address indexed user, uint256 ethAmount);
    event LiquidityFailed(address indexed user, uint256 ethAmount);
    event EthRefunded(address indexed user, uint256 ethAmount);

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

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != i_owner) revert FundMe__NotOwner();
        _;
    }

    function fund() public payable whenNotPaused {
    require(msg.value.getConversionRate(priceFeed) >= MINIMUM_USD, "You need to spend more ETH!");
    
    uint256 ethValueInUsd = msg.value.getConversionRate(priceFeed);
    uint256 buybackEth = (msg.value * BUYBACK_PERCENTAGE) / 100;
    uint256 liquidityEth = (msg.value * LIQUIDITY_PERCENTAGE) / 100;
    
    uint256 tokensBought = 0;
    uint256 failedEth = 0;

    // Try buyback with error handling
    try this.buyTokensFromLPExternal(buybackEth) returns (uint256 tokens) {
        tokensBought = tokens;
    } catch Error(string memory) {
        failedEth += buybackEth;
        emit BuybackFailed(msg.sender, buybackEth);
    } catch {
        failedEth += buybackEth;
        emit BuybackFailed(msg.sender, buybackEth);
    }

    // Try liquidity addition with error handling
    try this.addLiquidityToPoolExternal(liquidityEth) {
        // Success - event emitted in function
    } catch Error(string memory ) {
        failedEth += liquidityEth;
        emit LiquidityFailed(msg.sender, liquidityEth);
    } catch {
        failedEth += liquidityEth;
        emit LiquidityFailed(msg.sender, liquidityEth);
    }
    
    // Calculate NFT tier bonus
    uint256 bonusPercentage = getNFTTierBonus(msg.sender);
    uint256 bonusTokens = (tokensBought * bonusPercentage) / 100;
    
    // 🆕 ADD LIQUIDITY COMPENSATION
    uint256 liquidityValueInUsd = liquidityEth.getConversionRate(priceFeed);
    uint256 currentPicaPrice = getPicaPriceFromLP();
    uint256 liquidityCompensationTokens = 0;
    
    if (currentPicaPrice > 0) {
        liquidityCompensationTokens = (liquidityValueInUsd * 1e18) / currentPicaPrice;
    }
    
    // 🆕 TOTAL USER TOKENS = Buyback + NFT Bonus + Liquidity Compensation
    uint256 totalUserTokens = tokensBought + bonusTokens + liquidityCompensationTokens;
    
    // Transfer tokens to user if any were bought
    if (totalUserTokens > 0) {
        uint256 contractBalance = picaToken.balanceOf(address(this));
        if (contractBalance >= totalUserTokens) {
            bool success = picaToken.transfer(msg.sender, totalUserTokens);
            if (!success) {
                revert FundMe__TokenTransferFailed();
            }
        } else {
            // Transfer what we have
            if (contractBalance > 0) {
                picaToken.transfer(msg.sender, contractBalance);
            }
            revert FundMe__InsufficientTokenBalance();
        }
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

    // Refund failed ETH operations
    if (failedEth > 0) {
        (bool refundSuccess,) = payable(msg.sender).call{value: failedEth}("");
        require(refundSuccess, "ETH refund failed");
        emit EthRefunded(msg.sender, failedEth);
    }

    emit Funded(msg.sender, msg.value, totalUserTokens, bonusPercentage, liquidityCompensationTokens);
}

    // External wrapper for try/catch
    function buyTokensFromLPExternal(uint256 ethAmount) external returns (uint256) {
        require(msg.sender == address(this), "Only self");
        return buyTokensFromLP(ethAmount);
    }

    function buyTokensFromLP(uint256 ethAmount) internal returns (uint256 tokensBought) {
        if (ethAmount == 0) return 0;

        // Calculate expected output and minimum with slippage protection
        uint256 currentPrice = getPicaPriceFromLP();
        if (currentPrice == 0) return 0;

        uint256 ethInUsd = ethAmount.getConversionRate(priceFeed);
        uint256 expectedTokensOut = (ethInUsd * 1e18) / currentPrice;
        uint256 minAmountOut = (expectedTokensOut * (10000 - MAX_SLIPPAGE)) / 10000;

        // Wrap ETH to WETH
        IWETH(WETH).deposit{value: ethAmount}();
        IERC20(WETH).approve(address(swapRouter), ethAmount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: address(picaToken),
            fee: picaEthPool.fee(),
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: ethAmount,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });

        try swapRouter.exactInputSingle(params)
            returns (uint256 amountOut) {

            totalTokensBought += amountOut;
            totalEthUsedForBuyback += ethAmount;

            uint256 newPrice = getPicaPriceFromLP();
            emit TokensBought(ethAmount, amountOut, newPrice);

            return amountOut;

        } catch Error(string memory reason) {
            emit SwapFailed(msg.sender, ethAmount, reason);
            revert FundMe__BuybackFailed();
        } catch {
            revert FundMe__BuybackFailed();
        }
    }

    // External wrapper for try/catch
    function addLiquidityToPoolExternal(uint256 ethAmount) external {
        require(msg.sender == address(this), "Only self");
        addLiquidityToPool(ethAmount);
    }

    function addLiquidityToPool(uint256 ethAmount) internal {
        if (ethAmount == 0) return;
        
        uint256 picaTokensNeeded = _calculatePicaTokensNeeded(ethAmount);
        if (picaTokensNeeded == 0) return;
        
        // Approve tokens
        picaToken.approve(address(positionManager), picaTokensNeeded);
        _mintLiquidityPosition(ethAmount, picaTokensNeeded);
    }

    function _calculatePicaTokensNeeded(uint256 ethAmount) private view returns (uint256) {
        uint256 currentPrice = getPicaPriceFromLP();
        if (currentPrice == 0) return 0;
        
        uint256 ethInUsd = ethAmount.getConversionRate(priceFeed);
        uint256 picaTokensNeeded = (ethInUsd * 1e18) / currentPrice;
        
        uint256 contractBalance = picaToken.balanceOf(address(this));
        return contractBalance < picaTokensNeeded ? contractBalance : picaTokensNeeded;
    }

    function _mintLiquidityPosition(uint256 ethAmount, uint256 picaTokensNeeded) private {
        address token0 = picaEthPool.token0();
        bool picaIsToken0 = token0 == address(picaToken);

        int24 tickSpacing = picaEthPool.tickSpacing();
        (, int24 currentTick,,,,,) = picaEthPool.slot0();

        // Use a reasonable range (e.g., 10-50 tick spacings, not 200)
        int24 tickLower = ((currentTick / tickSpacing) - 10) * tickSpacing;
        int24 tickUpper = ((currentTick / tickSpacing) + 10) * tickSpacing;

        // Ensure ticks are within valid range
        int24 MIN_TICK = -887272;
        int24 MAX_TICK = 887272;
        if (tickLower < MIN_TICK) tickLower = MIN_TICK;
        if (tickUpper > MAX_TICK) tickUpper = MAX_TICK;

        // Wrap ETH to WETH
        IWETH(WETH).deposit{value: ethAmount}();
        IERC20(WETH).approve(address(positionManager), ethAmount);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: picaEthPool.token1(),
            fee: picaEthPool.fee(),
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: picaIsToken0 ? picaTokensNeeded : ethAmount,
            amount1Desired: picaIsToken0 ? ethAmount : picaTokensNeeded,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 300
        });

        try positionManager.mint(params)
            returns (uint256 tokenId, uint128, uint256, uint256) {

            liquidityPositionIds.push(tokenId);
            totalEthUsedForLiquidity += ethAmount;
            totalTokensAddedToLiquidity += picaTokensNeeded;

            emit LiquidityAdded(ethAmount, picaTokensNeeded, tokenId);

        } catch Error(string memory) {
            revert FundMe__LiquidityAdditionFailed();
        } catch {
            revert FundMe__LiquidityAdditionFailed();
        }
    }
    
    function getNFTTierBonus(address user) internal view returns (uint256) {
        if (!alreadyReceivedNft[user]) {
            return 0;
        }
        
        try braboNft.getUserTier(user) returns (uint256 tier) {
            if (tier == 0) return BRONZE_BONUS;
            if (tier == 1) return SILVER_BONUS;
            if (tier == 2) return GOLD_BONUS;
            return 0;
        } catch {
            return 0;
        }
    }

   function getPicaPriceFromLP() internal view returns (uint256) {
    try picaEthPool.slot0() returns (
        uint160 sqrtPriceX96,
        int24,
        uint16,
        uint16,
        uint16,
        uint8,
        bool
    ) {
        // FIX: Use realistic fallback price ($0.001 = 1e15)
        if (sqrtPriceX96 == 0) return 1e15; // $0.001 per PICA

        address token0 = picaEthPool.token0();
        uint256 ethPriceInUsd = uint256(1 * 10**18).getConversionRate(priceFeed);

        if (token0 == address(picaToken)) {
            // PICAchu is token0, WETH is token1
            uint256 wethPerPica = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18) >> 192;

            // FIX: Add zero check and realistic minimum
            if (wethPerPica == 0) return 1e15; // $0.001 per PICA

            uint256 priceInUsd = (wethPerPica * ethPriceInUsd) / 1e18;

            // FIX: Ensure price is reasonable (minimum $0.0001, no maximum)
            if (priceInUsd < 1e14) return 1e14; // Min $0.0001

            return priceInUsd;

        } else {
            // WETH is token0, PICAchu is token1
            uint256 picaPerWeth = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 192;

            // FIX: Proper zero protection with realistic fallback
            if (picaPerWeth == 0) return 1e15; // $0.001 per PICA

            uint256 priceInUsd = (ethPriceInUsd * 1e18) / picaPerWeth;

            // FIX: Ensure price is reasonable (minimum $0.0001, no maximum)
            if (priceInUsd < 1e14) return 1e14; // Min $0.0001

            return priceInUsd;
        }
    } catch {
        // FIX: Use realistic fallback price instead of $1 trillion
        return 1e15; // $0.001 per PICA
    }
}

    // Admin functions
    function upgradeTierForUser(address user) external onlyOwner {
        require(alreadyReceivedNft[user], "User doesn't have an NFT");
        braboNft.upgradeTierBasedOnFunding(user, addressToAmountFundedInUsd[user]);
        emit TierUpgraded(user, addressToAmountFundedInUsd[user]);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
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

    // Emergency rescue functions
    function rescueStuckETH() external onlyOwner {
        payable(i_owner).transfer(address(this).balance);
    }

    function rescueStuckTokens(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        token.transfer(i_owner, token.balanceOf(address(this)));
    }

    fallback() external payable whenNotPaused {
        fund();
    }

    receive() external payable whenNotPaused {
        fund();
    }

    // View functions
    function getVersion() public view returns (uint256) {
        return priceFeed.version();
    }

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
    
    function calculateUserReward(address user, uint256 ethAmount) external view returns (uint256 baseTokens, uint256 bonusTokens, uint256 totalTokens) {
        uint256 buybackEth = (ethAmount * BUYBACK_PERCENTAGE) / 100;
        uint256 currentPicaPrice = getPicaPriceFromLP();
        
        uint256 buybackEthInUsd = buybackEth.getConversionRate(priceFeed);
        baseTokens = currentPicaPrice > 0 ? (buybackEthInUsd * 1e18) / currentPicaPrice : 0;
        
        uint256 bonusPercentage = getNFTTierBonus(user);
        bonusTokens = (baseTokens * bonusPercentage) / 100;

        uint256 liquidityEth = (ethAmount * LIQUIDITY_PERCENTAGE) / 100;
        uint256 liquidityValueInUsd = liquidityEth.getConversionRate(priceFeed);
        uint256 liquidityCompensation = currentPicaPrice > 0 ? (liquidityValueInUsd * 1e18) / currentPicaPrice : 0;

        totalTokens = baseTokens + bonusTokens + liquidityCompensation;
        
        return (baseTokens, bonusTokens, totalTokens);
    }

    function getTotalEthFundedInEth() public view returns (uint256) {
        return totalEthFunded / 1e18;
    }
    
    function getCurrentPicaPrice() external view returns (uint256) {
        return getPicaPriceFromLP();
    }
    
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
    
    function getUserTierBonus(address user) external view returns (uint256 bonusPercentage, string memory tierName) {
        bonusPercentage = getNFTTierBonus(user);
        
        if (bonusPercentage == BRONZE_BONUS) return (bonusPercentage, "Bronze");
        if (bonusPercentage == SILVER_BONUS) return (bonusPercentage, "Silver");
        if (bonusPercentage == GOLD_BONUS) return (bonusPercentage, "Gold");
        return (0, "No NFT");
    }

    function testPoolPrice() public view returns (
    uint160 sqrtPriceX96,
    address token0,
    address token1,
    uint256 calculatedPrice
    ) {
        (sqrtPriceX96,,,,,,) = picaEthPool.slot0();
        token0 = picaEthPool.token0();
        token1 = picaEthPool.token1();
        calculatedPrice = getPicaPriceFromLP();
    }

    function collectAllFees() external onlyOwner {
    for (uint i = 0; i < liquidityPositionIds.length; i++) {
        INonfungiblePositionManager.CollectParams memory params = 
            INonfungiblePositionManager.CollectParams({
                tokenId: liquidityPositionIds[i],
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });
        
        try positionManager.collect(params) {} catch {}
    }
}
}