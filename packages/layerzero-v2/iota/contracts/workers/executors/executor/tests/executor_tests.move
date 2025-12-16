#[test_only]
module executor::executor_tests;

use call::call_cap;
use executor::{
    executor_info_v1,
    executor_type,
    executor_worker::{Self, Executor, DstConfigSetEvent, NativeDropAppliedEvent},
    native_drop_type::{Self, NativeDropParams}
};
use ptb_move_call::{argument::{Self as argument, Argument}, move_call::{Self as move_call, MoveCall}};
use std::{ascii, type_name};
use iota::{coin, event, iota::IOTA, test_scenario::{Self, Scenario}, test_utils};
use utils::bytes32::{Self, Bytes32};
use worker_common::{
    worker_common::{
        Self,
        OwnerCap,
        AdminCap,
        SetAdminEvent,
        SetAllowlistEvent,
        SetDenylistEvent,
        SetSupportedMessageLibEvent,
        PausedEvent,
        UnpausedEvent
    },
    worker_info_v1
};
use worker_registry::worker_registry;

// === Test Constants ===

const OWNER: address = @0xaaa;
const ADMIN: address = @0xbbb;
const OAPP: address = @0xddd;
const PRICE_FEED: address = @0xfff;
const WORKER_FEE_LIB: address = @0x111;
const DEPOSIT_ADDRESS: address = @0x222;
const MESSAGE_LIB: address = @0x333;

const SRC_EID: u32 = 101;
const DST_EID: u32 = 102;

const DEFAULT_MULTIPLIER_BPS: u16 = 10000;
const TEST_LZ_RECEIVE_BASE_GAS: u64 = 200000;
const TEST_LZ_COMPOSE_BASE_GAS: u64 = 300000;
const TEST_NATIVE_DROP_AMOUNT: u64 = 500000;

// === Test Helper Functions ===

fun setup_scenario(): Scenario {
    test_scenario::begin(OWNER)
}

fun create_test_executor(scenario: &mut Scenario): (Executor, OwnerCap, AdminCap) {
    scenario.next_tx(OWNER);

    let admins = vector[ADMIN];
    let supported_message_libs = vector[]; // Empty vector for test
    let worker_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let mut worker_registry = worker_registry::init_for_test(scenario.ctx());

    executor_worker::create_executor(
        worker_cap,
        DEPOSIT_ADDRESS,
        supported_message_libs,
        PRICE_FEED,
        WORKER_FEE_LIB,
        DEFAULT_MULTIPLIER_BPS,
        OWNER,
        admins,
        &mut worker_registry,
        scenario.ctx(),
    );

    scenario.next_tx(OWNER);
    let executor = test_scenario::take_shared<Executor>(scenario);
    let owner_cap = test_scenario::take_from_sender<OwnerCap>(scenario);
    test_utils::destroy(worker_registry);

    scenario.next_tx(ADMIN);
    let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);

    (executor, owner_cap, admin_cap)
}

fun create_test_dst_config(): executor_type::DstConfig {
    executor_type::create_dst_config(
        TEST_LZ_RECEIVE_BASE_GAS,
        TEST_LZ_COMPOSE_BASE_GAS,
        12000,
        1000000,
        5000000,
    )
}

fun create_test_native_drop_params(): vector<NativeDropParams> {
    let mut params = vector::empty<NativeDropParams>();
    vector::push_back(
        &mut params,
        native_drop_type::new_native_drop_params(@0x1001, TEST_NATIVE_DROP_AMOUNT),
    );
    vector::push_back(
        &mut params,
        native_drop_type::new_native_drop_params(@0x1002, TEST_NATIVE_DROP_AMOUNT * 2),
    );
    params
}

fun clean(scenario: Scenario, executor: Executor, owner_cap: OwnerCap, admin_cap: AdminCap) {
    test_scenario::return_shared(executor);
    test_scenario::return_to_address(OWNER, owner_cap);
    test_scenario::return_to_address(ADMIN, admin_cap);
    scenario.end();
}

#[test]
fun test_complete_executor_functionality() {
    let mut scenario = setup_scenario();
    let (mut executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    // === Test 1: Constructor and Initial State (create_executor) ===
    assert!(executor.deposit_address() == DEPOSIT_ADDRESS, 1);
    assert!(executor.price_feed() == PRICE_FEED, 2);
    assert!(executor.worker_fee_lib() == WORKER_FEE_LIB, 3);
    assert!(executor.default_multiplier_bps() == DEFAULT_MULTIPLIER_BPS, 4);
    assert!(executor.is_admin(&admin_cap), 5);
    assert!(!executor.is_paused(), 6);
    assert!(executor.allowlist_size() == 0, 7);
    assert!(!executor.is_allowlisted(OAPP), 8);
    assert!(!executor.is_denylisted(OAPP), 9);
    assert!(executor.has_acl(OAPP), 10); // Default allows all when no restrictions
    assert!(executor.worker_cap_address() != @0x0, 11);

    // === Test 2: Admin Functions ===
    scenario.next_tx(ADMIN);

    // Test set_dst_config
    let config = create_test_dst_config();
    executor.set_dst_config(&admin_cap, DST_EID, config);
    let retrieved_config = executor.dst_config(DST_EID);
    assert!(retrieved_config.lz_receive_base_gas() == TEST_LZ_RECEIVE_BASE_GAS, 12);

    // Test admin setters
    executor.set_default_multiplier_bps(&admin_cap, 15000);
    assert!(executor.default_multiplier_bps() == 15000, 13);

    let new_deposit = @0x999;
    executor.set_deposit_address(&admin_cap, new_deposit);
    assert!(executor.deposit_address() == new_deposit, 14);

    let new_price_feed = @0x888;
    executor.set_price_feed(&admin_cap, new_price_feed);
    assert!(executor.price_feed() == new_price_feed, 15);

    let new_fee_lib = @0x777;
    executor.set_worker_fee_lib(&admin_cap, new_fee_lib);
    assert!(executor.worker_fee_lib() == new_fee_lib, 16);

    let option_types = vector[1u8, 2u8, 3u8];
    executor.set_supported_option_types(&admin_cap, DST_EID, option_types);
    let retrieved_types = executor.supported_option_types(DST_EID);
    assert!(retrieved_types == option_types, 17);

    // Test native_drop with success
    let params = create_test_native_drop_params();
    let total_drop_amount = TEST_NATIVE_DROP_AMOUNT + (TEST_NATIVE_DROP_AMOUNT * 2); // 500000 + 1000000 = 1500000
    let payment_coin = coin::mint_for_testing<IOTA>(total_drop_amount, scenario.ctx());
    executor.native_drop(
        &admin_cap,
        SRC_EID,
        bytes32::from_address(OAPP),
        DST_EID,
        OAPP,
        1,
        params,
        payment_coin,
        scenario.ctx(),
    );

    // Event verification is done in test_event_emissions

    // === Test 3: Owner Functions ===
    scenario.next_tx(OWNER);

    // Test set_admin
    let new_admin = @0x666;
    executor.set_admin(&owner_cap, new_admin, true, scenario.ctx());
    scenario.next_tx(ADMIN);
    let new_admin_cap = scenario.take_from_address<AdminCap>(new_admin);
    assert!(executor.is_admin(&new_admin_cap), 18);
    executor.set_admin(&owner_cap, new_admin, false, scenario.ctx());
    assert!(!executor.is_admin(&new_admin_cap), 19);
    test_utils::destroy(new_admin_cap);

    // Test set_allowlist
    executor.set_allowlist(&owner_cap, OAPP, true);
    assert!(executor.is_allowlisted(OAPP), 20);
    assert!(executor.allowlist_size() == 1, 21);
    assert!(executor.has_acl(OAPP), 22);

    // Test set_denylist (overrides allowlist)
    executor.set_denylist(&owner_cap, OAPP, true);
    assert!(executor.is_denylisted(OAPP), 23);
    assert!(!executor.has_acl(OAPP), 24); // Denylist overrides allowlist

    // Test set_supported_message_lib
    executor.set_supported_message_lib(&owner_cap, MESSAGE_LIB, true);
    assert!(executor.is_supported_message_lib(MESSAGE_LIB), 25);
    executor.set_supported_message_lib(&owner_cap, MESSAGE_LIB, false);
    assert!(!executor.is_supported_message_lib(MESSAGE_LIB), 26);

    // Test set_paused
    executor.set_paused(&owner_cap, true);
    assert!(executor.is_paused(), 27);
    executor.set_paused(&owner_cap, false);
    assert!(!executor.is_paused(), 28);

    clean(scenario, executor, owner_cap, admin_cap);
}

// === Error Condition Tests ===

#[test]
#[expected_failure(abort_code = executor_worker::EEidNotSupported)]
fun test_dst_config_not_found() {
    let mut scenario = setup_scenario();
    let (executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    executor.dst_config(999); // Non-existent EID

    clean(scenario, executor, owner_cap, admin_cap);
}

#[test]
#[expected_failure(abort_code = executor_worker::EInvalidNativeDropAmount)]
fun test_native_drop_invalid_amount() {
    let mut scenario = setup_scenario();
    let (executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    scenario.next_tx(ADMIN);
    let mut params = vector::empty<NativeDropParams>();
    vector::push_back(&mut params, native_drop_type::new_native_drop_params(@0x1001, 0)); // Invalid amount
    let payment_coin = coin::mint_for_testing<IOTA>(1000000, scenario.ctx());

    executor.native_drop(
        &admin_cap,
        SRC_EID,
        bytes32::from_address(OAPP),
        DST_EID,
        OAPP,
        1,
        params,
        payment_coin,
        scenario.ctx(),
    );

    clean(scenario, executor, owner_cap, admin_cap);
}

#[test]
#[expected_failure(abort_code = worker_common::EWorkerUnauthorized)]
fun test_unauthorized_admin_access() {
    let mut scenario = setup_scenario();
    let (mut executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    // Try to call admin function from unauthorized address
    let unauthorized_user = @0x1234567890abcdef1234567890abcdef12345678;
    scenario.next_tx(unauthorized_user);
    let user_admin_cap = worker_common::create_admin_cap_for_test(scenario.ctx());
    executor.set_default_multiplier_bps(&user_admin_cap, 15000);
    test_utils::destroy(user_admin_cap);

    clean(scenario, executor, owner_cap, admin_cap);
}

#[test]
#[expected_failure(abort_code = worker_common::EWorkerUnauthorized)]
fun test_unauthorized_admin_native_drop() {
    let mut scenario = setup_scenario();
    let (executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    // Try to call native_drop from unauthorized address
    let unauthorized_user = @0x1234567890abcdef1234567890abcdef12345678;
    scenario.next_tx(unauthorized_user);
    let params = create_test_native_drop_params();
    let payment_coin = coin::mint_for_testing<IOTA>(1000000, scenario.ctx());
    let user_admin_cap = worker_common::create_admin_cap_for_test(scenario.ctx());
    executor.native_drop(
        &user_admin_cap,
        SRC_EID,
        bytes32::from_address(OAPP),
        DST_EID,
        OAPP,
        1,
        params,
        payment_coin,
        scenario.ctx(),
    );
    test_utils::destroy(user_admin_cap);

    clean(scenario, executor, owner_cap, admin_cap);
}

// === Edge Case Tests ===

#[test]
fun test_native_drop_edge_cases() {
    let mut scenario = setup_scenario();
    let (executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    // Test 1: Empty params
    let empty_params = vector::empty<NativeDropParams>();
    let payment_coin1 = coin::mint_for_testing<IOTA>(1000000, scenario.ctx());
    executor.native_drop(
        &admin_cap,
        SRC_EID,
        bytes32::from_address(OAPP),
        DST_EID,
        OAPP,
        1,
        empty_params,
        payment_coin1,
        scenario.ctx(),
    );

    // Test 2: Insufficient payment (partial failure)
    let params = create_test_native_drop_params();
    let insufficient_amount = TEST_NATIVE_DROP_AMOUNT / 2; // 250000
    let insufficient_payment = coin::mint_for_testing<IOTA>(insufficient_amount, scenario.ctx());
    executor.native_drop(
        &admin_cap,
        SRC_EID,
        bytes32::from_address(OAPP),
        DST_EID,
        OAPP,
        1,
        params,
        insufficient_payment,
        scenario.ctx(),
    );

    // Test 3: Partial success - enough for first drop but not second
    let params3 = create_test_native_drop_params();
    let partial_amount = TEST_NATIVE_DROP_AMOUNT + 100; // Enough for first (500000) but not second (1000000)
    let partial_payment = coin::mint_for_testing<IOTA>(partial_amount, scenario.ctx());
    executor.native_drop(
        &admin_cap,
        SRC_EID,
        bytes32::from_address(OAPP),
        DST_EID,
        OAPP,
        1,
        params3,
        partial_payment,
        scenario.ctx(),
    );

    clean(scenario, executor, owner_cap, admin_cap);
}

// === Error Condition Tests for Missing Assert Branches ===

#[test]
#[expected_failure(abort_code = worker_common::EWorkerAttemptingToRemoveOnlyAdmin)]
fun test_remove_only_admin() {
    let mut scenario = setup_scenario();
    let (mut executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    scenario.next_tx(OWNER);
    // Try to remove the only admin
    executor.set_admin(&owner_cap, ADMIN, false, scenario.ctx());

    clean(scenario, executor, owner_cap, admin_cap);
}

#[test]
#[expected_failure(abort_code = worker_common::EWorkerPauseStatusUnchanged)]
fun test_pause_status_unchanged() {
    let mut scenario = setup_scenario();
    let (mut executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    scenario.next_tx(OWNER);
    // First pause the executor
    executor.set_paused(&owner_cap, true);

    // Try to pause again - should fail
    executor.set_paused(&owner_cap, true);

    clean(scenario, executor, owner_cap, admin_cap);
}

#[test]
#[expected_failure(abort_code = worker_common::EWorkerAdminAlreadyExists)]
fun test_add_admin_already_exists() {
    let mut scenario = setup_scenario();
    let (mut executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    // Try to add ADMIN again (already exists)
    scenario.next_tx(OWNER);
    executor.set_admin(&owner_cap, ADMIN, true, scenario.ctx());

    clean(scenario, executor, owner_cap, admin_cap);
}

#[test]
#[expected_failure(abort_code = worker_common::EWorkerAlreadyOnAllowlist)]
fun test_add_to_allowlist_already_exists() {
    let mut scenario = setup_scenario();
    let (mut executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    // Add to allowlist first time
    scenario.next_tx(OWNER);
    executor.set_allowlist(&owner_cap, OAPP, true);

    // Try to add to allowlist again (should fail)
    executor.set_allowlist(&owner_cap, OAPP, true);

    clean(scenario, executor, owner_cap, admin_cap);
}

#[test]
#[expected_failure(abort_code = worker_common::EWorkerNotOnAllowlist)]
fun test_remove_from_allowlist_not_exists() {
    let mut scenario = setup_scenario();
    let (mut executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    // Try to remove from allowlist without adding first (should fail)
    scenario.next_tx(OWNER);
    executor.set_allowlist(&owner_cap, OAPP, false);

    clean(scenario, executor, owner_cap, admin_cap);
}

#[test]
#[expected_failure(abort_code = worker_common::EWorkerAlreadyOnDenylist)]
fun test_add_to_denylist_already_exists() {
    let mut scenario = setup_scenario();
    let (mut executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    // Add to denylist first time
    scenario.next_tx(OWNER);
    executor.set_denylist(&owner_cap, OAPP, true);

    // Try to add to denylist again (should fail)
    executor.set_denylist(&owner_cap, OAPP, true);

    clean(scenario, executor, owner_cap, admin_cap);
}

#[test]
#[expected_failure(abort_code = worker_common::EWorkerNotOnDenylist)]
fun test_remove_from_denylist_not_exists() {
    let mut scenario = setup_scenario();
    let (mut executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    // Try to remove from denylist without adding first (should fail)
    scenario.next_tx(OWNER);
    executor.set_denylist(&owner_cap, OAPP, false);

    clean(scenario, executor, owner_cap, admin_cap);
}

#[test]
#[expected_failure(abort_code = worker_common::EWorkerMessageLibAlreadySupported)]
fun test_add_to_supported_message_lib_already_exists() {
    let mut scenario = setup_scenario();
    let (mut executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    // Add to supported message lib first time
    scenario.next_tx(OWNER);
    executor.set_supported_message_lib(&owner_cap, MESSAGE_LIB, true);

    // Try to add to supported message lib again (should fail)
    executor.set_supported_message_lib(&owner_cap, MESSAGE_LIB, true);

    clean(scenario, executor, owner_cap, admin_cap);
}

#[test]
#[expected_failure(abort_code = worker_common::EWorkerMessageLibNotSupported)]
fun test_remove_from_supported_message_lib_not_exists() {
    let mut scenario = setup_scenario();
    let (mut executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    // Try to remove from supported message lib without adding first (should fail)
    scenario.next_tx(OWNER);
    executor.set_supported_message_lib(&owner_cap, MESSAGE_LIB, false);

    clean(scenario, executor, owner_cap, admin_cap);
}

#[test]
#[expected_failure(abort_code = worker_common::EWorkerNoAdminsProvided)]
fun test_create_executor_with_empty_admins() {
    let mut scenario = setup_scenario();

    // Try to create executor with empty admins vector (should fail)
    scenario.next_tx(OWNER);

    let empty_admins = vector::empty<address>();
    let supported_message_libs = vector[]; // Empty vector for test
    let worker_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let mut worker_registry = worker_registry::init_for_test(scenario.ctx());

    executor_worker::create_executor(
        worker_cap,
        DEPOSIT_ADDRESS,
        supported_message_libs,
        PRICE_FEED,
        WORKER_FEE_LIB,
        DEFAULT_MULTIPLIER_BPS,
        OWNER,
        empty_admins,
        &mut worker_registry,
        scenario.ctx(),
    );

    // This should never be reached due to expected failure
    test_utils::destroy(worker_registry);
    scenario.end();
}

#[test]
fun test_create_executor_will_set_worker_info() {
    let mut scenario = setup_scenario();

    // Try to create executor with empty admins vector (should fail)
    scenario.next_tx(OWNER);

    let admins = vector[ADMIN];
    let supported_message_libs = vector[]; // Empty vector for test
    let worker_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let worker_address = worker_cap.id();
    let mut worker_registry = worker_registry::init_for_test(scenario.ctx());

    let executor_object = executor_worker::create_executor(
        worker_cap,
        DEPOSIT_ADDRESS,
        supported_message_libs,
        PRICE_FEED,
        WORKER_FEE_LIB,
        DEFAULT_MULTIPLIER_BPS,
        OWNER,
        admins,
        &mut worker_registry,
        scenario.ctx(),
    );
    let worker_info = worker_registry.get_worker_info(worker_address);
    let worker_info_bytes = worker_info_v1::decode(*worker_info).worker_info();
    let executor_info = executor_info_v1::decode(*worker_info_bytes);
    assert!(executor_info.executor_object() == executor_object, 0);

    // This should never be reached due to expected failure
    test_utils::destroy(worker_registry);
    scenario.end();
}

#[test]
fun test_set_ptb_builder_move_calls_with_real_calls() {
    let mut scenario = setup_scenario();
    let (mut executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    scenario.next_tx(ADMIN);

    // Create fake MoveCall objects
    let target_ptb_builder = @0x1234567890abcdef1234567890abcdef12345678;

    // Create arguments for MoveCall
    let mut arguments = vector::empty<Argument>();
    vector::push_back(&mut arguments, argument::create_object(@0x123));
    vector::push_back(&mut arguments, argument::create_pure(b"test_data"));

    // Create type arguments
    let mut type_arguments = vector::empty<type_name::TypeName>();
    vector::push_back(&mut type_arguments, type_name::get<u64>());

    // Create result IDs
    let mut result_ids = vector::empty<Bytes32>();
    vector::push_back(&mut result_ids, bytes32::zero_bytes32());

    // Create first MoveCall for get_fee
    let get_fee_call = move_call::create(
        @0x999, // package
        ascii::string(b"test_module"), // module_name
        ascii::string(b"get_fee_function"), // function_name
        arguments,
        type_arguments,
        false, // is_builder_call
        result_ids,
    );

    // Create arguments for assign_job call
    let mut assign_arguments = vector::empty<Argument>();
    vector::push_back(&mut assign_arguments, argument::create_object(@0x456));
    vector::push_back(&mut assign_arguments, argument::create_pure(b"assign_data"));

    // Create second MoveCall for assign_job
    let assign_job_call = move_call::create(
        @0x888, // package
        ascii::string(b"job_module"), // module_name
        ascii::string(b"assign_job_function"), // function_name
        assign_arguments,
        vector::empty<type_name::TypeName>(),
        true, // is_builder_call
        vector::empty<Bytes32>(),
    );

    // Create vectors of MoveCall objects
    let mut get_fee_move_calls = vector::empty<MoveCall>();
    vector::push_back(&mut get_fee_move_calls, get_fee_call);

    let mut assign_job_move_calls = vector::empty<MoveCall>();
    vector::push_back(&mut assign_job_move_calls, assign_job_call);

    // Call the actual function with real MoveCall objects
    let returned_call = executor.set_ptb_builder_move_calls(
        &owner_cap,
        target_ptb_builder,
        get_fee_move_calls,
        assign_job_move_calls,
        scenario.ctx(),
    );

    // Verify the return value
    assert!(returned_call.callee() == target_ptb_builder, 0);
    assert!(returned_call.caller() == executor.worker_cap_address(), 1);
    assert!(returned_call.is_root(), 2);
    assert!(returned_call.one_way(), 3);

    // Clean up the returned call
    test_utils::destroy(returned_call);

    clean(scenario, executor, owner_cap, admin_cap);
}

// Test edge cases with different MoveCall configurations
#[test]
fun test_set_ptb_builder_move_calls_edge_cases_real() {
    let mut scenario = setup_scenario();
    let (mut executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    scenario.next_tx(ADMIN);

    let target_ptb_builder = @0xabcdef1234567890abcdef1234567890abcdef12;

    // Test 1: Empty MoveCall vectors
    let empty_get_fee = vector::empty<MoveCall>();
    let empty_assign_job = vector::empty<MoveCall>();

    let call_empty = executor.set_ptb_builder_move_calls(
        &owner_cap,
        target_ptb_builder,
        empty_get_fee,
        empty_assign_job,
        scenario.ctx(),
    );

    // Verify empty case
    assert!(call_empty.callee() == target_ptb_builder, 0);
    assert!(call_empty.caller() == executor.worker_cap_address(), 1);
    test_utils::destroy(call_empty);

    // Test 2: MoveCall with nested results
    let nested_arg = argument::create_nested_result(0, 1);
    let mut nested_arguments = vector::empty<Argument>();
    vector::push_back(&mut nested_arguments, nested_arg);

    let nested_call = move_call::create(
        @0x777,
        ascii::string(b"nested_module"),
        ascii::string(b"nested_function"),
        nested_arguments,
        vector::empty<type_name::TypeName>(),
        false,
        vector::empty<Bytes32>(),
    );

    let mut nested_calls = vector::empty<MoveCall>();
    vector::push_back(&mut nested_calls, nested_call);

    let call_nested = executor.set_ptb_builder_move_calls(
        &owner_cap,
        target_ptb_builder,
        nested_calls,
        vector::empty<MoveCall>(),
        scenario.ctx(),
    );

    // Verify nested case
    assert!(call_nested.callee() == target_ptb_builder, 2);
    test_utils::destroy(call_nested);

    // Test 3: MoveCall with multiple type arguments
    let mut multi_types = vector::empty<type_name::TypeName>();
    vector::push_back(&mut multi_types, type_name::get<u64>());
    vector::push_back(&mut multi_types, type_name::get<bool>());
    vector::push_back(&mut multi_types, type_name::get<address>());

    let multi_type_call = move_call::create(
        @0x666,
        ascii::string(b"multi_module"),
        ascii::string(b"multi_function"),
        vector::empty<Argument>(),
        multi_types,
        true,
        vector::empty<Bytes32>(),
    );

    let mut multi_calls = vector::empty<MoveCall>();
    vector::push_back(&mut multi_calls, multi_type_call);

    let call_multi = executor.set_ptb_builder_move_calls(
        &owner_cap,
        target_ptb_builder,
        vector::empty<MoveCall>(),
        multi_calls,
        scenario.ctx(),
    );

    // Verify multi-type case
    assert!(call_multi.callee() == target_ptb_builder, 3);
    test_utils::destroy(call_multi);

    clean(scenario, executor, owner_cap, admin_cap);
}

// === Event Testing ===

#[test]
fun test_event_emissions() {
    let mut scenario = setup_scenario();
    let (mut executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    // Test DstConfigSetEvent
    let config = create_test_dst_config();
    executor.set_dst_config(&admin_cap, DST_EID, config);
    let config_events = event::events_by_type<DstConfigSetEvent>();
    assert!(vector::length(&config_events) == 1, 0);
    // Verify event content
    let executor_address = executor.worker_cap_address();
    let expected_config_event = executor_worker::create_dst_config_set_event(executor_address, DST_EID, config);
    assert!(config_events[0] == expected_config_event, 1);

    // Test NativeDropAppliedEvent - full success case
    let drop_params = create_test_native_drop_params();
    let total_amount = TEST_NATIVE_DROP_AMOUNT + (TEST_NATIVE_DROP_AMOUNT * 2);
    let payment_coin = coin::mint_for_testing<IOTA>(total_amount, scenario.ctx());
    executor.native_drop(
        &admin_cap,
        SRC_EID,
        bytes32::from_address(OAPP),
        DST_EID,
        OAPP,
        1,
        drop_params,
        payment_coin,
        scenario.ctx(),
    );

    let drop_events = event::events_by_type<NativeDropAppliedEvent>();
    assert!(vector::length(&drop_events) == 1, 2);
    // Verify event content for full success
    let expected_success = vector[true, true];
    let expected_drop_event = executor_worker::create_native_drop_applied_event(
        executor_address,
        SRC_EID,
        bytes32::from_address(OAPP),
        DST_EID,
        OAPP,
        1,
        drop_params,
        expected_success,
    );
    assert!(drop_events[0] == expected_drop_event, 3);

    // Test partial success event
    let drop_params2 = create_test_native_drop_params();
    let partial_payment = coin::mint_for_testing<IOTA>(TEST_NATIVE_DROP_AMOUNT + 100, scenario.ctx());
    executor.native_drop(
        &admin_cap,
        SRC_EID,
        bytes32::from_address(OAPP),
        DST_EID,
        OAPP,
        1,
        drop_params2,
        partial_payment,
        scenario.ctx(),
    );

    let drop_events2 = event::events_by_type<NativeDropAppliedEvent>();
    assert!(vector::length(&drop_events2) >= 1, 4); // Now we have at least 1 event
    // Verify partial success event content
    let expected_partial_success = vector[true, false];
    let expected_partial_event = executor_worker::create_native_drop_applied_event(
        executor_address,
        SRC_EID,
        bytes32::from_address(OAPP),
        DST_EID,
        OAPP,
        1,
        drop_params2,
        expected_partial_success,
    );
    if (vector::length(&drop_events2) > 1) {
        assert!(drop_events2[1] == expected_partial_event, 5);
    };

    // Test empty params event
    let empty_params = vector::empty<NativeDropParams>();
    let payment3 = coin::mint_for_testing<IOTA>(1000000, scenario.ctx());
    executor.native_drop(
        &admin_cap,
        SRC_EID,
        bytes32::from_address(OAPP),
        DST_EID,
        OAPP,
        1,
        empty_params,
        payment3,
        scenario.ctx(),
    );
    let drop_events3 = event::events_by_type<NativeDropAppliedEvent>();
    let expected_empty_success = vector::empty<bool>();
    let expected_empty_event = executor_worker::create_native_drop_applied_event(
        executor_address,
        SRC_EID,
        bytes32::from_address(OAPP),
        DST_EID,
        OAPP,
        1,
        empty_params,
        expected_empty_success,
    );
    assert!(drop_events3[2] == expected_empty_event, 6);

    // Test Worker events with content verification
    scenario.next_tx(OWNER);

    // Test SetAdminEvent
    let new_admin = @0x999;
    executor.set_admin(&owner_cap, new_admin, true, scenario.ctx());
    let admin_events = event::events_by_type<SetAdminEvent>();
    assert!(vector::length(&admin_events) == 1, 7);
    let expected_admin_event = worker_common::create_set_admin_event(
        executor_worker::get_worker_for_testing(&executor),
        new_admin,
        true,
    );
    assert!(admin_events[0] == expected_admin_event, 9);

    // Test SetAllowlistEvent
    executor.set_allowlist(&owner_cap, OAPP, true);
    let allowlist_events = event::events_by_type<SetAllowlistEvent>();
    assert!(vector::length(&allowlist_events) == 1, 10);
    let expected_allowlist_event = worker_common::create_set_allowlist_event(
        executor_worker::get_worker_for_testing(&executor),
        OAPP,
        true,
    );
    assert!(allowlist_events[0] == expected_allowlist_event, 11);

    // Test SetDenylistEvent
    executor.set_denylist(&owner_cap, OAPP, true);
    let denylist_events = event::events_by_type<SetDenylistEvent>();
    assert!(vector::length(&denylist_events) == 1, 8);
    let expected_denylist_event = worker_common::create_set_denylist_event(
        executor_worker::get_worker_for_testing(&executor),
        OAPP,
        true,
    );
    assert!(denylist_events[0] == expected_denylist_event, 12);

    // Test SetSupportedMessageLibEvent
    executor.set_supported_message_lib(&owner_cap, MESSAGE_LIB, true);
    let supported_message_lib_events = event::events_by_type<SetSupportedMessageLibEvent>();
    assert!(vector::length(&supported_message_lib_events) == 1, 13);
    let expected_supported_message_lib_event = worker_common::create_set_supported_message_lib_event(
        executor_worker::get_worker_for_testing(&executor),
        MESSAGE_LIB,
        true,
    );
    assert!(supported_message_lib_events[0] == expected_supported_message_lib_event, 14);

    // Test PausedEvent
    executor.set_paused(&owner_cap, true);
    let pause_events = event::events_by_type<PausedEvent>();
    assert!(vector::length(&pause_events) == 1, 15);
    let expected_pause_event = worker_common::create_paused_event(
        executor_worker::get_worker_for_testing(&executor),
    );
    assert!(pause_events[0] == expected_pause_event, 16);

    // Test UnpausedEvent
    executor.set_paused(&owner_cap, false);
    let unpause_events = event::events_by_type<UnpausedEvent>();
    assert!(vector::length(&unpause_events) == 1, 17);
    let expected_unpause_event = worker_common::create_unpaused_event(
        executor_worker::get_worker_for_testing(&executor),
    );
    assert!(unpause_events[0] == expected_unpause_event, 18);

    clean(scenario, executor, owner_cap, admin_cap);
}

// === Alert Function Tests ===

#[test]
fun test_lz_receive_alert() {
    let mut scenario = setup_scenario();
    let (executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    // Test successful lz_receive_alert call
    let src_eid = SRC_EID;
    let sender = bytes32::from_address(OAPP);
    let nonce = 42u64;
    let receiver = @0x1234567890abcdef1234567890abcdef12345678;
    let guid = bytes32::from_address(@0xabcdef1234567890abcdef1234567890abcdef12);
    let gas = 1000000u64;
    let value = 500000u64;
    let message = b"test message payload";
    let extra_data = b"test extra data";
    let reason = ascii::string(b"Test failure reason");

    // Call the alert function
    executor.lz_receive_alert(
        &admin_cap,
        src_eid,
        sender,
        nonce,
        receiver,
        guid,
        gas,
        value,
        message,
        extra_data,
        reason,
    );

    clean(scenario, executor, owner_cap, admin_cap);
}

#[test]
fun test_lz_compose_alert() {
    let mut scenario = setup_scenario();
    let (executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    // Test successful lz_compose_alert call
    let from = @0x1234567890abcdef1234567890abcdef12345678;
    let to = @0xabcdef1234567890abcdef1234567890abcdef12;
    let guid = bytes32::from_address(@0xfedcba9876543210fedcba9876543210fedcba98);
    let index = 1u16;
    let gas = 2000000u64;
    let value = 750000u64;
    let message = b"test compose message payload";
    let extra_data = b"test compose extra data";
    let reason = ascii::string(b"Test compose failure reason");

    // Call the alert function
    executor.lz_compose_alert(
        &admin_cap,
        from,
        to,
        guid,
        index,
        gas,
        value,
        message,
        extra_data,
        reason,
    );

    clean(scenario, executor, owner_cap, admin_cap);
}

#[test]
#[expected_failure(abort_code = worker_common::EWorkerUnauthorized)]
fun test_lz_receive_alert_unauthorized() {
    let mut scenario = setup_scenario();
    let (executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    // Try to call lz_receive_alert from unauthorized address
    let unauthorized_user = @0x1234567890abcdef1234567890abcdef12345678;
    scenario.next_tx(unauthorized_user);
    let user_admin_cap = worker_common::create_admin_cap_for_test(scenario.ctx());

    executor.lz_receive_alert(
        &user_admin_cap,
        SRC_EID,
        bytes32::from_address(OAPP),
        42u64,
        @0x1234567890abcdef1234567890abcdef12345678,
        bytes32::from_address(@0xabcdef1234567890abcdef1234567890abcdef12),
        1000000u64,
        500000u64,
        b"test message",
        b"test extra data",
        ascii::string(b"Test failure"),
    );

    test_utils::destroy(user_admin_cap);

    clean(scenario, executor, owner_cap, admin_cap);
}

#[test]
#[expected_failure(abort_code = worker_common::EWorkerUnauthorized)]
fun test_lz_compose_alert_unauthorized() {
    let mut scenario = setup_scenario();
    let (executor, owner_cap, admin_cap) = create_test_executor(&mut scenario);

    // Try to call lz_compose_alert from unauthorized address
    let unauthorized_user = @0x1234567890abcdef1234567890abcdef12345678;
    scenario.next_tx(unauthorized_user);
    let user_admin_cap = worker_common::create_admin_cap_for_test(scenario.ctx());

    executor.lz_compose_alert(
        &user_admin_cap,
        @0x1234567890abcdef1234567890abcdef12345678,
        @0xabcdef1234567890abcdef1234567890abcdef12,
        bytes32::from_address(@0xfedcba9876543210fedcba9876543210fedcba98),
        1u16,
        2000000u64,
        750000u64,
        b"test compose message",
        b"test compose extra data",
        ascii::string(b"Test compose failure"),
    );

    test_utils::destroy(user_admin_cap);

    clean(scenario, executor, owner_cap, admin_cap);
}
