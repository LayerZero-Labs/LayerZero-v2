#[test_only]
module oft_common::oft_compose_msg_codec_tests;

use oft_common::oft_compose_msg_codec;
use utils::bytes32;

// === Test Constants ===

const ALICE: address = @0xa11ce;
const BOB: address = @0xb0b;

const SRC_EID: u32 = 1;

// === Error Codes ===

const E_INVALID_NONCE: u64 = 0;
const E_INVALID_SRC_EID: u64 = 1;
const E_INVALID_AMOUNT_LD: u64 = 2;
const E_INVALID_MESSAGE_LENGTH: u64 = 3;
const E_INVALID_COMPOSE_FROM: u64 = 4;
const E_COMPOSE_MSG_NOT_EMPTY: u64 = 5;
const E_COMPOSE_MSG_EMPTY: u64 = 6;
const E_MESSAGE_TOO_SMALL: u64 = 7;

// === Compose Message Codec Tests ===

#[test]
fun test_encode_decode_basic() {
    let nonce = 12345u64;
    let src_eid = SRC_EID;
    let amount_ld = 1000000000000000000u64; // 1 ether
    let compose_from = bytes32::from_address(ALICE);
    let compose_msg = b"test compose message";

    // Encode
    let encoded = oft_compose_msg_codec::encode(nonce, src_eid, amount_ld, compose_from, compose_msg);

    // Decode and verify basic fields
    let decoded = oft_compose_msg_codec::decode(&encoded);
    let decoded_nonce = oft_compose_msg_codec::nonce(&decoded);
    let decoded_src_eid = oft_compose_msg_codec::src_eid(&decoded);
    let decoded_amount_ld = oft_compose_msg_codec::amount_ld(&decoded);
    let decoded_compose_from = oft_compose_msg_codec::compose_from(&decoded);

    assert!(decoded_nonce == nonce, E_INVALID_NONCE);
    assert!(decoded_src_eid == src_eid, E_INVALID_SRC_EID);
    assert!(decoded_amount_ld == amount_ld, E_INVALID_AMOUNT_LD);
    assert!(decoded_compose_from == compose_from, E_INVALID_COMPOSE_FROM);
    // Just test that the encoded message is not empty
    assert!(encoded.length() > 0, E_INVALID_MESSAGE_LENGTH);
}

#[test]
fun test_encode_with_compose_from() {
    let nonce = 67890u64;
    let src_eid = SRC_EID;
    let amount_ld = 1000000000000000000u64; // 1 ether
    let compose_from = bytes32::from_address(ALICE);
    let compose_msg = b"actual message";

    // Encode with compose_from as separate parameter
    let encoded = oft_compose_msg_codec::encode(nonce, src_eid, amount_ld, compose_from, compose_msg);

    // Decode and verify compose_from
    let decoded = oft_compose_msg_codec::decode(&encoded);
    let decoded_compose_from = oft_compose_msg_codec::compose_from(&decoded);
    let decoded_compose_msg = oft_compose_msg_codec::compose_msg(&decoded);

    assert!(decoded_compose_from == compose_from, E_INVALID_COMPOSE_FROM);
    assert!(*decoded_compose_msg == compose_msg, E_INVALID_MESSAGE_LENGTH);
}

#[test]
fun test_encode_empty_msg() {
    let nonce = 123u64;
    let src_eid = SRC_EID;
    let amount_ld = 1000000000000000000u64;
    let compose_from = bytes32::from_address(BOB);
    let compose_msg = vector::empty<u8>();

    // Encode with empty compose message
    let encoded = oft_compose_msg_codec::encode(nonce, src_eid, amount_ld, compose_from, compose_msg);

    // Should still decode correctly
    let decoded = oft_compose_msg_codec::decode(&encoded);
    let decoded_nonce = oft_compose_msg_codec::nonce(&decoded);
    let decoded_src_eid = oft_compose_msg_codec::src_eid(&decoded);
    let decoded_amount_ld = oft_compose_msg_codec::amount_ld(&decoded);
    let decoded_compose_from = oft_compose_msg_codec::compose_from(&decoded);
    let decoded_compose_msg = oft_compose_msg_codec::compose_msg(&decoded);

    assert!(decoded_nonce == nonce, E_INVALID_NONCE);
    assert!(decoded_src_eid == src_eid, E_INVALID_SRC_EID);
    assert!(decoded_amount_ld == amount_ld, E_INVALID_AMOUNT_LD);
    assert!(decoded_compose_from == compose_from, E_INVALID_COMPOSE_FROM);
    assert!(decoded_compose_msg.is_empty(), E_COMPOSE_MSG_NOT_EMPTY);
}

#[test]
fun test_field_extraction_precision() {
    let nonce = 999999u64;
    let src_eid = 42u32;
    let amount_ld = 12345678901234567890u64; // Large amount within u64 range
    let compose_from = bytes32::from_address(ALICE);
    let compose_msg = b"precision test message with special chars: !@#$%^&*()";

    // Encode
    let encoded = oft_compose_msg_codec::encode(nonce, src_eid, amount_ld, compose_from, compose_msg);

    // Decode and verify exact field extraction
    let decoded = oft_compose_msg_codec::decode(&encoded);
    assert!(oft_compose_msg_codec::nonce(&decoded) == nonce, E_INVALID_NONCE);
    assert!(oft_compose_msg_codec::src_eid(&decoded) == src_eid, E_INVALID_SRC_EID);
    assert!(oft_compose_msg_codec::amount_ld(&decoded) == amount_ld, E_INVALID_AMOUNT_LD);
    assert!(oft_compose_msg_codec::compose_from(&decoded) == compose_from, E_INVALID_COMPOSE_FROM);

    // Message should be non-empty
    let decoded_msg = oft_compose_msg_codec::compose_msg(&decoded);
    assert!(!decoded_msg.is_empty(), E_COMPOSE_MSG_EMPTY);
}

#[test]
fun test_zero_values() {
    let nonce = 0u64;
    let src_eid = 0u32;
    let amount_ld = 0u64;
    let compose_from = bytes32::from_address(ALICE);
    let compose_msg = vector::empty<u8>();

    // Encode
    let encoded = oft_compose_msg_codec::encode(nonce, src_eid, amount_ld, compose_from, compose_msg);

    // Decode and verify zero values are preserved
    let decoded = oft_compose_msg_codec::decode(&encoded);
    assert!(oft_compose_msg_codec::nonce(&decoded) == 0, E_INVALID_NONCE);
    assert!(oft_compose_msg_codec::src_eid(&decoded) == 0, E_INVALID_SRC_EID);
    assert!(oft_compose_msg_codec::amount_ld(&decoded) == 0, E_INVALID_AMOUNT_LD);
    assert!(oft_compose_msg_codec::compose_from(&decoded) == compose_from, E_INVALID_COMPOSE_FROM);
    assert!(oft_compose_msg_codec::compose_msg(&decoded).is_empty(), E_COMPOSE_MSG_NOT_EMPTY);
}

#[test]
fun test_max_values() {
    let nonce = 18446744073709551615u64; // Max u64
    let src_eid = 4294967295u32; // Max u32
    let amount_ld = 18446744073709551615u64; // Max u64
    let compose_from = bytes32::from_address(BOB);
    let compose_msg = b"max values test";

    // Encode
    let encoded = oft_compose_msg_codec::encode(nonce, src_eid, amount_ld, compose_from, compose_msg);

    // Decode and verify max values are preserved
    let decoded = oft_compose_msg_codec::decode(&encoded);
    assert!(oft_compose_msg_codec::nonce(&decoded) == nonce, E_INVALID_NONCE);
    assert!(oft_compose_msg_codec::src_eid(&decoded) == src_eid, E_INVALID_SRC_EID);
    assert!(oft_compose_msg_codec::amount_ld(&decoded) == amount_ld, E_INVALID_AMOUNT_LD);
    assert!(oft_compose_msg_codec::compose_from(&decoded) == compose_from, E_INVALID_COMPOSE_FROM);
    // Just verify the encoded message itself is not empty
    assert!(encoded.length() > 0, E_INVALID_MESSAGE_LENGTH);
}

#[test]
fun test_compose_from_extraction_edge_cases() {
    let nonce = 456u64;
    let src_eid = SRC_EID;
    let amount_ld = 500000000000000000u64;

    // Test with different compose_from addresses
    let compose_from_bob = bytes32::from_address(BOB);
    let empty_msg = vector::empty<u8>();
    let encoded_min = oft_compose_msg_codec::encode(nonce, src_eid, amount_ld, compose_from_bob, empty_msg);
    let decoded = oft_compose_msg_codec::decode(&encoded_min);
    let decoded_compose_from = oft_compose_msg_codec::compose_from(&decoded);
    assert!(decoded_compose_from == compose_from_bob, E_INVALID_COMPOSE_FROM);

    // Test with different compose_from + additional message data
    let compose_from_alice = bytes32::from_address(ALICE);
    let msg_with_data = b"additional data after compose_from";
    let encoded_with_data = oft_compose_msg_codec::encode(nonce, src_eid, amount_ld, compose_from_alice, msg_with_data);
    let decoded_2 = oft_compose_msg_codec::decode(&encoded_with_data);
    let decoded_compose_from_2 = oft_compose_msg_codec::compose_from(&decoded_2);
    let decoded_compose_msg_2 = oft_compose_msg_codec::compose_msg(&decoded_2);
    assert!(decoded_compose_from_2 == compose_from_alice, E_INVALID_COMPOSE_FROM);
    assert!(*decoded_compose_msg_2 == msg_with_data, E_INVALID_MESSAGE_LENGTH);
}

#[test]
fun test_multiple_encode_decode_cycles() {
    let mut nonce = 1u64;
    let mut src_eid = 10u32;
    let mut amount_ld = 1000u64;
    let compose_from = bytes32::from_address(ALICE);

    // Test multiple encoding/decoding cycles
    let mut i = 0;
    while (i < 5) {
        let compose_msg = b"cycle test";

        let encoded = oft_compose_msg_codec::encode(nonce, src_eid, amount_ld, compose_from, compose_msg);

        let decoded = oft_compose_msg_codec::decode(&encoded);
        assert!(oft_compose_msg_codec::nonce(&decoded) == nonce, E_INVALID_NONCE);
        assert!(oft_compose_msg_codec::src_eid(&decoded) == src_eid, E_INVALID_SRC_EID);
        assert!(oft_compose_msg_codec::amount_ld(&decoded) == amount_ld, E_INVALID_AMOUNT_LD);
        assert!(oft_compose_msg_codec::compose_from(&decoded) == compose_from, E_INVALID_COMPOSE_FROM);
        // Just verify the encoded message itself is not empty
        assert!(encoded.length() > 0, E_INVALID_MESSAGE_LENGTH);

        // Update values for next cycle
        nonce = nonce + 1;
        src_eid = src_eid + 1;
        amount_ld = amount_ld * 2;
        i = i + 1;
    };
}

#[test]
fun test_large_compose_message() {
    let nonce = 777u64;
    let src_eid = SRC_EID;
    let amount_ld = 2000000000000000000u64; // 2 ether
    let compose_from = bytes32::from_address(BOB);

    // Create a large compose message
    let mut large_msg = vector::empty<u8>();
    let mut i = 0;
    while (i < 100) {
        large_msg.append(b"This is a test message to create a large compose payload. ");
        i = i + 1;
    };

    // Encode
    let encoded = oft_compose_msg_codec::encode(nonce, src_eid, amount_ld, compose_from, large_msg);

    // Decode and verify basic fields still work with large messages
    let decoded = oft_compose_msg_codec::decode(&encoded);
    assert!(oft_compose_msg_codec::nonce(&decoded) == nonce, E_INVALID_NONCE);
    assert!(oft_compose_msg_codec::src_eid(&decoded) == src_eid, E_INVALID_SRC_EID);
    assert!(oft_compose_msg_codec::amount_ld(&decoded) == amount_ld, E_INVALID_AMOUNT_LD);
    assert!(oft_compose_msg_codec::compose_from(&decoded) == compose_from, E_INVALID_COMPOSE_FROM);

    // Verify message is not empty and has reasonable size
    let decoded_msg = oft_compose_msg_codec::compose_msg(&decoded);
    assert!(!decoded_msg.is_empty(), E_COMPOSE_MSG_EMPTY);
    assert!(decoded_msg.length() > 1000, E_MESSAGE_TOO_SMALL); // Should be quite large
}
