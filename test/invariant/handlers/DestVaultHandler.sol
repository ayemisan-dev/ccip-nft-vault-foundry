// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {NFTPoolBurnAndMint} from "../../../src/core/NFTPoolBurnAndMint.sol";
import {WrappedNFT} from "../../../src/core/WrappedNFT.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

contract InvariantMockRouter {
    function getFee(uint64, Client.EVM2AnyMessage memory) external pure returns (uint256) {
        return 0.001 ether;
    }

    function ccipSend(uint64, Client.EVM2AnyMessage memory) external payable returns (bytes32) {
        return keccak256(abi.encodePacked(block.timestamp, msg.sender));
    }
}

/// @title DestVaultHandler
/// @notice Wraps NFTPoolBurnAndMint into bounded actions for invariant fuzzing.
contract DestVaultHandler is Test {
    NFTPoolBurnAndMint public immutable pool;
    WrappedNFT public immutable wnft;
    uint64 public immutable sourceChainSelector;

    address[] public actors;
    uint256 public constant MAX_TOKEN_ID = 10;

    uint256 public mintSuccesses;
    uint256 public burnSuccesses;

    constructor(NFTPoolBurnAndMint _pool, WrappedNFT _wnft, uint64 _sourceChain, address[] memory _actors) {
        pool = _pool;
        wnft = _wnft;
        sourceChainSelector = _sourceChain;
        actors = _actors;
    }

    // ----------------------------------------------------------------
    // Inbound: mint (simulated source-chain lock message)
    // ----------------------------------------------------------------
    function mint(uint256 actorSeed, uint256 tokenId) external {
        tokenId = bound(tokenId, 0, MAX_TOKEN_ID - 1);
        address recipient = actors[actorSeed % actors.length];

        if (pool.mintedTokenIds(tokenId)) return;

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256(abi.encodePacked("mint", tokenId, block.timestamp)),
            sourceChainSelector: sourceChainSelector,
            sender: abi.encode(address(this)),
            data: abi.encode(NFTPoolBurnAndMint.RequestData({tokenId: tokenId, newOwner: recipient})), //abi.encode(uint256(tokenId), address(recipient))
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        try pool.ccipReceive(message) {
            mintSuccesses++;
        } catch {}
    }

    // ----------------------------------------------------------------
    // Outbound: burn and send back
    // ----------------------------------------------------------------
    function burn(uint256 actorSeed, uint256 tokenId) external {
        tokenId = bound(tokenId, 0, MAX_TOKEN_ID - 1);
        address actor = actors[actorSeed % actors.length];

        if (!pool.mintedTokenIds(tokenId)) return;
        if (wnft.ownerOf(tokenId) != actor) return;

        vm.startPrank(actor);
        wnft.approve(address(pool), tokenId);
        try pool.burnAndSendNFT{value: 0.001 ether}(
            tokenId, actor, sourceChainSelector, address(this), address(0), 400_000
        ) {
            burnSuccesses++;
        } catch {}
        vm.stopPrank();
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }
}
