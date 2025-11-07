#[test_only]
module ptb_move_call::move_calls_builder_tests;

use ptb_move_call::{
    move_calls_builder::{
        new,
        create,
        add,
        append,
        build,
        to_nested_result_arg,
        to_id_arg,
        is_builder_call
    },
    move_call::{Self, MoveCall},
    argument::{Self, Argument}
};
use std::ascii;
use utils::bytes32::{Self, Bytes32};

// === Test Constants ===

const TEST_PACKAGE: address = @0x1234;
const TEST_MODULE: vector<u8> = b"test_module";
const TEST_FUNCTION: vector<u8> = b"test_function";

// === Helper Functions ===

fun create_test_move_call(
    is_builder: bool,
    result_ids: vector<Bytes32>,
    arguments: vector<Argument>
): MoveCall {
    move_call::create(
        TEST_PACKAGE,
        ascii::string(TEST_MODULE),
        ascii::string(TEST_FUNCTION),
        arguments,
        vector[],
        is_builder,
        result_ids
    )
}

// === Constructor Tests ===

#[test]
fun test_new_creates_empty_builder() {
    let builder = new();
    let calls = build(builder);
    assert!(calls.is_empty(), 0);
}

#[test]
fun test_create_with_initial_calls() {
    let initial_calls = vector[
        create_test_move_call(false, vector[], vector[]),
        create_test_move_call(false, vector[], vector[]),
        create_test_move_call(true, vector[bytes32::from_bytes_right_padded(b"result1")], vector[])
    ];
    
    let builder = create(initial_calls);
    let calls = build(builder);
    assert!(calls.length() == 3, 0);
}

// === Add Function Tests ===

#[test]
fun test_add_mixed_call_types() {
    let mut builder = new();
    
    // Add mix of direct and builder calls
    let direct1 = add(&mut builder, create_test_move_call(false, vector[], vector[]));
    let id1 = bytes32::from_bytes_right_padded(b"id1");
    let builder1 = add(&mut builder, create_test_move_call(true, vector[id1], vector[]));
    let direct2 = add(&mut builder, create_test_move_call(false, vector[], vector[]));
    let id2 = bytes32::from_bytes_right_padded(b"id2");
    let builder2 = add(&mut builder, create_test_move_call(true, vector[id2], vector[]));
    
    // Verify return values
    assert!(!is_builder_call(&direct1), 0);
    assert!(is_builder_call(&builder1), 1);
    assert!(!is_builder_call(&direct2), 2);
    assert!(is_builder_call(&builder2), 3);
    
    // Verify we can use the results correctly
    let arg1 = to_nested_result_arg(&direct1, 0);
    let (call_idx, _) = arg1.nested_result();
    assert!(call_idx == 0, 4); // First direct call at index 0
    
    let arg2 = to_id_arg(&builder1, id1);
    assert!(arg2.id() == id1, 5);
    
    let arg3 = to_nested_result_arg(&direct2, 1);
    let (call_idx3, _) = arg3.nested_result();
    assert!(call_idx3 == 2, 6); // Second direct call at index 2
    
    let calls = build(builder);
    assert!(calls.length() == 4, 7);
}

// === Append Function Tests ===

#[test]
fun test_append_empty_vector() {
    let mut builder = new();
    add(&mut builder, create_test_move_call(false, vector[], vector[]));
    
    // Append empty vector should not change anything
    append(&mut builder, vector[]);
    
    let calls = build(builder);
    assert!(calls.length() == 1, 0);
}

#[test]
fun test_append_adjusts_nested_result_indices() {
    let mut builder = new();
    
    // Add initial calls (indices 0, 1)
    add(&mut builder, create_test_move_call(false, vector[], vector[]));
    add(&mut builder, create_test_move_call(false, vector[], vector[]));
    
    // Create calls with nested result arguments
    let nested_arg1 = argument::create_nested_result(0, 0); // References first call
    let nested_arg2 = argument::create_nested_result(1, 1); // References second call
    
    let calls_to_append = vector[
        create_test_move_call(false, vector[], vector[nested_arg1]),
        create_test_move_call(false, vector[], vector[nested_arg2])
    ];
    
    append(&mut builder, calls_to_append);
    
    let final_calls = build(builder);
    assert!(final_calls.length() == 4, 0);
    
    // Verify the nested results were adjusted
    // Original indices 0,1 should now be 2,3 (offset by 2)
    let adjusted_args1 = final_calls[2].arguments();
    let adjusted_args2 = final_calls[3].arguments();
    
    assert!(adjusted_args1[0].is_nested_result(), 1);
    assert!(adjusted_args2[0].is_nested_result(), 2);
    
    let (call_idx1, result_idx1) = adjusted_args1[0].nested_result();
    let (call_idx2, result_idx2) = adjusted_args2[0].nested_result();
    
    assert!(call_idx1 == 2, 3); // 0 + offset(2) = 2
    assert!(result_idx1 == 0, 4);
    assert!(call_idx2 == 3, 5); // 1 + offset(2) = 3
    assert!(result_idx2 == 1, 6);
}

#[test]
fun test_append_with_complex_nested_structure() {
    let mut builder = new();
    
    // Setup: main builder has 3 calls
    add(&mut builder, create_test_move_call(false, vector[], vector[])); // 0
    add(&mut builder, create_test_move_call(false, vector[], vector[])); // 1
    add(&mut builder, create_test_move_call(false, vector[], vector[])); // 2
    
    // Create complex calls to append with various nested references
    let calls_to_append = vector[
        // Call that references multiple previous results
        create_test_move_call(
            false,
            vector[],
            vector[
                argument::create_nested_result(0, 0),
                argument::create_nested_result(1, 0),
                argument::create_nested_result(2, 0)
            ]
        ),
        // Call that mixes nested and non-nested args
        create_test_move_call(
            false,
            vector[],
            vector[
                argument::create_pure(b"data"),
                argument::create_nested_result(0, 1),
                argument::create_object(@0xABCD)
            ]
        )
    ];
    
    append(&mut builder, calls_to_append);
    
    let final_calls = build(builder);
    assert!(final_calls.length() == 5, 0);
    
    // Verify first appended call (index 3) has adjusted references
    let args3 = final_calls[3].arguments();
    let (idx0, _) = args3[0].nested_result();
    let (idx1, _) = args3[1].nested_result();
    let (idx2, _) = args3[2].nested_result();
    assert!(idx0 == 3 && idx1 == 4 && idx2 == 5, 1); // All offset by 3
    
    // Verify second appended call (index 4) has mixed args
    let args4 = final_calls[4].arguments();
    assert!(args4[0].is_pure(), 2);
    assert!(args4[1].is_nested_result(), 3);
    assert!(args4[2].is_object(), 4);
    
    let (idx_nested, _) = args4[1].nested_result();
    assert!(idx_nested == 3, 5); // 0 + offset(3) = 3
}


#[test]
fun test_to_nested_result_arg_creates_correct_argument() {
    let mut builder = new();
    let result = add(&mut builder, create_test_move_call(false, vector[], vector[]));
    
    // Create nested result argument with result_index 2
    let arg = to_nested_result_arg(&result, 2);
    
    assert!(arg.is_nested_result(), 0);
    let (call_idx, result_idx) = arg.nested_result();
    // Should create NestedResult(0, 2) since it was the first call added
    assert!(call_idx == 0, 1);
    assert!(result_idx == 2, 2);
    
    let _calls = build(builder); // Consume builder
}

#[test]
#[expected_failure(abort_code = ptb_move_call::move_calls_builder::EInvalidMoveCallResult)]
fun test_to_nested_result_arg_fails_on_builder_result() {
    let mut builder = new();
    let result = add(&mut builder, create_test_move_call(true, vector[bytes32::from_bytes_right_padded(b"id")], vector[]));
    
    // Should fail because builder results can't be converted to nested results
    to_nested_result_arg(&result, 0);
    
    let _calls = build(builder); // Consume builder
}

#[test]
fun test_to_id_arg_creates_correct_argument() {
    let mut builder = new();
    let expected_id = bytes32::from_bytes_right_padded(b"expected_result_id");
    let result = add(&mut builder, create_test_move_call(true, vector[expected_id], vector[]));
    
    // Create ID argument
    let arg = to_id_arg(&result, expected_id);
    
    assert!(arg.is_id(), 0);
    assert!(arg.id() == expected_id, 1);
    
    let _calls = build(builder); // Consume builder
}

#[test]
#[expected_failure(abort_code = ptb_move_call::move_calls_builder::EResultIDNotFound)]
fun test_to_id_arg_fails_when_id_not_found() {
    let mut builder = new();
    let actual_id = bytes32::from_bytes_right_padded(b"actual_id");
    let wrong_id = bytes32::from_bytes_right_padded(b"wrong_id");
    let result = add(&mut builder, create_test_move_call(true, vector[actual_id], vector[]));
    
    // Should fail because wrong_id is not in the result
    to_id_arg(&result, wrong_id);
    
    let _calls = build(builder); // Consume builder
}

#[test]
#[expected_failure(abort_code = ptb_move_call::move_calls_builder::EInvalidMoveCallResult)]
fun test_to_id_arg_fails_on_direct_result() {
    let mut builder = new();
    let result = add(&mut builder, create_test_move_call(false, vector[], vector[]));
    
    // Should fail because direct results can't be converted to ID arguments
    to_id_arg(&result, bytes32::from_bytes_right_padded(b"any_id"));
    
    let _calls = build(builder); // Consume builder
}

// === Integration Tests ===

#[test]
fun test_complete_workflow_with_references() {
    let mut builder = new();
    
    // Add some base calls
    let result1 = add(&mut builder, create_test_move_call(false, vector[], vector[]));
    let result2 = add(&mut builder, create_test_move_call(false, vector[], vector[]));
    
    // Add builder call with result IDs
    let id1 = bytes32::from_bytes_right_padded(b"builder_result_1");
    let id2 = bytes32::from_bytes_right_padded(b"builder_result_2");
    let builder_ids = vector[id1, id2];
    let result3 = add(&mut builder, create_test_move_call(true, builder_ids, vector[]));
    
    // Create arguments referencing previous results
    let arg1 = to_nested_result_arg(&result1, 0);
    let arg2 = to_nested_result_arg(&result2, 1);
    let arg3 = to_id_arg(&result3, id1);
    
    // Verify argument values
    let (call_idx1, result_idx1) = arg1.nested_result();
    assert!(call_idx1 == 0 && result_idx1 == 0, 3);
    
    let (call_idx2, result_idx2) = arg2.nested_result();
    assert!(call_idx2 == 1 && result_idx2 == 1, 4);
    
    assert!(arg3.id() == id1, 5);
    
    // Add a call using these arguments
    let final_call = create_test_move_call(
        false,
        vector[],
        vector[arg1, arg2, arg3]
    );
    let result4 = add(&mut builder, final_call);
    assert!(!is_builder_call(&result4), 6);
    
    let calls = build(builder);
    assert!(calls.length() == 4, 7);
    
    // Verify the last call has the correct arguments
    let last_call_args = calls[3].arguments();
    assert!(last_call_args.length() == 3, 8);
    assert!(last_call_args[0].is_nested_result(), 9);
    assert!(last_call_args[1].is_nested_result(), 10);
    assert!(last_call_args[2].is_id(), 11);
    
    // Verify the actual argument values in the final call
    let (final_call_idx1, final_result_idx1) = last_call_args[0].nested_result();
    assert!(final_call_idx1 == 0 && final_result_idx1 == 0, 12);
    
    let (final_call_idx2, final_result_idx2) = last_call_args[1].nested_result();
    assert!(final_call_idx2 == 1 && final_result_idx2 == 1, 13);
    
    assert!(last_call_args[2].id() == id1, 14);
}
