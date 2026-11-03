// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCIPReceiverBase} from "./CCIPReceiverBase.sol";
import {WrappedNFT} from "./WrappedNFT.sol";

contract NFTPoolBurnAndMint is CCIPReceiverBase {
    // ---------- errors ----------
    error DestinationChainNotAllowlisted(uint64 chainSelector);
    error TokenAlreadyMinted(uint256 tokenId);
    error TokenNotMinted(uint256 tokenId);
    error ZeroAddress();

    // ---------- events ----------
    event WrappedNFTMinted(uint256 indexed tokenId, address indexed newOwner, bytes32 indexed messageId);
    event WrappedNFTBurnedAndSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address indexed receiver,
        uint256 tokenId,
        address newOwner,
        address feeToken,
        uint256 fees
    );

    // ---------- Types ----------
    struct RequestData {
        uint256 tokenId;
        address newOwner;
    }

    // ---------- storage ----------
    WrappedNFT private immutable i_wnft;
    mapping(uint64 => bool) public allowlistedDestinationChains;
    mapping(uint256 => bool) public mintedTokenIds;

    constructor(address _router, address _link, address _wnft, address _initialOwner)
        CCIPReceiverBase(_router, _link, _initialOwner)
    {
        if (_wnft == address(0)) revert ZeroAddress();
        i_wnft = WrappedNFT(_wnft);
    }

    function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }

    function burnAndSendNFT(
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
        if (!mintedTokenIds[tokenId]) revert TokenNotMinted(tokenId);

        i_wnft.transferFrom(msg.sender, address(this), tokenId);
        i_wnft.burn(tokenId);
        mintedTokenIds[tokenId] = false;

        bytes memory payload = abi.encode(RequestData({tokenId: tokenId, newOwner: newOwner}));
        uint256 fees;
        (messageId, fees) = _sendMessage(destChainSelector, destReceiver, payload, feeToken, gasLimit);

        emit WrappedNFTBurnedAndSent(messageId, destChainSelector, destReceiver, tokenId, newOwner, feeToken, fees);
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage)
        internal
        override
        onlyAllowlisted(any2EvmMessage.sourceChainSelector, abi.decode(any2EvmMessage.sender, (address)))
    {
        _recordIncoming(any2EvmMessage.messageId);
        RequestData memory req = abi.decode(any2EvmMessage.data, (RequestData));

        if (mintedTokenIds[req.tokenId]) revert TokenAlreadyMinted(req.tokenId);

        mintedTokenIds[req.tokenId] = true;
        i_wnft.mintWithSpecificTokenId(req.newOwner, req.tokenId);

        emit WrappedNFTMinted(req.tokenId, req.newOwner, any2EvmMessage.messageId);
    }

    function wnft() external view returns (address) {
        return address(i_wnft);
    }
}
