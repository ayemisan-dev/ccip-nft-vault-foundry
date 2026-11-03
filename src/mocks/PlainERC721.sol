// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Minimal plain ERC721 used ONLY for gas comparison in tests.
/// @dev Deliberately excludes URIStorage / Enumerable to isolate baseline mint cost.
contract PlainERC721 is ERC721, Ownable {
    uint256 private _nextId;

    constructor() ERC721("Plain", "PLAIN") Ownable(msg.sender) {}

    function mint(address to) external onlyOwner returns (uint256) {
        uint256 id = _nextId++;
        _safeMint(to, id);
        return id;
    }
}
