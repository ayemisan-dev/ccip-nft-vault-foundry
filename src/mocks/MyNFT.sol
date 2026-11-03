// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Original NFT on the source chain.
contract MyNFT is ERC721, ERC721URIStorage, Ownable {
    uint256 private _nextTokenId;
    uint256 private _totalSupply;

    string public constant META_DATA = "ipfs://Qmd7B6o3nEhWN58jaBiQW7goFQh7yL8vemY5fBnfSUmnC1";

    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) Ownable(msg.sender) {}

    function safeMint(address to) external onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, META_DATA);
        return tokenId;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = super._update(to, tokenId, auth);
        if (from == address(0)) {
            unchecked {
                _totalSupply++;
            }
        } else if (to == address(0)) {
            unchecked {
                _totalSupply--;
            }
        }
        return from;
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
