// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Minimal ERC721Enumerable used ONLY for gas comparison in tests.
contract PlainERC721Enumerable is ERC721, ERC721Enumerable, Ownable {
    uint256 private _nextId;

    constructor() ERC721("PlainEnum", "PLAINE") Ownable(msg.sender) {}

    function mint(address to) external onlyOwner returns (uint256) {
        uint256 id = _nextId++;
        _safeMint(to, id);
        return id;
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
