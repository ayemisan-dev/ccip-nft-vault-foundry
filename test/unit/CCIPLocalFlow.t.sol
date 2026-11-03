// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {CCIPLocalSimulator} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {LinkToken} from "@chainlink/local/src/shared/LinkToken.sol";
import {NFTPoolLockAndRelease} from "../../src/core/NFTPoolLockAndRelease.sol";
import {NFTPoolBurnAndMint} from "../../src/core/NFTPoolBurnAndMint.sol";
import {MyNFT} from "../../src/mocks/MyNFT.sol";
import {WrappedNFT} from "../../src/core/WrappedNFT.sol";

/// @title CCIPLocalFlowTest
/// @notice Integration tests for the NFT lock-mint-burn-release flow.
contract CCIPLocalFlowTest is Test {
    CCIPLocalSimulator internal simulator;
    NFTPoolLockAndRelease internal sourcePool;
    NFTPoolBurnAndMint internal destPool;
    MyNFT internal nft;
    WrappedNFT internal wnft;
    IRouterClient internal sourceRouter;
    IRouterClient internal destRouter;
    LinkToken internal linkToken;

    uint64 internal chainSelector;
    address internal owner;
    address internal alice;
    uint256 internal constant TOKEN_ID = 0;
    uint256 internal constant LINK_AMOUNT = 10 ether;
    uint256 internal constant NATIVE_AMOUNT = 1 ether;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");

        // 1. Deploy Chainlink Local Simulator.
        simulator = new CCIPLocalSimulator();

        // 2. Retrieve local CCIP configuration.
        (chainSelector, sourceRouter, destRouter,, linkToken,,) = simulator.configuration();

        // 3. Deploy NFT contracts.
        nft = new MyNFT("Original", "ONFT");
        wnft = new WrappedNFT("Wrapped", "WNFT");

        // 4. Deploy source and destination pools.
        sourcePool = new NFTPoolLockAndRelease(address(sourceRouter), address(linkToken), address(nft), owner);
        destPool = new NFTPoolBurnAndMint(address(destRouter), address(linkToken), address(wnft), owner);

        // 5. Transfer WrappedNFT ownership to destination pool.
        wnft.transferOwnership(address(destPool));

        // 6. Configure source pool permissions.
        sourcePool.allowlistDestinationChain(chainSelector, true);
        sourcePool.allowlistSourceChain(chainSelector, true);
        sourcePool.allowlistSender(address(destPool), true);

        // 7. Configure destination pool permissions.
        destPool.allowlistDestinationChain(chainSelector, true);
        destPool.allowlistSourceChain(chainSelector, true);
        destPool.allowlistSender(address(sourcePool), true);

        // 8. Fund Alice with LINK and native tokens.
        simulator.requestLinkFromFaucet(alice, LINK_AMOUNT);
        vm.deal(alice, 100 ether);

        // 9. Mint original NFT to Alice.
        nft.safeMint(alice);

        // 10. Alice approves both pools to spend LINK.
        vm.startPrank(alice);
        linkToken.approve(address(sourcePool), type(uint256).max);
        linkToken.approve(address(destPool), type(uint256).max);
        vm.stopPrank();
    }

    // =============================================================
    // LINK PAYMENT: FULL ROUND TRIP
    // =============================================================

    function test_FullRoundTrip_LinkPayment() public {
        // ---------------------------------------------------------
        // Step 1: Alice locks the original NFT on the source side.
        // ---------------------------------------------------------
        vm.startPrank(alice);
        nft.approve(address(sourcePool), TOKEN_ID);
        bytes32 outboundId =
            sourcePool.lockAndSendNFT(TOKEN_ID, alice, chainSelector, address(destPool), address(linkToken), 400_000);
        vm.stopPrank();

        // Verify source NFT is locked.
        assertTrue(sourcePool.tokenLocked(TOKEN_ID));
        assertEq(nft.ownerOf(TOKEN_ID), address(sourcePool));

        // Verify destination WrappedNFT is minted.
        assertTrue(destPool.mintedTokenIds(TOKEN_ID));
        assertEq(wnft.ownerOf(TOKEN_ID), alice);
        assertEq(wnft.totalSupply(), 1);
        assertNotEq(outboundId, bytes32(0));

        // ---------------------------------------------------------
        // Step 2: Alice burns WrappedNFT and sends it back.
        // ---------------------------------------------------------

        vm.startPrank(alice);
        wnft.approve(address(destPool), TOKEN_ID);
        bytes32 inboundId =
            destPool.burnAndSendNFT(TOKEN_ID, alice, chainSelector, address(sourcePool), address(linkToken), 400_000);
        vm.stopPrank();

        // ---------------------------------------------------------
        // Step 3: Verify destination NFT was burned.
        // ---------------------------------------------------------

        assertFalse(destPool.mintedTokenIds(TOKEN_ID));
        assertEq(wnft.totalSupply(), 0);
        vm.expectRevert();
        wnft.ownerOf(TOKEN_ID);

        // ---------------------------------------------------------
        // Step 4: Verify original NFT was released.
        // ---------------------------------------------------------

        assertFalse(sourcePool.tokenLocked(TOKEN_ID));
        assertFalse(destPool.mintedTokenIds(TOKEN_ID));
        assertEq(nft.ownerOf(TOKEN_ID), alice);
        assertNotEq(inboundId, bytes32(0));
    }

    // =============================================================
    // NATIVE PAYMENT: FULL ROUND TRIP
    // =============================================================

    function test_FullRoundTrip_NativePayment() public {
        // ---------------------------------------------------------
        // Step 1: Lock and send using native gas payment.
        // ---------------------------------------------------------

        vm.startPrank(alice);
        nft.approve(address(sourcePool), TOKEN_ID);
        uint256 balanceBefore = alice.balance;
        sourcePool.lockAndSendNFT{value: NATIVE_AMOUNT}(
            TOKEN_ID, alice, chainSelector, address(destPool), address(0), 400_000
        );
        uint256 spent = balanceBefore - alice.balance;
        vm.stopPrank();

        // The pool should refund any excess native payment.
        assertLt(spent, NATIVE_AMOUNT);
        assertTrue(sourcePool.tokenLocked(TOKEN_ID));
        assertTrue(destPool.mintedTokenIds(TOKEN_ID));
        assertEq(wnft.ownerOf(TOKEN_ID), alice);

        // ---------------------------------------------------------
        // Step 2: Burn and send back using native gas payment.
        // ---------------------------------------------------------

        vm.startPrank(alice);
        wnft.approve(address(destPool), TOKEN_ID);
        destPool.burnAndSendNFT{value: NATIVE_AMOUNT}(
            TOKEN_ID, alice, chainSelector, address(sourcePool), address(0), 400_000
        );
        vm.stopPrank();

        // ---------------------------------------------------------
        // Step 3: Verify final state.
        // ---------------------------------------------------------

        assertEq(wnft.totalSupply(), 0);
        assertFalse(destPool.mintedTokenIds(TOKEN_ID));
        assertFalse(sourcePool.tokenLocked(TOKEN_ID));
        assertEq(nft.ownerOf(TOKEN_ID), alice);
    }
}
