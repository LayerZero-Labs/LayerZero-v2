/// Unit tests for sequential_multi_call module
///
/// This test suite covers:
/// 1. Basic creation and destruction of sequential multi-calls
/// 2. Sequential processing with duplicate callees (key difference from regular multi_call)
/// 3. Mixed callee sequences to verify ordered processing
/// 4. Index management with increment_index parameter
/// 5. Error conditions: unauthorized access, no more calls, wrong callee order
/// 6. Edge cases: single call, multiple borrows without increment
#[test_only]
module multi_call::multi_call_tests;

use call::{call, call_cap};
use multi_call::multi_call;
use iota::{test_scenario as ts, test_utils};

// === Test Constants ===

const ADMIN: address = @0x0;

// === Test Structs ===

public struct TestParam has copy, drop, store {
    value: u64,
}

public struct TestResult has copy, drop, store {
    computed: u64,
}

// === Helper Functions ===

fun setup(): ts::Scenario {
    ts::begin(ADMIN)
}

fun clean(scenario: ts::Scenario) {
    ts::end(scenario);
}

fun create_test_param(value: u64): TestParam {
    TestParam { value }
}

fun create_test_call(
    scenario: &mut ts::Scenario,
    caller_cap: &call_cap::CallCap,
    callee: address,
    param_value: u64,
): call::Call<TestParam, TestResult> {
    call::create<TestParam, TestResult>(
        caller_cap,
        callee,
        true,
        create_test_param(param_value),
        scenario.ctx(),
    )
}

// === Basic Tests ===

#[test]
fun test_sequential_multi_call_creation_and_destruction() {
    let mut scenario = setup();

    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee1_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee2_cap = call_cap::new_individual_cap(scenario.ctx());

    // Test empty sequential multi-call creation
    let empty_calls = vector::empty<call::Call<TestParam, TestResult>>();
    let empty_sequential_multi_call = multi_call::create(&caller_cap, empty_calls);

    assert!(empty_sequential_multi_call.caller() == object::id_address(&caller_cap), 0);
    assert!(empty_sequential_multi_call.length() == 0, 1);
    assert!(!empty_sequential_multi_call.has_next(), 2);

    let empty_calls_ret = empty_sequential_multi_call.destroy(&caller_cap);
    assert!(empty_calls_ret.length() == 0, 3);
    test_utils::destroy(empty_calls_ret);

    // Test sequential multi-call with multiple calls
    let call1 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee1_cap),
        42,
    );
    let call2 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee2_cap),
        84,
    );

    let calls = vector[call1, call2];
    let sequential_multi_call = multi_call::create(&caller_cap, calls);

    assert!(sequential_multi_call.caller() == object::id_address(&caller_cap), 4);
    assert!(sequential_multi_call.length() == 2, 5);
    assert!(sequential_multi_call.has_next(), 6);

    let mut calls_ret = sequential_multi_call.destroy(&caller_cap);
    assert!(calls_ret.length() == 2, 7);

    // Clean up the returned calls
    while (!calls_ret.is_empty()) {
        let mut call_to_destroy = calls_ret.pop_back();
        let appropriate_cap = if (call_to_destroy.callee() == object::id_address(&callee1_cap)) {
            &callee1_cap
        } else {
            &callee2_cap
        };
        call_to_destroy.complete(appropriate_cap, TestResult { computed: 0 });
        let (_, _, _) = call_to_destroy.destroy(appropriate_cap);
    };
    test_utils::destroy(calls_ret);

    test_utils::destroy(caller_cap);
    test_utils::destroy(callee1_cap);
    test_utils::destroy(callee2_cap);
    clean(scenario);
}

#[test]
fun test_sequential_processing_with_duplicate_callees() {
    let mut scenario = setup();

    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());

    // Create multiple calls with the same callee (demonstrates support for duplicates)
    let call1 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee_cap),
        10,
    );
    let call2 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee_cap),
        20,
    );
    let call3 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee_cap),
        30,
    );

    let calls = vector[call1, call2, call3];
    let mut sequential_multi_call = multi_call::create(&caller_cap, calls);

    assert!(sequential_multi_call.length() == 3, 0);
    assert!(sequential_multi_call.has_next(), 1);
    assert!(sequential_multi_call.next_index() == 0, 2);

    // Process first call without incrementing index
    let call1_ref = sequential_multi_call.borrow_next(&callee_cap, false);
    assert!(call1_ref.param().value == 10, 3);
    assert!(sequential_multi_call.next_index() == 0, 4);

    // Process first call again (since we didn't increment) and complete it
    let call1_ref = sequential_multi_call.borrow_next(&callee_cap, true);
    call1_ref.complete(&callee_cap, TestResult { computed: 10 * 2 });
    assert!(sequential_multi_call.has_next(), 5);
    assert!(sequential_multi_call.next_index() == 1, 6);

    // Process second call
    let call2_ref = sequential_multi_call.borrow_next(&callee_cap, true);
    assert!(call2_ref.param().value == 20, 4);
    call2_ref.complete(&callee_cap, TestResult { computed: 20 * 2 });
    assert!(sequential_multi_call.has_next(), 7);
    assert!(sequential_multi_call.next_index() == 2, 8);

    // Process third call
    let call3_ref = sequential_multi_call.borrow_next(&callee_cap, true);
    assert!(call3_ref.param().value == 30, 9);
    call3_ref.complete(&callee_cap, TestResult { computed: 30 * 2 });
    assert!(!sequential_multi_call.has_next(), 10); // No more calls
    assert!(sequential_multi_call.next_index() == 3, 11);

    // Extract and verify all calls
    let mut calls_ret = sequential_multi_call.destroy(&caller_cap);
    assert!(calls_ret.length() == 3, 8);

    // Verify results in order
    let call3_completed = calls_ret.pop_back();
    let call2_completed = calls_ret.pop_back();
    let call1_completed = calls_ret.pop_back();

    let (_, param1, result1) = call1_completed.destroy(&callee_cap);
    assert!(param1.value == 10, 9);
    assert!(result1.computed == 20, 10);

    let (_, param2, result2) = call2_completed.destroy(&callee_cap);
    assert!(param2.value == 20, 11);
    assert!(result2.computed == 40, 12);

    let (_, param3, result3) = call3_completed.destroy(&callee_cap);
    assert!(param3.value == 30, 13);
    assert!(result3.computed == 60, 14);

    test_utils::destroy(calls_ret);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    clean(scenario);
}

#[test]
fun test_sequential_processing_mixed_callees() {
    let mut scenario = setup();

    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee1_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee2_cap = call_cap::new_individual_cap(scenario.ctx());

    // Create calls with mixed callees in specific order
    let call1 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee1_cap),
        100,
    );
    let call2 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee2_cap),
        200,
    );
    let call3 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee1_cap), // Same as first
        300,
    );

    let calls = vector[call1, call2, call3];
    let mut sequential_multi_call = multi_call::create(&caller_cap, calls);

    // Process first call (callee1)
    let call1_ref = sequential_multi_call.borrow_next(&callee1_cap, true);
    assert!(call1_ref.param().value == 100, 0);
    call1_ref.complete(&callee1_cap, TestResult { computed: 100 });
    assert!(sequential_multi_call.next_index() == 1, 1);

    // Process second call (callee2)
    let call2_ref = sequential_multi_call.borrow_next(&callee2_cap, true);
    assert!(call2_ref.param().value == 200, 2);
    call2_ref.complete(&callee2_cap, TestResult { computed: 200 });
    assert!(sequential_multi_call.next_index() == 2, 3);

    // Process third call (callee1 again)
    let call3_ref = sequential_multi_call.borrow_next(&callee1_cap, true);
    assert!(call3_ref.param().value == 300, 4);
    call3_ref.complete(&callee1_cap, TestResult { computed: 300 });
    assert!(sequential_multi_call.next_index() == 3, 5);

    assert!(!sequential_multi_call.has_next(), 6);

    // Clean up
    let mut calls_ret = sequential_multi_call.destroy(&caller_cap);

    // Destroy all calls
    let call3_completed = calls_ret.pop_back();
    let call2_completed = calls_ret.pop_back();
    let call1_completed = calls_ret.pop_back();

    let (_, _, _) = call1_completed.destroy(&callee1_cap);
    let (_, _, _) = call2_completed.destroy(&callee2_cap);
    let (_, _, _) = call3_completed.destroy(&callee1_cap);

    test_utils::destroy(calls_ret);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee1_cap);
    test_utils::destroy(callee2_cap);
    clean(scenario);
}

// === Negative Tests ===

#[test]
#[expected_failure(abort_code = multi_call::EUnauthorized)]
fun test_unauthorized_destroy() {
    let mut scenario = setup();

    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let wrong_cap = call_cap::new_individual_cap(scenario.ctx()); // Different cap
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());

    let call1 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee_cap),
        42,
    );
    let calls = vector[call1];
    let sequential_multi_call = multi_call::create(&caller_cap, calls);

    // Try to destroy with wrong capability - should fail with EUnauthorized
    let calls_ret = sequential_multi_call.destroy(&wrong_cap);

    test_utils::destroy(calls_ret);
    test_utils::destroy(caller_cap);
    test_utils::destroy(wrong_cap);
    test_utils::destroy(callee_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = multi_call::ENoMoreCalls)]
fun test_borrow_next_when_no_more_calls() {
    let mut scenario = setup();

    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());

    let call1 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee_cap),
        42,
    );
    let calls = vector[call1];
    let mut sequential_multi_call = multi_call::create(&caller_cap, calls);

    // Process the only call and increment index
    let call1_ref = sequential_multi_call.borrow_next(&callee_cap, true);
    call1_ref.complete(&callee_cap, TestResult { computed: 42 });

    assert!(!sequential_multi_call.has_next(), 0);

    // Try to borrow next when there are no more calls - should fail with ENoMoreCalls
    let _call_ref = sequential_multi_call.borrow_next(&callee_cap, false);

    let mut calls_ret = sequential_multi_call.destroy(&caller_cap);
    let call_ret = calls_ret.pop_back();
    let (_, _, _) = call_ret.destroy(&callee_cap);
    test_utils::destroy(calls_ret);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = multi_call::EUnauthorized)]
fun test_borrow_next_unauthorized_callee() {
    let mut scenario = setup();

    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let wrong_callee_cap = call_cap::new_individual_cap(scenario.ctx()); // Wrong callee

    let call1 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee_cap),
        42,
    );
    let calls = vector[call1];
    let mut multi_call = multi_call::create(&caller_cap, calls);

    // Try to borrow with wrong callee capability - should fail with EUnauthorized
    let _call_ref = multi_call.borrow_next(&wrong_callee_cap, false);

    let mut calls_ret = multi_call.destroy(&caller_cap);
    let mut call_ret = calls_ret.pop_back();
    call_ret.complete(&callee_cap, TestResult { computed: 0 });
    let (_, _, _) = call_ret.destroy(&callee_cap);
    test_utils::destroy(calls_ret);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(wrong_callee_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = multi_call::EUnauthorized)]
fun test_wrong_callee_in_sequence() {
    let mut scenario = setup();

    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee1_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee2_cap = call_cap::new_individual_cap(scenario.ctx());

    // Create sequence: callee1, callee2
    let call1 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee1_cap),
        10,
    );
    let call2 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee2_cap),
        20,
    );

    let calls = vector[call1, call2];
    let mut multi_call = multi_call::create(&caller_cap, calls);

    // Try to process first call with callee2 (should be callee1) - should fail
    let _call_ref = multi_call.borrow_next(&callee2_cap, false);

    let mut calls_ret = multi_call.destroy(&caller_cap);
    // Clean up calls
    let mut call2_ret = calls_ret.pop_back();
    let mut call1_ret = calls_ret.pop_back();
    call1_ret.complete(&callee1_cap, TestResult { computed: 0 });
    call2_ret.complete(&callee2_cap, TestResult { computed: 0 });
    let (_, _, _) = call1_ret.destroy(&callee1_cap);
    let (_, _, _) = call2_ret.destroy(&callee2_cap);
    test_utils::destroy(calls_ret);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee1_cap);
    test_utils::destroy(callee2_cap);
    clean(scenario);
}

// === Edge Case Tests ===

#[test]
fun test_sequential_multi_call_single_call() {
    let mut scenario = setup();

    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());

    let call1 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee_cap),
        777,
    );
    let calls = vector[call1];
    let mut sequential_multi_call = multi_call::create(&caller_cap, calls);

    assert!(sequential_multi_call.length() == 1, 0);
    assert!(sequential_multi_call.has_next(), 1);

    // Process the single call
    let call_ref = sequential_multi_call.borrow_next(&callee_cap, true);
    assert!(call_ref.param().value == 777, 2);
    call_ref.complete(&callee_cap, TestResult { computed: 777 * 3 });

    assert!(!sequential_multi_call.has_next(), 3);

    // Extract and verify
    let mut calls_ret = sequential_multi_call.destroy(&caller_cap);
    let call_completed = calls_ret.pop_back();

    let (_, param, result) = call_completed.destroy(&callee_cap);
    assert!(param.value == 777, 4);
    assert!(result.computed == 2331, 5);

    test_utils::destroy(calls_ret);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    clean(scenario);
}

#[test]
fun test_borrow_next_without_increment_multiple_times() {
    let mut scenario = setup();

    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());

    let call1 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee_cap),
        123,
    );
    let calls = vector[call1];
    let mut multi_call = multi_call::create(&caller_cap, calls);

    // Borrow the same call multiple times without incrementing
    let call_ref1 = multi_call.borrow_next(&callee_cap, false);
    assert!(call_ref1.param().value == 123, 0);
    assert!(multi_call.next_index() == 0, 1);

    let call_ref2 = multi_call.borrow_next(&callee_cap, false);
    assert!(call_ref2.param().value == 123, 2);
    assert!(multi_call.next_index() == 0, 3);

    let call_ref3 = multi_call.borrow_next(&callee_cap, false);
    assert!(call_ref3.param().value == 123, 4);
    assert!(multi_call.next_index() == 0, 5);

    // Should still have next available since we haven't incremented
    assert!(multi_call.has_next(), 6);

    // Finally increment and complete
    let call_ref_final = multi_call.borrow_next(&callee_cap, true);
    call_ref_final.complete(&callee_cap, TestResult { computed: 456 });

    assert!(!multi_call.has_next(), 7);

    // Clean up
    let mut calls_ret = multi_call.destroy(&caller_cap);
    let call_completed = calls_ret.pop_back();
    let (_, _, _) = call_completed.destroy(&callee_cap);
    test_utils::destroy(calls_ret);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    clean(scenario);
}
