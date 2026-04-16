// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {NftBrabo} from "../../src/NftBrabo.sol";

contract NftBraboTest is Test {
    NftBrabo public braboNft;

    address public OWNER   = makeAddr("owner");
    address public USER    = makeAddr("user");
    address public USER_B  = makeAddr("userB");
    address public MINTER  = makeAddr("minter");

    function setUp() public {
        vm.prank(OWNER);
        braboNft = new NftBrabo("bronze_uri", "silver_uri", "gold_uri");

        // Set a dedicated minter so we can test authorization separately from owner
        vm.prank(OWNER);
        braboNft.setMinterContract(MINTER);
    }

    // ─── Metadata ──────────────────────────────────────────────────────────────

    function test_Name_IsCorrect() public view {
        assertEq(braboNft.name(), "BraboNft");
    }

    function test_Symbol_IsCorrect() public view {
        assertEq(braboNft.symbol(), "BNFT");
    }

    function test_InitialTotalSupply_IsZero() public view {
        assertEq(braboNft.getTotalSupply(), 0);
    }

    // ─── setMinterContract ─────────────────────────────────────────────────────

    function test_SetMinterContract_ByOwner() public {
        vm.prank(OWNER);
        braboNft.setMinterContract(USER_B);
        assertEq(braboNft.s_minterContract(), USER_B);
    }

    function test_SetMinterContract_RevertIf_NotOwner() public {
        vm.prank(USER);
        vm.expectRevert("Not owner");
        braboNft.setMinterContract(USER);
    }

    // ─── mintNftTo ─────────────────────────────────────────────────────────────

    function test_MintNftTo_ByMinter_Success() public {
        vm.prank(MINTER);
        braboNft.mintNftTo(USER);

        assertEq(braboNft.balanceOf(USER), 1);
        assertEq(braboNft.getTotalSupply(), 1);
    }

    function test_MintNftTo_ByOwner_Success() public {
        // Owner also satisfies the onlyMinter modifier
        vm.prank(OWNER);
        braboNft.mintNftTo(USER);

        assertEq(braboNft.balanceOf(USER), 1);
    }

    function test_MintNftTo_AssignsTokenIdToRecipient() public {
        vm.prank(MINTER);
        braboNft.mintNftTo(USER);

        // First minted token is always id 0
        assertEq(braboNft.getTokenIdByOwner(USER), 0);
    }

    function test_MintNftTo_DefaultsToBronzeTier() public {
        vm.prank(MINTER);
        braboNft.mintNftTo(USER);

        assertEq(braboNft.getUserTier(USER), 0); // 0 = Bronze
    }

    function test_MintNftTo_IncrementsTotalSupply() public {
        vm.prank(MINTER);
        braboNft.mintNftTo(USER);

        vm.prank(MINTER);
        braboNft.mintNftTo(USER_B);

        assertEq(braboNft.getTotalSupply(), 2);
    }

    function test_MintNftTo_RevertIf_NotAuthorized() public {
        vm.prank(USER);
        vm.expectRevert(NftBrabo.MoodNft__NotAuthorizedToMint.selector);
        braboNft.mintNftTo(USER);
    }

    function test_MintNftTo_RevertIf_AlreadyHasNft() public {
        vm.prank(MINTER);
        braboNft.mintNftTo(USER);

        vm.prank(MINTER);
        vm.expectRevert("Address already has an NFT");
        braboNft.mintNftTo(USER);
    }

    // ─── getUserTier / getTokenIdByOwner ───────────────────────────────────────

    function test_GetUserTier_RevertIf_NoNft() public {
        vm.expectRevert(NftBrabo.MoodNft__TokenDoesNotExist.selector);
        braboNft.getUserTier(USER);
    }

    function test_GetTokenIdByOwner_RevertIf_NoNft() public {
        vm.expectRevert(NftBrabo.MoodNft__TokenDoesNotExist.selector);
        braboNft.getTokenIdByOwner(USER);
    }

    // ─── upgradeTierBasedOnFunding ─────────────────────────────────────────────

    function test_UpgradeTier_ToSilver_At50Usd() public {
        vm.prank(MINTER);
        braboNft.mintNftTo(USER);

        vm.prank(MINTER);
        braboNft.upgradeTierBasedOnFunding(USER, 50e18); // exactly $50

        assertEq(braboNft.getUserTier(USER), 1); // 1 = Silver
    }

    function test_UpgradeTier_ToGold_At100Usd() public {
        vm.prank(MINTER);
        braboNft.mintNftTo(USER);

        vm.prank(MINTER);
        braboNft.upgradeTierBasedOnFunding(USER, 100e18); // exactly $100

        assertEq(braboNft.getUserTier(USER), 2); // 2 = Gold
    }

    function test_UpgradeTier_DoesNotDowngrade() public {
        vm.prank(MINTER);
        braboNft.mintNftTo(USER);

        // Upgrade to Gold
        vm.prank(MINTER);
        braboNft.upgradeTierBasedOnFunding(USER, 100e18);
        assertEq(braboNft.getUserTier(USER), 2);

        // Call with a low amount — tier must stay at Gold
        vm.prank(MINTER);
        braboNft.upgradeTierBasedOnFunding(USER, 1e18);
        assertEq(braboNft.getUserTier(USER), 2);
    }

    function test_UpgradeTier_NoOp_IfUserHasNoNft() public {
        // Should not revert, just return early
        vm.prank(MINTER);
        braboNft.upgradeTierBasedOnFunding(USER, 100e18);
        // getUserTier would revert here, but no NFT means nothing changed
    }

    function test_UpgradeTier_RevertIf_NotMinter() public {
        vm.prank(MINTER);
        braboNft.mintNftTo(USER);

        vm.prank(USER);
        vm.expectRevert(NftBrabo.MoodNft__NotAuthorizedToMint.selector);
        braboNft.upgradeTierBasedOnFunding(USER, 100e18);
    }

    // ─── getMoodString ─────────────────────────────────────────────────────────

    function test_GetMoodString_Bronze() public {
        vm.prank(MINTER);
        braboNft.mintNftTo(USER);

        assertEq(braboNft.getMoodString(0), "Bronze");
    }

    function test_GetMoodString_Silver() public {
        vm.prank(MINTER);
        braboNft.mintNftTo(USER);

        vm.prank(MINTER);
        braboNft.upgradeTierBasedOnFunding(USER, 50e18);

        assertEq(braboNft.getMoodString(0), "Silver");
    }

    function test_GetMoodString_Gold() public {
        vm.prank(MINTER);
        braboNft.mintNftTo(USER);

        vm.prank(MINTER);
        braboNft.upgradeTierBasedOnFunding(USER, 100e18);

        assertEq(braboNft.getMoodString(0), "Gold");
    }

    // ─── tokenURI ──────────────────────────────────────────────────────────────

    function test_TokenURI_StartsWithCorrectDataPrefix() public {
        vm.prank(MINTER);
        braboNft.mintNftTo(USER);

        string memory uri = braboNft.tokenURI(0);
        bytes memory uriBytes     = bytes(uri);
        bytes memory expectedPrefix = bytes("data:application/json;base64,");

        assertGe(uriBytes.length, expectedPrefix.length);
        for (uint256 i = 0; i < expectedPrefix.length; i++) {
            assertEq(uriBytes[i], expectedPrefix[i]);
        }
    }

    function test_TokenURI_RevertIf_TokenDoesNotExist() public {
        vm.expectRevert("Token does not exist");
        braboNft.tokenURI(999);
    }

    // ─── Transfer updates ownership mappings ───────────────────────────────────

    function test_Transfer_UpdatesOwnerMapping() public {
        vm.prank(MINTER);
        braboNft.mintNftTo(USER);

        uint256 tokenId = braboNft.getTokenIdByOwner(USER);

        // USER transfers NFT to USER_B
        vm.prank(USER);
        braboNft.transferFrom(USER, USER_B, tokenId);

        assertEq(braboNft.getTokenIdByOwner(USER_B), tokenId);

        // Original owner no longer has NFT
        vm.expectRevert(NftBrabo.MoodNft__TokenDoesNotExist.selector);
        braboNft.getTokenIdByOwner(USER);
    }
}
