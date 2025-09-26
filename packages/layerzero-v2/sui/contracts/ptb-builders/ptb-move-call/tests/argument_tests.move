#[test_only]
module ptb_move_call::argument_tests;

use ptb_move_call::argument::{
    create_id,
    create_object,
    create_pure,
    create_nested_result,
    id,
    object,
    pure,
    nested_result,
    is_id,
    is_object,
    is_pure,
    is_nested_result
};
use utils::bytes32;
use std::bcs;

// === Test Constants ===

const TEST_ADDRESS: address = @0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
const TEST_CALL_INDEX: u16 = 42;
const TEST_RESULT_INDEX: u16 = 7;

// === Creation Tests ===

#[test]
fun test_create_and_type_checking_functions() {
    // Test create_id
    let test_bytes32 = bytes32::from_bytes(b"test_id_bytes32_value_here_12345");
    let id_arg = create_id(test_bytes32);
    assert!(is_id(&id_arg) && !is_object(&id_arg) && !is_pure(&id_arg) && !is_nested_result(&id_arg), 0);
    
    // Test create_object
    let obj_arg = create_object(TEST_ADDRESS);
    assert!(!is_id(&obj_arg) && is_object(&obj_arg) && !is_pure(&obj_arg) && !is_nested_result(&obj_arg), 1);
    
    // Test create_pure
    let pure_arg = create_pure(b"test pure data");
    assert!(!is_id(&pure_arg) && !is_object(&pure_arg) && is_pure(&pure_arg) && !is_nested_result(&pure_arg), 2);
    
    // Test create_nested_result
    let nested_arg = create_nested_result(TEST_CALL_INDEX, TEST_RESULT_INDEX);
    assert!(!is_id(&nested_arg) && !is_object(&nested_arg) && !is_pure(&nested_arg) && is_nested_result(&nested_arg), 3);
}

// === Extraction Tests ===

#[test]
fun test_extract_functions() {
    // Test id extraction
    let test_bytes32 = bytes32::from_bytes(b"test_id_bytes32_value_here_12345");
    let id_arg = create_id(test_bytes32);
    assert!(id(&id_arg) == test_bytes32, 0);
    
    // Test object extraction
    let obj_arg = create_object(TEST_ADDRESS);
    assert!(object(&obj_arg) == TEST_ADDRESS, 1);
    
    // Test pure extraction
    let test_data = b"test pure data";
    let pure_arg = create_pure(test_data);
    assert!(*pure(&pure_arg) == test_data, 2);
    
    // Test nested_result extraction
    let nested_arg = create_nested_result(TEST_CALL_INDEX, TEST_RESULT_INDEX);
    let (call_idx, result_idx) = nested_result(&nested_arg);
    assert!(call_idx == TEST_CALL_INDEX && result_idx == TEST_RESULT_INDEX, 3);
}

// === Complex Data Tests ===

#[test]
fun test_pure_with_bcs_encoded_data() {
    // Test with different types of BCS-encoded data
    let u64_value: u64 = 12345678;
    let encoded_u64 = bcs::to_bytes(&u64_value);
    let arg_u64 = create_pure(encoded_u64);
    assert!(is_pure(&arg_u64), 0);
    
    let bool_value: bool = true;
    let encoded_bool = bcs::to_bytes(&bool_value);
    let arg_bool = create_pure(encoded_bool);
    assert!(is_pure(&arg_bool), 1);
    
    let vector_value: vector<u8> = vector[1, 2, 3, 4, 5];
    let encoded_vector = bcs::to_bytes(&vector_value);
    let arg_vector = create_pure(encoded_vector);
    assert!(is_pure(&arg_vector), 2);
}

#[test]
fun test_nested_result_edge_cases() {
    // Test with minimum values
    let arg_min = create_nested_result(0, 0);
    let (call_idx, result_idx) = nested_result(&arg_min);
    assert!(call_idx == 0 && result_idx == 0, 0);
    
    // Test with maximum u16 values
    let max_u16: u16 = 65535;
    let arg_max = create_nested_result(max_u16, max_u16);
    let (call_idx_max, result_idx_max) = nested_result(&arg_max);
    assert!(call_idx_max == max_u16 && result_idx_max == max_u16, 1);
}

// === Error Cases Tests ===

#[test]
#[expected_failure(abort_code = ptb_move_call::argument::EInvalidArgument)]
fun test_id_on_wrong_type_object() {
    let arg = create_object(TEST_ADDRESS);
    id(&arg); // Should abort
}

#[test]
#[expected_failure(abort_code = ptb_move_call::argument::EInvalidArgument)]
fun test_id_on_wrong_type_pure() {
    let arg = create_pure(b"data");
    id(&arg); // Should abort
}

#[test]
#[expected_failure(abort_code = ptb_move_call::argument::EInvalidArgument)]
fun test_id_on_wrong_type_nested() {
    let arg = create_nested_result(1, 2);
    id(&arg); // Should abort
}

#[test]
#[expected_failure(abort_code = ptb_move_call::argument::EInvalidArgument)]
fun test_object_on_wrong_type_id() {
    let test_bytes32 = bytes32::from_bytes(b"test_id_bytes32_value_here_12345");
    let arg = create_id(test_bytes32);
    object(&arg); // Should abort
}

#[test]
#[expected_failure(abort_code = ptb_move_call::argument::EInvalidArgument)]
fun test_object_on_wrong_type_pure() {
    let arg = create_pure(b"data");
    object(&arg); // Should abort
}

#[test]
#[expected_failure(abort_code = ptb_move_call::argument::EInvalidArgument)]
fun test_object_on_wrong_type_nested() {
    let arg = create_nested_result(1, 2);
    object(&arg); // Should abort
}

#[test]
#[expected_failure(abort_code = ptb_move_call::argument::EInvalidArgument)]
fun test_pure_on_wrong_type_id() {
    let test_bytes32 = bytes32::from_bytes(b"test_id_bytes32_value_here_12345");
    let arg = create_id(test_bytes32);
    pure(&arg); // Should abort
}

#[test]
#[expected_failure(abort_code = ptb_move_call::argument::EInvalidArgument)]
fun test_pure_on_wrong_type_object() {
    let arg = create_object(TEST_ADDRESS);
    pure(&arg); // Should abort
}

#[test]
#[expected_failure(abort_code = ptb_move_call::argument::EInvalidArgument)]
fun test_pure_on_wrong_type_nested() {
    let arg = create_nested_result(1, 2);
    pure(&arg); // Should abort
}

#[test]
#[expected_failure(abort_code = ptb_move_call::argument::EInvalidArgument)]
fun test_nested_result_on_wrong_type_id() {
    let test_bytes32 = bytes32::from_bytes(b"test_id_bytes32_value_here_12345");
    let arg = create_id(test_bytes32);
    nested_result(&arg); // Should abort
}

#[test]
#[expected_failure(abort_code = ptb_move_call::argument::EInvalidArgument)]
fun test_nested_result_on_wrong_type_object() {
    let arg = create_object(TEST_ADDRESS);
    nested_result(&arg); // Should abort
}

#[test]
#[expected_failure(abort_code = ptb_move_call::argument::EInvalidArgument)]
fun test_nested_result_on_wrong_type_pure() {
    let arg = create_pure(b"data");
    nested_result(&arg); // Should abort
}