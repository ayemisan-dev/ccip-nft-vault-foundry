// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title CCIPErrors
/// @notice Central registry of CCIP-related custom errors.
library CCIPErrors {
    error InvalidAddress();
    error ChainNotAllowlisted(uint64 chainSelector);
    error SenderNotAllowlisted(address sender);
    error UnexpectedNativeValue();
    error IncorrectNativeFee(uint256 provided, uint256 required);
    error UnsupportedFeeToken(address feeToken);
    error RefundFailed();
}
