// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {NFTPoolBurnAndMint} from "../../src/core/NFTPoolBurnAndMint.sol";
import {WrappedNFT} from "../../src/core/WrappedNFT.sol";
import {InvariantMockRouter, DestVaultHandler} from "./handlers/DestVaultHandler.sol";

/// @title DestVaultInvariantTest
/// @notice Invariant tests for the destination-chain burn-and-mint pool.
contract DestVaultInvariantTest is Test {
    NFTPoolBurnAndMint pool;
    WrappedNFT wnft;
    InvariantMockRouter router;
    DestVaultHandler handler;

    address owner = address(this);
    address[] actors;

    uint64 constant SOURCE_CHAIN = 16015286601757825753;
    uint256 constant MAX_TOKEN_ID = 10;

    function setUp() public {
        router = new InvariantMockRouter();
        wnft = new WrappedNFT("Wrapped", "WNFT");
        pool = new NFTPoolBurnAndMint(address(router), address(this), address(wnft), owner);
        wnft.transferOwnership(address(pool));

        pool.allowlistDestinationChain(SOURCE_CHAIN, true);
        pool.allowlistSourceChain(SOURCE_CHAIN, true);

        for (uint256 i = 0; i < 3; i++) {
            actors.push(makeAddr(string(abi.encodePacked("actor", i))));
        }

        handler = new DestVaultHandler(pool, wnft, SOURCE_CHAIN, actors);
        pool.allowlistSender(address(handler), true);

        for (uint256 i = 0; i < actors.length; i++) {
            vm.deal(actors[i], 100 ether);
        }

        targetContract(address(handler));
    }

    // ----------------------------------------------------------------
    // Invariant 1: mintedTokenIds flag is equivalent to Wrapped NFT existence
    // ----------------------------------------------------------------
    function invariant_MintedFlagMatchesExistence() public view {
        for (uint256 id = 0; id < MAX_TOKEN_ID; id++) {
            bool flagged = pool.mintedTokenIds(id);
            bool exists = _exists(id);
            assertEq(flagged, exists, "mintedTokenIds flag must exactly match wrapped NFT existence");
        }
    }

    // ----------------------------------------------------------------
    // Invariant 2: WrappedNFT totalSupply == number of flagged minted tokenIds
    // ----------------------------------------------------------------
    function invariant_SupplyMatchesMintedCount() public view {
        uint256 flaggedCount;
        for (uint256 id = 0; id < MAX_TOKEN_ID; id++) {
            if (pool.mintedTokenIds(id)) flaggedCount++;
        }
        assertEq(wnft.totalSupply(), flaggedCount, "wrapped totalSupply must equal number of minted flag entries");
    }

    // ----------------------------------------------------------------
    // Invariant 3: pool never holds wrapped NFTs directly
    //   (burnAndSendNFT transfers in then burns, so the balance should be zero
    //    between transactions and at rest)
    // ----------------------------------------------------------------
    function invariant_PoolNeverHoldsWrapped() public view {
        for (uint256 id = 0; id < MAX_TOKEN_ID; id++) {
            if (_exists(id)) {
                assertTrue(wnft.ownerOf(id) != address(pool), "pool must not retain ownership of wrapped NFTs");
            }
        }
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        try wnft.ownerOf(tokenId) returns (address) {
            return true;
        } catch {
            return false;
        }
    }
}
