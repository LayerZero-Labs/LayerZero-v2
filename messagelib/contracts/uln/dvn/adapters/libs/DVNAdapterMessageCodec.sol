// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";

library DVNAdapterMessageCodec {
    using AddressCast for bytes32;

    error DVNAdapter_InvalidMessageSize();

    uint256 private constant RECEIVE_LIB_OFFSET = 0;
    uint256 private constant PAYLOAD_HASH_OFFSET = 32;
    uint256 private constant PACKET_HEADER_OFFSET = 64;

    uint256 internal constant PACKET_HEADER_SIZE = 81; // version(uint8) + nonce(uint64) + path(uint32,bytes32,uint32,bytes32)
    uint256 internal constant MESSAGE_SIZE = 32 + 32 + PACKET_HEADER_SIZE; // receive_lib(bytes32) + payloadHash(bytes32) + packetHeader

    function encode(
        bytes32 _receiveLib,
        bytes memory _packetHeader,
        bytes32 _payloadHash
    ) internal pure returns (bytes memory payload) {
        return abi.encodePacked(_receiveLib, _payloadHash, _packetHeader);
    }

    function decode(
        bytes calldata _message
    ) internal pure returns (address receiveLib, bytes memory packetHeader, bytes32 payloadHash) {
        if (_message.length != MESSAGE_SIZE) revert DVNAdapter_InvalidMessageSize();

        receiveLib = bytes32(_message[RECEIVE_LIB_OFFSET:PAYLOAD_HASH_OFFSET]).toAddress();
        payloadHash = bytes32(_message[PAYLOAD_HASH_OFFSET:PACKET_HEADER_OFFSET]);
        packetHeader = _message[PACKET_HEADER_OFFSET:];
    }
}
