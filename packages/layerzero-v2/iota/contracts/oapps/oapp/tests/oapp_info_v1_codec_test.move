#[test_only]
module oapp::oapp_info_v1_codec_test;

use oapp::oapp_info_v1;

// === Test Constants ===

const TEST_OAPP_OBJECT: address = @0x1234567890abcdef1234567890abcdef12345678;

// === Codec Tests ===

#[test]
fun test_encode_decode_round_trip() {
    // Create test OAppInfoV1 data
    let test_oapp_info = oapp_info_v1::create_test_oapp_info(
        TEST_OAPP_OBJECT,
        b"test_lz_receive_info_data",
        b"test_next_nonce_info_data",
        b"test_extra_info_data",
    );

    // Encode the data
    let encoded_bytes = oapp_info_v1::encode_for_test(&test_oapp_info);

    // Decode the bytes back
    let decoded_oapp_info = oapp_info_v1::decode(encoded_bytes);

    // Verify all fields match exactly
    assert!(oapp_info_v1::oapp_object(&decoded_oapp_info) == TEST_OAPP_OBJECT, 0);
    assert!(*oapp_info_v1::lz_receive_info(&decoded_oapp_info) == b"test_lz_receive_info_data", 1);
    assert!(*oapp_info_v1::next_nonce_info(&decoded_oapp_info) == b"test_next_nonce_info_data", 2);
    assert!(*oapp_info_v1::extra_info(&decoded_oapp_info) == b"test_extra_info_data", 3);
}

#[test]
fun test_encode_decode_empty_data() {
    // Test with empty vectors
    let test_oapp_info = oapp_info_v1::create_test_oapp_info(
        @0x0,
        vector<u8>[], // empty lz_receive_info
        vector<u8>[], // empty next_nonce_info
        vector<u8>[], // empty extra_info
    );

    let encoded_bytes = oapp_info_v1::encode_for_test(&test_oapp_info);
    let decoded_oapp_info = oapp_info_v1::decode(encoded_bytes);

    assert!(oapp_info_v1::oapp_object(&decoded_oapp_info) == @0x0, 0);
    assert!(oapp_info_v1::lz_receive_info(&decoded_oapp_info).length() == 0, 1);
    assert!(oapp_info_v1::next_nonce_info(&decoded_oapp_info).length() == 0, 2);
    assert!(oapp_info_v1::extra_info(&decoded_oapp_info).length() == 0, 3);
}
