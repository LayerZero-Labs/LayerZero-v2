#[test_only]
module message_lib_common::packet_v1_codec_tests;

use endpoint_v2::outbound_packet::{Self, OutboundPacket};
use message_lib_common::packet_v1_codec::{Self, PacketHeader};
use utils::{buffer_reader, buffer_writer, bytes32::{Self, Bytes32}, hash};

// Test constants
const TEST_SRC_EID: u32 = 101;
const TEST_DST_EID: u32 = 102;
const TEST_NONCE: u64 = 0x123456789abcdef0;
const TEST_SENDER: address = @0x1234567890abcdef1234567890abcdef12345678;
const TEST_RECEIVER: address = @0x9876543210fedcba9876543210fedcba98765432;
const TEST_MESSAGE: vector<u8> = vector[0x01, 0x02, 0x03, 0x04, 0x05];

#[test]
fun test_encode_decode_packet_header() {
    let ctx = &mut tx_context::dummy();
    let outbound_packet = create_test_outbound_packet(ctx);

    // Encode the packet header
    let encoded_header = packet_v1_codec::encode_packet_header(&outbound_packet);

    // Verify the encoded header has the correct length
    assert!(encoded_header.length() == 81, 1001); // HEADER_LENGTH = 81

    // Decode the header back
    let decoded_header = packet_v1_codec::decode_header(encoded_header);

    // Verify all fields match
    assert!(decoded_header.version() == 1, 1002);
    assert!(decoded_header.nonce() == TEST_NONCE, 1003);
    assert!(decoded_header.src_eid() == TEST_SRC_EID, 1004);
    assert!(decoded_header.dst_eid() == TEST_DST_EID, 1005);
    assert!(decoded_header.sender() == bytes32::from_address(TEST_SENDER), 1006);
    assert!(decoded_header.receiver() == bytes32::from_address(TEST_RECEIVER), 1007);
}

#[test]
fun test_payload_functions() {
    let ctx = &mut tx_context::dummy();
    let outbound_packet = create_test_outbound_packet(ctx);

    // Test payload extraction
    let payload = packet_v1_codec::payload(&outbound_packet);
    let expected_payload = vector::flatten(vector[outbound_packet.guid().to_bytes(), TEST_MESSAGE]);
    assert!(payload == expected_payload, 3001);

    // Test payload hash
    let payload_hash = packet_v1_codec::payload_hash(&outbound_packet);
    let expected_hash = hash::keccak256!(&payload);
    assert!(payload_hash == expected_hash, 3002);
}

#[test]
#[expected_failure(abort_code = packet_v1_codec::EInvalidPacketHeader)] // EInvalidPacketHeader
fun test_invalid_header_length() {
    // Create a header with wrong length (too short)
    let invalid_header = vector[0x01, 0x02, 0x03]; // Only 3 bytes instead of 81
    packet_v1_codec::decode_header(invalid_header);
}

#[test]
#[expected_failure(abort_code = packet_v1_codec::EInvalidPacketVersion)] // EInvalidPacketVersion
fun test_invalid_packet_version() {
    // Create a header with correct length but wrong version
    let mut invalid_header = vector::empty<u8>();
    let mut i = 0;
    while (i < 81) {
        invalid_header.push_back(0x00);
        i = i + 1;
    };
    *invalid_header.borrow_mut(0) = 2; // Wrong version (should be 1)

    packet_v1_codec::decode_header(invalid_header);
}

#[test]
fun test_header_getters() {
    let header = create_test_header();

    // Test all getter functions
    assert!(header.version() == 1, 6001);
    assert!(header.nonce() == TEST_NONCE, 6002);
    assert!(header.src_eid() == TEST_SRC_EID, 6003);
    assert!(header.dst_eid() == TEST_DST_EID, 6004);
    assert!(header.sender() == bytes32::from_address(TEST_SENDER), 6005);
    assert!(header.receiver() == bytes32::from_address(TEST_RECEIVER), 6006);
}

#[test]
fun test_encode_header_roundtrip() {
    let header = create_test_header();

    // Encode then decode should give back the same header
    let encoded = header.encode_header();
    let decoded = packet_v1_codec::decode_header(encoded);

    assert!(decoded.version() == header.version(), 7001);
    assert!(decoded.nonce() == header.nonce(), 7002);
    assert!(decoded.src_eid() == header.src_eid(), 7003);
    assert!(decoded.dst_eid() == header.dst_eid(), 7004);
    assert!(decoded.sender() == header.sender(), 7005);
    assert!(decoded.receiver() == header.receiver(), 7006);
}

#[test]
fun test_empty_message() {
    let _ctx = &tx_context::dummy();
    let empty_message = vector::empty<u8>();

    let outbound_packet = outbound_packet::create_for_test(
        TEST_NONCE,
        TEST_SRC_EID,
        TEST_SENDER,
        TEST_DST_EID,
        bytes32::from_address(TEST_RECEIVER),
        empty_message,
    );

    // Test encoding and decoding with empty message
    let encoded = packet_v1_codec::encode_packet(&outbound_packet);
    let (header, decoded_guid, decoded_message) = decode_packet_for_test(encoded);

    assert!(header.src_eid() == TEST_SRC_EID, 8001);
    assert!(decoded_guid == outbound_packet.guid(), 8002);
    assert!(decoded_message.length() == 0, 8003);
}

#[test]
fun test_large_message() {
    let _ctx = &tx_context::dummy();

    // Create a large message (1KB)
    let mut large_message = vector::empty<u8>();
    let mut i = 0;
    while (i < 1024) {
        large_message.push_back((i % 256) as u8);
        i = i + 1;
    };
    let outbound_packet = outbound_packet::create_for_test(
        TEST_NONCE,
        TEST_SRC_EID,
        TEST_SENDER,
        TEST_DST_EID,
        bytes32::from_address(TEST_RECEIVER),
        large_message,
    );

    // Test encoding and decoding with large message
    let encoded = packet_v1_codec::encode_packet(&outbound_packet);
    let (header, decoded_guid, decoded_message) = decode_packet_for_test(encoded);

    assert!(header.src_eid() == TEST_SRC_EID, 9001);
    assert!(decoded_guid == outbound_packet.guid(), 9002);
    assert!(decoded_message.length() == 1024, 9003);
    assert!(decoded_message == large_message, 9004);
}

// Helper functions
fun create_test_outbound_packet(_ctx: &mut TxContext): OutboundPacket {
    outbound_packet::create_for_test(
        TEST_NONCE,
        TEST_SRC_EID,
        TEST_SENDER,
        TEST_DST_EID,
        bytes32::from_address(TEST_RECEIVER),
        TEST_MESSAGE,
    )
}

fun create_test_header(): PacketHeader {
    let mut writer = buffer_writer::new();
    writer
        .write_u8(1) // version
        .write_u64(TEST_NONCE)
        .write_u32(TEST_SRC_EID)
        .write_bytes32(bytes32::from_address(TEST_SENDER))
        .write_u32(TEST_DST_EID)
        .write_bytes32(bytes32::from_address(TEST_RECEIVER));
    packet_v1_codec::decode_header(writer.to_bytes())
}

fun decode_packet_for_test(encoded: vector<u8>): (PacketHeader, Bytes32, vector<u8>) {
    let mut reader = buffer_reader::create(encoded);
    let header = packet_v1_codec::decode_header(reader.read_fixed_len_bytes(81));
    let guid = reader.read_bytes32();
    let message = reader.read_bytes_until_end();
    (header, guid, message)
}
