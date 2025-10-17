#[test_only]
module counter::options_builder_format_tests;

use counter::options_builder;
use utils::{buffer_reader, bytes32};

// Test constants
const TEST_GAS: u128 = 200000;
const TEST_VALUE: u128 = 1000000;
const TEST_AMOUNT: u128 = 500000;
const TEST_RECEIVER_ADDRESS: vector<u8> = x"f39fd6e51aad88f6f4ce6ab8827279cfffb92266000000000000000000000000";
const TEST_COMPOSE_INDEX: u16 = 1;
const TEST_CALLDATA_SIZE: u32 = 256;

// Protocol constants
const TYPE_3: u16 = 3;
const EXECUTOR_WORKER_ID: u8 = 1;
const DVN_WORKER_ID: u8 = 2;
const EXECUTOR_OPTION_TYPE_LZRECEIVE: u8 = 1;
const EXECUTOR_OPTION_TYPE_NATIVE_DROP: u8 = 2;
const EXECUTOR_OPTION_TYPE_LZCOMPOSE: u8 = 3;
const EXECUTOR_OPTION_TYPE_ORDERED_EXECUTION: u8 = 4;
const EXECUTOR_OPTION_TYPE_LZREAD: u8 = 5;
const DVN_OPTION_TYPE_PRECRIME: u8 = 1;

// =========================================================================
// === PROTOCOL FORMAT VALIDATION TESTS ===
// =========================================================================

#[test]
fun test_type3_header_format() {
    let builder = options_builder::new_builder();
    let options = builder.build();

    // Type 3 options should start with 2-byte type header
    assert!(options.length() == 2, 0);
    assert!(options[0] == 0u8, 1); // Type 3 = 0x0003 in big-endian
    assert!(options[1] == 3u8, 2);
}

#[test]
fun test_lz_receive_option_format_with_value() {
    let mut builder = options_builder::new_builder();
    builder.add_executor_lz_receive_option(TEST_GAS, TEST_VALUE);
    let options = builder.build();

    // Expected format: [type:2] + [worker_id:1][size:2][option_type:1][gas:16][value:16]
    // Total: 2 + 1 + 2 + 1 + 16 + 16 = 38 bytes
    assert!(options.length() == 38, 0);

    let mut reader = buffer_reader::create(options);

    // Check type header
    let option_type = reader.read_u16();
    assert!(option_type == TYPE_3, 1);

    // Check executor option structure
    let worker_id = reader.read_u8();
    assert!(worker_id == EXECUTOR_WORKER_ID, 2);

    let size = reader.read_u16();
    assert!(size == 33, 3); // option_type(1) + gas(16) + value(16) = 33

    let executor_option_type = reader.read_u8();
    assert!(executor_option_type == EXECUTOR_OPTION_TYPE_LZRECEIVE, 4);

    let gas = reader.read_u128();
    assert!(gas == TEST_GAS, 5);

    let value = reader.read_u128();
    assert!(value == TEST_VALUE, 6);
}

#[test]
fun test_lz_receive_option_format_without_value() {
    let mut builder = options_builder::new_builder();
    builder.add_executor_lz_receive_option(TEST_GAS, 0);
    let options = builder.build();

    // Expected format: [type:2] + [worker_id:1][size:2][option_type:1][gas:16]
    // Total: 2 + 1 + 2 + 1 + 16 = 22 bytes (no value when 0)
    assert!(options.length() == 22, 0);

    let mut reader = buffer_reader::create(options);
    reader.skip(2); // Skip type header

    let _worker_id = reader.read_u8();
    let size = reader.read_u16();
    assert!(size == 17, 1); // option_type(1) + gas(16) = 17

    let _executor_option_type = reader.read_u8();
    let gas = reader.read_u128();
    assert!(gas == TEST_GAS, 2);

    // Should be at end of options
    assert!(reader.remaining_length() == 0, 3);
}

#[test]
fun test_native_drop_option_format() {
    let receiver = bytes32::from_bytes(TEST_RECEIVER_ADDRESS);
    let mut builder = options_builder::new_builder();
    builder.add_executor_native_drop_option(TEST_AMOUNT, receiver);
    let options = builder.build();

    // Expected format: [type:2] + [worker_id:1][size:2][option_type:1][amount:16][receiver:32]
    // Total: 2 + 1 + 2 + 1 + 16 + 32 = 54 bytes
    assert!(options.length() == 54, 0);

    let mut reader = buffer_reader::create(options);
    reader.skip(2); // Skip type header

    let worker_id = reader.read_u8();
    assert!(worker_id == EXECUTOR_WORKER_ID, 1);

    let size = reader.read_u16();
    assert!(size == 49, 2); // option_type(1) + amount(16) + receiver(32) = 49

    let executor_option_type = reader.read_u8();
    assert!(executor_option_type == EXECUTOR_OPTION_TYPE_NATIVE_DROP, 3);

    let amount = reader.read_u128();
    assert!(amount == TEST_AMOUNT, 4);

    let receiver_bytes = reader.read_bytes32();
    assert!(receiver_bytes == receiver, 5);
}

#[test]
fun test_lz_compose_option_format_with_value() {
    let mut builder = options_builder::new_builder();
    builder.add_executor_lz_compose_option(TEST_COMPOSE_INDEX, TEST_GAS, TEST_VALUE);
    let options = builder.build();

    // Expected format: [type:2] + [worker_id:1][size:2][option_type:1][index:2][gas:16][value:16]
    // Total: 2 + 1 + 2 + 1 + 2 + 16 + 16 = 40 bytes
    assert!(options.length() == 40, 0);

    let mut reader = buffer_reader::create(options);
    reader.skip(2); // Skip type header

    let worker_id = reader.read_u8();
    assert!(worker_id == EXECUTOR_WORKER_ID, 1);

    let size = reader.read_u16();
    assert!(size == 35, 2); // option_type(1) + index(2) + gas(16) + value(16) = 35

    let executor_option_type = reader.read_u8();
    assert!(executor_option_type == EXECUTOR_OPTION_TYPE_LZCOMPOSE, 3);

    let index = reader.read_u16();
    assert!(index == TEST_COMPOSE_INDEX, 4);

    let gas = reader.read_u128();
    assert!(gas == TEST_GAS, 5);

    let value = reader.read_u128();
    assert!(value == TEST_VALUE, 6);
}

#[test]
fun test_lz_compose_option_format_without_value() {
    let mut builder = options_builder::new_builder();
    builder.add_executor_lz_compose_option(TEST_COMPOSE_INDEX, TEST_GAS, 0);
    let options = builder.build();

    // Expected format: [type:2] + [worker_id:1][size:2][option_type:1][index:2][gas:16]
    // Total: 2 + 1 + 2 + 1 + 2 + 16 = 24 bytes (no value when 0)
    assert!(options.length() == 24, 0);

    let mut reader = buffer_reader::create(options);
    reader.skip(2); // Skip type header

    let _worker_id = reader.read_u8();
    let size = reader.read_u16();
    assert!(size == 19, 1); // option_type(1) + index(2) + gas(16) = 19

    let _executor_option_type = reader.read_u8();
    let index = reader.read_u16();
    assert!(index == TEST_COMPOSE_INDEX, 2);

    let gas = reader.read_u128();
    assert!(gas == TEST_GAS, 3);

    assert!(reader.remaining_length() == 0, 4);
}

#[test]
fun test_ordered_execution_option_format() {
    let mut builder = options_builder::new_builder();
    builder.add_executor_ordered_execution_option();
    let options = builder.build();

    // Expected format: [type:2] + [worker_id:1][size:2][option_type:1]
    // Total: 2 + 1 + 2 + 1 = 6 bytes (no option data)
    assert!(options.length() == 6, 0);

    let mut reader = buffer_reader::create(options);
    reader.skip(2); // Skip type header

    let worker_id = reader.read_u8();
    assert!(worker_id == EXECUTOR_WORKER_ID, 1);

    let size = reader.read_u16();
    assert!(size == 1, 2); // only option_type(1)

    let executor_option_type = reader.read_u8();
    assert!(executor_option_type == EXECUTOR_OPTION_TYPE_ORDERED_EXECUTION, 3);

    assert!(reader.remaining_length() == 0, 4);
}

#[test]
fun test_lz_read_option_format() {
    let mut builder = options_builder::new_builder();
    builder.add_executor_lz_read_option(TEST_GAS, TEST_CALLDATA_SIZE, TEST_VALUE);
    let options = builder.build();

    // Expected format: [type:2] + [worker_id:1][size:2][option_type:1][gas:16][calldata_size:4][value:16]
    // Total: 2 + 1 + 2 + 1 + 16 + 4 + 16 = 42 bytes
    assert!(options.length() == 42, 0);

    let mut reader = buffer_reader::create(options);
    reader.skip(2); // Skip type header

    let worker_id = reader.read_u8();
    assert!(worker_id == EXECUTOR_WORKER_ID, 1);

    let size = reader.read_u16();
    assert!(size == 37, 2); // option_type(1) + gas(16) + calldata_size(4) + value(16) = 37

    let executor_option_type = reader.read_u8();
    assert!(executor_option_type == EXECUTOR_OPTION_TYPE_LZREAD, 3);

    let gas = reader.read_u128();
    assert!(gas == TEST_GAS, 4);

    let calldata_size = reader.read_u32();
    assert!(calldata_size == TEST_CALLDATA_SIZE, 5);

    let value = reader.read_u128();
    assert!(value == TEST_VALUE, 6);
}

#[test]
fun test_dvn_pre_crime_option_format() {
    let dvn_idx = 5u8;
    let mut builder = options_builder::new_builder();
    builder.add_dvn_pre_crime_option(dvn_idx);
    let options = builder.build();

    // Expected format: [type:2] + [worker_id:1][size:2][dvn_idx:1][option_type:1]
    // Total: 2 + 1 + 2 + 1 + 1 = 7 bytes
    assert!(options.length() == 7, 0);

    let mut reader = buffer_reader::create(options);
    reader.skip(2); // Skip type header

    let worker_id = reader.read_u8();
    assert!(worker_id == DVN_WORKER_ID, 1);

    let size = reader.read_u16();
    assert!(size == 2, 2); // dvn_idx(1) + option_type(1) = 2

    let dvn_index = reader.read_u8();
    assert!(dvn_index == dvn_idx, 3);

    let dvn_option_type = reader.read_u8();
    assert!(dvn_option_type == DVN_OPTION_TYPE_PRECRIME, 4);
}

// =========================================================================
// === MULTIPLE OPTIONS FORMAT TESTS ===
// =========================================================================

#[test]
fun test_multiple_options_concatenation_format() {
    let receiver = bytes32::from_bytes(TEST_RECEIVER_ADDRESS);
    let mut builder = options_builder::new_builder();
    builder
        .add_executor_lz_receive_option(TEST_GAS, TEST_VALUE)
        .add_executor_native_drop_option(TEST_AMOUNT, receiver)
        .add_executor_ordered_execution_option();
    let options = builder.build();

    // Expected: [type:2] + [lz_receive:36] + [native_drop:52] + [ordered:4]
    // Total: 2 + 36 + 52 + 4 = 94 bytes
    assert!(options.length() == 94, 0);

    let mut reader = buffer_reader::create(options);

    // Verify type header
    let option_type = reader.read_u16();
    assert!(option_type == TYPE_3, 1);

    // Verify first option (LZ receive)
    let worker_id1 = reader.read_u8();
    assert!(worker_id1 == EXECUTOR_WORKER_ID, 2);
    let size1 = reader.read_u16();
    assert!(size1 == 33, 3);
    reader.skip(33); // Skip lz_receive option content

    // Verify second option (native drop)
    let worker_id2 = reader.read_u8();
    assert!(worker_id2 == EXECUTOR_WORKER_ID, 4);
    let size2 = reader.read_u16();
    assert!(size2 == 49, 5);
    reader.skip(49); // Skip native_drop option content

    // Verify third option (ordered execution)
    let worker_id3 = reader.read_u8();
    assert!(worker_id3 == EXECUTOR_WORKER_ID, 6);
    let size3 = reader.read_u16();
    assert!(size3 == 1, 7);
    reader.skip(1); // Skip ordered option content

    // Should be at end
    assert!(reader.remaining_length() == 0, 8);
}

#[test]
fun test_multiple_same_type_options_format() {
    let mut builder = options_builder::new_builder();
    builder.add_executor_lz_receive_option(TEST_GAS, TEST_VALUE).add_executor_lz_receive_option(TEST_GAS * 2, 0); // Different gas, no value
    let options = builder.build();

    // Expected: [type:2] + [lz_receive_with_value:36] + [lz_receive_without_value:20]
    // Total: 2 + 36 + 20 = 58 bytes
    assert!(options.length() == 58, 0);

    let mut reader = buffer_reader::create(options);
    reader.skip(2); // Skip type header

    // First LZ receive (with value)
    reader.skip(1); // worker_id
    let size1 = reader.read_u16();
    assert!(size1 == 33, 1); // Has value
    reader.skip(33);

    // Second LZ receive (without value)
    reader.skip(1); // worker_id
    let size2 = reader.read_u16();
    assert!(size2 == 17, 2); // No value
    reader.skip(17);

    assert!(reader.remaining_length() == 0, 3);
}

// =========================================================================
// === LEGACY OPTIONS FORMAT TESTS ===
// =========================================================================

#[test]
fun test_legacy_type1_format() {
    let execution_gas = 200000u256;
    let legacy_options = options_builder::encode_legacy_options_type1(execution_gas);

    // Expected format: [type:2][gas:32] = 34 bytes
    assert!(legacy_options.length() == 34, 0);

    let mut reader = buffer_reader::create(legacy_options);
    let option_type = reader.read_u16();
    assert!(option_type == 1, 1);

    let gas = reader.read_u256();
    assert!(gas == execution_gas, 2);

    assert!(reader.remaining_length() == 0, 3);
}

#[test]
fun test_legacy_type2_format() {
    let execution_gas = 200000u256;
    let native_for_dst = 10000000u256;
    let receiver_bytes = x"f39fd6e51aad88f6f4ce6ab8827279cfffb92266";

    let legacy_options = options_builder::encode_legacy_options_type2(
        execution_gas,
        native_for_dst,
        receiver_bytes,
    );

    // Expected format: [type:2][gas:32][native:32][receiver:20] = 86 bytes
    assert!(legacy_options.length() == 86, 0);

    let mut reader = buffer_reader::create(legacy_options);
    let option_type = reader.read_u16();
    assert!(option_type == 2, 1);

    let gas = reader.read_u256();
    assert!(gas == execution_gas, 2);

    let native_amount = reader.read_u256();
    assert!(native_amount == native_for_dst, 3);

    let receiver = reader.read_fixed_len_bytes(20);
    assert!(receiver == receiver_bytes, 4);

    assert!(reader.remaining_length() == 0, 5);
}

// =========================================================================
// === PROTOCOL COMPLIANCE TESTS ===
// =========================================================================

#[test]
fun test_worker_option_format_compliance() {
    // Test that worker options follow the format: [worker_id][size][option_data]
    let mut builder = options_builder::new_builder();
    builder.add_executor_lz_receive_option(TEST_GAS, 0);
    let options = builder.build();

    let mut reader = buffer_reader::create(options);
    reader.skip(2); // Skip type header

    // Worker option structure validation
    let worker_id = reader.read_u8();
    assert!(worker_id == EXECUTOR_WORKER_ID, 0);

    let size = reader.read_u16();
    let remaining_before = reader.remaining_length();

    // Size should exactly match remaining option data
    assert!((size as u64) == remaining_before, 1);

    // Option type should be first byte of option data
    let option_type = reader.read_u8();
    assert!(option_type == EXECUTOR_OPTION_TYPE_LZRECEIVE, 2);
}

#[test]
fun test_size_field_accuracy() {
    // Test that size fields accurately represent option data length
    let receiver = bytes32::from_bytes(TEST_RECEIVER_ADDRESS);
    let mut builder = options_builder::new_builder();
    builder.add_executor_native_drop_option(TEST_AMOUNT, receiver);
    let options = builder.build();

    let mut reader = buffer_reader::create(options);
    reader.skip(2); // Skip type header
    reader.skip(1); // Skip worker_id

    let size = reader.read_u16();
    let data_start_pos = reader.position();

    // Read all option data
    reader.skip(size as u64);
    let data_end_pos = reader.position();

    // Verify size field is accurate
    assert!((data_end_pos - data_start_pos) == (size as u64), 0);
    assert!(reader.remaining_length() == 0, 1);
}

// =========================================================================
// === ERROR CONDITION TESTS ===
// =========================================================================

#[test, expected_failure(abort_code = options_builder::EInvalidSize)]
fun test_legacy_type1_gas_overflow() {
    // Test with gas value that exceeds u128::max_value
    let invalid_gas = 340282366920938463463374607431768211456u256; // u128::max + 1
    options_builder::encode_legacy_options_type1(invalid_gas);
}

#[test, expected_failure(abort_code = options_builder::EInvalidSize)]
fun test_legacy_type2_gas_overflow() {
    let invalid_gas = 340282366920938463463374607431768211456u256; // u128::max + 1
    let valid_native = 1000000u256;
    let receiver = x"f39fd6e51aad88f6f4ce6ab8827279cfffb92266";

    options_builder::encode_legacy_options_type2(invalid_gas, valid_native, receiver);
}

#[test, expected_failure(abort_code = options_builder::EInvalidSize)]
fun test_legacy_type2_native_overflow() {
    let valid_gas = 200000u256;
    let invalid_native = 340282366920938463463374607431768211456u256; // u128::max + 1
    let receiver = x"f39fd6e51aad88f6f4ce6ab8827279cfffb92266";

    options_builder::encode_legacy_options_type2(valid_gas, invalid_native, receiver);
}

#[test, expected_failure(abort_code = options_builder::EInvalidSize)]
fun test_legacy_type2_receiver_too_long() {
    let valid_gas = 200000u256;
    let valid_native = 1000000u256;
    // 33 bytes - too long for receiver (should be max 32)
    let invalid_receiver = x"f39fd6e51aad88f6f4ce6ab8827279cfffb92266000000000000000000000000ff";

    options_builder::encode_legacy_options_type2(valid_gas, valid_native, invalid_receiver);
}

// =========================================================================
// === EDGE CASE TESTS ===
// =========================================================================

#[test]
fun test_zero_values_format() {
    // Test options with zero values are handled correctly
    let mut builder = options_builder::new_builder();
    builder.add_executor_lz_receive_option(1, 0); // Minimum gas, zero value
    let options = builder.build();

    // Should produce compact format without value field
    assert!(options.length() == 22, 0); // 2 + 1 + 2 + 1 + 16 = 22

    let mut reader = buffer_reader::create(options);
    reader.skip(6); // Skip type + worker_id + size + option_type

    let gas = reader.read_u128();
    assert!(gas == 1, 1);

    // Should be at end (no value field)
    assert!(reader.remaining_length() == 0, 2);
}

#[test]
fun test_maximum_values_format() {
    // Test with maximum u128 values
    let max_gas = 340282366920938463463374607431768211455u128; // u128::max
    let max_value = 340282366920938463463374607431768211455u128;

    let mut builder = options_builder::new_builder();
    builder.add_executor_lz_receive_option(max_gas, max_value);
    let options = builder.build();

    let mut reader = buffer_reader::create(options);
    reader.skip(6); // Skip headers

    let gas = reader.read_u128();
    assert!(gas == max_gas, 0);

    let value = reader.read_u128();
    assert!(value == max_value, 1);
}

#[test]
fun test_empty_receiver_bytes() {
    // Test legacy type 2 with empty receiver
    let execution_gas = 200000u256;
    let native_for_dst = 1000000u256;
    let empty_receiver = vector::empty<u8>();

    let legacy_options = options_builder::encode_legacy_options_type2(
        execution_gas,
        native_for_dst,
        empty_receiver,
    );

    // Should still have 32-byte slot for receiver, just zero-filled
    assert!(legacy_options.length() == 66, 0); // 2 + 32 + 32 + 0 = 66
}

#[test]
fun test_option_chaining_order() {
    // Test that option chaining preserves order
    let receiver = bytes32::from_bytes(TEST_RECEIVER_ADDRESS);
    let mut builder = options_builder::new_builder();
    builder
        .add_executor_lz_receive_option(100, 0)
        .add_executor_native_drop_option(200, receiver)
        .add_executor_lz_compose_option(1, 300, 0)
        .add_executor_ordered_execution_option();
    let options = builder.build();

    let mut reader = buffer_reader::create(options);
    reader.skip(2); // Skip type

    // Verify order by checking option types in sequence

    // First: LZ receive
    reader.skip(3); // worker_id + size
    let opt1 = reader.read_u8();
    assert!(opt1 == EXECUTOR_OPTION_TYPE_LZRECEIVE, 0);
    reader.skip(16); // gas

    // Second: Native drop
    reader.skip(3); // worker_id + size
    let opt2 = reader.read_u8();
    assert!(opt2 == EXECUTOR_OPTION_TYPE_NATIVE_DROP, 1);
    reader.skip(48); // amount + receiver

    // Third: LZ compose
    reader.skip(3); // worker_id + size
    let opt3 = reader.read_u8();
    assert!(opt3 == EXECUTOR_OPTION_TYPE_LZCOMPOSE, 2);
    reader.skip(18); // index + gas

    // Fourth: Ordered execution
    reader.skip(3); // worker_id + size
    let opt4 = reader.read_u8();
    assert!(opt4 == EXECUTOR_OPTION_TYPE_ORDERED_EXECUTION, 3);
}
