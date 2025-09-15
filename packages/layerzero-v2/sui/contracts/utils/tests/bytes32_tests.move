#[test_only]
module utils::bytes32_tests;

use utils::bytes32::{
    Self,
    zero_bytes32,
    is_zero,
    from_bytes,
    is_ff,
    ff_bytes32,
    to_bytes,
    from_address,
    to_address,
    from_id,
    to_id,
    from_bytes_left_padded,
    from_bytes_right_padded
};

#[test]
public fun test_is_zero() {
    let zero = zero_bytes32();
    assert!(is_zero(&zero));

    let zero = x"0000000000000000000000000000000000000000000000000000000000000000";
    assert!(is_zero(&from_bytes(zero)));
}

#[test]
public fun test_is_ff() {
    let ff = ff_bytes32();
    assert!(is_ff(&ff));

    let ff = x"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    assert!(is_ff(&from_bytes(ff)));
}

#[test]
public fun test_from_bytes_to_bytes() {
    let bytes = x"0000000000000000000000000000000000000000000000000000000000001234";
    let bytes32 = from_bytes(bytes);
    assert!(bytes32.to_bytes() == bytes);
}

#[test]
public fun test_from_address_to_address() {
    let addr = @0x1234567890abcdef;
    let bytes32 = from_address(addr);
    assert!(bytes32.to_address() == addr);
}

#[test]
public fun test_from_id_to_id() {
    let id = sui::object::id_from_bytes(
        x"0000000000000000000000000000000000000000000000000000000000001234",
    );
    let bytes32 = from_id(id);
    assert!(bytes32.to_id() == id);
}

#[test]
public fun test_from_bytes_left_padded() {
    // Test with 1 byte - should pad with 31 zeros on the left
    let input = x"ab";
    let bytes32 = from_bytes_left_padded(input);
    let expected = x"00000000000000000000000000000000000000000000000000000000000000ab";
    assert!(bytes32.to_bytes() == expected);

    // Test with 32 bytes - should not pad at all
    let input = x"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    let bytes32 = from_bytes_left_padded(input);
    assert!(bytes32.to_bytes() == input);
}

#[test]
public fun test_from_bytes_right_padded() {
    // Test with 1 byte - should pad with 31 zeros on the right
    let input = x"ab";
    let bytes32 = from_bytes_right_padded(input);
    let expected = x"ab00000000000000000000000000000000000000000000000000000000000000";
    assert!(bytes32.to_bytes() == expected);

    // Test with 32 bytes - should not pad at all
    let input = x"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    let bytes32 = from_bytes_right_padded(input);
    assert!(bytes32.to_bytes() == input);
}

#[test, expected_failure(abort_code = bytes32::EInvalidLength)]
public fun test_from_bytes_left_padded_invalid_length() {
    // Test with more than 32 bytes - should fail
    let bytes = x"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef12";
    from_bytes_left_padded(bytes);
}

#[test, expected_failure(abort_code = bytes32::EInvalidLength)]
public fun test_from_bytes_right_padded_invalid_length() {
    // Test with more than 32 bytes - should fail
    let bytes = x"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef12";
    from_bytes_right_padded(bytes);
}

#[test, expected_failure(abort_code = bytes32::EInvalidLength)]
public fun test_invalid_length() {
    let bytes = x"1234";
    let _bytes32 = from_bytes(bytes);
}
