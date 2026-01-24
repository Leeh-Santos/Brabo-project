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
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';

interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;  // NO deadline field!
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

error FundMe__NotOwner();
error FundMe__InsufficientTokenBalance();
error FundMe__TokenTransferFailed();
error FundMe__BuybackFailed();
error FundMe__LiquidityAdditionFailed();
error FundMe__SlippageExceeded();
error InsufficientPicaBalance();
error InsufficientPicaBalance2();
        
contract FundMe is ReentrancyGuard {
    using PriceConverter for uint256;


    mapping(address => uint256) private addressToAmountFunded;
    mapping(address => uint256) private addressToAmountFundedInUsd;
    mapping(address => bool) private alreadyReceivedNft;
    mapping(address => bool) private hasFunded;
    mapping(uint256 => Deposit) public deposits;


    uint256[] public liquidityPositionIds;
    address[] private funders;
    uint256 public totalFunders;
    uint256 public totalEthFunded;
    uint256 public batchAmount;
    uint256 public totalBoughtBack;

    //for v2 debugging
    uint256 public brbused;
    uint256 public ethused;

    address public immutable WETH;

    address public  token0;
    address public token1;


    uint256 public mainPositionId;
    bool public hasMainPosition;
    
    address private immutable i_owner;
    uint256 public constant MINIMUM_USD = 2 * 10 ** 17;
    uint256 public constant MINLIQADD = 2 * 10 ** 15;
    
    AggregatorV3Interface internal priceFeed;
    IERC20 public immutable picaToken;
    NftBrabo public immutable braboNft;

    // Uniswap V3 specific variables
    IUniswapV3Pool public immutable picaEthPool;
    ISwapRouter public immutable swapRouter;
    INonfungiblePositionManager public immutable positionManager;
    
    // Split percentages
    
    
    // NFT Tier Bonuses
    uint256 public constant BRONZE_BONUS = 2; // 2% bonus
    uint256 public constant SILVER_BONUS = 5; // 5% bonus  
    uint256 public constant GOLD_BONUS = 10;  // 10% bonus
    uint24 public constant POOL_FEE = 3000;

    // Tracking variables
    uint256 public totalTokensBought;
    uint256 public totalEthUsedForBuyback;
    uint256 public totalEthUsedForLiquidity;
    uint256 public totalTokensAddedToLiquidity;

    // Emergency pause mechanism
    bool public paused = false;

    event Funded(address indexed funder, uint256 ethAmount, uint256 picaTokensAwarded, uint256 bonusPercentage);
    event NftMinted(address indexed recipient);
    event TierUpgraded(address indexed user, uint256 totalFundingUsd);
    event TokensBought(uint256 ethSpent, uint256 picaTokensBought, uint256 newPrice);
    event LiquidityAdded(uint256 ethAmount, uint256 picaAmount, uint256 tokenId);
    event SwapFailed(address indexed user, uint256 ethAmount, string reason);
    event BuybackFailed(address indexed user, uint256 ethAmount);
    event LiquidityFailed(address indexed user, uint256 ethAmount);
    event EthRefunded(address indexed user, uint256 ethAmount);

     struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }


    constructor(
        address _priceFeed, 
        address _picaToken,
        address _moodNft,
        address _picaEthPool,
        address _swapRouter,
        address _positionManager,
        address _WETH   
    ) {
        i_owner = msg.sender;
        priceFeed = AggregatorV3Interface(_priceFeed);
        picaToken = IERC20(_picaToken);
        braboNft = NftBrabo(_moodNft);
        picaEthPool = IUniswapV3Pool(_picaEthPool);
        swapRouter = ISwapRouter(_swapRouter);
        positionManager = INonfungiblePositionManager(_positionManager);
        WETH = _WETH;
        token0 = _WETH;
        token1 = _picaToken;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != i_owner) revert FundMe__NotOwner();
        _;
    }

    function fund() public payable whenNotPaused nonReentrant {

    require(msg.value.getConversionRate(priceFeed) >= MINIMUM_USD, "You need to spend more ETH!");

    uint256 ethValueInUsd = msg.value.getConversionRate(priceFeed);
    
    // BUY BACK PART
    uint256 buybackAmount = (msg.value * 20) / 100;  
    uint256 batchAllocation = (msg.value * 80) / 100;


    uint256 price_before_swap = getPicaPerWeth();


    ISwapRouter02 router02 = ISwapRouter02(0x2626664c2603336E57B271c5C0b26F421741e481);
    
    ISwapRouter02.ExactInputSingleParams memory params =
        ISwapRouter02.ExactInputSingleParams({
            tokenIn: address(WETH),
            tokenOut: address(picaToken),
            fee: POOL_FEE,
            recipient: msg.sender,
            amountIn: buybackAmount,  
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

    totalBoughtBack = router02.exactInputSingle{value: buybackAmount}(params);

    uint256 compensation = (price_before_swap * batchAllocation) / 1e18;

    uint256 contractBalance = picaToken.balanceOf(address(this));

    if (contractBalance >= compensation){
        require(picaToken.transfer(msg.sender, compensation), "Compensation transfer failed");
    }
    else {
        revert InsufficientPicaBalance();
    }
    
    batchAmount += batchAllocation;



    
    // NFT BONUS COOMPENSATION 
    uint256 bonusPercentage = getNFTTierBonus(msg.sender);
    uint256 bonusTokens = ((totalBoughtBack + compensation) * bonusPercentage) / 100;  

    if (bonusTokens <= picaToken.balanceOf(address(this))){
          require(picaToken.transfer(msg.sender, bonusTokens), "Compensation transfer failed");
      } else {
          revert InsufficientPicaBalance2();
      }
    // NFT minting logic
    if (addressToAmountFundedInUsd[msg.sender] + ethValueInUsd >= 5 * 10 ** 18 && !alreadyReceivedNft[msg.sender]) {
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



    emit Funded(msg.sender, msg.value, totalBoughtBack, bonusPercentage);
}


function addLiquidityToPool() public nonReentrant returns (  //GIVE COMPENSATION FOR CLICKER **IDEA
    uint256 tokenId,
    uint128 liquidity,
    uint256 amount0,
    uint256 amount1
) {

    if (batchAmount < MINLIQADD) {
        revert FundMe__LiquidityAdditionFailed();
    }

    // require(address(this).balance >= ethAmount, "Insufficient Pica"); check requirements 
    
    uint256 picaAmount = (getPicaPerWeth() * batchAmount) / 1e18; // Adjust for decimals since is wei     
    require(picaAmount > 0, "issue calculating PICA amount");    
    require(picaToken.balanceOf(address(this)) >= picaAmount, "Insufficient PICA in contract");

     if (hasMainPosition) {
            return _increaseExistingPosition(picaAmount, batchAmount);
        } 
    
   
    // Get pool information
    uint24 fee = picaEthPool.fee();
    
    // Determine which token is which
    bool picaIsToken0 = token0 == address(picaToken);
    
    // Approve tokens for position manager
    TransferHelper.safeApprove(
        address(picaToken),
        address(positionManager),
        picaAmount
    );
    
    // For full range liquidity, use MIN_TICK and MAX_TICK
    int24 tickSpacing = picaEthPool.tickSpacing();
    int24 tickLower = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
    int24 tickUpper = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
    
    // Calculate minimum amounts (5% slippage tolerance)
    uint256 amount0Min = picaIsToken0 ? (picaAmount * 95) / 100 : (batchAmount * 95) / 100;
    uint256 amount1Min = picaIsToken0 ? (batchAmount * 95) / 100 : (picaAmount * 95) / 100;
    
    // Set up mint parameters
    INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
        token0: token0,
        token1: token1,
        fee: fee,
        tickLower: tickLower,
        tickUpper: tickUpper,
        amount0Desired: picaIsToken0 ? picaAmount : batchAmount,
        amount1Desired: picaIsToken0 ? batchAmount : picaAmount,
        amount0Min: amount0Min,        // ✅ Added slippage protection
        amount1Min: amount1Min,        // ✅ Added slippage protection
        recipient: address(this),
        deadline: block.timestamp + 300  // ✅ 5 minute deadline
    });
    
    // Mint the position with ETH
    (tokenId, liquidity, amount0, amount1) = positionManager.mint{value: batchAmount}(params);
    
    // Store the position
    _createDeposit(address(this), tokenId);
    liquidityPositionIds.push(tokenId);
    
    // Calculate actual amounts used
    uint256 picaUsed = picaIsToken0 ? amount0 : amount1;
    uint256 ethUsed = picaIsToken0 ? amount1 : amount0;
    
    // Track totals with ACTUAL amounts
    totalEthUsedForLiquidity += ethUsed;        // ✅ Fixed
    totalTokensAddedToLiquidity += picaUsed;    // ✅ Fixed
    
    brbused += picaUsed;
    ethused += ethUsed;
    
    hasMainPosition = true;
    mainPositionId = tokenId; // should be here?

    emit LiquidityAdded(ethUsed, picaUsed, tokenId);

    batchAmount = 0;
    
    return (tokenId, liquidity, amount0, amount1);
}

function _increaseExistingPosition(uint256 picaAmount, uint256 ethAmount)
        internal
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        tokenId = mainPositionId;

        bool picaIsToken0 = token0 == address(picaToken);
        
        // Approve position manager
        TransferHelper.safeApprove(
            address(picaToken),
            address(positionManager),
            picaAmount
        );
        
        // Calculate minimums
        uint256 amount0Min = picaIsToken0 ? (picaAmount * 95) / 100 : (ethAmount * 95) / 100;
        uint256 amount1Min = picaIsToken0 ? (ethAmount * 95) / 100 : (picaAmount * 95) / 100;
        
        INonfungiblePositionManager.IncreaseLiquidityParams memory params = 
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: picaIsToken0 ? picaAmount : ethAmount,
                amount1Desired: picaIsToken0 ? ethAmount : picaAmount,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: block.timestamp + 300
            });
        
        (liquidity, amount0, amount1) = positionManager.increaseLiquidity{value: ethAmount}(params);
        
        // Update liquidity tracking
        deposits[tokenId].liquidity += liquidity;
        
        // Track amounts
        uint256 picaUsed = picaIsToken0 ? amount0 : amount1;
        uint256 ethUsed = picaIsToken0 ? amount1 : amount0;
        
        totalEthUsedForLiquidity += ethUsed;
        totalTokensAddedToLiquidity += picaUsed;
        
        brbused = picaUsed;
        ethused = ethUsed;
    
        batchAmount = 0;

        emit LiquidityAdded(ethUsed, picaUsed, tokenId);
        
        return (tokenId, liquidity, amount0, amount1);
    }
    
  

    function collectFees(uint256 tokenId) external onlyOwner returns (uint256 amount0, uint256 amount1) {
        
        
        INonfungiblePositionManager.CollectParams memory params =
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });
        
        (amount0, amount1) = positionManager.collect(params);
        
        // Send collected fees to owner
        _sendToOwner(amount0, amount1);
    }
    
    
    function removeLiquidity() external onlyOwner returns (uint256 amount0, uint256 amount1) {
        
        require(hasMainPosition, "No main position");
    
        uint256 tokenId = mainPositionId;

        uint128 liquidity = deposits[tokenId].liquidity;
        
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });
        
        (amount0, amount1) = positionManager.decreaseLiquidity(params);
        
        // Collect the tokens
        INonfungiblePositionManager.CollectParams memory collectParams =
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });
        
        positionManager.collect(collectParams);
        
        // Send tokens to owner
        _sendToOwner(amount0, amount1);
        
        // Update liquidity tracking
        deposits[tokenId].liquidity = 0;
    }


    function _sendToOwner(
        uint256 amount0,
        uint256 amount1
    ) internal {

        // Transfer both tokens as ERC20 (including WETH)
        if (amount0 > 0) {
            TransferHelper.safeTransfer(token0, i_owner, amount0);
        }

        if (amount1 > 0) {
            TransferHelper.safeTransfer(token1, i_owner, amount1);
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

    function _createDeposit(address owner, uint256 tokenId) internal {
        (, , , , , , , uint128 liquidity, , , , ) =
            positionManager.positions(tokenId);
        
        deposits[tokenId] = Deposit({
            owner: owner,
            liquidity: liquidity,
            token0: token0,
            token1: token1
        });
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

    function withdrawToken(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No balance");
        TransferHelper.safeTransfer(token, i_owner, balance);
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
    

    function getTotalEthFundedInEth() public view returns (uint256) {
        return totalEthFunded / 1e18;
    }
    
    
    function getUserTierBonus(address user) external view returns (uint256 bonusPercentage, string memory tierName) {
        bonusPercentage = getNFTTierBonus(user);
        
        if (bonusPercentage == BRONZE_BONUS) return (bonusPercentage, "Bronze");
        if (bonusPercentage == SILVER_BONUS) return (bonusPercentage, "Silver");
        if (bonusPercentage == GOLD_BONUS) return (bonusPercentage, "Gold");
        return (0, "No NFT");
    }


    function getWethPerPica() public view returns (uint256) {
        (uint160 sqrtPriceX96, , , , , , ) = picaEthPool.slot0();
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        // price represents the ratio of token1/token0
        uint256 priceX192 = uint256(sqrtPrice) * uint256(sqrtPrice);

        if (token0 == address(WETH)) {
            // token0 = WETH, token1 = PICA
            // priceX192 = (PICA/WETH) * 2^192
            // We want WETH/PICA, so invert: (WETH/PICA) = 2^192 / priceX192
            // With 18 decimal adjustment: result = (2^192 * 1e18) / priceX192
            return (uint256(1) << 192) * 1e18 / priceX192;
        } else {
            // token0 = PICA, token1 = WETH
            // priceX192 = (WETH/PICA) * 2^192
            // We want WETH/PICA: result = priceX192 * 1e18 / 2^192
            return priceX192 * 1e18 >> 192;
        }
    }

        // How many PICA can I buy with 1 WETH (should return ~2,652,780 * 1e18)
function getPicaPerWeth() public view returns (uint256) {
    (uint160 sqrtPriceX96, , , , , , ) = picaEthPool.slot0();
    
    if (token0 == address(WETH)) {
        // token0 = WETH, token1 = PICA
        // price = (sqrtPriceX96 / 2^96)^2 with 18 decimals
        
        // Method: Use FullMath-style calculation to avoid overflow
        // price = sqrtPriceX96^2 * 1e18 / 2^192
        
        // Split into: (sqrtPriceX96^2 / 2^64) * 1e18 / 2^128
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        uint256 ratioX128 = (sqrtPrice * sqrtPrice) >> 64;  // Now it's X128 format
        
        return (ratioX128 * 1e18) >> 128;
        
    } else {
        // token0 = PICA, token1 = WETH
        // price in pool = WETH/PICA, we need PICA/WETH
        
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        uint256 ratioX128 = (sqrtPrice * sqrtPrice) >> 64;
        uint256 wethPerPica = (ratioX128 * 1e18) >> 128;
        
        require(wethPerPica > 0, "Invalid price");
        return 1e36 / wethPerPica;
    }
}

}