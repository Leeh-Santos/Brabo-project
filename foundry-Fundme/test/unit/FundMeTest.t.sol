// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {FundMe} from "../../src/FundMe.sol";
import {NftBrabo} from "../../src/NftBrabo.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockUniswapV3Pool} from "../mocks/MockUniswapV3Pool.sol";

contract FundMeTest is Test {
    // ─── Contracts ─────────────────────────────────────────────────────────────
    FundMe              public fundMe;
    NftBrabo            public braboNft;
    MockV3Aggregator    public priceFeed;
    MockERC20           public picaToken;
    MockUniswapV3Pool   public picaEthPool;

    // ─── Addresses ─────────────────────────────────────────────────────────────
    address public OWNER = makeAddr("owner");
    address public USER  = makeAddr("user");

    /// Base Uniswap V3 SwapRouter02 — hardcoded inside FundMe.fund().
    address public constant ROUTER02 = 0x2626664c2603336E57B271c5C0b26F421741e481;

    /// Canonical WETH address on Base.
    address public constant WETH = 0x4200000000000000000000000000000000000006;

    // ─── Constants ─────────────────────────────────────────────────────────────
    /// ETH price: $2 000 (8 decimals, as returned by Chainlink).
    int256  public constant ETH_PRICE            = 2_000e8;

    /// sqrtPriceX96 = 2^96  →  getPicaPerWeth() returns exactly 1e18.
    ///      Derivation: ratioX128 = (2^96)^2 >> 64 = 2^128
    ///                  result    = (2^128 * 1e18) >> 128 = 1e18
    uint160 public constant SQRT_PRICE_X96       = uint160(1 << 96);

    /// Large PICA balance seeded into FundMe for compensation payouts.
    uint256 public constant INITIAL_PICA_BALANCE = 1_000_000e18;

    uint256 public constant SEND_VALUE = 0.01 ether;

    // ─── Setup ─────────────────────────────────────────────────────────────────

    function setUp() public {
        // 1. Deploy mocks
        priceFeed  = new MockV3Aggregator(8, ETH_PRICE);
        picaToken  = new MockERC20("PicaToken", "PICA");
        picaEthPool = new MockUniswapV3Pool(
            WETH,               // token0 = WETH
            address(picaToken), // token1 = PICA
            SQRT_PRICE_X96
        );

        // 2. Deploy NftBrabo (OWNER is its i_owner)
        vm.prank(OWNER);
        braboNft = new NftBrabo("bronze_uri", "silver_uri", "gold_uri");

        // 3. Deploy FundMe (OWNER is its i_owner)
        //    swapRouter / positionManager are not called in the functions under test
        //    so we pass dummy addresses.
        vm.prank(OWNER);
        fundMe = new FundMe(
            address(priceFeed),
            address(picaToken),
            address(braboNft),
            address(picaEthPool),
            address(1), // swapRouter  — unused in tested paths
            address(2), // positionManager — unused in tested paths
            WETH
        );

        // 4. Authorise FundMe to mint NFTs
        vm.prank(OWNER);
        braboNft.setMinterContract(address(fundMe));

        // 5. Seed FundMe with PICA tokens so compensation transfers succeed
        picaToken.mint(address(fundMe), INITIAL_PICA_BALANCE);

        // 6. Give USER enough ETH for multiple fund() calls
        vm.deal(USER, 10 ether);

        // 7. Mock the hardcoded Base SwapRouter02 called inside fund().
        //    The mock intercepts any call to exactInputSingle on that address
        //    and returns 500e18 PICA as the amount bought back.
        vm.mockCall(
            ROUTER02,
            abi.encodeWithSelector(
                bytes4(keccak256(
                    "exactInputSingle((address,address,uint24,address,uint256,uint256,uint160))"
                ))
            ),
            abi.encode(uint256(500e18))
        );
    }

    // ─── Constructor / Initial State ───────────────────────────────────────────

    function test_Constructor_SetsOwner() public view {
        assertEq(fundMe.getOwner(), OWNER);
    }

    function test_Constructor_NotPaused() public view {
        assertFalse(fundMe.paused());
    }

    function test_Constructor_ZeroFunders() public view {
        assertEq(fundMe.totalFunders(), 0);
    }

    function test_Constants_MinimumUsd() public view {
        assertEq(fundMe.MINIMUM_USD(), 2e17);
    }

    function test_Constants_NftBonuses() public view {
        assertEq(fundMe.BRONZE_BONUS(), 2);
        assertEq(fundMe.SILVER_BONUS(), 5);
        assertEq(fundMe.GOLD_BONUS(), 10);
    }

    // ─── fund() reverts ────────────────────────────────────────────────────────

    function test_Fund_RevertIf_ZeroEth() public {
        vm.prank(USER);
        vm.expectRevert("You need to spend more ETH!");
        fundMe.fund{value: 0}();
    }

    function test_Fund_RevertIf_BelowMinimumUsd() public {
        // At $2 000 / ETH, 0.00000001 ETH ≈ $0.00002, well below $0.20 minimum
        vm.prank(USER);
        vm.expectRevert("You need to spend more ETH!");
        fundMe.fund{value: 0.00000001 ether}();
    }

    function test_Fund_RevertIf_Paused() public {
        vm.prank(OWNER);
        fundMe.setPaused(true);

        vm.prank(USER);
        vm.expectRevert("Contract is paused");
        fundMe.fund{value: SEND_VALUE}();
    }

    // ─── fund() success ────────────────────────────────────────────────────────

    function test_Fund_RecordsAmountFunded() public {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        assertEq(fundMe.getHowMuchDudeFunded(USER), SEND_VALUE);
    }

    function test_Fund_IncreasesTotalEthTracker() public {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        assertEq(fundMe.totaleth(), SEND_VALUE);
    }

    function test_Fund_AddsFunderToList() public {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        assertEq(fundMe.getFunders(0), USER);
        assertEq(fundMe.totalFunders(), 1);
    }

    function test_Fund_CountsFunderOnlyOnce() public {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        // Two fund() calls → totalFunders must still be 1
        assertEq(fundMe.totalFunders(), 1);
        // But the funded amount accumulates
        assertEq(fundMe.getHowMuchDudeFunded(USER), SEND_VALUE * 2);
    }

    function test_Fund_TransfersPicaCompensationToUser() public {
        uint256 userPicaBefore = picaToken.balanceOf(USER);

        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        // Compensation = getPicaPerWeth() * batchAllocation / 1e18
        //              = 1e18 * (0.01 ETH * 80%) / 1e18
        //              = 1e18 * 8e15 / 1e18 = 8e15
        uint256 expectedCompensation = 8e15;
        assertGe(picaToken.balanceOf(USER), userPicaBefore + expectedCompensation);
    }

    function test_Fund_ReducesPicaContractBalance() public {
        uint256 contractPicaBefore = picaToken.balanceOf(address(fundMe));

        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        assertLt(picaToken.balanceOf(address(fundMe)), contractPicaBefore);
    }

    function test_Fund_MintsNftWhenThresholdReached() public {
        // $0.01 ETH × $2 000 = $20, which is >= $5 NFT threshold
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        assertEq(braboNft.balanceOf(USER), 1);
        assertEq(braboNft.getTotalSupply(), 1);
    }

    // ─── setPaused ─────────────────────────────────────────────────────────────

    function test_SetPaused_ByOwner() public {
        vm.prank(OWNER);
        fundMe.setPaused(true);
        assertTrue(fundMe.paused());

        vm.prank(OWNER);
        fundMe.setPaused(false);
        assertFalse(fundMe.paused());
    }

    function test_SetPaused_RevertIf_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert(bytes4(keccak256("FundMe__NotOwner()")));
        fundMe.setPaused(true);
    }

    // ─── withdraw ──────────────────────────────────────────────────────────────

    function test_Withdraw_RevertIf_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert(bytes4(keccak256("FundMe__NotOwner()")));
        fundMe.withdraw();
    }

    function test_Withdraw_SendsEthToOwner() public {
        // Fund the contract so it holds some ETH
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        uint256 ownerBalanceBefore   = OWNER.balance;
        uint256 contractBalanceBefore = address(fundMe).balance;
        assertGt(contractBalanceBefore, 0);

        vm.prank(OWNER);
        fundMe.withdraw();

        assertEq(address(fundMe).balance, 0);
        assertEq(OWNER.balance, ownerBalanceBefore + contractBalanceBefore);
    }

    // ─── withdrawPicaTokens ────────────────────────────────────────────────────

    function test_WithdrawPicaTokens_RevertIf_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert(bytes4(keccak256("FundMe__NotOwner()")));
        fundMe.withdrawPicaTokens();
    }

    function test_WithdrawPicaTokens_ByOwner() public {
        uint256 contractBalance = picaToken.balanceOf(address(fundMe));
        assertGt(contractBalance, 0);

        vm.prank(OWNER);
        fundMe.withdrawPicaTokens();

        assertEq(picaToken.balanceOf(address(fundMe)), 0);
        assertEq(picaToken.balanceOf(OWNER), contractBalance);
    }

    // ─── view helpers ──────────────────────────────────────────────────────────

    function test_GetOwner_ReturnsDeployer() public view {
        assertEq(fundMe.getOwner(), OWNER);
    }

    function test_GetPicaTokenBalance_ReturnsContractBalance() public view {
        assertEq(fundMe.getPicaTokenBalance(), INITIAL_PICA_BALANCE);
    }

    function test_GetVersion_ReturnsPriceFeedVersion() public view {
        // MockV3Aggregator exposes version = 4
        assertEq(fundMe.getVersion(), 4);
    }

    function test_GetHowMuchDudeFundedInUsd_AfterFunding() public {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        // 0.01 ETH × $2 000 = $20 → 20e18 in 18-decimal representation
        // getHowMuchDudeFundedInUsd returns the raw 1e18-scaled value
        assertEq(fundMe.getHowMuchDudeFundedInUsd(USER), 20e18);
    }

    // ─── receive() / fallback() ────────────────────────────────────────────────

    function test_Receive_CallsFund() public {
        vm.prank(USER);
        (bool success,) = address(fundMe).call{value: SEND_VALUE}("");
        assertTrue(success);
        assertEq(fundMe.getHowMuchDudeFunded(USER), SEND_VALUE);
    }

    function test_Receive_RevertIf_Paused() public {
        vm.prank(OWNER);
        fundMe.setPaused(true);

        vm.prank(USER);
        vm.expectRevert("Contract is paused");
        (bool success,) = address(fundMe).call{value: SEND_VALUE}("");
        // suppress unused variable warning — revert is asserted above
        (success);
    }
}
