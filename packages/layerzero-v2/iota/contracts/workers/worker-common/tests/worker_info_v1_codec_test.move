#[test_only]
module worker_common::worker_info_v1_codec_test;

use worker_common::worker_info_v1;

// === Test Constants ===

const TEST_WORKER_ID: u8 = 1;

// === Test Data ===

fun create_test_info(): vector<u8> {
    b"test_payload"
}

fun create_empty_info(): vector<u8> {
    vector[]
}

// === Codec Tests ===

#[test]
fun test_encode_decode_round_trip() {
    // Create test WorkerInfoV1 for DVN
    let test_worker_info = worker_info_v1::create(
        TEST_WORKER_ID,
        create_test_info(),
    );

    // Encode the data
    let encoded_bytes = worker_info_v1::encode(&test_worker_info);

    // Decode the bytes back
    let decoded_worker_info = worker_info_v1::decode(encoded_bytes);

    // Verify all fields match exactly
    assert!(decoded_worker_info.worker_id() == TEST_WORKER_ID, 0);
    std::debug::print(decoded_worker_info.worker_info());
    std::debug::print(&create_test_info());
    assert!(*decoded_worker_info.worker_info() == create_test_info(), 1);
}

#[test]
fun test_encode_decode_empty_payload() {
    // Test with empty payload
    let test_worker_info = worker_info_v1::create(
        TEST_WORKER_ID,
        create_empty_info(),
    );

    let encoded_bytes = worker_info_v1::encode(&test_worker_info);
    let decoded_worker_info = worker_info_v1::decode(encoded_bytes);

    assert!(decoded_worker_info.worker_id() == TEST_WORKER_ID, 0);
    assert!(decoded_worker_info.worker_info().length() == 0, 1);
}

#[test]
#[expected_failure(abort_code = worker_info_v1::EInvalidVersion)]
fun test_decode_invalid_version() {
    // Create invalid encoded data with wrong version
    let mut invalid_encoded = vector::empty<u8>();
    invalid_encoded.push_back(0u8); // Invalid version (2, big-endian high byte)
    invalid_encoded.push_back(2u8); // Invalid version (2, big-endian low byte)
    invalid_encoded.push_back(TEST_WORKER_ID); // Worker type
    invalid_encoded.append(b"some_payload");

    // Should fail with EInvalidVersion
    worker_info_v1::decode(invalid_encoded);
}

#[test]
#[expected_failure(abort_code = worker_info_v1::EInvalidData)]
fun test_decode_invalid_data() {
    let test_worker_info = worker_info_v1::create(
        TEST_WORKER_ID,
        create_empty_info(),
    );
    // Create invalid encoded data with valid version but invalid BCS data (trailing bytes)
    let mut invalid_encoded = vector::empty<u8>();
    invalid_encoded.append(test_worker_info.encode());
    invalid_encoded.append(b"deadbeef"); // Extra trailing bytes
    worker_info_v1::decode(invalid_encoded);
}

#[test]
fun test_view_functions() {
    // Test all view functions work correctly
    let worker_id = TEST_WORKER_ID;
    let payload = b"view_function_test_payload";
    let worker_info = worker_info_v1::create(worker_id, payload);

    // Test worker_id view function
    assert!(worker_info.worker_id() == worker_id, 0);

    // Test worker_info view function
    assert!(*worker_info.worker_info() == payload, 1);
}
