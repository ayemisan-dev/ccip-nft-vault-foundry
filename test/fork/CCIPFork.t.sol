// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NFTPoolLockAndRelease} from "../../src/core/NFTPoolLockAndRelease.sol";
import {NFTPoolBurnAndMint} from "../../src/core/NFTPoolBurnAndMint.sol";
import {MyNFT} from "../../src/mocks/MyNFT.sol";
import {WrappedNFT} from "../../src/core/WrappedNFT.sol";

/// @title CCIPForkTest
/// @notice Fork-based integration test for NFT cross-chain transfers.
contract CCIPForkTest is Test {
    // =============================================================
    // Forks and Simulator
    // =============================================================
    CCIPLocalSimulatorFork internal ccipSimulatorFork;
    uint256 internal sepoliaFork;
    uint256 internal arbSepoliaFork;
    Register.NetworkDetails internal sepoliaDetails; //routerAddress,linkAddress
    Register.NetworkDetails internal arbSepoliaDetails;

    // =============================================================
    // Application Contracts
    // =============================================================
    NFTPoolLockAndRelease internal sourcePool;
    NFTPoolBurnAndMint internal destPool;
    MyNFT internal nft;
    WrappedNFT internal wnft;

    // =============================================================
    // Actors and Constants
    // =============================================================
    address internal owner;
    address internal alice;
    uint256 internal constant TOKEN_ID = 0;
    uint256 internal constant LINK_AMOUNT = 10 ether;
    uint256 internal constant NATIVE_AMOUNT = 1 ether;

    // =============================================================
    // Setup
    // =============================================================

    function setUp() public {
        owner = address(this);
        alice = makeAddr("A11CE");

        // 1. Create Sepolia fork and select it.
        sepoliaFork = vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));

        // 2. Create Arbitrum Sepolia fork.
        arbSepoliaFork = vm.createFork(vm.envString("ARBITRUM_SEPOLIA_RPC_URL"));

        // 3. Deploy the simulator on Sepolia fork.
        ccipSimulatorFork = new CCIPLocalSimulatorFork();
        // Keep the simulator available across both forks.
        vm.makePersistent(address(ccipSimulatorFork));

        // =========================================================
        // Source Chain: Sepolia
        // =========================================================

        vm.selectFork(sepoliaFork);
        sepoliaDetails = ccipSimulatorFork.getNetworkDetails(block.chainid);

        assertEq(block.chainid, 11155111, "Not Sepolia");
        assertEq(sepoliaDetails.chainSelector, 16015286601757825753);
        assertTrue(sepoliaDetails.routerAddress != address(0));
        assertTrue(sepoliaDetails.linkAddress != address(0));

        //console.log("Sepolia chainSelector:", sepoliaDetails.chainSelector);
        //console.log("Sepolia Router:", sepoliaDetails.routerAddress);
        //console.log("Sepolia LINK:", sepoliaDetails.linkAddress);

        // 4. Deploy original NFT.
        nft = new MyNFT("Original", "ONFT");
        // Mint original NFT to Alice
        nft.safeMint(alice);

        // 5. Deploy source pool.
        sourcePool =
            new NFTPoolLockAndRelease(sepoliaDetails.routerAddress, sepoliaDetails.linkAddress, address(nft), owner);

        // =========================================================
        // Destination Chain: Arbitrum Sepolia
        // =========================================================

        vm.selectFork(arbSepoliaFork);
        arbSepoliaDetails = ccipSimulatorFork.getNetworkDetails(block.chainid);
        assertEq(block.chainid, 421614, "Not Arbitrum Sepolia");
        assertEq(arbSepoliaDetails.chainSelector, 3478487238524512106);
        assertTrue(arbSepoliaDetails.routerAddress != address(0));
        assertTrue(arbSepoliaDetails.linkAddress != address(0));

        //console.log("Arbitrum chainSelector:", arbSepoliaDetails.chainSelector);
        //console.log("Arbitrum Router:", arbSepoliaDetails.routerAddress);
        //console.log("Arbitrum LINK:", arbSepoliaDetails.linkAddress);

        // 6. Deploy wrapped NFT.
        wnft = new WrappedNFT("Wrapped", "WNFT");

        // 7. Deploy destination pool.
        destPool = new NFTPoolBurnAndMint(
            arbSepoliaDetails.routerAddress, arbSepoliaDetails.linkAddress, address(wnft), owner
        );

        // Destination pool must control WrappedNFT.
        wnft.transferOwnership(address(destPool));

        // =========================================================
        // Cross-chain Configuration
        // =========================================================

        // 8. Configure source pool on Sepolia.
        vm.selectFork(sepoliaFork);
        sourcePool.allowlistDestinationChain(arbSepoliaDetails.chainSelector, true);
        sourcePool.allowlistSourceChain(arbSepoliaDetails.chainSelector, true);
        sourcePool.allowlistSender(address(destPool), true);

        // 9. Configure destination pool on Arbitrum Sepolia.
        vm.selectFork(arbSepoliaFork);
        destPool.allowlistDestinationChain(sepoliaDetails.chainSelector, true);
        destPool.allowlistSourceChain(sepoliaDetails.chainSelector, true);
        destPool.allowlistSender(address(sourcePool), true);

        // =========================================================
        // Funding
        // =========================================================

        // 10. Fund Alice on Sepolia fork.
        vm.selectFork(sepoliaFork);
        vm.deal(alice, 100 ether);
        deal(sepoliaDetails.linkAddress, alice, LINK_AMOUNT);
        assertGe(IERC20(sepoliaDetails.linkAddress).balanceOf(alice), LINK_AMOUNT);

        // 11. Fund Alice on Arbitrum Sepolia fork.
        vm.selectFork(arbSepoliaFork);
        vm.deal(alice, 100 ether);
        deal(arbSepoliaDetails.linkAddress, alice, LINK_AMOUNT);
        assertGe(IERC20(arbSepoliaDetails.linkAddress).balanceOf(alice), LINK_AMOUNT);
    }

    // =============================================================
    // LINK Payment: Full Round Trip
    // =============================================================

    function test_ForkRoundTrip_LinkPayment() public {
        uint256 tokenId = TOKEN_ID;

        // Step 1: Sepolia - Lock original NFT and send CCIP message.
        vm.selectFork(sepoliaFork);
        vm.startPrank(alice);
        nft.approve(address(sourcePool), tokenId);
        IERC20(sepoliaDetails.linkAddress).approve(address(sourcePool), LINK_AMOUNT);
        bytes32 outboundId = sourcePool.lockAndSendNFT(
            tokenId, alice, arbSepoliaDetails.chainSelector, address(destPool), sepoliaDetails.linkAddress, 400_000
        );
        vm.stopPrank();

        assertTrue(sourcePool.tokenLocked(tokenId));
        assertEq(nft.ownerOf(tokenId), address(sourcePool));
        assertNotEq(outboundId, bytes32(0));

        // ---------------------------------------------------------
        // Step 2: Route message to Arbitrum Sepolia.
        // ---------------------------------------------------------

        ccipSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);
        assertTrue(destPool.mintedTokenIds(tokenId));
        assertEq(wnft.ownerOf(tokenId), alice);
        assertEq(wnft.totalSupply(), 1);

        // ---------------------------------------------------------
        // Step 3: Arbitrum Sepolia - Burn WrappedNFT and send back.
        // ---------------------------------------------------------

        vm.startPrank(alice);
        wnft.approve(address(destPool), tokenId);
        IERC20(arbSepoliaDetails.linkAddress).approve(address(destPool), LINK_AMOUNT);

        bytes32 inboundId = destPool.burnAndSendNFT(
            tokenId, alice, sepoliaDetails.chainSelector, address(sourcePool), arbSepoliaDetails.linkAddress, 400_000
        );
        vm.stopPrank();

        assertFalse(destPool.mintedTokenIds(tokenId));
        assertEq(wnft.totalSupply(), 0);
        assertNotEq(inboundId, bytes32(0));

        // ---------------------------------------------------------
        // Step 4: Route message back to Sepolia.
        // ---------------------------------------------------------

        ccipSimulatorFork.switchChainAndRouteMessage(sepoliaFork);
        assertFalse(sourcePool.tokenLocked(tokenId));
        assertEq(nft.ownerOf(tokenId), alice);

        // Final source NFT state.
        assertNotEq(outboundId, bytes32(0));
        assertNotEq(inboundId, bytes32(0));
    }

    // =============================================================
    // Native Payment: Full Round Trip
    // =============================================================

    function test_ForkRoundTrip_NativePayment() public {
        uint256 tokenId = TOKEN_ID;

        // ---------------------------------------------------------
        // Step 1: Sepolia - Lock and send using native ETH.
        // ---------------------------------------------------------

        vm.selectFork(sepoliaFork);
        vm.startPrank(alice);
        nft.approve(address(sourcePool), tokenId);
        bytes32 outboundId = sourcePool.lockAndSendNFT{value: NATIVE_AMOUNT}(
            tokenId, alice, arbSepoliaDetails.chainSelector, address(destPool), address(0), 400_000
        );
        vm.stopPrank();

        assertTrue(sourcePool.tokenLocked(tokenId));
        assertEq(nft.ownerOf(tokenId), address(sourcePool));
        assertNotEq(outboundId, bytes32(0));

        // ---------------------------------------------------------
        // Step 2: Route to Arbitrum Sepolia.
        // ---------------------------------------------------------

        ccipSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);
        assertTrue(destPool.mintedTokenIds(tokenId));
        assertEq(wnft.ownerOf(tokenId), alice);

        // ---------------------------------------------------------
        // Step 3: Burn and send back using native ETH.
        // ---------------------------------------------------------

        vm.startPrank(alice);
        wnft.approve(address(destPool), tokenId);
        bytes32 inboundId = destPool.burnAndSendNFT{value: NATIVE_AMOUNT}(
            tokenId, alice, sepoliaDetails.chainSelector, address(sourcePool), address(0), 400_000
        );
        vm.stopPrank();

        assertFalse(destPool.mintedTokenIds(tokenId));
        assertNotEq(inboundId, bytes32(0));
        assertEq(wnft.totalSupply(), 0);

        // ---------------------------------------------------------
        // Step 4: Route back to Sepolia.
        // ---------------------------------------------------------

        ccipSimulatorFork.switchChainAndRouteMessage(sepoliaFork);
        assertFalse(sourcePool.tokenLocked(tokenId));
        assertEq(nft.ownerOf(tokenId), alice);
    }
}
