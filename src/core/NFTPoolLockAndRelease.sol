// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCIPReceiverBase} from "./CCIPReceiverBase.sol";
import {MyNFT} from "../mocks/MyNFT.sol";
import {CCIPErrors} from "../../src/libraries/CCIPErrors.sol";

contract NFTPoolLockAndRelease is CCIPReceiverBase {
    // ---------- errors ----------
    error DestinationChainNotAllowlisted(uint64 chainSelector);
    error TokenNotLocked(uint256 tokenId);
    error ZeroAddress();

    // ---------- events ----------
    event NFTLockedAndSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address indexed receiver,
        uint256 tokenId,
        address newOwner,
        address feeToken,
        uint256 fees
    );
    event NFTUnlocked(uint256 indexed tokenId, address indexed newOwner);

    // ---------- Types ----------
    struct RequestData {
        uint256 tokenId;
        address newOwner;
    } // string tokenURI: nft.tokenURI(tokenId)

    // ---------- storage ----------
    MyNFT private immutable i_nft;
    mapping(uint64 => bool) public allowlistedDestinationChains;
    mapping(uint256 => bool) public tokenLocked;

    constructor(address _router, address _link, address _nftAddr, address _initialOwner)
        CCIPReceiverBase(_router, _link, _initialOwner)
    {
        if (_nftAddr == address(0)) revert ZeroAddress();
        i_nft = MyNFT(_nftAddr);
    }

    function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }

    function lockAndSendNFT(
        uint256 tokenId,
        address newOwner,
        uint64 destChainSelector,
        address destReceiver,
        address feeToken,
        uint32 gasLimit
    ) external payable returns (bytes32 messageId) {
        if (!allowlistedDestinationChains[destChainSelector]) {
            revert DestinationChainNotAllowlisted(destChainSelector);
        }
        if (newOwner == address(0) || destReceiver == address(0)) revert ZeroAddress();

        i_nft.transferFrom(msg.sender, address(this), tokenId);
        tokenLocked[tokenId] = true;

        bytes memory payload = abi.encode(RequestData({tokenId: tokenId, newOwner: newOwner}));
        uint256 fees;
        (messageId, fees) = _sendMessage(destChainSelector, destReceiver, payload, feeToken, gasLimit);

        emit NFTLockedAndSent(messageId, destChainSelector, destReceiver, tokenId, newOwner, feeToken, fees);
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage)
        internal
        override
        onlyAllowlisted(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address)))
    {
        _recordIncoming(any2EvmMessage.messageId);
        RequestData memory req = abi.decode(any2EvmMessage.data, (RequestData));

        if (!tokenLocked[req.tokenId]) revert TokenNotLocked(req.tokenId);

        tokenLocked[req.tokenId] = false;
        i_nft.transferFrom(address(this), req.newOwner, req.tokenId);

        emit NFTUnlocked(req.tokenId, req.newOwner);
    }

    function nft() external view returns (address) {
        return address(i_nft);
    }
}
