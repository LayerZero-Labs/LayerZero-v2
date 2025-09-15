#[test_only]
module uln_302::executor_config_test;

use sui::bcs;
use uln_302::executor_config;

#[test]
fun test_deserialize_max_values() {
    // Test with maximum values
    let mut config_bytes = vector[];

    // Max message size as u64::MAX (18446744073709551615)
    config_bytes.append(x"ffffffffffffffff"); // u64::MAX

    // Executor address with all bytes set to 0xFF
    config_bytes.append(x"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

    let config = executor_config::deserialize(config_bytes);

    assert!(config.max_message_size() == 18446744073709551615, 1);
    assert!(config.executor() == @0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, 0);
}

#[test]
fun test_deserialize_zero_values() {
    // Test with zero values (should be allowed in deserialization)
    let mut config_bytes = vector[];

    // Max message size 0
    config_bytes.append(x"0000000000000000"); // 0 as u64

    // Executor address @0x0
    config_bytes.append(x"0000000000000000000000000000000000000000000000000000000000000000");

    let config = executor_config::deserialize(config_bytes);

    assert!(config.max_message_size() == 0, 1);
    assert!(config.executor() == @0x0, 0);
}

#[test, expected_failure(abort_code = sui::bcs::EOutOfRange)]
fun test_deserialize_should_fail_when_too_few_bytes() {
    // Should fail when not enough bytes (less than 40 bytes)
    // BCS will fail with its own error when trying to read u64 from insufficient bytes
    let config_bytes = x"00000000000000000000000000000000000000000000000000000000000001234567"; // Only 36 bytes

    executor_config::deserialize(config_bytes);
}

#[test, expected_failure(abort_code = executor_config::EInvalidExecutorBytes)]
fun test_deserialize_should_fail_when_too_many_bytes() {
    // Should fail when too many bytes (more than 40 bytes)
    // This one should still fail with our error code since BCS succeeds but remainder check fails
    let mut config_bytes = vector[];

    // Valid 40 bytes
    config_bytes.append(x"1027000000000000");
    config_bytes.append(x"0000000000000000000000000000000000000000000000000000000000000123");

    // Extra bytes (should cause failure)
    config_bytes.append(x"deadbeef");

    executor_config::deserialize(config_bytes);
}

#[test, expected_failure(abort_code = sui::bcs::EOutOfRange)]
fun test_deserialize_should_fail_when_empty_bytes() {
    // Should fail with empty byte vector
    // BCS will fail with its own error when trying to read address from empty bytes
    let config_bytes = vector[];

    executor_config::deserialize(config_bytes);
}

#[test, expected_failure(abort_code = sui::bcs::EOutOfRange)]
fun test_deserialize_should_fail_when_only_address() {
    // Should fail when only address is provided (32 bytes, missing u64)
    // BCS will fail with its own error when trying to read u64 from insufficient bytes
    let config_bytes = x"0000000000000000000000000000000000000000000000000000000000000123";

    executor_config::deserialize(config_bytes);
}

#[test]
fun test_deserialize_roundtrip_with_bcs() {
    // Test roundtrip serialization/deserialization using BCS directly
    let original_executor = @0x987654321;
    let original_size = 25000;

    // Create config manually (not used but good for verification)
    let _original_config = executor_config::create(original_size, original_executor);

    // Serialize using BCS (manually create the expected byte format)
    let mut serialized_bytes = vector[];
    serialized_bytes.append(bcs::to_bytes(&original_size));
    serialized_bytes.append(bcs::to_bytes(&original_executor));

    // Deserialize and verify
    let deserialized_config = executor_config::deserialize(serialized_bytes);

    assert!(deserialized_config.max_message_size() == original_size, 1);
    assert!(deserialized_config.executor() == original_executor, 0);
}

#[test]
fun test_assert_default_config() {
    let config = executor_config::create(1000, @0x123);
    config.assert_default_config();
}

#[test, expected_failure(abort_code = executor_config::EZeroMessageSize)]
fun test_assert_default_config_should_fail_when_zero_message_size() {
    let config = executor_config::create(0, @0x123);
    config.assert_default_config();
}

#[test, expected_failure(abort_code = executor_config::EInvalidExecutorAddress)]
fun test_assert_default_config_should_fail_when_zero_executor() {
    let config = executor_config::create(12, @0x00);
    config.assert_default_config();
}

#[test]
fun test_get_effective_executor_config_uses_oapp_values() {
    let default_config = executor_config::create(1000, @0x123);
    let oapp_config = executor_config::create(2000, @0x456);
    let effective_config = executor_config::get_effective_executor_config(&oapp_config, &default_config);
    assert!(effective_config.max_message_size() == 2000, 1);
    assert!(effective_config.executor() == @0x456, 0);
}

#[test]
fun test_get_effective_executor_config_uses_default_message_size() {
    let default_config = executor_config::create(1000, @0x123);
    let oapp_config = executor_config::create(0, @0x456);
    let effective_config = executor_config::get_effective_executor_config(&oapp_config, &default_config);
    assert!(effective_config.max_message_size() == 1000, 1);
    assert!(effective_config.executor() == @0x456, 0);
}

#[test]
fun test_get_effective_executor_config_uses_default_executor() {
    let default_config = executor_config::create(1000, @0x123);
    let oapp_config = executor_config::create(9999, @0x0);
    let effective_config = executor_config::get_effective_executor_config(&oapp_config, &default_config);
    assert!(effective_config.max_message_size() == 9999, 1);
    assert!(effective_config.executor() == @0x123, 0);
}
