#[test_only]
module call::call_tests;

use call::{call, call_cap};
use sui::{test_scenario as ts, test_utils};

// === Test Structs ===

public struct TestParam has copy, drop, store {
    value: u64,
}

public struct TestResult has copy, drop, store {
    computed: u64,
}

// === Helper Functions ===

fun setup(): ts::Scenario {
    ts::begin(@0x1)
}

fun clean(scenario: ts::Scenario) {
    ts::end(scenario);
}

fun create_test_param(value: u64): TestParam {
    TestParam { value }
}

fun create_test_result(computed: u64): TestResult {
    TestResult { computed }
}

// === Basic Tests ===

#[test]
fun test_new_cap() {
    let mut scenario = setup();

    let cap = call_cap::new_individual_cap(scenario.ctx());

    // Verify cap was created successfully
    assert!(object::id_address(&cap) != @0x0, 0);

    test_utils::destroy(cap);
    clean(scenario);
}

fun complete_call_lifecycle(oneway: bool) {
    let mut scenario = setup();

    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let recipient_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);
    let result = create_test_result(84);

    // Step 1: Create call and verify initial properties with ALL view functions
    let mut call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        oneway,
        param,
        scenario.ctx(),
    );
    call.enable_mutable_param(&caller_cap);

    // Test ALL view functions on initial call
    assert!(call.id() != @0x0, 0); // Call has valid unique ID
    assert!(call.caller() == object::id_address(&caller_cap), 1);
    assert!(call.callee() == object::id_address(&callee_cap), 2);
    assert!(call.one_way() == oneway, 3); // Verify one_way flag matches parameter

    // Verify recipient based on oneway flag
    if (oneway) {
        assert!(call.recipient() == call.callee(), 4);
    } else {
        assert!(call.recipient() == call.caller(), 4);
    };

    assert!(call.param().value == 42, 5);
    assert!(call.result().is_none(), 6); // No result initially
    assert!(call.parent_id() == @0x0, 7); // Root call has no parent (ROOT_CALL_PARENT_ID)
    assert!(call.is_root(), 8); // This is a root call
    assert!(call.batch_nonce() == 0, 9); // Initial batch nonce is 0
    assert!(call.child_batch().length() == 0, 10); // No children initially
    assert!(call.status().is_active(), 11); // Initial status is Active

    // Test status function on Active status
    assert!(call.status().is_active(), 12);
    assert!(!call.status().is_creating(), 13);
    assert!(!call.status().is_waiting(), 14);
    assert!(!call.status().is_completed(), 15);

    // Test assert_caller function with correct caller
    call.assert_caller(object::id_address(&caller_cap)); // Should pass

    // Step 2: Test param_mut access and modification in Active state
    let param_ref = call.param_mut(&callee_cap);
    assert!(param_ref.value == 42, 16);
    param_ref.value = 100; // Modify parameter in active state
    assert!(call.param().value == 100, 17); // Verify modification through param() view function

    // Test param_mut before completion
    call.param_mut(&callee_cap).value = 200;
    assert!(call.param().value == 200, 18); // Verify modification persists

    // Step 3: Complete call and verify completion with view functions
    call.complete(&callee_cap, result);

    // Test ALL view functions after completion
    assert!(call.id() != @0x0, 19); // ID remains the same
    assert!(call.caller() == object::id_address(&caller_cap), 20); // Caller unchanged
    assert!(call.callee() == object::id_address(&callee_cap), 21); // Callee unchanged
    assert!(call.one_way() == oneway, 22); // one_way flag unchanged

    // Recipient still based on oneway flag
    if (oneway) {
        assert!(call.recipient() == call.callee(), 23);
    } else {
        assert!(call.recipient() == call.caller(), 23);
    };

    assert!(call.param().value == 200, 24); // Parameter value persists
    assert!(call.result().is_some(), 25); // Result is now available
    assert!(call.result().borrow().computed == 84, 26); // Correct result value
    assert!(call.parent_id() == @0x0, 27); // Still a root call
    assert!(call.is_root(), 28); // Still a root call
    assert!(call.batch_nonce() == 0, 29); // Batch nonce unchanged (no children created)
    assert!(call.child_batch().length() == 0, 30); // Still no children
    assert!(call.status().is_completed(), 31); // Status changed to Completed

    // Test status functions on Completed status
    assert!(!call.status().is_active(), 32);
    assert!(!call.status().is_creating(), 33);
    assert!(!call.status().is_waiting(), 34);
    assert!(call.status().is_completed(), 35);

    // Test param_mut in Completed state (should still work)
    call.param_mut(&callee_cap).value = 300;
    assert!(call.param().value == 300, 36); // Verify modification in completed state

    // Step 4: Destroy call with appropriate recipient based on oneway flag
    let destroy_cap = if (oneway) &callee_cap else &caller_cap;
    let (callee_addr, param_ret, result_ret) = call.destroy(destroy_cap);

    // Verify returned values from destroy (param should reflect final modification)
    assert!(callee_addr == object::id_address(&callee_cap), 37);
    assert!(param_ret.value == 300, 38); // Final modified value
    assert!(result_ret.computed == 84, 39);

    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(recipient_cap);
    clean(scenario);
}

#[test]
fun test_complete_call_lifecycle() {
    // Test one-way calls (callee can destroy)
    complete_call_lifecycle(true);

    // Test two-way calls (caller can destroy)
    complete_call_lifecycle(false);
}

#[test]
fun test_complete_call_create_single_child() {
    let mut scenario = setup();

    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(100);

    // Step 1: Create parent call
    let mut parent_call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        false, // two-way call (caller destroys)
        param,
        scenario.ctx(),
    );

    // Verify initial parent call state
    assert!(parent_call.child_batch().length() == 0, 0);
    assert!(parent_call.status().is_active(), 1);
    assert!(parent_call.batch_nonce() == 0, 2);

    // Step 2: Use create_single_child convenience function (Active → Creating → Waiting)
    let mut child_call = call::create_single_child<TestParam, TestResult, TestParam, TestResult>(
        &mut parent_call,
        &callee_cap,
        object::id_address(&child_callee_cap),
        create_test_param(50),
        scenario.ctx(),
    );

    // Verify parent state after create_single_child using view functions
    assert!(parent_call.child_batch().length() == 1, 3);
    assert!(parent_call.status().is_waiting(), 4); // Should be in Waiting status
    assert!(child_call.status().is_active(), 5);

    // Step 3: Complete child call and verify view functions
    child_call.complete(&child_callee_cap, create_test_result(100));
    assert!(child_call.status().is_completed(), 6);
    assert!(child_call.result().is_some(), 7);
    assert!(child_call.result().borrow().computed == 100, 8);

    // Step 4: Destroy child call (parent returns to Active)
    let (child_callee_addr, child_param, child_result) = call::destroy_child(
        &mut parent_call,
        &callee_cap,
        child_call,
    );

    // Verify child destruction results
    assert!(child_callee_addr == object::id_address(&child_callee_cap), 9);
    assert!(child_param.value == 50, 10);
    assert!(child_result.computed == 100, 11);

    // Verify parent state after child destruction (Waiting → Active) using view functions
    assert!(parent_call.child_batch().length() == 0, 12); // No children left
    assert!(parent_call.status().is_active(), 13); // Returned to Active
    assert!(parent_call.batch_nonce() == 1, 14); // Batch nonce preserved

    // Step 5: Complete parent call and verify final view functions
    parent_call.complete(&callee_cap, create_test_result(200));

    // Step 6: Destroy parent call (two-way, so caller destroys)
    let (_, _, _) = parent_call.destroy(&caller_cap);

    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(child_callee_cap);
    clean(scenario);
}

#[test]
fun test_complete_call_lifecycle_with_child_calls() {
    let mut scenario = setup();

    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child1_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child2_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let recipient_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(100);

    // Step 1: Create parent call
    let mut parent_call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    // Verify initial parent call state
    assert!(parent_call.child_batch().length() == 0, 0);
    assert!(parent_call.status().is_active(), 1);

    // Step 2: Start child batch (Active → Creating)
    parent_call.new_child_batch(&callee_cap, 1);
    assert!(parent_call.status().is_creating(), 2);

    // Create first child call with is_last=false
    let mut child1_call = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut parent_call,
        &callee_cap,
        object::id_address(&child1_callee_cap),
        create_test_param(50),
        false, // not the last child in this batch
        scenario.ctx(),
    );

    // Verify parent state after first child (still in Creating) using view functions
    assert!(parent_call.child_batch().length() == 1, 3);
    assert!(parent_call.status().is_creating(), 4);
    assert!(!parent_call.status().is_active(), 5);
    assert!(!parent_call.status().is_waiting(), 6);
    assert!(!parent_call.status().is_completed(), 7);

    // Verify ALL child call view functions
    assert!(child1_call.id() != @0x0, 8); // Child has valid unique ID
    assert!(child1_call.caller() == object::id_address(&callee_cap), 9); // Parent callee becomes child caller
    assert!(child1_call.callee() == object::id_address(&child1_callee_cap), 10);
    assert!(!child1_call.one_way(), 11); // Child calls are always two-way
    assert!(child1_call.recipient() == child1_call.caller(), 12); // Two-way: caller is recipient
    assert!(child1_call.param().value == 50, 13);
    assert!(child1_call.result().is_none(), 14); // No result yet
    assert!(child1_call.parent_id() == parent_call.id(), 15); // Parent ID matches
    assert!(!child1_call.is_root(), 16); // Not a root call
    assert!(child1_call.batch_nonce() == 0, 17); // Child starts with batch nonce 0
    assert!(child1_call.child_batch().length() == 0, 18); // Child has no children
    assert!(child1_call.status().is_active(), 19); // Child starts in Active status

    // Test child status functions
    assert!(child1_call.status().is_active(), 20);
    assert!(!child1_call.status().is_creating(), 21);
    assert!(!child1_call.status().is_waiting(), 22);
    assert!(!child1_call.status().is_completed(), 23);

    // Test assert_caller on child call
    child1_call.assert_caller(object::id_address(&callee_cap)); // Should pass

    // Step 3: Create second child call with is_last=true (Creating → Waiting)
    let mut child2_call = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut parent_call,
        &callee_cap,
        object::id_address(&child2_callee_cap),
        create_test_param(30),
        true, // last child in this batch
        scenario.ctx(),
    );

    // Verify parent state after second child marked as last (now in Waiting) using view functions
    assert!(parent_call.child_batch().length() == 2, 24);
    assert!(parent_call.status().is_waiting(), 25);
    assert!(!parent_call.status().is_active(), 26);
    assert!(!parent_call.status().is_creating(), 27);
    assert!(!parent_call.status().is_completed(), 28);
    assert!(parent_call.batch_nonce() == 1, 29); // Batch nonce should remain 1

    // Step 4: Complete first child call and verify view functions
    child1_call.complete(&child1_callee_cap, create_test_result(100));
    // Test status functions on completed child
    assert!(!child1_call.status().is_active(), 56);
    assert!(!child1_call.status().is_creating(), 57);
    assert!(!child1_call.status().is_waiting(), 58);
    assert!(child1_call.status().is_completed(), 59);

    // Step 5: Destroy first child call (parent still in Waiting)
    let (child1_callee_addr, child1_param, child1_result) = call::destroy_child(
        &mut parent_call,
        &callee_cap,
        child1_call,
    );

    // Verify first child destruction results
    assert!(child1_callee_addr == object::id_address(&child1_callee_cap), 60);
    assert!(child1_param.value == 50, 61);
    assert!(child1_result.computed == 100, 62);

    // Verify parent state after first child destruction (still Waiting for child2) using view functions
    assert!(parent_call.child_batch().length() == 1, 63); // One child remaining
    assert!(parent_call.status().is_waiting(), 64); // Still waiting
    assert!(!parent_call.status().is_active(), 65);
    assert!(!parent_call.status().is_creating(), 66);
    assert!(!parent_call.status().is_completed(), 67);
    assert!(parent_call.batch_nonce() == 1, 68); // Batch nonce unchanged

    // Step 6: Complete second child call and verify view functions
    child2_call.complete(&child2_callee_cap, create_test_result(60));
    assert!(child2_call.status().is_completed(), 69);
    assert!(child2_call.result().is_some(), 70);
    assert!(child2_call.result().borrow().computed == 60, 71);

    // Step 7: Destroy second child call (last child, parent returns to Active)
    let (child2_callee_addr, child2_param, child2_result) = call::destroy_child(
        &mut parent_call,
        &callee_cap,
        child2_call,
    );

    // Verify second child destruction results
    assert!(child2_callee_addr == object::id_address(&child2_callee_cap), 72);
    assert!(child2_param.value == 30, 73);
    assert!(child2_result.computed == 60, 74);

    // Verify parent state after all children destroyed (Waiting → Active) using view functions
    assert!(parent_call.child_batch().length() == 0, 75); // No children left
    assert!(parent_call.status().is_active(), 76); // Returned to Active
    assert!(!parent_call.status().is_creating(), 77);
    assert!(!parent_call.status().is_waiting(), 78);
    assert!(!parent_call.status().is_completed(), 79);
    assert!(parent_call.batch_nonce() == 1, 80); // Batch nonce preserved

    // Step 8: Complete parent call and verify final view functions
    parent_call.complete(&callee_cap, create_test_result(200));

    // Test ALL view functions on completed parent call
    assert!(parent_call.id() != @0x0, 81); // ID unchanged
    assert!(parent_call.caller() == object::id_address(&caller_cap), 82); // Caller unchanged
    assert!(parent_call.callee() == object::id_address(&callee_cap), 83); // Callee unchanged
    assert!(parent_call.one_way(), 84); // one_way unchanged (true)
    assert!(parent_call.recipient() == parent_call.callee(), 85); // one_way: callee is recipient
    assert!(parent_call.param().value == 100, 86); // Original parameter value
    assert!(parent_call.result().is_some(), 87); // Result now available
    assert!(parent_call.result().borrow().computed == 200, 88); // Correct result value
    assert!(parent_call.parent_id() == @0x0, 89); // Still root call
    assert!(parent_call.is_root(), 90); // Still root call
    assert!(parent_call.batch_nonce() == 1, 91); // Batch nonce preserved
    assert!(parent_call.child_batch().length() == 0, 92); // No children
    assert!(parent_call.status().is_completed(), 93); // Status is Completed

    // Test status functions on completed parent
    assert!(!parent_call.status().is_active(), 94);
    assert!(!parent_call.status().is_creating(), 95);
    assert!(!parent_call.status().is_waiting(), 96);
    assert!(parent_call.status().is_completed(), 97);

    // Step 9: Destroy parent call (one-way, so callee destroys)
    let (parent_callee_addr, parent_param, parent_result) = parent_call.destroy(&callee_cap);

    // Verify parent destruction results
    assert!(parent_callee_addr == object::id_address(&callee_cap), 98);
    assert!(parent_param.value == 100, 99);
    assert!(parent_result.computed == 200, 100);

    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(child1_callee_cap);
    test_utils::destroy(child2_callee_cap);
    test_utils::destroy(recipient_cap);
    clean(scenario);
}

#[test]
fun test_void_result_lifecycle() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let recipient_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    // Create call with Void result type for operations that don't return meaningful data
    let mut call = call::create<TestParam, call::Void>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    call.complete(&callee_cap, call::void());
    assert!(call.status().is_completed());
    assert!(call.result().is_some());

    // Destroy and extract components - void result should be handled properly (callee destroys one-way calls)
    let (callee_addr, extracted_param, void_result) = call.destroy(&callee_cap);

    // Verify extracted values
    assert!(callee_addr == object::id_address(&callee_cap));
    assert!(extracted_param == create_test_param(42));
    // void_result is of type Void - just verify we can use it
    let _void_copy = copy void_result; // Void has copy, so this should work

    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(recipient_cap);
    clean(scenario);
}

#[test]
fun test_mutable_param_enabled_allows_callee_modification() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    // Create call with mutable param enabled
    let mut call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        false, // two-way call
        param,
        scenario.ctx(),
    );

    assert!(!call.mutable_param(), 0);

    // Enable mutable param (only caller can do this)
    call.enable_mutable_param(&caller_cap);

    // Verify mutable_param flag is set
    assert!(call.mutable_param(), 0);

    // Callee should be able to get mutable reference and modify param
    let param_ref = call.param_mut(&callee_cap);
    assert!(param_ref.value == 42, 1);
    param_ref.value = 100; // Modify parameter

    // Verify modification through immutable reference
    assert!(call.param().value == 100, 2);

    // Complete and destroy call
    call.complete(&callee_cap, create_test_result(200));
    let (_, final_param, _) = call.destroy(&caller_cap);

    // Verify final parameter reflects the modification
    assert!(final_param.value == 100, 3);

    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    clean(scenario);
}

#[test]
fun test_complete_and_destroy_one_way_void_call() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    // Create a one-way call with Void result type (typical use case for complete_and_destroy)
    let call = call::create<TestParam, call::Void>(
        &caller_cap,
        object::id_address(&callee_cap),
        true, // one-way call (callee can destroy)
        param,
        scenario.ctx(),
    );

    // Verify initial call state
    assert!(call.one_way(), 0);
    assert!(call.status().is_active(), 1);
    assert!(call.param().value == 42, 2);
    assert!(call.result().is_none(), 3);
    assert!(call.recipient() == call.callee(), 4); // one-way: callee is recipient

    // Use complete_and_destroy convenience function - should complete with void result and destroy in one operation
    let returned_param = call::complete_and_destroy(call, &callee_cap);

    // Verify the returned parameter matches the original
    assert!(returned_param.value == 42, 5);

    // Call object should be consumed and destroyed at this point
    // No need to manually destroy since complete_and_destroy consumed it

    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    clean(scenario);
}

// === Negative Tests ===

#[test]
#[expected_failure(abort_code = call::EParameterNotMutable)]
fun test_param_mut_without_enable_mutable_param() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    // Create call without enabling mutable param
    let mut call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        false, // two-way call
        param,
        scenario.ctx(),
    );

    // Verify mutable_param flag is false by default
    assert!(!call.mutable_param(), 0);

    // Try to get mutable reference without enabling mutable param - should fail with EParameterNotMutable
    call.param_mut(&callee_cap);

    test_utils::destroy(call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::EUnauthorized)]
fun test_param_mut_unauthorized_caller() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let wrong_cap = call_cap::new_individual_cap(scenario.ctx()); // Wrong capability
    let recipient_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    let mut call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    // Try to access mutable parameters with caller capability - should fail
    call.param_mut(&caller_cap);

    test_utils::destroy(call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(wrong_cap);
    test_utils::destroy(recipient_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::EUnauthorized)]
fun test_unauthorized_complete() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let wrong_cap = call_cap::new_individual_cap(scenario.ctx()); // Different cap
    let recipient_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);
    let result = create_test_result(84);

    let mut call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    // Start child batch (Active → Creating)
    call.new_child_batch(&callee_cap, 1);

    // create a child call
    let mut child_call = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut call,
        &callee_cap,
        object::id_address(&child_callee_cap),
        create_test_param(42), // Use a new param since original is moved
        true,
        scenario.ctx(),
    );

    child_call.complete(&child_callee_cap, result);
    let (_, _, _) = call::destroy_child(
        &mut call,
        &callee_cap,
        child_call,
    );

    // Try to complete with wrong capability - should fail with EUnauthorized
    call.complete(&wrong_cap, result);

    test_utils::destroy(call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(wrong_cap);
    test_utils::destroy(recipient_cap);
    test_utils::destroy(child_callee_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::EUnauthorized)]
fun test_unauthorized_destroy() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let recipient_cap = call_cap::new_individual_cap(scenario.ctx());
    let wrong_cap = call_cap::new_individual_cap(scenario.ctx()); // Different cap
    let param = create_test_param(42);
    let result = create_test_result(84);

    let mut call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    call.complete(&callee_cap, result);

    // Try to destroy with wrong capability - should fail with EUnauthorized
    let (_, _, _) = call.destroy(&wrong_cap);

    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(recipient_cap);
    test_utils::destroy(wrong_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::EUnauthorized)]
fun test_unauthorized_create_child() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let wrong_cap = call_cap::new_individual_cap(scenario.ctx()); // Different cap
    let child_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let recipient_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    let mut parent_call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    // Start child batch (Active → Creating) with correct cap first
    parent_call.new_child_batch(&callee_cap, 1);

    // Try to create child with wrong capability - should fail with EUnauthorized
    let child_call = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut parent_call,
        &wrong_cap, // Wrong cap
        object::id_address(&child_callee_cap),
        create_test_param(21),
        false,
        scenario.ctx(),
    );

    test_utils::destroy(child_call);
    test_utils::destroy(parent_call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(wrong_cap);
    test_utils::destroy(child_callee_cap);
    test_utils::destroy(recipient_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::EUnauthorized)]
fun test_unauthorized_destroy_child() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let wrong_cap = call_cap::new_individual_cap(scenario.ctx()); // Different cap
    let child_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let recipient_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    let mut parent_call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    // Start child batch (Active → Creating)
    parent_call.new_child_batch(&callee_cap, 1);

    let mut child_call = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut parent_call,
        &callee_cap,
        object::id_address(&child_callee_cap),
        create_test_param(21),
        true, // last child in batch (Creating → Waiting)
        scenario.ctx(),
    );

    child_call.complete(&child_callee_cap, create_test_result(42));

    // Try to destroy child with wrong capability - should fail with EUnauthorized
    let (_, _, _) = call::destroy_child(&mut parent_call, &wrong_cap, child_call);

    test_utils::destroy(parent_call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(wrong_cap);
    test_utils::destroy(child_callee_cap);
    test_utils::destroy(recipient_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::EUnauthorized)]
fun test_unauthorized_new_child_batch() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let wrong_cap = call_cap::new_individual_cap(scenario.ctx()); // Different cap
    let param = create_test_param(42);

    let mut call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    // Verify call is in Active status initially
    assert!(call.status().is_active(), 0);

    // Try to start child batch with wrong capability - should fail with EUnauthorized
    call.new_child_batch(&wrong_cap, 1);

    test_utils::destroy(call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(wrong_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::ECallNotRoot)]
fun test_destroy_non_root_call() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let recipient_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    let mut parent_call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    parent_call.new_child_batch(&callee_cap, 1);

    let mut child_call = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut parent_call,
        &callee_cap,
        object::id_address(&child_callee_cap),
        create_test_param(21),
        false,
        scenario.ctx(),
    );

    child_call.complete(&child_callee_cap, create_test_result(42));

    // Try to destroy child call directly (not as child) - should fail with EInvalidParent
    let (_, _, _) = child_call.destroy(&callee_cap);

    test_utils::destroy(parent_call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(child_callee_cap);
    test_utils::destroy(recipient_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::EInvalidParent)]
fun test_destroy_child_with_wrong_parent() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let recipient_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    // Create two separate parent calls
    let mut parent_call1 = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    let mut parent_call2 = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        create_test_param(84),
        scenario.ctx(),
    );

    parent_call1.new_child_batch(&callee_cap, 1);
    parent_call2.new_child_batch(&callee_cap, 1);

    let mut child_call1 = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut parent_call1,
        &callee_cap,
        object::id_address(&child_callee_cap),
        create_test_param(21),
        true,
        scenario.ctx(),
    );
    let child_call2 = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut parent_call2,
        &callee_cap,
        object::id_address(&child_callee_cap),
        create_test_param(21),
        true,
        scenario.ctx(),
    );
    child_call1.complete(&child_callee_cap, create_test_result(42));

    // Try to destroy child with wrong parent - should fail with EInvalidParent
    let (_, _, _) = call::destroy_child(&mut parent_call2, &callee_cap, child_call1);

    test_utils::destroy(parent_call1);
    test_utils::destroy(parent_call2);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(child_callee_cap);
    test_utils::destroy(recipient_cap);
    test_utils::destroy(child_call2);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::ECallNotCompleted)]
fun test_destroy_creating_call() {
    destroy_uncompleted_call(false, false);
}

#[test]
#[expected_failure(abort_code = call::ECallNotCompleted)]
fun test_destroy_waiting_call() {
    destroy_uncompleted_call(true, false);
}

#[test]
#[expected_failure(abort_code = call::ECallNotCompleted)]
fun test_destroy_active_call() {
    destroy_uncompleted_call(true, true);
}

fun destroy_uncompleted_call(is_batch_finalized: bool, destroy_child: bool) {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let recipient_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    let mut call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    // Start child batch (Active → Creating) before creating child
    call.new_child_batch(&callee_cap, 1);

    let mut child_call = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut call,
        &callee_cap,
        object::id_address(&child_callee_cap),
        create_test_param(21),
        is_batch_finalized,
        scenario.ctx(),
    );

    if (is_batch_finalized && destroy_child) {
        child_call.complete(&child_callee_cap, create_test_result(42));
        call.destroy_child(&callee_cap, child_call);
    } else {
        test_utils::destroy(child_call);
    };

    // Try to destroy without completing - should fail with ECallNotCompleted (callee destroys one-way calls)
    let (_, _, _) = call.destroy(&callee_cap);

    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(recipient_cap);
    test_utils::destroy(child_callee_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::ECallNotCompleted)]
fun test_destroy_uncompleted_child_while_waiting() {
    destroy_child_uncompleted(false, true);
}

#[test]
#[expected_failure(abort_code = call::ECallNotWaiting)]
fun test_destroy_child_while_not_waiting() {
    destroy_child_uncompleted(true, false);
}

fun destroy_child_uncompleted(is_child_completed: bool, is_parent_batch_finalized: bool) {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let recipient_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    let mut parent_call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    parent_call.new_child_batch(&callee_cap, 1);

    let mut child_call = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut parent_call,
        &callee_cap,
        object::id_address(&child_callee_cap),
        create_test_param(21),
        is_parent_batch_finalized,
        scenario.ctx(),
    );

    if (!is_parent_batch_finalized && is_child_completed) {
        child_call.complete(&child_callee_cap, create_test_result(42));
    };

    // Try to destroy child without completing - should fail with ECallNotCompleted
    let (_, _, _) = call::destroy_child(&mut parent_call, &callee_cap, child_call);

    test_utils::destroy(parent_call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(child_callee_cap);
    test_utils::destroy(recipient_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::ECallNotActive)]
fun test_complete_creating_call() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);
    let result = create_test_result(84);

    let mut call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    call.new_child_batch(&callee_cap, 1);

    let child_call = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut call,
        &callee_cap,
        object::id_address(&child_callee_cap),
        create_test_param(21),
        false,
        scenario.ctx(),
    );

    // Try to complete while still in Creating status - should fail with ECallNotActive
    call.complete(&callee_cap, result);

    test_utils::destroy(call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(child_callee_cap);
    test_utils::destroy(child_call);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::ECallNotActive)]
fun test_complete_wating_call_with_undestroyed_child() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);
    let result = create_test_result(84);

    let mut call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    call.new_child_batch(&callee_cap, 1);

    let mut child_call = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut call,
        &callee_cap,
        object::id_address(&child_callee_cap),
        create_test_param(21),
        true,
        scenario.ctx(),
    );

    child_call.complete(&child_callee_cap, result);

    // Try to complete while still in Creating status - should fail with ECallNotActive
    call.complete(&callee_cap, result);

    test_utils::destroy(call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(child_callee_cap);
    test_utils::destroy(child_call);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::ECallNotActive)]
fun test_complete_completed_call() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let recipient_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);
    let result = create_test_result(84);

    let mut call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    call.new_child_batch(&callee_cap, 1);

    let mut child_call = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut call,
        &callee_cap,
        object::id_address(&child_callee_cap),
        create_test_param(21),
        true,
        scenario.ctx(),
    );

    child_call.complete(&child_callee_cap, result);
    call.destroy_child(&callee_cap, child_call);

    call.complete(&callee_cap, result);
    // Try to complete already completed call - should fail with ECallNotActive
    call.complete(&callee_cap, result);

    test_utils::destroy(call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(recipient_cap);
    test_utils::destroy(child_callee_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::ECallNotCreating)]
fun test_create_child_when_parent_is_active() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    let mut parent_call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    // Try to create child when parent is in Active status (should fail)
    let child_call = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut parent_call,
        &callee_cap,
        object::id_address(&child_callee_cap),
        create_test_param(21),
        false,
        scenario.ctx(),
    );

    test_utils::destroy(child_call);
    test_utils::destroy(parent_call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(child_callee_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::ECallNotCreating)]
fun test_create_child_when_parent_is_waiting() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    let mut parent_call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    // Transition to Creating then Waiting
    parent_call.new_child_batch(&callee_cap, 1);
    let first_child = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut parent_call,
        &callee_cap,
        object::id_address(&child_callee_cap),
        create_test_param(21),
        true, // is_last=true transitions parent to Waiting
        scenario.ctx(),
    );

    // Try to create another child when parent is in Waiting status (should fail)
    let second_child = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut parent_call,
        &callee_cap,
        object::id_address(&child_callee_cap),
        create_test_param(22),
        false,
        scenario.ctx(),
    );

    test_utils::destroy(first_child);
    test_utils::destroy(second_child);
    test_utils::destroy(parent_call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(child_callee_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::ECallNotCreating)]
fun test_create_child_when_parent_is_completed() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    let mut parent_call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    // Complete the parent call
    parent_call.complete(&callee_cap, create_test_result(84));

    // Try to create child when parent is in Completed status (should fail)
    let child_call = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut parent_call,
        &callee_cap,
        object::id_address(&child_callee_cap),
        create_test_param(21),
        false,
        scenario.ctx(),
    );

    test_utils::destroy(child_call);
    test_utils::destroy(parent_call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(child_callee_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::EInvalidChild)]
fun test_destroy_child_in_wrong_order() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child1_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child2_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    let mut parent_call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    // Start child batch and create two children
    parent_call.new_child_batch(&callee_cap, 1);

    let mut child1_call = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut parent_call,
        &callee_cap,
        object::id_address(&child1_callee_cap),
        create_test_param(21),
        false,
        scenario.ctx(),
    );

    let mut child2_call = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut parent_call,
        &callee_cap,
        object::id_address(&child2_callee_cap),
        create_test_param(22),
        true, // is_last=true
        scenario.ctx(),
    );

    // Complete both children
    child1_call.complete(&child1_callee_cap, create_test_result(42));
    child2_call.complete(&child2_callee_cap, create_test_result(44));

    // Try to destroy child2 first (should fail - must destroy in FIFO order: child1 first)
    let (_, _, _) = call::destroy_child(&mut parent_call, &callee_cap, child2_call);

    test_utils::destroy(child1_call);
    test_utils::destroy(parent_call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(child1_callee_cap);
    test_utils::destroy(child2_callee_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::EInvalidNonce)]
fun test_new_child_batch_with_wrong_nonce() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    let mut call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    // Verify initial batch_nonce is 0
    assert!(call.batch_nonce() == 0, 0);

    // Try to start child batch with wrong nonce (should be 1, but provide 2)
    call.new_child_batch(&callee_cap, 2); // Should fail with EInvalidNonce

    test_utils::destroy(call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::ECallNotActive)]
fun test_new_child_batch_when_creating() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    let mut call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    // Transition to Creating status
    call.new_child_batch(&callee_cap, 1);
    assert!(call.status().is_creating(), 0);

    // Try to start another child batch while in Creating status (should fail)
    call.new_child_batch(&callee_cap, 2); // Should fail with ECallNotActive

    test_utils::destroy(call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(child_callee_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::ECallNotActive)]
fun test_new_child_batch_when_waiting() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    let mut call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    // Transition to Creating then Waiting status
    call.new_child_batch(&callee_cap, 1);
    let child_call = call::create_child<TestParam, TestResult, TestParam, TestResult>(
        &mut call,
        &callee_cap,
        object::id_address(&child_callee_cap),
        create_test_param(21),
        true, // is_last=true transitions to Waiting
        scenario.ctx(),
    );
    assert!(call.status().is_waiting(), 0);

    // Try to start child batch while in Waiting status (should fail)
    call.new_child_batch(&callee_cap, 2); // Should fail with ECallNotActive

    test_utils::destroy(call);
    test_utils::destroy(child_call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(child_callee_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::ECallNotActive)]
fun test_new_child_batch_when_completed() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    let mut call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    // Complete the call
    call.complete(&callee_cap, create_test_result(84));
    assert!(call.status().is_completed(), 0);

    // Try to start child batch when call is Completed (should fail)
    call.new_child_batch(&callee_cap, 1); // Should fail with ECallNotActive

    test_utils::destroy(call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call::EInvalidNonce)]
fun test_create_single_child_more_than_one_batch() {
    let mut scenario = setup();
    let caller_cap = call_cap::new_individual_cap(scenario.ctx());
    let callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child1_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let child2_callee_cap = call_cap::new_individual_cap(scenario.ctx());
    let param = create_test_param(42);

    let mut parent_call = call::create<TestParam, TestResult>(
        &caller_cap,
        object::id_address(&callee_cap),
        true,
        param,
        scenario.ctx(),
    );

    // Create first single child using create_single_child
    let mut child1_call = call::create_single_child<TestParam, TestResult, TestParam, TestResult>(
        &mut parent_call,
        &callee_cap,
        object::id_address(&child1_callee_cap),
        create_test_param(21),
        scenario.ctx(),
    );

    // Complete and destroy first child to return parent to Active
    child1_call.complete(&child1_callee_cap, create_test_result(42));
    call::destroy_child(&mut parent_call, &callee_cap, child1_call);

    // Verify parent is back to Active and batch_nonce is 1
    assert!(parent_call.status().is_active(), 0);
    assert!(parent_call.batch_nonce() == 1, 1);

    // Try to create another single child - this should fail because create_single_child
    // always tries to use batch nonce 1, but the parent call now has batch_nonce = 1,
    // so it expects nonce 2 for the next batch
    let child2_call = call::create_single_child<TestParam, TestResult, TestParam, TestResult>(
        &mut parent_call,
        &callee_cap,
        object::id_address(&child2_callee_cap),
        create_test_param(22),
        scenario.ctx(),
    );

    test_utils::destroy(child2_call);
    test_utils::destroy(parent_call);
    test_utils::destroy(caller_cap);
    test_utils::destroy(callee_cap);
    test_utils::destroy(child1_callee_cap);
    test_utils::destroy(child2_callee_cap);
    clean(scenario);
}
