#[test_only]
module call::multi_call_tests;

use call::{call, call_cap, multi_call};
use sui::{test_scenario as ts, test_utils};

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
fun test_multi_call_complete_lifecycle() {
    let mut scenario = setup();

    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee1_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee2_cap = call_cap::new_individual_cap(scenario.ctx());
    let recipient_cap = call_cap::new_individual_cap(scenario.ctx());

    // Step 1: Test empty multi-call creation
    let empty_calls = vector::empty<call::Call<TestParam, TestResult>>();
    let empty_multi_call = multi_call::create(&caller_cap, empty_calls);

    assert!(empty_multi_call.caller() == object::id_address(&caller_cap), 0);
    assert!(empty_multi_call.length() == 0, 1);

    let empty_calls_ret = empty_multi_call.destroy(&caller_cap);
    assert!(empty_calls_ret.length() == 0, 2);
    test_utils::destroy(empty_calls_ret);

    // Step 2: Create multi-call with two calls for complete workflow
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
    let mut multi_call = multi_call::create(&caller_cap, calls);

    assert!(multi_call.caller() == object::id_address(&caller_cap), 3);
    assert!(multi_call.length() == 2, 4);
    assert!(multi_call.contains(object::id_address(&callee1_cap)), 5);

    // Step 3: Process first call
    let call1_ref = multi_call.borrow_mut(&callee1_cap);
    call1_ref.complete(&callee1_cap, TestResult { computed: 42 * 2 });

    // Step 4: Process second call
    let call2_ref = multi_call.borrow_mut(&callee2_cap);
    call2_ref.complete(&callee2_cap, TestResult { computed: 84 * 2 });

    // Step 5: Extract and destroy completed calls
    let mut calls_ret = multi_call.destroy(&caller_cap);

    let call2_completed = calls_ret.pop_back();
    let call1_completed = calls_ret.pop_back();

    let (callee1_addr, param1, result1) = call1_completed.destroy(&callee1_cap);
    assert!(callee1_addr == object::id_address(&callee1_cap), 6);
    assert!(param1.value == 42, 7);
    assert!(result1.computed == 84, 8);

    let (callee2_addr, param2, result2) = call2_completed.destroy(&callee2_cap);
    assert!(callee2_addr == object::id_address(&callee2_cap), 9);
    assert!(param2.value == 84, 10);
    assert!(result2.computed == 168, 11);

    test_utils::destroy(calls_ret);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee1_cap);
    test_utils::destroy(callee2_cap);
    test_utils::destroy(recipient_cap);
    clean(scenario);
}

// === Negative Tests ===

#[test]
#[expected_failure(abort_code = multi_call::EUnauthorized)]
fun test_unauthorized_destroy_multi_call() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let wrong_cap = call_cap::new_individual_cap(scenario.ctx()); // Different cap
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let recipient_cap = call_cap::new_individual_cap(scenario.ctx());

    let call1 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee_cap),
        42,
    );
    let calls = vector[call1];
    let multi_call = multi_call::create(&caller_cap, calls);

    // Try to destroy with wrong capability - should fail with EUnauthorized
    let calls_ret = multi_call.destroy(&wrong_cap);

    test_utils::destroy(calls_ret);
    test_utils::destroy(caller_cap);
    test_utils::destroy(wrong_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(recipient_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = multi_call::ECalleeNotFound)]
fun test_borrow_non_existent_callee() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let non_existent_callee_cap = call_cap::new_individual_cap(scenario.ctx()); // This callee is not in the multi-call
    let recipient_cap = call_cap::new_individual_cap(scenario.ctx());

    let call1 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee_cap),
        42,
    );
    let calls = vector[call1];
    let multi_call = multi_call::create(&caller_cap, calls);

    assert!(!multi_call.contains(object::id_address(&non_existent_callee_cap)), 0);
    // Try to borrow call with non-existent callee - should fail with ECalleeNotFound
    let _call_ref = multi_call.borrow(&non_existent_callee_cap);

    let mut calls_ret = multi_call.destroy(&caller_cap);
    let call_ret = calls_ret.pop_back();
    test_utils::destroy(call_ret);
    test_utils::destroy(calls_ret);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(non_existent_callee_cap);
    test_utils::destroy(recipient_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = multi_call::ECalleeNotFound)]
fun test_borrow_mut_non_existent_callee() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let non_existent_callee_cap = call_cap::new_individual_cap(scenario.ctx()); // This callee is not in the multi-call
    let recipient_cap = call_cap::new_individual_cap(scenario.ctx());

    let call1 = create_test_call(
        &mut scenario,
        &caller_cap,
        object::id_address(&callee_cap),
        42,
    );
    let calls = vector[call1];
    let mut multi_call = multi_call::create(&caller_cap, calls);

    assert!(!multi_call.contains(object::id_address(&non_existent_callee_cap)), 0);
    // Try to borrow_mut call with non-existent callee - should fail with ECalleeNotFound
    let _call_ref = multi_call.borrow_mut(&non_existent_callee_cap);

    let mut calls_ret = multi_call.destroy(&caller_cap);
    let call_ret = calls_ret.pop_back();
    test_utils::destroy(call_ret);
    test_utils::destroy(calls_ret);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(non_existent_callee_cap);
    test_utils::destroy(recipient_cap);
    clean(scenario);
}
