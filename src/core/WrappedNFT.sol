// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {MyNFT} from "../mocks/MyNFT.sol";

/// @notice Wrapped NFT minted on the destination chain with the original tokenId.
/// @dev Both minting and burning are restricted to the owner (the bridge pool).
contract WrappedNFT is MyNFT {
    constructor(string memory name_, string memory symbol_) MyNFT(name_, symbol_) {}

    /// @notice Mint a wrapped NFT with the original tokenId. Pool-only.
    function mintWithSpecificTokenId(address to, uint256 tokenId) external onlyOwner {
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, META_DATA);
    }

    /// @notice Burn a wrapped NFT. Pool-only, so users cannot bypass the bridge.
    function burn(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }
}
