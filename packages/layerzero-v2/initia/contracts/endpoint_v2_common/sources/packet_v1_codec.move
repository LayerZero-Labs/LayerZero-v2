module endpoint_v2_common::packet_v1_codec {
    use std::vector;

    use endpoint_v2_common::bytes32::{Self, Bytes32};
    use endpoint_v2_common::packet_raw::{Self, borrow_packet_bytes, bytes_to_raw_packet, RawPacket};
    use endpoint_v2_common::serde;

    const PACKET_VERSION: u8 = 1;

    // Header Offsets
    const VERSION_OFFSET: u64 = 0;
    const NONCE_OFFSET: u64 = 1;
    const SRC_EID_OFFSET: u64 = 9;
    const SENDER_OFFSET: u64 = 13;
    const DST_EID_OFFSET: u64 = 45;
    const RECEIVER_OFFSET: u64 = 49;
    const HEADER_LENGTH: u64 = 81;

    // Message Offsets
    const GUID_OFFSET: u64 = 81;
    const MESSAGE_OFFSET: u64 = 113;

    /// Build a new packet with the given parameters
    public fun new_packet_v1(
        src_eid: u32,
        sender: Bytes32,
        dst_eid: u32,
        receiver: Bytes32,
        nonce: u64,
        guid: Bytes32,
        message: vector<u8>,
    ): RawPacket {
        let bytes = new_packet_v1_header_only_bytes(src_eid, sender, dst_eid, receiver, nonce);
        serde::append_bytes32(&mut bytes, guid);
        vector::append(&mut bytes, message);
        bytes_to_raw_packet(bytes)
    }

    /// Build a new packet (header only) with the given parameters
    public fun new_packet_v1_header_only(
        src_eid: u32,
        sender: Bytes32,
        dst_eid: u32,
        receiver: Bytes32,
        nonce: u64,
    ): RawPacket {
        bytes_to_raw_packet(
            new_packet_v1_header_only_bytes(src_eid, sender, dst_eid, receiver, nonce)
        )
    }

    /// Build a new packet (header only) with the given parameters and output byte form
    public fun new_packet_v1_header_only_bytes(
        src_eid: u32,
        sender: Bytes32,
        dst_eid: u32,
        receiver: Bytes32,
        nonce: u64,
    ): vector<u8> {
        let bytes = vector<u8>[];
        serde::append_u8(&mut bytes, PACKET_VERSION);
        serde::append_u64(&mut bytes, nonce);
        serde::append_u32(&mut bytes, src_eid);
        serde::append_bytes32(&mut bytes, sender);
        serde::append_u32(&mut bytes, dst_eid);
        serde::append_bytes32(&mut bytes, receiver);
        bytes
    }

    /// Extract only the Packet header part from a RawPacket
    public fun extract_header(raw_packet: &RawPacket): RawPacket {
        if (packet_raw::length(raw_packet) > GUID_OFFSET) {
            let packet_header_bytes = vector::slice(borrow_packet_bytes(raw_packet), 0, GUID_OFFSET);
            bytes_to_raw_packet(packet_header_bytes)
        } else {
            *raw_packet
        }
    }

    /// Check that the packet is the expected version for this codec (version 1)
    public fun is_valid_version(raw_packet: &RawPacket): bool {
        get_version(raw_packet) == PACKET_VERSION
    }

    /// Get the version of the packet
    public fun get_version(raw_packet: &RawPacket): u8 {
        let packet_bytes = packet_raw::borrow_packet_bytes(raw_packet);
        serde::extract_u8(packet_bytes, &mut VERSION_OFFSET)
    }

    /// Get the nonce of the packet
    public fun get_nonce(raw_packet: &RawPacket): u64 {
        let packet_bytes = packet_raw::borrow_packet_bytes(raw_packet);
        serde::extract_u64(packet_bytes, &mut NONCE_OFFSET)
    }

    /// Get the source EID of the packet
    public fun get_src_eid(raw_packet: &RawPacket): u32 {
        let packet_bytes = packet_raw::borrow_packet_bytes(raw_packet);
        serde::extract_u32(packet_bytes, &mut SRC_EID_OFFSET)
    }

    /// Get the sender of the packet
    public fun get_sender(raw_packet: &RawPacket): Bytes32 {
        let packet_bytes = packet_raw::borrow_packet_bytes(raw_packet);
        serde::extract_bytes32(packet_bytes, &mut SENDER_OFFSET)
    }

    /// Get the destination EID of the packet
    public fun get_dst_eid(raw_packet: &RawPacket): u32 {
        let packet_bytes = packet_raw::borrow_packet_bytes(raw_packet);
        serde::extract_u32(packet_bytes, &mut DST_EID_OFFSET)
    }

    /// Get the receiver of the packet
    public fun get_receiver(raw_packet: &RawPacket): Bytes32 {
        let packet_bytes = packet_raw::borrow_packet_bytes(raw_packet);
        serde::extract_bytes32(packet_bytes, &mut RECEIVER_OFFSET)
    }

    /// Get the GUID of the packet
    public fun get_guid(raw_packet: &RawPacket): Bytes32 {
        let packet_bytes = packet_raw::borrow_packet_bytes(raw_packet);
        serde::extract_bytes32(packet_bytes, &mut GUID_OFFSET)
    }

    /// Get the length of the message in the packet
    public fun get_message_length(raw_packet: &RawPacket): u64 {
        let packet_length = packet_raw::length(raw_packet);
        packet_length - MESSAGE_OFFSET
    }

    /// Get the message of the packet
    public fun get_message(raw_packet: &RawPacket): vector<u8> {
        let packet_bytes = packet_raw::borrow_packet_bytes(raw_packet);
        serde::extract_bytes_until_end(packet_bytes, &mut MESSAGE_OFFSET)
    }

    /// Get the payload of the packet
    public fun get_payload_hash(packet: &RawPacket): Bytes32 {
        let guid = get_guid(packet);
        let message = get_message(packet);
        compute_payload_hash(guid, message)
    }

    /// Compute the payload of the packet
    public fun compute_payload(guid: Bytes32, message: vector<u8>): vector<u8> {
        let payload = vector[];
        vector::append(&mut payload, bytes32::from_bytes32(guid));
        vector::append(&mut payload, message);
        payload
    }

    /// Compute the payload hash of the packet
    public fun compute_payload_hash(guid: Bytes32, message: vector<u8>): Bytes32 {
        bytes32::keccak256(compute_payload(guid, message))
    }

    /// Assert that the packet is a valid packet for the local EID
    public fun assert_receive_header(packet_header: &RawPacket, local_eid: u32) {
        let packet_bytes = packet_raw::borrow_packet_bytes(packet_header);
        assert!(vector::length(packet_bytes) == HEADER_LENGTH, EINVALID_PACKET_HEADER);
        assert!(is_valid_version(packet_header), EINVALID_PACKET_VERSION);
        assert!(get_dst_eid(packet_header) == local_eid, EINVALID_EID)
    }

    public fun is_receive_header_valid(packet_header: &RawPacket, local_eid: u32): bool {
        let packet_bytes = packet_raw::borrow_packet_bytes(packet_header);
        vector::length(packet_bytes) == HEADER_LENGTH
            && is_valid_version(packet_header)
            && get_dst_eid(packet_header) == local_eid
    }

    // ================================================== Error Codes =================================================

    const EINVALID_EID: u64 = 1;
    const EINVALID_PACKET_HEADER: u64 = 2;
    const EINVALID_PACKET_VERSION: u64 = 3;
}