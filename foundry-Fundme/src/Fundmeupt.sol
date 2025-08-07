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
    uint256 public constant MINIMUM_USD = 1 * 10 ** 18;
    
    AggregatorV3Interface internal priceFeed;
    IERC20 public immutable picaToken;
    NftBrabo public immutable braboNft;

    // Uniswap V3 specific variables
    IUniswapV3Pool public immutable picaEthPool;
    INonfungiblePositionManager public immutable positionManager;
    ISwapRouter public immutable swapRouter;
    
    uint256 public constant LP_PERCENTAGE = 10; // 10% goes to LP
    uint256 public constant REWARD_PERCENTAGE = 90; // 90% goes to user
    
    // V3 specific variables
    uint256 public positionTokenId; // NFT token ID of our LP position
    int24 public tickLower; // Lower tick of our position
    int24 public tickUpper; // Upper tick of our position

    event Funded(address indexed funder, uint256 ethAmount, uint256 picaTokensAwarded);
    event NftMinted(address indexed recipient);
    event TierUpgraded(address indexed user, uint256 totalFundingUsd);
    event LiquidityAdded(uint256 ethAmount, uint256 picaAmount);

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
        
        // Set wide tick range for maximum liquidity coverage
        int24 tickSpacing = picaEthPool.tickSpacing();
        (, int24 currentTick,,,,,) = picaEthPool.slot0();
        tickLower = currentTick - (tickSpacing * 100); // 100 ticks below
        tickUpper = currentTick + (tickSpacing * 100); // 100 ticks above
    }

    function fund() public payable {
        require(msg.value.getConversionRate(priceFeed) >= MINIMUM_USD, "You need to spend more ETH!");
        
        uint256 ethValueInUsd = msg.value.getConversionRate(priceFeed);
        
        // Split the funding: 10% to LP, 90% to user rewards
        uint256 lpEthAmount = msg.value * LP_PERCENTAGE / 100;
        uint256 rewardValueInUsd = ethValueInUsd * REWARD_PERCENTAGE / 100;
        
        // Add liquidity immediately (Base L2 = low gas costs)
        addLiquidityToPoolImmediate(lpEthAmount);
        
        // Get current PICA price from LP and calculate reward tokens
        uint256 currentPicaPrice = getPicaPriceFromLP();
        uint256 picaTokenAmount = rewardValueInUsd / currentPicaPrice;
        
        // NFT minting logic (using total funding amount)
        if (addressToAmountFundedInUsd[msg.sender] + ethValueInUsd >= 10 * 10 ** 18 && !alreadyReceivedNft[msg.sender]) {
            alreadyReceivedNft[msg.sender] = true;
            braboNft.mintNftTo(msg.sender);
            emit NftMinted(msg.sender);
        }
       
        // Update tracking
        addressToAmountFunded[msg.sender] += msg.value;
        totalEthFunded += msg.value;
        addressToAmountFundedInUsd[msg.sender] += ethValueInUsd;

        // NFT tier upgrade logic
        if (alreadyReceivedNft[msg.sender]) {
            braboNft.upgradeTierBasedOnFunding(msg.sender, addressToAmountFundedInUsd[msg.sender]);
            emit TierUpgraded(msg.sender, addressToAmountFundedInUsd[msg.sender]);
        }

        // Update funders list
        if (!hasFunded[msg.sender]) {
            funders.push(msg.sender);       
            hasFunded[msg.sender] = true;
            totalFunders++;
        }
       
        // Transfer PICA reward tokens to user
        uint256 contractBalance = picaToken.balanceOf(address(this));
        if (contractBalance < picaTokenAmount) {
            revert FundMe__InsufficientTokenBalance();
        }
        
        bool success = picaToken.transfer(msg.sender, picaTokenAmount);
        if (!success) {
            revert FundMe__TokenTransferFailed();
        }

        emit Funded(msg.sender, msg.value, picaTokenAmount);
    }

    function addLiquidityToPoolImmediate(uint256 ethAmount) internal {
        // Calculate proportional PICA tokens needed for LP
        uint256 currentPicaPrice = getPicaPriceFromLP();
        uint256 ethValueInUsd = ethAmount.getConversionRate(priceFeed);
        uint256 picaTokensNeeded = ethValueInUsd / currentPicaPrice;
        
        // Check if contract has enough PICA tokens
        uint256 contractPicaBalance = picaToken.balanceOf(address(this));
        if (contractPicaBalance < picaTokensNeeded) {
            revert FundMe__InsufficientTokenBalance();
        }
        
        // Approve PICA tokens for position manager
        picaToken.approve(address(positionManager), picaTokensNeeded);
        
        // Determine token order (token0 vs token1)
        address token0 = picaEthPool.token0();
        address token1 = picaEthPool.token1();
        
        uint256 amount0Desired;
        uint256 amount1Desired;
        
        if (token0 == address(picaToken)) {
            amount0Desired = picaTokensNeeded;
            amount1Desired = ethAmount;
        } else {
            amount0Desired = ethAmount;
            amount1Desired = picaTokensNeeded;
        }
        
        // Increase liquidity if we already have a position
        if (positionTokenId > 0) {
            INonfungiblePositionManager.IncreaseLiquidityParams memory params = 
                INonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: positionTokenId,
                    amount0Desired: amount0Desired,
                    amount1Desired: amount1Desired,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 300
                });
            
            try positionManager.increaseLiquidity{value: ethAmount}(params) 
                returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
                emit LiquidityAdded(ethAmount, picaTokensNeeded);
            } catch {
                revert FundMe__LiquidityAdditionFailed();
            }
        } else {
            // Create new position if we don't have one
            INonfungiblePositionManager.MintParams memory params = 
                INonfungiblePositionManager.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: picaEthPool.fee(),
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: amount0Desired,
                    amount1Desired: amount1Desired,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp + 300
                });
            
            try positionManager.mint{value: ethAmount}(params) 
                returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
                positionTokenId = tokenId;
                emit LiquidityAdded(ethAmount, picaTokensNeeded);
            } catch {
                revert FundMe__LiquidityAdditionFailed();
            }
        }
    }

    function getPicaPriceFromLP() internal view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,) = picaEthPool.slot0();
        
        // Convert sqrtPriceX96 to actual price
        // Price = (sqrtPriceX96 / 2^96)^2
        uint256 price = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) / (2**192);
        
        // Adjust for token decimals and determine which token is token0
        address token0 = picaEthPool.token0();
        uint256 ethPriceInUsd = uint256(1 * 10**18).getConversionRate(priceFeed);
        
        if (token0 == address(picaToken)) {
            // PICA is token0, ETH is token1
            // Price is ETH per PICA, so we need to invert and multiply by ETH price
            return price == 0 ? 1e18 : (ethPriceInUsd * (2**192)) / (uint256(sqrtPriceX96) * uint256(sqrtPriceX96));
        } else {
            // ETH is token0, PICA is token1
            // Price is PICA per ETH, so multiply by ETH price and invert
            return price == 0 ? 1e18 : (ethPriceInUsd) / price;
        }
    }

    // Function to set initial position (call after creating initial LP)
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

    // View functions
    function getHowMuchDudeFunded(address _sAdrees) external view returns (uint256) {
        return addressToAmountFunded[_sAdrees];
    }

    function getHowMuchDudeFundedInUsdActual(address _address) external view returns (uint256) {
        return addressToAmountFundedInUsd[_address] / 1e18;
    }

    function getHowMuchDudeFundedInUsd(address _sAdrees) external view returns (uint256) {
        return addressToAmountFundedInUsd[_sAdrees];
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
    
    function calculatePicaTokenReward(uint256 ethAmount) external view returns (uint256) {
        uint256 ethValueInUsd = ethAmount.getConversionRate(priceFeed);
        uint256 rewardValueInUsd = ethValueInUsd * REWARD_PERCENTAGE / 100;
        uint256 currentPicaPrice = getPicaPriceFromLP();
        return rewardValueInUsd / currentPicaPrice;
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
}