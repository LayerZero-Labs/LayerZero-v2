#[test_only]
module executor::executor_info_v1_codec_test;

use executor::executor_info_v1;

// === Test Constants ===

const TEST_EXECUTOR_OBJECT: address = @0x1234567890abcdef1234567890abcdef12345678;

// === Codec Tests ===

#[test]
fun test_encode_decode_round_trip() {
    // Create test ExecutorInfoV1 data
    let test_executor_info = executor_info_v1::create(TEST_EXECUTOR_OBJECT);

    // Encode the data
    let encoded_bytes = test_executor_info.encode();

    // Decode the bytes back
    let decoded_executor_info = executor_info_v1::decode(encoded_bytes);

    // Verify all fields match exactly
    assert!(decoded_executor_info.executor_object() == TEST_EXECUTOR_OBJECT, 0);
}

#[test]
fun test_encode_decode_empty_data() {
    // Test with zero address
    let test_executor_info = executor_info_v1::create(@0x0);

    let encoded_bytes = test_executor_info.encode();
    let decoded_executor_info = executor_info_v1::decode(encoded_bytes);

    assert!(decoded_executor_info.executor_object() == @0x0, 0);
}

#[test]
#[expected_failure(abort_code = executor_info_v1::EInvalidVersion)]
fun test_decode_invalid_version() {
    // Create invalid encoded data with wrong version
    let mut invalid_encoded = vector::empty<u8>();
    vector::push_back(&mut invalid_encoded, 0u8); // Invalid version (2, big-endian high byte)
    vector::push_back(&mut invalid_encoded, 2u8); // Invalid version (2, big-endian low byte)
    // Add some BCS-encoded address data
    vector::append(&mut invalid_encoded, x"0000000000000000000000000000000000000000000000000000000000000001");

    // Should fail with EInvalidVersion
    executor_info_v1::decode(invalid_encoded);
}

#[test]
#[expected_failure(abort_code = executor_info_v1::EInvalidData)]
fun test_decode_invalid_data() {
    // Create encoded data with valid version but invalid BCS data (trailing bytes)
    let mut invalid_encoded = vector::empty<u8>();
    vector::push_back(&mut invalid_encoded, 0u8); // Version 1 (big-endian high byte)
    vector::push_back(&mut invalid_encoded, 1u8); // Version 1 (big-endian low byte)
    // Add valid BCS-encoded address plus extra trailing bytes
    vector::append(&mut invalid_encoded, x"0000000000000000000000000000000000000000000000000000000000000001");
    vector::append(&mut invalid_encoded, x"deadbeef"); // Extra trailing bytes

    // Should fail with EInvalidData due to trailing bytes
    executor_info_v1::decode(invalid_encoded);
}
