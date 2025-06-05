// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

contract NftBrabo is ERC721 {

    error MoodNft__CantFlipMoodIfNotOwner();
    error MoodNft__NotAuthorizedToMint();
    
    uint256 private s_tokenIdCounter;
    string private s_bronzeSvgUriimage;
    string private s_silverSvgUriimage;
    string private s_goldSvgUriimage;
    
    address public immutable i_owner;
    address public minterContract;

    mapping(uint256 => MOOD) private s_tokenIdtoMood;
    mapping(address => uint256[]) private s_ownerToTokenIds;


    enum MOOD {
        BRONZE,
        SILVER,
        GOLD
    }
    

    modifier onlyOwner() {
        require(msg.sender == i_owner, "Not owner");
        _;
    }

    modifier onlyMinter() {
        if (msg.sender != minterContract && msg.sender != i_owner) {
            revert MoodNft__NotAuthorizedToMint();
        }
        _;
    }

    constructor(string memory bronzeSvg, string memory silverSvg, string memory goldSvg) ERC721("MoodNft", "MNFT") {
        s_tokenIdCounter = 0;
        s_bronzeSvgUriimage= bronzeSvg;
        s_silverSvgUriimage = silverSvg;
        s_goldSvgUriimage = goldSvg;
        i_owner = msg.sender;
    }

    function setMinterContract(address _minterContract) external onlyOwner {
        minterContract = _minterContract;
    }


    function mintNftTo(address recipient) public onlyMinter {
        _safeMint(recipient, s_tokenIdCounter);
        s_tokenIdtoMood[s_tokenIdCounter] = MOOD.BRONZE;
        s_tokenIdCounter++;
    }

    function _baseURI() internal pure override returns (string memory) {
        return "data:application/json;base64,";
    }

    /*function checkTier(uint256 tokenId) public { /// different logic 
        require(_ownerOf(tokenId) == msg.sender, "Not token owner");
        
      
    }*/

   function getMoodString(uint256 tokenId) internal view returns (string memory) {
        MOOD mood = s_tokenIdtoMood[tokenId];
        if (mood == MOOD.GOLD) return "Gold";
        if (mood == MOOD.SILVER) return "Silver";
        return "Bronze";
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        string memory imageURI;

        if(s_tokenIdtoMood[tokenId] == MOOD.GOLD){
            imageURI = s_goldSvgUriimage;
        } else if (s_tokenIdtoMood[tokenId] == MOOD.SILVER) {
            imageURI = s_silverSvgUriimage;
        } else {
            imageURI = s_bronzeSvgUriimage;
        }

        return string(
             abi.encodePacked(
                 _baseURI(),
                 Base64.encode(
                     bytes(
                         abi.encodePacked(
                             '{"name":"',
                             name(),
                             '", "description":"A reactive NFT that reflects how BRABO you are, three tiers available: Bronze, Silver and Gold", ',
                             '"attributes": [{"trait_type": "Tier", "value": "', getMoodString(tokenId), '"}], "image":"',
                             imageURI,
                             '"}'
                         )
                     )
                 )
             )
         );
    }

    function getTotalSupply() external view returns (uint256) {
        return s_tokenIdCounter;
    }
}