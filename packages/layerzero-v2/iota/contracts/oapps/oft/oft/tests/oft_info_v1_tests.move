#[test_only]
module oft::oft_info_v1_tests;

use oft::oft_info_v1;

// === Creation Tests ===

#[test]
fun test_create_oft_info() {
    let oft_package = @0x1234;
    let oft_object = @0x5678;

    let oft_info = oft_info_v1::create(oft_package, oft_object);

    assert!(oft_info_v1::oft_package(&oft_info) == oft_package, 0);
    assert!(oft_info_v1::oft_object(&oft_info) == oft_object, 1);
}

#[test]
fun test_view_functions() {
    let oft_package = @0x9999;
    let oft_object = @0x8888;

    let oft_info = oft_info_v1::create(oft_package, oft_object);

    assert!(oft_info_v1::oft_package(&oft_info) == oft_package, 0);
    assert!(oft_info_v1::oft_object(&oft_info) == oft_object, 1);
}

// === Serialization Tests ===

#[test]
fun test_encode_decode_roundtrip() {
    let oft_package = @0xabcd;
    let oft_object = @0xef01;

    let original_info = oft_info_v1::create(oft_package, oft_object);
    let encoded = oft_info_v1::encode(&original_info);
    let decoded_info = oft_info_v1::decode(encoded);

    assert!(oft_info_v1::oft_package(&decoded_info) == oft_info_v1::oft_package(&original_info), 0);
    assert!(oft_info_v1::oft_object(&decoded_info) == oft_info_v1::oft_object(&original_info), 1);
}

#[test]
fun test_encode_decode_with_zero_addresses() {
    let oft_package = @0x0;
    let oft_object = @0x0;

    let original_info = oft_info_v1::create(oft_package, oft_object);
    let encoded = oft_info_v1::encode(&original_info);
    let decoded_info = oft_info_v1::decode(encoded);

    assert!(oft_info_v1::oft_package(&decoded_info) == @0x0, 0);
    assert!(oft_info_v1::oft_object(&decoded_info) == @0x0, 1);
}
