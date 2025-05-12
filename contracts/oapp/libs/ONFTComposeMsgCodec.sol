// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

/**
 * @title ONFT Composed Message Codec
 * @notice Library for encoding and decoding ONFT composed messages.
 */
library ONFTComposeMsgCodec {
    // Offset constants for decoding composed messages
    uint8 private constant NONCE_OFFSET = 8;
    uint8 private constant SRC_EID_OFFSET = 12;
    uint8 private constant COMPOSE_FROM_OFFSET = 44;

    /**
     * @dev Encodes a ONFT721 composed message.
     * @param _nonce The nonce value.
     * @param _srcEid The source LayerZero endpoint ID.
     * @param _composeMsg The composed message.
     * @return The encoded payload, including the composed message.
     */
    function encode(
        uint64 _nonce,
        uint32 _srcEid,
        bytes memory _composeMsg // 0x[composeFrom][composeMsg]
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(_nonce, _srcEid, _composeMsg);
    }

    /**
     * @dev Retrieves the nonce for the composed message.
     * @param _msg The message.
     * @return The nonce value.
     */
    function nonce(bytes calldata _msg) internal pure returns (uint64) {
        return uint64(bytes8(_msg[:NONCE_OFFSET]));
    }

    /**
     * @dev Retrieves the source LayerZero endpoint ID for the composed message.
     * @param _msg The message.
     * @return The source LayerZero endpoint ID.
     */
    function srcEid(bytes calldata _msg) internal pure returns (uint32) {
        return uint32(bytes4(_msg[NONCE_OFFSET:SRC_EID_OFFSET]));
    }

    /**
     * @dev Retrieves the composeFrom value from the composed message.
     * @param _msg The message.
     * @return The composeFrom value as bytes32.
     */
    function composeFrom(bytes calldata _msg) internal pure returns (bytes32) {
        return bytes32(_msg[SRC_EID_OFFSET:COMPOSE_FROM_OFFSET]);
    }

    /**
     * @dev Retrieves the composed message.
     * @param _msg The message.
     * @return The composed message.
     */
    function composeMsg(bytes calldata _msg) internal pure returns (bytes memory) {
        return _msg[COMPOSE_FROM_OFFSET:];
    }

    /**
     * @dev Converts an address to bytes32.
     * @param _addr The address to convert.
     * @return The bytes32 representation of the address.
     */
    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    /**
     * @dev Converts bytes32 to an address.
     * @param _b The bytes32 value to convert.
     * @return The address representation of bytes32.
     */
    function bytes32ToAddress(bytes32 _b) internal pure returns (address) {
        return address(uint160(uint256(_b)));
    }
}
