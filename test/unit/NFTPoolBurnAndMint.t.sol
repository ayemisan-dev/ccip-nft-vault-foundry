// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {NFTPoolBurnAndMint} from "../../src/core/NFTPoolBurnAndMint.sol";
import {WrappedNFT} from "../../src/core/WrappedNFT.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCIPErrors} from "../../src/libraries/CCIPErrors.sol";

contract MockRouter {
    uint256 public fee;
    bytes32 public lastMessageId;
    uint256 public receivedNative;

    constructor(uint256 _fee) {
        fee = _fee;
    }

    function getFee(uint64, Client.EVM2AnyMessage memory) external view returns (uint256) {
        return fee;
    }

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

contract NFTPoolBurnAndMintTest is Test {
    NFTPoolBurnAndMint pool;
    WrappedNFT wnft;
    MockRouter router;
    MockERC20 link;

    address owner = address(this);
    address alice = makeAddr("alice");
    address sourcePool = makeAddr("sourcePool");

    uint64 constant SOURCE_CHAIN = 16015286601757825753; // Ethereum Sepolia

    function setUp() public {
        router = new MockRouter(1 ether);
        link = new MockERC20();
        wnft = new WrappedNFT("Wrapped", "WNFT");
        pool = new NFTPoolBurnAndMint(address(router), address(link), address(wnft), owner);
        // Pool must own the WrappedNFT to mint/burn.
        wnft.transferOwnership(address(pool));

        pool.allowlistSourceChain(SOURCE_CHAIN, true);
        pool.allowlistSender(sourcePool, true);

        vm.deal(alice, 100 ether);
    }

    // ----------------------------------------------------------------
    // Helper: build a valid inbound CCIP message
    // ----------------------------------------------------------------
    function _buildIncoming(uint256 tokenId, address newOwner) internal view returns (Client.Any2EVMMessage memory) {
        return Client.Any2EVMMessage({
            messageId: keccak256(abi.encode(tokenId, newOwner)),
            sourceChainSelector: SOURCE_CHAIN,
            sender: abi.encode(sourcePool),
            data: abi.encode(NFTPoolBurnAndMint.RequestData({tokenId: tokenId, newOwner: newOwner})),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
    }

    // ----------------------------------------------------------------
    // Inbound: mint
    // ----------------------------------------------------------------
    function test_MintOnIncomingMessage() public {
        Client.Any2EVMMessage memory msg1 = _buildIncoming(0, alice);

        vm.prank(address(router));
        pool.ccipReceive(msg1);

        assertTrue(pool.mintedTokenIds(0));
        assertEq(wnft.ownerOf(0), alice);
        assertEq(wnft.totalSupply(), 1);
        assertEq(pool.getLastReceivedMessageId(), msg1.messageId);
    }

    function test_RevertWhen_ReplayMint() public {
        Client.Any2EVMMessage memory msg1 = _buildIncoming(0, alice);

        vm.startPrank(address(router));
        pool.ccipReceive(msg1);
        vm.expectRevert(abi.encodeWithSelector(NFTPoolBurnAndMint.TokenAlreadyMinted.selector, 0));
        pool.ccipReceive(msg1);
        vm.stopPrank();
    }

    function test_RevertWhen_SourceChainNotAllowlisted() public {
        Client.Any2EVMMessage memory msg1 = _buildIncoming(0, alice);
        msg1.sourceChainSelector = 999;

        vm.prank(address(router));
        vm.expectRevert(abi.encodeWithSelector(CCIPErrors.ChainNotAllowlisted.selector, 999));
        pool.ccipReceive(msg1);
    }

    function test_RevertWhen_SenderNotAllowlisted() public {
        Client.Any2EVMMessage memory msg1 = _buildIncoming(0, alice);
        msg1.sender = abi.encode(makeAddr("attacker"));

        vm.prank(address(router));
        vm.expectRevert(abi.encodeWithSelector(CCIPErrors.SenderNotAllowlisted.selector, makeAddr("attacker")));
        pool.ccipReceive(msg1);
    }

    // ----------------------------------------------------------------
    // Outbound: burn & send
    // ----------------------------------------------------------------
    function _mintWrapped(uint256 tokenId, address to) internal {
        Client.Any2EVMMessage memory msg1 = _buildIncoming(tokenId, to);
        vm.prank(address(router));
        pool.ccipReceive(msg1);
    }

    function test_BurnAndSend_RoundTrip() public {
        _mintWrapped(0, alice);
        pool.allowlistDestinationChain(SOURCE_CHAIN, true);

        vm.prank(alice);
        wnft.approve(address(pool), 0);

        vm.prank(alice);
        bytes32 mid = pool.burnAndSendNFT{value: 1 ether}(0, alice, SOURCE_CHAIN, sourcePool, address(0), 400_000);

        assertFalse(pool.mintedTokenIds(0));
        assertEq(wnft.totalSupply(), 0);
        assertEq(mid, router.lastMessageId());
        assertEq(router.receivedNative(), 1 ether);
        vm.expectRevert();
        wnft.ownerOf(0);
    }

    function test_RemintAfterRoundTrip() public {
        // mint → burn → mint again with same tokenId, flag must be reset.
        _mintWrapped(0, alice);
        pool.allowlistDestinationChain(SOURCE_CHAIN, true);

        vm.prank(alice);
        wnft.approve(address(pool), 0);
        vm.prank(alice);
        pool.burnAndSendNFT{value: 1 ether}(0, alice, SOURCE_CHAIN, sourcePool, address(0), 400_000);

        _mintWrapped(0, alice);
        assertEq(wnft.ownerOf(0), alice);
        assertTrue(pool.mintedTokenIds(0));
    }

    function test_RevertWhen_BurnUnknownToken() public {
        pool.allowlistDestinationChain(SOURCE_CHAIN, true);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NFTPoolBurnAndMint.TokenNotMinted.selector, 0));
        pool.burnAndSendNFT(0, alice, SOURCE_CHAIN, sourcePool, address(0), 400_000);
    }

    function test_RevertWhen_UserBurnsDirectly() public {
        _mintWrapped(0, alice);
        vm.prank(alice);
        vm.expectRevert(); // onlyOwner
        wnft.burn(0);
    }

    function test_RevertWhen_DestChainNotAllowlisted_Burn() public {
        _mintWrapped(0, alice);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(NFTPoolBurnAndMint.DestinationChainNotAllowlisted.selector, SOURCE_CHAIN)
        );
        pool.burnAndSendNFT{value: 1 ether}(0, alice, SOURCE_CHAIN, sourcePool, address(0), 400_000);
    }

    function test_Burn_LINKPayment() public {
        _mintWrapped(0, alice);
        pool.allowlistDestinationChain(SOURCE_CHAIN, true);
        link.mint(alice, 10 ether);

        vm.startPrank(alice);
        wnft.approve(address(pool), 0);
        link.approve(address(pool), 10 ether);
        pool.burnAndSendNFT(0, alice, SOURCE_CHAIN, sourcePool, address(link), 400_000);
        vm.stopPrank();

        assertEq(link.balanceOf(alice), 9 ether);
        assertEq(router.receivedNative(), 0);
    }
}
