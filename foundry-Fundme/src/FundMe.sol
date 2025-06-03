// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./PriceConverter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NftBrabo} from "./NftBrabo.sol";

error FundMe__NotOwner();
error FundMe__InsufficientTokenBalance();
error FundMe__TokenTransferFailed();

contract FundMe {
    using PriceConverter for uint256;

    mapping(address => uint256) private addressToAmountFunded;
    address[] private funders;

    address private immutable i_owner;
    uint256 public constant MINIMUM_USD = 5 * 10 ** 18;
    
    AggregatorV3Interface internal priceFeed;
    IERC20 public immutable picaToken;
    NftBrabo public immutable braboNft;
    
    // Exchange rate: for 1 ETH worth, give 2 PicaTokens
    uint256 public constant PICA_MULTIPLIER = 2;

    event Funded(address indexed funder, uint256 ethAmount, uint256 picaTokensAwarded);

    constructor(
        address _priceFeed, 
        address _picaToken,
        address _moodNft
    ) {
        i_owner = msg.sender;
        priceFeed = AggregatorV3Interface(_priceFeed);
        picaToken = IERC20(_picaToken);
        braboNft = NftBrabo(_moodNft);
    }

    function fund() public payable {
        require(msg.value.getConversionRate(priceFeed) >= MINIMUM_USD, "You need to spend more ETH!");
        
        // Calculate how much PicaToken to give (2x the ETH value)
        uint256 ethValueInUsd = msg.value.getConversionRate(priceFeed);
        uint256 picaTokenAmount = (ethValueInUsd * PICA_MULTIPLIER) / 1e18; // Assuming PicaToken has 18 decimals
        
        // Check if contract has enough PicaTokens
        uint256 contractBalance = picaToken.balanceOf(address(this));
        if (contractBalance < picaTokenAmount) {
            revert FundMe__InsufficientTokenBalance();
        }
        
        // Transfer PicaTokens to the funder
        bool success = picaToken.transfer(msg.sender, picaTokenAmount);
        if (!success) {
            revert FundMe__TokenTransferFailed();
        }
        
        // Mint an NFT for the funder
        braboNft.mintNftTo(msg.sender);
        
        // Update funding records
        addressToAmountFunded[msg.sender] += msg.value;
        funders.push(msg.sender);
        
        emit Funded(msg.sender, msg.value, picaTokenAmount);
    }

    function getVersion() public view returns (uint256) {
        return priceFeed.version();
    }

    modifier onlyOwner() {
        if (msg.sender != i_owner) revert FundMe__NotOwner();
        _;
    }

    function withdraw() public onlyOwner {
        for (uint256 funderIndex = 0; funderIndex < funders.length; funderIndex++) {
            address funder = funders[funderIndex];
            addressToAmountFunded[funder] = 0;
        }
        funders = new address[](0);
        
        (bool callSuccess,) = payable(msg.sender).call{value: address(this).balance}("");
        require(callSuccess, "Call failed");
    }
    
    // Allow owner to withdraw any remaining PicaTokens
    function withdrawPicaTokens() public onlyOwner {
        uint256 balance = picaToken.balanceOf(address(this));
        bool success = picaToken.transfer(i_owner, balance);
        require(success, "Token withdrawal failed");
    }
    
    // Allow owner to deposit more PicaTokens for rewards
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
        return (ethValueInUsd * PICA_MULTIPLIER) / 1e18;
    }
}