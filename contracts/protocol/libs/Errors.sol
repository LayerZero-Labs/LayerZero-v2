// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

library Errors {
    error LZ_LzTokenUnavailable();
    error LZ_InvalidReceiveLibrary();
    error LZ_InvalidNonce(uint64 nonce);
    error LZ_InvalidArgument();
    error LZ_InvalidExpiry();
    error LZ_InvalidAmount(uint256 required, uint256 supplied);
    error LZ_OnlyRegisteredOrDefaultLib();
    error LZ_OnlyRegisteredLib();
    error LZ_OnlyNonDefaultLib();
    error LZ_Unauthorized();
    error LZ_DefaultSendLibUnavailable();
    error LZ_DefaultReceiveLibUnavailable();
    error LZ_PathNotInitializable();
    error LZ_PathNotVerifiable();
    error LZ_OnlySendLib();
    error LZ_OnlyReceiveLib();
    error LZ_UnsupportedEid();
    error LZ_UnsupportedInterface();
    error LZ_AlreadyRegistered();
    error LZ_SameValue();
    error LZ_InvalidPayloadHash();
    error LZ_PayloadHashNotFound(bytes32 expected, bytes32 actual);
    error LZ_ComposeNotFound(bytes32 expected, bytes32 actual);
    error LZ_ComposeExists();
    error LZ_SendReentrancy();
    error LZ_NotImplemented();
    error LZ_InsufficientFee(
        uint256 requiredNative,
        uint256 suppliedNative,
        uint256 requiredLzToken,
        uint256 suppliedLzToken
    );
    error LZ_ZeroLzTokenFee();
}
