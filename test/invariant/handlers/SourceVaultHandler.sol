// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {NFTPoolLockAndRelease} from "../../../src/core/NFTPoolLockAndRelease.sol";
import {MyNFT} from "../../../src/mocks/MyNFT.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

/// @notice Mock router used inside the handler.
contract InvariantMockRouter {
    function getFee(uint64, Client.EVM2AnyMessage memory) external pure returns (uint256) {
        return 0.001 ether;
    }

    function ccipSend(uint64, Client.EVM2AnyMessage memory) external payable returns (bytes32) {
        return keccak256(abi.encodePacked(block.timestamp, msg.sender));
    }
}

/// @title SourceVaultHandler
/// @notice Wraps NFTPoolLockAndRelease into bounded, precondition-guarded actions
///         so the invariant fuzzer explores realistic state transitions only.
contract SourceVaultHandler is Test {
    NFTPoolLockAndRelease public immutable pool;
    MyNFT public immutable nft;
    uint64 public immutable destChainSelector;

    address[] public actors;
    uint256 public constant MAX_TOKEN_ID = 10;

    uint256 public lockSuccesses;
    uint256 public unlockSuccesses;

    constructor(NFTPoolLockAndRelease _pool, MyNFT _nft, uint64 _destChain, address[] memory _actors) {
        pool = _pool;
        nft = _nft;
        destChainSelector = _destChain;
        actors = _actors;
    }

    // ----------------------------------------------------------------
    // Outbound: lock
    // ----------------------------------------------------------------
    function lockAndSend(uint256 actorSeed, uint256 tokenId) external {
        tokenId = bound(tokenId, 0, MAX_TOKEN_ID - 1);
        address actor = actors[actorSeed % actors.length];

        // Token must exist and be owned by the actor, not already locked.
        if (nft.balanceOf(actor) == 0) return;
        if (nft.ownerOf(tokenId) != actor) return;
        if (pool.tokenLocked(tokenId)) return;

        vm.startPrank(actor);
        nft.approve(address(pool), tokenId);
        try pool.lockAndSendNFT{value: 0.001 ether}(
            tokenId, actor, destChainSelector, address(this), address(0), 400_000
        ) {
            lockSuccesses++;
        } catch {}
        vm.stopPrank();
    }

    // ----------------------------------------------------------------
    // Inbound: unlock (simulated destination-chain burn message)
    // ----------------------------------------------------------------
    function unlock(uint256 actorSeed, uint256 tokenId) external {
        tokenId = bound(tokenId, 0, MAX_TOKEN_ID - 1);
        address recipient = actors[actorSeed % actors.length];

        if (!pool.tokenLocked(tokenId)) return;

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256(abi.encodePacked("unlock", tokenId, block.timestamp)),
            sourceChainSelector: destChainSelector,
            sender: abi.encode(address(this)),
            data: abi.encode(NFTPoolLockAndRelease.RequestData({tokenId: tokenId, newOwner: recipient})), //abi.encode(uint256(tokenId), address(recipient))
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        try pool.ccipReceive(message) {
            unlockSuccesses++;
        } catch {}
    }

    // ----------------------------------------------------------------
    // View helpers
    // ----------------------------------------------------------------
    function actorCount() external view returns (uint256) {
        return actors.length;
    }
}
