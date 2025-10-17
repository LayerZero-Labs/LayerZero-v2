#[test_only]
module counter::options_builder_basic_tests;

use counter::options_builder;
use utils::{buffer_reader, bytes32};

// Constants for testing
const TEST_GAS: u128 = 200000;
const TEST_VALUE: u128 = 1000000;
const TEST_AMOUNT: u128 = 500000;
const TEST_RECEIVER_ADDRESS: vector<u8> = x"f39fd6e51aad88f6f4ce6ab8827279cfffb92266000000000000000000000000";
const TEST_COMPOSE_INDEX: u16 = 1;
const TEST_CALLDATA_SIZE: u32 = 256;

// Expected constants
const TYPE_3: u16 = 3;
const EXECUTOR_WORKER_ID: u8 = 1;
const DVN_WORKER_ID: u8 = 2;
const EXECUTOR_OPTION_TYPE_LZRECEIVE: u8 = 1;
const EXECUTOR_OPTION_TYPE_NATIVE_DROP: u8 = 2;
const EXECUTOR_OPTION_TYPE_LZCOMPOSE: u8 = 3;
const EXECUTOR_OPTION_TYPE_ORDERED_EXECUTION: u8 = 4;
const DVN_OPTION_TYPE_PRECRIME: u8 = 1;

// =========================================================================
// === BUILDER PATTERN TESTS ===
// =========================================================================

#[test]
fun test_new_type3_builder() {
    let builder = options_builder::new_builder();
    let options = builder.build();

    // Should contain just the type header (2 bytes)
    assert!(options.length() == 2, 0);

    let mut reader = buffer_reader::create(options);
    let option_type = reader.read_u16();
    assert!(option_type == TYPE_3, 1);
}

#[test]
fun test_builder_with_explicit_type() {
    let builder = options_builder::new_builder();
    let options = builder.build();

    assert!(options.length() == 2, 0);

    let mut reader = buffer_reader::create(options);
    let option_type = reader.read_u16();
    assert!(option_type == TYPE_3, 1);
}

#[test]
fun test_type_constants() {
    assert!(options_builder::type_1() == 1, 0);
    assert!(options_builder::type_2() == 2, 1);
    assert!(options_builder::type_3() == 3, 2);
}

// =========================================================================
// === EXECUTOR OPTION ENCODING TESTS ===
// =========================================================================

#[test]
fun test_lz_receive_option_encoding() {
    let mut builder = options_builder::new_builder();
    builder.add_executor_lz_receive_option(TEST_GAS, TEST_VALUE);
    let options = builder.build();

    // Should contain: [type:2] + [worker_id:1][size:2][option_type:1][gas:16][value:16]
    // Total: 2 + 1 + 2 + 1 + 16 + 16 = 38 bytes
    assert!(options.length() == 38, 0);

    let mut reader = buffer_reader::create(options);
    let option_type = reader.read_u16();
    assert!(option_type == TYPE_3, 1);

    let worker_id = reader.read_u8();
    assert!(worker_id == EXECUTOR_WORKER_ID, 2);

    let size = reader.read_u16();
    assert!(size == 33, 3); // option_type (1) + gas (16) + value (16) = 33

    let executor_option_type = reader.read_u8();
    assert!(executor_option_type == EXECUTOR_OPTION_TYPE_LZRECEIVE, 4);

    let gas = reader.read_u128();
    assert!(gas == TEST_GAS, 5);

    let value = reader.read_u128();
    assert!(value == TEST_VALUE, 6);
}

#[test]
fun test_lz_receive_option_zero_value() {
    let mut builder = options_builder::new_builder();
    builder.add_executor_lz_receive_option(TEST_GAS, 0);
    let options = builder.build();

    // Should contain: [type:2] + [worker_id:1][size:2][option_type:1][gas:16]
    // Total: 2 + 1 + 2 + 1 + 16 = 22 bytes (no value field when 0)
    assert!(options.length() == 22, 0);

    let mut reader = buffer_reader::create(options);
    let _option_type = reader.read_u16();
    let _worker_id = reader.read_u8();
    let size = reader.read_u16();
    assert!(size == 17, 1); // option_type (1) + gas (16) = 17

    let _executor_option_type = reader.read_u8();
    let gas = reader.read_u128();
    assert!(gas == TEST_GAS, 2);
}

#[test]
fun test_native_drop_option_encoding() {
    let receiver = bytes32::from_bytes(TEST_RECEIVER_ADDRESS);
    let mut builder = options_builder::new_builder();
    builder.add_executor_native_drop_option(TEST_AMOUNT, receiver);
    let options = builder.build();

    // Should contain: [type:2] + [worker_id:1][size:2][option_type:1][amount:16][receiver:32]
    // Total: 2 + 1 + 2 + 1 + 16 + 32 = 54 bytes
    assert!(options.length() == 54, 0);

    let mut reader = buffer_reader::create(options);
    let _option_type = reader.read_u16();
    let worker_id = reader.read_u8();
    assert!(worker_id == EXECUTOR_WORKER_ID, 1);

    let size = reader.read_u16();
    assert!(size == 49, 2); // option_type (1) + amount (16) + receiver (32) = 49

    let executor_option_type = reader.read_u8();
    assert!(executor_option_type == EXECUTOR_OPTION_TYPE_NATIVE_DROP, 3);

    let amount = reader.read_u128();
    assert!(amount == TEST_AMOUNT, 4);

    let receiver_bytes = reader.read_bytes32();
    assert!(receiver_bytes == receiver, 5);
}

#[test]
fun test_lz_compose_option_encoding() {
    let mut builder = options_builder::new_builder();
    builder.add_executor_lz_compose_option(TEST_COMPOSE_INDEX, TEST_GAS, TEST_VALUE);
    let options = builder.build();

    // Should contain: [type:2] + [worker_id:1][size:2][option_type:1][index:2][gas:16][value:16]
    // Total: 2 + 1 + 2 + 1 + 2 + 16 + 16 = 40 bytes
    assert!(options.length() == 40, 0);

    let mut reader = buffer_reader::create(options);
    let _option_type = reader.read_u16();
    let worker_id = reader.read_u8();
    assert!(worker_id == EXECUTOR_WORKER_ID, 1);

    let size = reader.read_u16();
    assert!(size == 35, 2); // option_type (1) + index (2) + gas (16) + value (16) = 35

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
fun test_lz_compose_option_zero_value() {
    let mut builder = options_builder::new_builder();
    builder.add_executor_lz_compose_option(TEST_COMPOSE_INDEX, TEST_GAS, 0);
    let options = builder.build();

    // Should contain: [type:2] + [worker_id:1][size:2][option_type:1][index:2][gas:16]
    // Total: 2 + 1 + 2 + 1 + 2 + 16 = 24 bytes (no value field when 0)
    assert!(options.length() == 24, 0);

    let mut reader = buffer_reader::create(options);
    let _option_type = reader.read_u16();
    let _worker_id = reader.read_u8();
    let size = reader.read_u16();
    assert!(size == 19, 1); // option_type (1) + index (2) + gas (16) = 19

    let _executor_option_type = reader.read_u8();
    let index = reader.read_u16();
    assert!(index == TEST_COMPOSE_INDEX, 2);

    let gas = reader.read_u128();
    assert!(gas == TEST_GAS, 3);
}

#[test]
fun test_ordered_execution_option_encoding() {
    let mut builder = options_builder::new_builder();
    builder.add_executor_ordered_execution_option();
    let options = builder.build();

    // Should contain: [type:2] + [worker_id:1][size:2][option_type:1]
    // Total: 2 + 1 + 2 + 1 = 6 bytes (no option data)
    assert!(options.length() == 6, 0);

    let mut reader = buffer_reader::create(options);
    let _option_type = reader.read_u16();
    let worker_id = reader.read_u8();
    assert!(worker_id == EXECUTOR_WORKER_ID, 1);

    let size = reader.read_u16();
    assert!(size == 1, 2); // only option_type (1)

    let executor_option_type = reader.read_u8();
    assert!(executor_option_type == EXECUTOR_OPTION_TYPE_ORDERED_EXECUTION, 3);
}

#[test]
fun test_lz_read_option_encoding() {
    let mut builder = options_builder::new_builder();
    builder.add_executor_lz_read_option(TEST_GAS, TEST_CALLDATA_SIZE, TEST_VALUE);
    let options = builder.build();

    // Should contain: [type:2] + [worker_id:1][size:2][option_type:1][gas:16][calldata_size:4][value:16]
    // Total: 2 + 1 + 2 + 1 + 16 + 4 + 16 = 42 bytes
    assert!(options.length() == 42, 0);

    let mut reader = buffer_reader::create(options);
    let _option_type = reader.read_u16();
    let worker_id = reader.read_u8();
    assert!(worker_id == EXECUTOR_WORKER_ID, 1);

    let size = reader.read_u16();
    assert!(size == 37, 2); // option_type (1) + gas (16) + calldata_size (4) + value (16) = 37

    let executor_option_type = reader.read_u8();
    assert!(executor_option_type == 5, 3); // EXECUTOR_OPTION_TYPE_LZREAD

    let gas = reader.read_u128();
    assert!(gas == TEST_GAS, 4);

    let calldata_size = reader.read_u32();
    assert!(calldata_size == TEST_CALLDATA_SIZE, 5);

    let value = reader.read_u128();
    assert!(value == TEST_VALUE, 6);
}

// =========================================================================
// === DVN OPTION ENCODING TESTS ===
// =========================================================================

#[test]
fun test_dvn_pre_crime_option_encoding() {
    let dvn_idx = 0u8;
    let mut builder = options_builder::new_builder();
    builder.add_dvn_pre_crime_option(dvn_idx);
    let options = builder.build();

    // Should contain: [type:2] + [worker_id:1][size:2][dvn_idx:1][option_type:1]
    // Total: 2 + 1 + 2 + 1 + 1 = 7 bytes (no option data)
    assert!(options.length() == 7, 0);

    let mut reader = buffer_reader::create(options);
    let _option_type = reader.read_u16();
    let worker_id = reader.read_u8();
    assert!(worker_id == DVN_WORKER_ID, 1);

    let size = reader.read_u16();
    assert!(size == 2, 2); // dvn_idx (1) + option_type (1) = 2

    let dvn_index = reader.read_u8();
    assert!(dvn_index == dvn_idx, 3);

    let dvn_option_type = reader.read_u8();
    assert!(dvn_option_type == DVN_OPTION_TYPE_PRECRIME, 4);
}

// =========================================================================
// === MULTIPLE OPTIONS TESTS ===
// =========================================================================

#[test]
fun test_multiple_options_chaining() {
    let receiver = bytes32::from_bytes(TEST_RECEIVER_ADDRESS);
    let mut builder = options_builder::new_builder();
    builder
        .add_executor_lz_receive_option(TEST_GAS, TEST_VALUE)
        .add_executor_native_drop_option(TEST_AMOUNT, receiver)
        .add_executor_ordered_execution_option();
    let options = builder.build();

    // Should contain multiple concatenated options
    // [type:2] + [lz_receive option] + [native_drop option] + [ordered_execution option]
    // Expected: [type:2] + [lz_receive:36] + [native_drop:52] + [ordered:4]
    let expected_length = 2 + 36 + 52 + 4;
    assert!(options.length() == expected_length, 0);

    // Verify the type header
    let mut reader = buffer_reader::create(options);
    let option_type = reader.read_u16();
    assert!(option_type == TYPE_3, 1);
}

// =========================================================================
// === LEGACY OPTIONS TESTS ===
// =========================================================================

#[test]
fun test_legacy_options_type1() {
    let execution_gas = 200000u256;
    let legacy_options = options_builder::encode_legacy_options_type1(execution_gas);

    // Should contain [type:2][gas:32] = 34 bytes
    assert!(legacy_options.length() == 34, 0);

    let mut reader = buffer_reader::create(legacy_options);
    let option_type = reader.read_u16();
    assert!(option_type == 1, 1);

    let gas = reader.read_u256();
    assert!(gas == execution_gas, 2);
}

#[test]
fun test_legacy_options_type2() {
    let execution_gas = 200000u256;
    let native_for_dst = 10000000u256;
    let receiver_bytes = x"f39fd6e51aad88f6f4ce6ab8827279cfffb92266";

    let legacy_options = options_builder::encode_legacy_options_type2(
        execution_gas,
        native_for_dst,
        receiver_bytes,
    );

    // Should contain [type:2][gas:32][native:32][receiver:20] = 86 bytes
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
}

// =========================================================================
// === INDIVIDUAL ENCODING FUNCTION TESTS ===
// =========================================================================

#[test]
fun test_encode_lz_receive_option() {
    let encoded = options_builder::encode_lz_receive_option(TEST_GAS, TEST_VALUE);

    // Should contain [gas:16][value:16] = 32 bytes
    assert!(encoded.length() == 32, 0);

    let mut reader = buffer_reader::create(encoded);
    let gas = reader.read_u128();
    assert!(gas == TEST_GAS, 1);

    let value = reader.read_u128();
    assert!(value == TEST_VALUE, 2);
}

#[test]
fun test_encode_lz_receive_option_zero_value() {
    let encoded = options_builder::encode_lz_receive_option(TEST_GAS, 0);

    // Should contain only [gas:16] = 16 bytes (no value when 0)
    assert!(encoded.length() == 16, 0);

    let mut reader = buffer_reader::create(encoded);
    let gas = reader.read_u128();
    assert!(gas == TEST_GAS, 1);
}

#[test]
fun test_encode_native_drop_option() {
    let receiver = bytes32::from_bytes(TEST_RECEIVER_ADDRESS);
    let encoded = options_builder::encode_native_drop_option(TEST_AMOUNT, receiver);

    // Should contain [amount:16][receiver:32] = 48 bytes
    assert!(encoded.length() == 48, 0);

    let mut reader = buffer_reader::create(encoded);
    let amount = reader.read_u128();
    assert!(amount == TEST_AMOUNT, 1);

    let receiver_bytes = reader.read_bytes32();
    assert!(receiver_bytes == receiver, 2);
}

#[test]
fun test_encode_lz_compose_option() {
    let encoded = options_builder::encode_lz_compose_option(TEST_COMPOSE_INDEX, TEST_GAS, TEST_VALUE);

    // Should contain [index:2][gas:16][value:16] = 34 bytes
    assert!(encoded.length() == 34, 0);

    let mut reader = buffer_reader::create(encoded);
    let index = reader.read_u16();
    assert!(index == TEST_COMPOSE_INDEX, 1);

    let gas = reader.read_u128();
    assert!(gas == TEST_GAS, 2);

    let value = reader.read_u128();
    assert!(value == TEST_VALUE, 3);
}

#[test]
fun test_encode_lz_compose_option_zero_value() {
    let encoded = options_builder::encode_lz_compose_option(TEST_COMPOSE_INDEX, TEST_GAS, 0);

    // Should contain [index:2][gas:16] = 18 bytes (no value when 0)
    assert!(encoded.length() == 18, 0);

    let mut reader = buffer_reader::create(encoded);
    let index = reader.read_u16();
    assert!(index == TEST_COMPOSE_INDEX, 1);

    let gas = reader.read_u128();
    assert!(gas == TEST_GAS, 2);
}

#[test]
fun test_encode_lz_read_option() {
    let encoded = options_builder::encode_lz_read_option(TEST_GAS, TEST_CALLDATA_SIZE, TEST_VALUE);

    // Should contain [gas:16][calldata_size:4][value:16] = 36 bytes
    assert!(encoded.length() == 36, 0);

    let mut reader = buffer_reader::create(encoded);
    let gas = reader.read_u128();
    assert!(gas == TEST_GAS, 1);

    let calldata_size = reader.read_u32();
    assert!(calldata_size == TEST_CALLDATA_SIZE, 2);

    let value = reader.read_u128();
    assert!(value == TEST_VALUE, 3);
}

#[test]
fun test_encode_lz_read_option_zero_value() {
    let encoded = options_builder::encode_lz_read_option(TEST_GAS, TEST_CALLDATA_SIZE, 0);

    // Should contain [gas:16][calldata_size:4] = 20 bytes (no value when 0)
    assert!(encoded.length() == 20, 0);

    let mut reader = buffer_reader::create(encoded);
    let gas = reader.read_u128();
    assert!(gas == TEST_GAS, 1);

    let calldata_size = reader.read_u32();
    assert!(calldata_size == TEST_CALLDATA_SIZE, 2);
}
