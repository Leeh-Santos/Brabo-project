// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

contract MoodNft is ERC721 {

    error MoodNft__CantFlipMoodIfNotOwner();
    error MoodNft__NotAuthorizedToMint();

    uint256 private s_tokenIdCounter;
    string private s_sadSvgUriimage;
    string private s_happySvgUriimage;
    
    address public immutable i_owner;
    address public minterContract;

    enum MOOD {
        SAD,
        HAPPY
    }
    
    mapping(uint256 => MOOD) private s_tokenIdtoMood;

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

    constructor(string memory sadSvg, string memory happySvg) ERC721("MoodNft", "MNFT") {
        s_tokenIdCounter = 0;
        s_sadSvgUriimage = sadSvg;
        s_happySvgUriimage = happySvg;
        i_owner = msg.sender;
    }

    function setMinterContract(address _minterContract) external onlyOwner {
        minterContract = _minterContract;
    }

    // Removed mintNft() function that used tx.origin - use mintNftTo instead

    function mintNftTo(address recipient) public onlyMinter {
        _safeMint(recipient, s_tokenIdCounter);
        s_tokenIdtoMood[s_tokenIdCounter] = MOOD.HAPPY;
        s_tokenIdCounter++;
    }

    function _baseURI() internal pure override returns (string memory) {
        return "data:application/json;base64,";
    }

    function flipMood(uint256 tokenId) public {
        require(_ownerOf(tokenId) == msg.sender, "Not token owner");
        
        if(s_tokenIdtoMood[tokenId] == MOOD.HAPPY){
            s_tokenIdtoMood[tokenId] = MOOD.SAD;
        } else {
            s_tokenIdtoMood[tokenId] = MOOD.HAPPY;
        }
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        string memory imageURI;

        if(s_tokenIdtoMood[tokenId] == MOOD.HAPPY){
            imageURI = s_happySvgUriimage;
        } else {
            imageURI = s_sadSvgUriimage;
        }

        return string(
            abi.encodePacked(
                _baseURI(),
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name":"',
                            name(),
                            '", "description":"An NFT that reflects the mood of the owner, 100% on Chain!", ',
                            '"attributes": [{"trait_type": "moodiness", "value": 100}], "image":"',
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