/// Packet V1 Codec
///
/// This module provides encoding and decoding utilities for LayerZero packets
/// using v1 of the packet format.
module message_lib_common::packet_v1_codec;

use endpoint_v2::outbound_packet::OutboundPacket;
use utils::{buffer_reader, buffer_writer, bytes32::{Self, Bytes32}, hash};

// === Error Codes ===

const EInvalidPacketHeader: u64 = 1;
const EInvalidPacketVersion: u64 = 2;

// === Constants ===

const PACKET_VERSION: u8 = 1;
const HEADER_LENGTH: u64 = 81;

// === Structs ===

/// Represents a decoded packet header.
public struct PacketHeader has copy, drop {
    // Packet format version
    version: u8,
    // Unique message nonce
    nonce: u64,
    // Source endpoint ID
    src_eid: u32,
    // Sender address as 32 bytes
    sender: Bytes32,
    // Destination endpoint ID
    dst_eid: u32,
    // Receiver address as 32 bytes
    receiver: Bytes32,
}

// === Packet Header Functions ===

/// Encodes a packet header into a byte vector.
public fun encode_header(self: &PacketHeader): vector<u8> {
    let mut writer = buffer_writer::new();
    writer
        .write_u8(self.version)
        .write_u64(self.nonce)
        .write_u32(self.src_eid)
        .write_bytes32(self.sender)
        .write_u32(self.dst_eid)
        .write_bytes32(self.receiver);
    writer.to_bytes()
}

/// Decodes a byte vector into a packet header and validates the format.
public fun decode_header(encoded_header: vector<u8>): PacketHeader {
    assert!(encoded_header.length() == HEADER_LENGTH, EInvalidPacketHeader);
    let mut reader = buffer_reader::create(encoded_header);
    let header = PacketHeader {
        version: reader.read_u8(),
        nonce: reader.read_u64(),
        src_eid: reader.read_u32(),
        sender: reader.read_bytes32(),
        dst_eid: reader.read_u32(),
        receiver: reader.read_bytes32(),
    };
    assert!(header.version == PACKET_VERSION, EInvalidPacketVersion);
    header
}

// === Getters ===

/// Returns the packet version.
public fun version(self: &PacketHeader): u8 {
    self.version
}

/// Returns the packet nonce.
public fun nonce(self: &PacketHeader): u64 {
    self.nonce
}

/// Returns the source endpoint ID.
public fun src_eid(self: &PacketHeader): u32 {
    self.src_eid
}

/// Returns the sender address.
public fun sender(self: &PacketHeader): Bytes32 {
    self.sender
}

/// Returns the destination endpoint ID.
public fun dst_eid(self: &PacketHeader): u32 {
    self.dst_eid
}

/// Returns the receiver address.
public fun receiver(self: &PacketHeader): Bytes32 {
    self.receiver
}

// === Outbound Packet Functions ===

/// Encodes a complete outbound packet including header, GUID, and message.
public fun encode_packet(packet: &OutboundPacket): vector<u8> {
    let header = encode_packet_header(packet);
    let mut writer = buffer_writer::create(header);
    writer.write_bytes32(packet.guid()).write_bytes(*packet.message());
    writer.to_bytes()
}

/// Encodes only the packet header from an outbound packet.
public fun encode_packet_header(packet: &OutboundPacket): vector<u8> {
    PacketHeader {
        version: PACKET_VERSION,
        nonce: packet.nonce(),
        src_eid: packet.src_eid(),
        sender: bytes32::from_address(packet.sender()),
        dst_eid: packet.dst_eid(),
        receiver: packet.receiver(),
    }.encode_header()
}

/// Returns the payload (GUID + message) from an outbound packet.
public fun payload(packet: &OutboundPacket): vector<u8> {
    let mut writer = buffer_writer::new();
    writer.write_bytes32(packet.guid()).write_bytes(*packet.message());
    writer.to_bytes()
}

/// Returns the keccak256 hash of the packet payload.
public fun payload_hash(packet: &OutboundPacket): Bytes32 {
    hash::keccak256!(&payload(packet))
}

// === Test-only Functions ===

#[test_only]
public fun create_packet_header_for_testing(
    version: u8,
    nonce: u64,
    src_eid: u32,
    sender: Bytes32,
    dst_eid: u32,
    receiver: Bytes32,
): PacketHeader {
    PacketHeader { version, nonce, src_eid, sender, dst_eid, receiver }
}
