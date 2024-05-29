// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { Packet } from "../../contracts/interfaces/ISendLib.sol";
import { AddressCast } from "../../contracts/libs/AddressCast.sol";
import { PacketV1Codec } from "../../contracts/messagelib/libs/PacketV1Codec.sol";

contract PacketV1CodecTest is Test {
    uint64 internal nonce;
    uint32 internal srcEid;
    address internal sender;
    uint32 internal dstEid;
    bytes32 internal receiver;
    bytes32 internal guid;
    bytes internal message;

    bytes internal encodedPacket;

    function setUp() public {
        nonce = 1;
        srcEid = 2;
        sender = address(0x123);
        dstEid = 3;
        receiver = AddressCast.toBytes32(address(0x456));
        guid = bytes32(uint256(0x789));
        message = hex"aabbcc";

        Packet memory packet = Packet(nonce, srcEid, sender, dstEid, receiver, guid, message);
        encodedPacket = PacketV1Codec.encode(packet);
    }

    function test_header() public {
        bytes memory header = PacketV1CodecWrapper.header(encodedPacket);
        bytes memory expectedHeader = abi.encodePacked(
            PacketV1Codec.PACKET_VERSION,
            nonce,
            srcEid,
            AddressCast.toBytes32(sender),
            dstEid,
            receiver
        );
        assertEq(header, expectedHeader);
    }

    function test_version() public {
        uint8 v = PacketV1CodecWrapper.version(encodedPacket);
        assertEq(PacketV1Codec.PACKET_VERSION, v);
    }

    function test_nonce() public {
        uint64 n = PacketV1CodecWrapper.nonce(encodedPacket);
        assertEq(nonce, n);
    }

    function test_srcEid() public {
        uint32 eid = PacketV1CodecWrapper.srcEid(encodedPacket);
        assertEq(srcEid, eid);
    }

    function test_sender() public {
        bytes32 s = PacketV1CodecWrapper.sender(encodedPacket);
        assertEq(sender, AddressCast.toAddress(s));
    }

    function test_senderAddressB20() public {
        address s = PacketV1CodecWrapper.senderAddressB20(encodedPacket);
        assertEq(sender, s);
    }

    function test_dstEid() public {
        uint32 eid = PacketV1CodecWrapper.dstEid(encodedPacket);
        assertEq(dstEid, eid);
    }

    function test_receiver() public {
        bytes32 r = PacketV1CodecWrapper.receiver(encodedPacket);
        assertEq(receiver, r);
    }

    function test_receiverB20() public {
        address r = PacketV1CodecWrapper.receiverB20(encodedPacket);
        assertEq(receiver, AddressCast.toBytes32(r));
    }

    function test_guid() public {
        bytes32 id = PacketV1CodecWrapper.guid(encodedPacket);
        assertEq(guid, id);
    }

    function test_message() public {
        bytes memory m = PacketV1CodecWrapper.message(encodedPacket);
        assertEq(message, m);
    }

    function test_payload() public {
        bytes memory expectedPayload = abi.encodePacked(guid, message);
        bytes memory payload = PacketV1CodecWrapper.payload(encodedPacket);
        assertEq(payload, expectedPayload);
    }
}

/// @dev A wrapper of PacketV1Codec to expose internal functions for calldata params
library PacketV1CodecWrapper {
    using PacketV1Codec for bytes;

    function header(bytes calldata _encodedPacket) external pure returns (bytes memory) {
        return _encodedPacket.header();
    }

    function version(bytes calldata _encodedPacket) external pure returns (uint8) {
        return _encodedPacket.version();
    }

    function nonce(bytes calldata _encodedPacket) external pure returns (uint64) {
        return _encodedPacket.nonce();
    }

    function srcEid(bytes calldata _encodedPacket) external pure returns (uint32) {
        return _encodedPacket.srcEid();
    }

    function sender(bytes calldata _encodedPacket) external pure returns (bytes32) {
        return _encodedPacket.sender();
    }

    function senderAddressB20(bytes calldata _encodedPacket) external pure returns (address) {
        return _encodedPacket.senderAddressB20();
    }

    function dstEid(bytes calldata _encodedPacket) external pure returns (uint32) {
        return _encodedPacket.dstEid();
    }

    function receiver(bytes calldata _encodedPacket) external pure returns (bytes32) {
        return _encodedPacket.receiver();
    }

    function receiverB20(bytes calldata _encodedPacket) external pure returns (address) {
        return _encodedPacket.receiverB20();
    }

    function guid(bytes calldata _encodedPacket) external pure returns (bytes32) {
        return _encodedPacket.guid();
    }

    function message(bytes calldata _encodedPacket) external pure returns (bytes memory) {
        return _encodedPacket.message();
    }

    function payload(bytes calldata _encodedPacket) external pure returns (bytes memory) {
        return _encodedPacket.payload();
    }
}
