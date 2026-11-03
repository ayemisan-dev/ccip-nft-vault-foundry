// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC721A} from "ERC721A/ERC721A.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Minimal ERC721A used ONLY for gas comparison in tests.
/// @dev Do NOT use in production without understanding ERC721A's storage model.
contract PlainERC721A is ERC721A, Ownable {
    constructor() ERC721A("PlainA", "PLAINA") Ownable(msg.sender) {}

    function mint(address to, uint256 quantity) external onlyOwner {
        _mint(to, quantity);
    }
}
