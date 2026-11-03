// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {NFTPoolLockAndRelease} from "../../src/core/NFTPoolLockAndRelease.sol";
import {MyNFT} from "../../src/mocks/MyNFT.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCIPErrors} from "../../src/libraries/CCIPErrors.sol";

/// @dev Minimal mock router matching IRouterClient selectors for getFee/ccipSend.
contract MockRouter {
    uint256 public fee;
    bytes32 public lastMessageId;
    uint256 public receivedNative;

    constructor(uint256 _fee) {
        fee = _fee;
    }

    // Signature MUST match IRouterClient.getFee(uint64, Client.EVM2AnyMessage)
    function getFee(uint64, Client.EVM2AnyMessage memory) external view returns (uint256) {
        return fee;
    }

    // Signature MUST match IRouterClient.ccipSend(uint64, Client.EVM2AnyMessage)
    function ccipSend(uint64, Client.EVM2AnyMessage memory) external payable returns (bytes32) {
        receivedNative += msg.value;
        lastMessageId = keccak256(abi.encodePacked(block.timestamp, msg.sender, block.number));
        return lastMessageId;
    }
}

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock LINK", "mLINK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract NFTPoolLockAndReleaseTest is Test {
    NFTPoolLockAndRelease pool;
    MyNFT nft;
    MockRouter router;
    MockERC20 link;

    address owner = address(this);
    address alice = makeAddr("alice");

    uint64 constant DEST_CHAIN = 3478487238524512106; // Arbitrum Sepolia

    function setUp() public {
        router = new MockRouter(1 ether);
        link = new MockERC20();
        nft = new MyNFT("Original", "ONFT");
        pool = new NFTPoolLockAndRelease(address(router), address(link), address(nft), owner);
        vm.deal(alice, 100 ether);
    }

    // ----------------------------------------------------------------
    // Access control
    // ----------------------------------------------------------------
    function test_RevertWhen_CallerIsNotOwnerForAllowlist() public {
        vm.prank(alice);
        vm.expectRevert();
        pool.allowlistDestinationChain(DEST_CHAIN, true);
    }

    function test_RevertWhen_DestChainNotAllowlisted() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(NFTPoolLockAndRelease.DestinationChainNotAllowlisted.selector, DEST_CHAIN)
        );
        pool.lockAndSendNFT(0, alice, DEST_CHAIN, alice, address(0), 400_000);
    }

    // ----------------------------------------------------------------
    // Happy paths
    // ----------------------------------------------------------------
    function test_LockSetsTokenLocked_NativeFee() public {
        pool.allowlistDestinationChain(DEST_CHAIN, true);
        nft.safeMint(alice);
        vm.prank(alice);
        nft.approve(address(pool), 0);

        vm.prank(alice);
        bytes32 messageId = pool.lockAndSendNFT{value: 1 ether}(0, alice, DEST_CHAIN, alice, address(0), 400_000);

        assertTrue(pool.tokenLocked(0));
        assertEq(nft.ownerOf(0), address(pool));
        assertEq(messageId, router.lastMessageId());
        assertEq(router.receivedNative(), 1 ether);
    }

    function test_LinkPaymentSucceeds() public {
        pool.allowlistDestinationChain(DEST_CHAIN, true);
        nft.safeMint(alice);
        link.mint(alice, 10 ether);

        vm.startPrank(alice);
        nft.approve(address(pool), 0);
        link.approve(address(pool), 10 ether);
        bytes32 messageId = pool.lockAndSendNFT(0, alice, DEST_CHAIN, alice, address(link), 400_000);
        vm.stopPrank();

        assertTrue(pool.tokenLocked(0));
        assertEq(nft.ownerOf(0), address(pool));
        assertEq(link.balanceOf(alice), 9 ether);
        assertEq(messageId, router.lastMessageId());
        assertEq(router.receivedNative(), 0);
    }

    // ----------------------------------------------------------------
    // Fee failure paths
    // ----------------------------------------------------------------
    function test_RevertWhen_LinkModeReceivesNativeValue() public {
        pool.allowlistDestinationChain(DEST_CHAIN, true);
        nft.safeMint(alice);
        vm.prank(alice);
        nft.approve(address(pool), 0);

        vm.prank(alice);
        vm.expectRevert(CCIPErrors.UnexpectedNativeValue.selector);
        pool.lockAndSendNFT{value: 1}(0, alice, DEST_CHAIN, alice, address(link), 400_000);
    }

    function test_RevertWhen_NativeFeeInsufficient() public {
        pool.allowlistDestinationChain(DEST_CHAIN, true);
        nft.safeMint(alice);
        vm.prank(alice);
        nft.approve(address(pool), 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CCIPErrors.IncorrectNativeFee.selector, 0.5 ether, 1 ether));
        pool.lockAndSendNFT{value: 0.5 ether}(0, alice, DEST_CHAIN, alice, address(0), 400_000);
    }

    function test_RevertWhen_UnsupportedFeeToken() public {
        pool.allowlistDestinationChain(DEST_CHAIN, true);
        nft.safeMint(alice);
        vm.prank(alice);
        nft.approve(address(pool), 0);

        address bogus = makeAddr("bogus");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CCIPErrors.UnsupportedFeeToken.selector, bogus));
        pool.lockAndSendNFT(0, alice, DEST_CHAIN, alice, bogus, 400_000);
    }

    // ----------------------------------------------------------------
    // Refund path
    // ----------------------------------------------------------------
    function test_NativeOverpayIsRefunded() public {
        pool.allowlistDestinationChain(DEST_CHAIN, true);
        nft.safeMint(alice);
        uint256 balBefore = alice.balance;

        vm.prank(alice);
        nft.approve(address(pool), 0);

        vm.prank(alice);
        pool.lockAndSendNFT{value: 3 ether}(0, alice, DEST_CHAIN, alice, address(0), 400_000);

        // Alice paid exactly 1 ether (mocked fee), 2 ether refunded.
        assertEq(alice.balance, balBefore - 1 ether);
        assertEq(router.receivedNative(), 1 ether);
        assertEq(address(pool).balance, 0);
    }
}
