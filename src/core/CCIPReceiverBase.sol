// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {ExtraArgsCodec} from "@chainlink/contracts-ccip/contracts/libraries/ExtraArgsCodec.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CCIPErrors} from "../libraries/CCIPErrors.sol";

/// @title CCIPReceiverBase
/// @notice Shared CCIP receiver and sender functionality.
abstract contract CCIPReceiverBase is CCIPReceiver, Ownable {
    using SafeERC20 for IERC20;

    // ---------- Storage ----------
    IRouterClient private immutable i_router;
    IERC20 private immutable i_linkToken;
    bytes32 private s_lastReceivedMessageId;
    mapping(uint64 => bool) public allowlistedSourceChains;
    mapping(address => bool) public allowlistedSenders;

    // ---------- Constructor ----------
    constructor(address _router, address _link, address _initialOwner) CCIPReceiver(_router) Ownable(_initialOwner) {
        if (_router == address(0) || _link == address(0)) {
            revert CCIPErrors.InvalidAddress();
        }

        i_router = IRouterClient(_router);
        i_linkToken = IERC20(_link);
    }

    // ---------- Modifiers ----------

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (!allowlistedSourceChains[_sourceChainSelector]) {
            revert CCIPErrors.ChainNotAllowlisted(_sourceChainSelector);
        }

        if (!allowlistedSenders[_sender]) {
            revert CCIPErrors.SenderNotAllowlisted(_sender);
        }

        _;
    }

    // ---------- Admin ----------

    function allowlistSourceChain(uint64 _sourceChainSelector, bool allowed) external onlyOwner {
        allowlistedSourceChains[_sourceChainSelector] = allowed;
    }

    function allowlistSender(address _sender, bool allowed) external onlyOwner {
        allowlistedSenders[_sender] = allowed;
    }

    // ---------- Views ----------

    function getLastReceivedMessageId() external view returns (bytes32) {
        return s_lastReceivedMessageId;
    }

    // ---------- Receiver Helper ----------

    function _recordIncoming(bytes32 messageId) internal {
        s_lastReceivedMessageId = messageId;
    }

    // ---------- Send Helper ----------

    function _sendMessage(
        uint64 destChainSelector,
        address receiver,
        bytes memory payload,
        address feeToken,
        uint32 gasLimit
    ) internal returns (bytes32 messageId, uint256 fees) {
        Client.EVM2AnyMessage memory msgReq = _buildMessage(receiver, payload, feeToken, gasLimit);

        fees = i_router.getFee(destChainSelector, msgReq);

        // LINK payment.
        if (feeToken == address(i_linkToken)) {
            if (msg.value != 0) {
                revert CCIPErrors.UnexpectedNativeValue();
            }
            i_linkToken.safeTransferFrom(msg.sender, address(this), fees);
            i_linkToken.forceApprove(address(i_router), fees);
            messageId = i_router.ccipSend(destChainSelector, msgReq);
        }
        // Native payment.
        else if (feeToken == address(0)) {
            if (msg.value < fees) {
                revert CCIPErrors.IncorrectNativeFee(msg.value, fees);
            }

            messageId = i_router.ccipSend{value: fees}(destChainSelector, msgReq);

            uint256 refund = msg.value - fees;

            if (refund > 0) {
                (bool success,) = payable(msg.sender).call{value: refund}("");

                if (!success) {
                    revert CCIPErrors.RefundFailed();
                }
            }
        }
        // Unsupported payment token.
        else {
            revert CCIPErrors.UnsupportedFeeToken(feeToken);
        }
    }

    // ---------- Message Builder ----------

    function _buildMessage(address receiver, bytes memory payload, address feeToken, uint32 gasLimit)
        internal
        pure
        returns (Client.EVM2AnyMessage memory)
    {
        return Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: payload,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            feeToken: feeToken,
            extraArgs: ExtraArgsCodec._getBasicEncodedExtraArgsV3(gasLimit, bytes4(0))
        });
    }

    // ---------- Native Token Receiver ----------

    receive() external payable {}
}
