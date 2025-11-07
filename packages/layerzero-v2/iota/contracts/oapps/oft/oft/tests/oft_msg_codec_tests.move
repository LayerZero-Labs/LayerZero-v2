#[test_only]
module oft::oft_msg_codec_tests;

use oft::oft_msg_codec;
use utils::bytes32;

// === Test Constants ===

const ALICE: address = @0xa11ce;
const BOB: address = @0xb0b;

const DEFAULT_AMOUNT_SD: u64 = 1000000; // 1 token in shared decimals

// === Error Codes ===

const E_UNEXPECTED_COMPOSE: u64 = 0;
const E_EXPECTED_COMPOSE: u64 = 1;
const E_INVALID_SEND_TO: u64 = 2;
const E_INVALID_AMOUNT_SD: u64 = 3;
const E_COMPOSE_MSG_NOT_EMPTY: u64 = 4;
const E_COMPOSE_MSG_EMPTY: u64 = 5;
const E_INVALID_COMPOSE_FROM: u64 = 6;

// === OFT Message Codec Tests ===

#[test]
fun test_encode_no_compose() {
    let send_to = bytes32::from_address(BOB);
    let amount_sd = DEFAULT_AMOUNT_SD;

    // Encode without compose
    let encoded = oft_msg_codec::encode(send_to, amount_sd, option::none(), option::none());

    // Decode the message
    let message = oft_msg_codec::decode(encoded);

    // Should not have compose
    assert!(!oft_msg_codec::is_composed(&message), E_UNEXPECTED_COMPOSE);

    // Verify decoded values
    let decoded_send_to = oft_msg_codec::send_to(&message);
    let decoded_amount_sd = oft_msg_codec::amount_sd(&message);
    let decoded_compose_from = oft_msg_codec::compose_from(&message);
    let decoded_compose_msg = oft_msg_codec::compose_msg(&message);

    assert!(decoded_send_to == BOB, E_INVALID_SEND_TO);
    assert!(decoded_amount_sd == amount_sd, E_INVALID_AMOUNT_SD);
    assert!(option::is_none(&decoded_compose_from), E_INVALID_COMPOSE_FROM);
    assert!(option::is_none(decoded_compose_msg), E_COMPOSE_MSG_NOT_EMPTY);
}

#[test]
fun test_encode_with_compose() {
    let send_to = bytes32::from_address(BOB);
    let amount_sd = DEFAULT_AMOUNT_SD;
    let compose_from = ALICE;
    let compose_msg = b"hello world";

    // Encode with compose
    let encoded = oft_msg_codec::encode(
        send_to,
        amount_sd,
        option::some(bytes32::from_address(compose_from)),
        option::some(compose_msg),
    );

    // Decode the message
    let message = oft_msg_codec::decode(encoded);

    // Should have compose
    assert!(oft_msg_codec::is_composed(&message), E_EXPECTED_COMPOSE);

    // Verify decoded values
    let decoded_send_to = oft_msg_codec::send_to(&message);
    let decoded_amount_sd = oft_msg_codec::amount_sd(&message);
    let decoded_compose_from = oft_msg_codec::compose_from(&message);
    let decoded_compose_msg = oft_msg_codec::compose_msg(&message);

    assert!(decoded_send_to == BOB, E_INVALID_SEND_TO);
    assert!(decoded_amount_sd == amount_sd, E_INVALID_AMOUNT_SD);
    assert!(option::is_some(&decoded_compose_from), E_INVALID_COMPOSE_FROM);
    assert!(*option::borrow(&decoded_compose_from) == bytes32::from_address(ALICE), E_INVALID_COMPOSE_FROM);
    assert!(option::is_some(decoded_compose_msg), E_COMPOSE_MSG_EMPTY);
    assert!(*option::borrow(decoded_compose_msg) == compose_msg, E_COMPOSE_MSG_EMPTY);
}

#[test]
fun test_empty_compose_msg() {
    let send_to = bytes32::from_address(BOB);
    let amount_sd = DEFAULT_AMOUNT_SD;
    let compose_from = ALICE;
    let compose_msg = vector::empty<u8>();

    // Test encoding with empty compose message - should still create composed message
    let encoded = oft_msg_codec::encode(
        send_to,
        amount_sd,
        option::some(bytes32::from_address(compose_from)),
        option::some(compose_msg),
    );

    // Decode the message
    let message = oft_msg_codec::decode(encoded);

    // Should still have compose even with empty message
    assert!(oft_msg_codec::is_composed(&message), E_EXPECTED_COMPOSE);

    // Verify decoded values
    let decoded_send_to = oft_msg_codec::send_to(&message);
    let decoded_amount_sd = oft_msg_codec::amount_sd(&message);
    let decoded_compose_from = oft_msg_codec::compose_from(&message);
    let decoded_compose_msg = oft_msg_codec::compose_msg(&message);

    assert!(decoded_send_to == BOB, E_INVALID_SEND_TO);
    assert!(decoded_amount_sd == amount_sd, E_INVALID_AMOUNT_SD);
    assert!(option::is_some(&decoded_compose_from), E_INVALID_COMPOSE_FROM);
    assert!(*option::borrow(&decoded_compose_from) == bytes32::from_address(ALICE), E_INVALID_COMPOSE_FROM);
    assert!(option::is_some(decoded_compose_msg), E_COMPOSE_MSG_NOT_EMPTY);
    assert!(option::borrow(decoded_compose_msg).is_empty(), E_COMPOSE_MSG_NOT_EMPTY);
}

#[test]
fun test_is_composed_detection() {
    let send_to = bytes32::from_address(BOB);
    let amount_sd = DEFAULT_AMOUNT_SD;

    // Test non-composed message
    let encoded_no_compose = oft_msg_codec::encode(send_to, amount_sd, option::none(), option::none());
    let msg_no_compose = oft_msg_codec::decode(encoded_no_compose);
    assert!(!oft_msg_codec::is_composed(&msg_no_compose), E_UNEXPECTED_COMPOSE);

    // Test composed message
    let encoded_with_compose = oft_msg_codec::encode(
        send_to,
        amount_sd,
        option::some(bytes32::from_address(ALICE)),
        option::some(b"test compose"),
    );
    let msg_with_compose = oft_msg_codec::decode(encoded_with_compose);
    assert!(oft_msg_codec::is_composed(&msg_with_compose), E_EXPECTED_COMPOSE);
}

// === Address Conversion Tests ===

#[test]
fun test_message_field_extraction() {
    let send_to = bytes32::from_address(BOB);
    let amount_sd = 12345u64;
    let compose_from = ALICE;
    let compose_msg = b"test message";

    // Encode with compose
    let encoded = oft_msg_codec::encode(
        send_to,
        amount_sd,
        option::some(bytes32::from_address(compose_from)),
        option::some(compose_msg),
    );

    // Decode the message
    let message = oft_msg_codec::decode(encoded);

    // Test all field extraction functions
    assert!(oft_msg_codec::send_to(&message) == BOB, E_INVALID_SEND_TO);
    assert!(oft_msg_codec::amount_sd(&message) == amount_sd, E_INVALID_AMOUNT_SD);
    assert!(oft_msg_codec::is_composed(&message), E_EXPECTED_COMPOSE);

    let decoded_compose_from = oft_msg_codec::compose_from(&message);
    assert!(option::is_some(&decoded_compose_from), E_INVALID_COMPOSE_FROM);
    assert!(*option::borrow(&decoded_compose_from) == bytes32::from_address(ALICE), E_INVALID_COMPOSE_FROM);

    let compose_msg_result = oft_msg_codec::compose_msg(&message);
    assert!(option::is_some(compose_msg_result), E_COMPOSE_MSG_EMPTY);
    assert!(*option::borrow(compose_msg_result) == compose_msg, E_COMPOSE_MSG_EMPTY);
}

#[test]
fun test_encode_decode_roundtrip() {
    let send_to = bytes32::from_address(BOB);
    let amount_sd = 9876543210u64;

    // Test roundtrip for non-composed message
    let encoded_simple = oft_msg_codec::encode(send_to, amount_sd, option::none(), option::none());
    let decoded_simple = oft_msg_codec::decode(encoded_simple);

    assert!(oft_msg_codec::send_to(&decoded_simple) == BOB, E_INVALID_SEND_TO);
    assert!(oft_msg_codec::amount_sd(&decoded_simple) == amount_sd, E_INVALID_AMOUNT_SD);
    assert!(!oft_msg_codec::is_composed(&decoded_simple), E_UNEXPECTED_COMPOSE);

    // Test roundtrip for composed message
    let compose_from = ALICE;
    let compose_msg = b"roundtrip test message with some data";

    let encoded_compose = oft_msg_codec::encode(
        send_to,
        amount_sd,
        option::some(bytes32::from_address(compose_from)),
        option::some(compose_msg),
    );
    let decoded_compose = oft_msg_codec::decode(encoded_compose);

    assert!(oft_msg_codec::send_to(&decoded_compose) == BOB, E_INVALID_SEND_TO);
    assert!(oft_msg_codec::amount_sd(&decoded_compose) == amount_sd, E_INVALID_AMOUNT_SD);
    assert!(oft_msg_codec::is_composed(&decoded_compose), E_EXPECTED_COMPOSE);

    let decoded_compose_from = oft_msg_codec::compose_from(&decoded_compose);
    let decoded_compose_msg = oft_msg_codec::compose_msg(&decoded_compose);

    assert!(option::is_some(&decoded_compose_from), E_INVALID_COMPOSE_FROM);
    assert!(*option::borrow(&decoded_compose_from) == bytes32::from_address(ALICE), E_INVALID_COMPOSE_FROM);
    assert!(option::is_some(decoded_compose_msg), E_COMPOSE_MSG_EMPTY);
    assert!(*option::borrow(decoded_compose_msg) == compose_msg, E_COMPOSE_MSG_EMPTY);
}
