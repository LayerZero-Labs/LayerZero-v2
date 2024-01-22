// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

/// @dev should be implemented by the ReceiveUln302 contract and future ReceiveUln contracts on EndpointV2
interface IReceiveUlnE2 {
    /// @notice for each dvn to verify the payload
    /// @dev this function signature 0x0223536e
    function verify(bytes calldata _packetHeader, bytes32 _payloadHash, uint64 _confirmations) external;

    /// @notice verify the payload at endpoint, will check if all DVNs verified
    function commitVerification(bytes calldata _packetHeader, bytes32 _payloadHash) external;
}
