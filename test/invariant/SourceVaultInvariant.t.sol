// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {NFTPoolLockAndRelease} from "../../src/core/NFTPoolLockAndRelease.sol";
import {MyNFT} from "../../src/mocks/MyNFT.sol";
import {InvariantMockRouter, SourceVaultHandler} from "./handlers/SourceVaultHandler.sol";

/// @title SourceVaultInvariantTest
/// @notice Invariant tests for the source-chain lock-and-release pool.
contract SourceVaultInvariantTest is Test {
    NFTPoolLockAndRelease pool;
    MyNFT nft;
    InvariantMockRouter router;
    SourceVaultHandler handler;

    address owner = address(this);
    address[] actors;

    uint64 constant DEST_CHAIN = 3478487238524512106;
    uint256 constant MAX_TOKEN_ID = 10;

    function setUp() public {
        // 1. Deploy dependencies.
        router = new InvariantMockRouter();
        nft = new MyNFT("Original", "ONFT");
        pool = new NFTPoolLockAndRelease(
            address(router),
            address(this), // LINK address (unused in native-only handler)
            address(nft),
            owner
        );

        // 2. Configure allowlist
        pool.allowlistDestinationChain(DEST_CHAIN, true);
        pool.allowlistSourceChain(DEST_CHAIN, true);

        // 3. Create actors.
        for (uint256 i = 0; i < 3; i++) {
            actors.push(makeAddr(string.concat("actor", vm.toString(i))));
        }

        // 4. Mint NFTs to actors.
        for (uint256 i = 0; i < MAX_TOKEN_ID; i++) {
            nft.safeMint(actors[i % actors.length]);
        }

        // 5. Deploy handler and allowlist it as the sender.
        handler = new SourceVaultHandler(pool, nft, DEST_CHAIN, actors);
        pool.allowlistSender(address(handler), true);

        // 6. Fund actors with native gas.
        for (uint256 i = 0; i < actors.length; i++) {
            vm.deal(actors[i], 100 ether);
        }

        // 7. Tell Foundry to only call the handler.
        targetContract(address(handler));
    }

    // ----------------------------------------------------------------
    // Invariant 1: locked token must be held by the pool
    // ----------------------------------------------------------------
    function invariant_LockedImpliesPoolOwns() public view {
        for (uint256 id = 0; id < MAX_TOKEN_ID; id++) {
            if (pool.tokenLocked(id)) {
                assertEq(nft.ownerOf(id), address(pool), "locked token must be held by pool");
            }
        }
    }

    // ----------------------------------------------------------------
    // Invariant 2: unlocked token must not be held by the pool
    //          (i.e. the pool holds *exactly* the set of locked tokens)
    // ----------------------------------------------------------------
    function invariant_PoolHoldsOnlyLocked() public view {
        // Every NFT the pool holds must have tokenLocked == true.
        for (uint256 id = 0; id < MAX_TOKEN_ID; id++) {
            if (nft.ownerOf(id) == address(pool)) {
                assertTrue(pool.tokenLocked(id), "pool holds an NFT that is not flagged as locked");
            }
        }
    }

    // ----------------------------------------------------------------
    // Invariant 3: every NFT is owned by exactly one address (ERC721 guaranteed)
    //   + the union of "held by pool" and "held by an actor" covers all tokens.
    // ----------------------------------------------------------------
    function invariant_AllTokensAccountedFor() public view {
        for (uint256 id = 0; id < MAX_TOKEN_ID; id++) {
            address holder = nft.ownerOf(id);
            assertTrue(holder == address(pool) || _isActor(holder), "token owned by unexpected address");
        }
    }

    // ----------------------------------------------------------------
    // Diagnostic helper
    // ----------------------------------------------------------------
    function _isActor(address who) internal view returns (bool) {
        for (uint256 i = 0; i < actors.length; i++) {
            if (actors[i] == who) return true;
        }
        return false;
    }
}
