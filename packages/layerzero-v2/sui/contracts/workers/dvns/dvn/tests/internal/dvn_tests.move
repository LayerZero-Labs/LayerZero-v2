#[test_only]
module dvn::dvn_tests;

use call::{call::Call, call_cap::{Self, CallCap}};
use dvn::{dvn::{Self, DVN}, dvn_info_v1, hashes, multisig, test_signature_utils as sig_utils};
use dvn_call_type::dvn_feelib_get_fee::FeelibGetFeeParam;
use ptb_move_call::{argument, move_call};
use std::{ascii, bcs, type_name};
use sui::{clock::{Self, Clock}, event, test_scenario::{Self, Scenario}, test_utils};
use utils::bytes32;
use worker_common::{worker_common::{Self, AdminCap as WorkerAdminCap}, worker_info_v1};
use worker_registry::worker_registry;

// use endpoint_v2::endpoint_v2::AdminCap; // Not needed, using worker_common::AdminCap

// === Test Constants ===

const OWNER: address = @0xaaa;
const ADMIN: address = @0xbbb;
const ADMIN2: address = @0xccc;
const OAPP: address = @0xddd;
const PRICE_FEED: address = @0xfff;
const WORKER_FEE_LIB: address = @0x111;
const DEPOSIT_ADDRESS: address = @0x222;
const NEW_DEPOSIT_ADDRESS: address = @0x333;
const NEW_PRICE_FEED: address = @0x444;
const NEW_WORKER_FEE_LIB: address = @0x555;
const PTB_BUILDER: address = @0x666;

const VID: u32 = 1001;
const DST_EID: u32 = 102;
const DST_EID_2: u32 = 103;

const DEFAULT_MULTIPLIER_BPS: u16 = 10000;
const NEW_MULTIPLIER_BPS: u16 = 12000;
const DST_MULTIPLIER_BPS: u16 = 11000;
const FLOOR_MARGIN_USD: u128 = 1000000;
const GAS: u256 = 200000;
const NEW_QUORUM: u64 = 2;

fun admin_cap_for(admin_addr: address, scenario: &mut Scenario): WorkerAdminCap {
    scenario.next_tx(admin_addr);
    test_scenario::take_from_address<WorkerAdminCap>(scenario, admin_addr)
}

// Test signers - using dynamically generated public keys
fun signer1(): vector<u8> { sig_utils::signer1() }

fun signer2(): vector<u8> { sig_utils::signer2() }

fun signer3(): vector<u8> { sig_utils::signer3() }

// Clean up helper function for tests
fun clean(dvn: DVN, admin_cap: WorkerAdminCap) {
    test_utils::destroy(dvn);
    test_utils::destroy(admin_cap);
}

// === Mock Objects ===

/// Mock fee library for testing worker call completion
public struct MockFeeLib has key, store {
    id: UID,
    call_cap: CallCap,
}

// === Test Helper Functions ===

fun setup_scenario(): Scenario {
    test_scenario::begin(OWNER)
}

fun create_test_dvn(scenario: &mut Scenario): (DVN, WorkerAdminCap) {
    scenario.next_tx(OWNER);

    let admins = vector[ADMIN];
    let supported_message_libs = vector[]; // Empty supported message libs for test
    let signers = vector[signer1(), signer2()];
    let quorum = 1;
    let worker_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let mut worker_registry = worker_registry::init_for_test(scenario.ctx());

    dvn::create_dvn(
        worker_cap,
        VID,
        DEPOSIT_ADDRESS,
        supported_message_libs,
        PRICE_FEED,
        WORKER_FEE_LIB,
        DEFAULT_MULTIPLIER_BPS,
        admins,
        signers,
        quorum,
        &mut worker_registry,
        scenario.ctx(),
    );

    test_utils::destroy(worker_registry);

    scenario.next_tx(OWNER);
    (test_scenario::take_shared<DVN>(scenario), test_scenario::take_from_address<WorkerAdminCap>(scenario, ADMIN))
}

/// Mock fee library get_fee implementation - completes the call with a mock fee
public fun feelib_get_fee(fee_lib: &MockFeeLib, call: &mut Call<FeelibGetFeeParam, u64>, _ctx: &mut TxContext) {
    let mock_fee = 1000u64;
    call.complete(&fee_lib.call_cap, mock_fee);
}

/// Create test clock with specific timestamp
fun create_test_clock(timestamp_ms: u64, ctx: &mut TxContext): Clock {
    let mut clock = clock::create_for_testing(ctx);
    clock::set_for_testing(&mut clock, timestamp_ms);
    clock
}

// Standard test expiration timestamp (far future)
const TEST_EXPIRATION: u64 = 9999999999;

// === DVN Creation and Basic Configuration Tests ===

#[test]
fun test_create_dvn() {
    let mut scenario = setup_scenario();
    let (dvn, admin_cap) = create_test_dvn(&mut scenario);

    // Verify initial configuration
    assert!(dvn.vid() == VID, 0);
    assert!(dvn.deposit_address() == DEPOSIT_ADDRESS, 1);
    assert!(dvn.price_feed() == PRICE_FEED, 2);
    assert!(dvn.worker_fee_lib() == WORKER_FEE_LIB, 3);
    assert!(dvn.default_multiplier_bps() == DEFAULT_MULTIPLIER_BPS, 4);
    assert!(dvn.is_admin(&admin_cap), 5);
    assert!(!dvn.is_paused(), 6);
    assert!(dvn.quorum() == 1, 7);
    assert!(dvn.signer_count() == 2, 8);
    assert!(dvn.is_signer(signer1()), 9);
    assert!(dvn.is_signer(signer2()), 10);

    clean(dvn, admin_cap);
    scenario.end();
}

#[test]
fun test_create_dvn_with_multiple_admins() {
    let mut scenario = setup_scenario();
    scenario.next_tx(OWNER);

    let admins = vector[ADMIN, ADMIN2];
    let supported_message_libs = vector[]; // Empty supported message libs for test
    let signers = vector[signer1(), signer2(), signer3()];
    let quorum = 2;
    let worker_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let mut worker_registry = worker_registry::init_for_test(scenario.ctx());

    dvn::create_dvn(
        worker_cap,
        VID,
        DEPOSIT_ADDRESS,
        supported_message_libs,
        PRICE_FEED,
        WORKER_FEE_LIB,
        DEFAULT_MULTIPLIER_BPS,
        admins,
        signers,
        quorum,
        &mut worker_registry,
        scenario.ctx(),
    );

    scenario.next_tx(OWNER);
    let dvn = scenario.take_shared<DVN>();

    let admin_cap = admin_cap_for(ADMIN, &mut scenario);
    let admin2_cap = admin_cap_for(ADMIN2, &mut scenario);
    assert!(dvn.is_admin(&admin_cap), 0);
    assert!(dvn.is_admin(&admin2_cap), 1);
    assert!(dvn.quorum() == 2, 2);
    assert!(dvn.signer_count() == 3, 3);

    // Share the DVN object for testing
    clean(dvn, admin_cap);
    test_scenario::return_to_address(ADMIN2, admin2_cap);
    test_utils::destroy(worker_registry);
    scenario.end();
}

#[test]
fun test_create_dvn_will_set_worker_info() {
    let mut scenario = setup_scenario();
    scenario.next_tx(OWNER);

    let admins = vector[ADMIN];
    let supported_message_libs = vector[]; // Empty supported message libs for test
    let signers = vector[signer1(), signer2()];
    let quorum = 2;
    let worker_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let worker_address = worker_cap.id();
    let mut worker_registry = worker_registry::init_for_test(scenario.ctx());

    let dvn_object = dvn::create_dvn(
        worker_cap,
        VID,
        DEPOSIT_ADDRESS,
        supported_message_libs,
        PRICE_FEED,
        WORKER_FEE_LIB,
        DEFAULT_MULTIPLIER_BPS,
        admins,
        signers,
        quorum,
        &mut worker_registry,
        scenario.ctx(),
    );

    let worker_info = worker_registry.get_worker_info(worker_address);
    let worker_info_bytes = worker_info_v1::decode(*worker_info).worker_info();
    let dvn_info = dvn_info_v1::decode(*worker_info_bytes);
    assert!(dvn_info.dvn_object() == dvn_object, 0);

    test_utils::destroy(admin_cap_for(ADMIN, &mut scenario));
    test_utils::destroy(worker_registry);
    scenario.end();
}

// === Admin Only Functions Tests ===

#[test]
fun test_set_admin() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    // Add new admin
    scenario.next_tx(ADMIN);
    dvn.set_admin(&admin_cap, ADMIN2, true, scenario.ctx());
    // Verify SetAdminEvent for adding admin

    let events = event::events_by_type<worker_common::SetAdminEvent>();
    let expected_add_event = worker_common::create_set_admin_event(dvn.test_worker(), ADMIN2, true);
    let last_idx = vector::length(&events) - 1;
    assert!(events[last_idx] == expected_add_event, 1);

    let admin2_cap = admin_cap_for(ADMIN2, &mut scenario);
    assert!(dvn.is_admin(&admin2_cap), 2);
    // Remove admin
    dvn.set_admin(&admin_cap, ADMIN2, false, scenario.ctx());
    assert!(!dvn.is_admin(&admin2_cap), 3);

    // Verify SetAdminEvent for removing admin
    let events2 = event::events_by_type<worker_common::SetAdminEvent>();
    let expected_remove_event = worker_common::create_set_admin_event(dvn.test_worker(), ADMIN2, false);
    let last_idx2 = vector::length(&events2) - 1;
    assert!(events2[last_idx2] == expected_remove_event, 4);

    clean(dvn, admin_cap);
    test_scenario::return_to_address(ADMIN2, admin2_cap);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = worker_common::EWorkerUnauthorized)]
fun test_set_admin_not_admin() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(OWNER); // Not an admin
    let unauthorized_admin_cap = worker_common::create_admin_cap_for_test(scenario.ctx());
    dvn.set_admin(&unauthorized_admin_cap, ADMIN2, true, scenario.ctx());

    clean(dvn, admin_cap);
    test_utils::destroy(unauthorized_admin_cap);
    scenario.end();
}

#[test]
fun test_set_default_multiplier_bps() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    dvn.set_default_multiplier_bps(&admin_cap, NEW_MULTIPLIER_BPS);
    assert!(dvn.default_multiplier_bps() == NEW_MULTIPLIER_BPS, 0);

    // Verify SetDefaultMultiplierBpsEvent
    let events = event::events_by_type<worker_common::SetDefaultMultiplierBpsEvent>();
    assert!(vector::length(&events) == 1, 1);
    let expected_event = worker_common::create_set_default_multiplier_bps_event(dvn.test_worker(), NEW_MULTIPLIER_BPS);
    assert!(events[0] == expected_event, 2);

    clean(dvn, admin_cap);
    scenario.end();
}

#[test]
fun test_set_deposit_address() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    dvn.set_deposit_address(&admin_cap, NEW_DEPOSIT_ADDRESS);
    assert!(dvn.deposit_address() == NEW_DEPOSIT_ADDRESS, 0);

    // Verify SetDepositAddressEvent
    let events = event::events_by_type<worker_common::SetDepositAddressEvent>();
    assert!(vector::length(&events) == 1, 1);
    let expected_event = worker_common::create_set_deposit_address_event(dvn.test_worker(), NEW_DEPOSIT_ADDRESS);
    assert!(events[0] == expected_event, 2);

    clean(dvn, admin_cap);
    scenario.end();
}

#[test]
fun test_set_dst_config() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    dvn.set_dst_config(&admin_cap, DST_EID, GAS, DST_MULTIPLIER_BPS, FLOOR_MARGIN_USD);

    let _dst_config = dvn.dst_config(DST_EID);

    // Verify SetDstConfigEvent
    let events = event::events_by_type<dvn::SetDstConfigEvent>();
    assert!(vector::length(&events) == 1, 0);
    let expected_event = dvn::create_test_set_dst_config_event(
        dvn.worker_cap_address(),
        DST_EID,
        GAS,
        DST_MULTIPLIER_BPS,
        FLOOR_MARGIN_USD,
    );
    assert!(events[0] == expected_event, 1);

    clean(dvn, admin_cap);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = dvn::EEidNotSupported)]
fun test_get_dst_config_not_configured() {
    let mut scenario = setup_scenario();
    let (dvn, admin_cap) = create_test_dvn(&mut scenario);

    // Try to get config for unconfigured EID
    let _ = dvn.dst_config(DST_EID);

    clean(dvn, admin_cap);
    scenario.end();
}

#[test]
fun test_set_price_feed() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    dvn.set_price_feed(&admin_cap, NEW_PRICE_FEED);
    assert!(dvn.price_feed() == NEW_PRICE_FEED, 0);

    // Verify SetPriceFeedEvent
    let events = event::events_by_type<worker_common::SetPriceFeedEvent>();
    assert!(vector::length(&events) == 1, 1);
    let expected_event = worker_common::create_set_price_feed_event(dvn.test_worker(), NEW_PRICE_FEED);
    assert!(events[0] == expected_event, 2);

    clean(dvn, admin_cap);
    scenario.end();
}

#[test]
fun test_init_ptb_builder_move_calls() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    // Initially PTB builder should not be initialized
    assert!(!dvn.is_ptb_builder_initialized(), 0);

    // Create mock MoveCall objects for get_fee
    let get_fee_arg1 = argument::create_pure(bcs::to_bytes(&ascii::string(b"DVN")));
    let get_fee_arg2 = argument::create_object(@0x123);
    let get_fee_args = vector[get_fee_arg1, get_fee_arg2];
    let get_fee_type_args = vector[type_name::get<u64>()];

    let get_fee_move_call = move_call::create(
        @0x1234567890abcdef,
        ascii::string(b"fee_module"),
        ascii::string(b"calculate_fee"),
        get_fee_args,
        get_fee_type_args,
        true, // is_builder_call (requires simulation)
        vector[bytes32::zero_bytes32()], // result_ids
    );
    let get_fee_move_calls = vector[get_fee_move_call];

    // Create mock MoveCall objects for assign_job
    let assign_job_arg1 = argument::create_pure(bcs::to_bytes(&100u64));
    let assign_job_arg2 = argument::create_nested_result(0, 1);
    let assign_job_args = vector[assign_job_arg1, assign_job_arg2];
    let assign_job_type_args = vector[];

    let assign_job_move_call = move_call::create(
        @0xabcdef1234567890,
        ascii::string(b"job_module"),
        ascii::string(b"assign_job"),
        assign_job_args,
        assign_job_type_args,
        false, // is_builder_call (final call, direct execution)
        vector[], // result_ids
    );
    let assign_job_move_calls = vector[assign_job_move_call];

    // Call the init function and get the returned Call object
    let call = dvn.init_ptb_builder_move_calls(
        &admin_cap,
        PTB_BUILDER,
        get_fee_move_calls,
        assign_job_move_calls,
        scenario.ctx(),
    );

    // Verify the Call object properties
    assert!(call.caller() == dvn.worker_cap_address(), 1);
    assert!(call.callee() == PTB_BUILDER, 2);
    assert!(call.is_root(), 3); // Root call since it's created directly
    assert!(call.one_way(), 4); // One-way call since return type is Void

    // PTB builder should now be initialized
    assert!(dvn.is_ptb_builder_initialized(), 5);

    // Clean up
    test_utils::destroy(call);

    clean(dvn, admin_cap);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = dvn::EPtbBuilderAlreadyInitialized)]
fun test_init_ptb_builder_move_calls_twice() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);

    // Create mock MoveCall objects
    let get_fee_arg = argument::create_pure(bcs::to_bytes(&ascii::string(b"DVN")));
    let get_fee_args = vector[get_fee_arg];
    let get_fee_type_args = vector[type_name::get<u64>()];

    let get_fee_move_call = move_call::create(
        @0x1234567890abcdef,
        ascii::string(b"fee_module"),
        ascii::string(b"calculate_fee"),
        get_fee_args,
        get_fee_type_args,
        true,
        vector[bytes32::zero_bytes32()],
    );
    let get_fee_move_calls = vector[get_fee_move_call];

    let assign_job_arg = argument::create_pure(bcs::to_bytes(&100u64));
    let assign_job_args = vector[assign_job_arg];
    let assign_job_type_args = vector[];

    let assign_job_move_call = move_call::create(
        @0xabcdef1234567890,
        ascii::string(b"job_module"),
        ascii::string(b"assign_job"),
        assign_job_args,
        assign_job_type_args,
        false,
        vector[],
    );
    let assign_job_move_calls = vector[assign_job_move_call];

    // First call should succeed
    let call1 = dvn.init_ptb_builder_move_calls(
        &admin_cap,
        PTB_BUILDER,
        get_fee_move_calls,
        assign_job_move_calls,
        scenario.ctx(),
    );
    test_utils::destroy(call1);

    // Second call should fail with EPtbBuilderAlreadyInitialized
    let call2 = dvn.init_ptb_builder_move_calls(
        &admin_cap,
        PTB_BUILDER,
        vector[],
        vector[],
        scenario.ctx(),
    );
    test_utils::destroy(call2);

    clean(dvn, admin_cap);
    scenario.end();
}

#[test]
fun test_set_ptb_builder_move_calls() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);

    // Create mock MoveCall objects for get_fee
    let get_fee_arg1 = argument::create_pure(bcs::to_bytes(&ascii::string(b"DVN")));
    let get_fee_arg2 = argument::create_object(@0x123);
    let get_fee_args = vector[get_fee_arg1, get_fee_arg2];
    let get_fee_type_args = vector[type_name::get<u64>()];

    let get_fee_move_call = move_call::create(
        @0x1234567890abcdef,
        ascii::string(b"fee_module"),
        ascii::string(b"calculate_fee"),
        get_fee_args,
        get_fee_type_args,
        true, // is_builder_call (requires simulation)
        vector[bytes32::zero_bytes32()], // result_ids
    );
    let get_fee_move_calls = vector[get_fee_move_call];

    // Create mock MoveCall objects for assign_job
    let assign_job_arg1 = argument::create_pure(bcs::to_bytes(&100u64));
    let assign_job_arg2 = argument::create_nested_result(0, 1);
    let assign_job_args = vector[assign_job_arg1, assign_job_arg2];
    let assign_job_type_args = vector[];

    let assign_job_move_call = move_call::create(
        @0xabcdef1234567890,
        ascii::string(b"job_module"),
        ascii::string(b"assign_job"),
        assign_job_args,
        assign_job_type_args,
        false, // is_builder_call (final call, direct execution)
        vector[], // result_ids
    );
    let assign_job_move_calls = vector[assign_job_move_call];

    // Call the function and get the returned Call object
    let clock = create_test_clock(1000000, scenario.ctx());
    let call = dvn.set_ptb_builder_move_calls(
        &admin_cap,
        PTB_BUILDER,
        get_fee_move_calls,
        assign_job_move_calls,
        TEST_EXPIRATION,
        sig_utils::sign_set_ptb_builder_move_calls(PTB_BUILDER, get_fee_move_calls, assign_job_move_calls, 1),
        &clock,
        scenario.ctx(),
    );

    // Verify the Call object properties
    assert!(call.caller() == dvn.worker_cap_address(), 0);
    assert!(call.callee() == PTB_BUILDER, 1);
    assert!(call.is_root(), 2); // Root call since it's created directly
    assert!(call.one_way(), 3); // One-way call since return type is Void

    // Clean up
    test_utils::destroy(call);
    clock.destroy_for_testing();

    clean(dvn, admin_cap);
    scenario.end();
}

#[test]
fun test_set_supported_option_types() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    let option_types = vector[1, 2, 3];
    dvn.set_supported_option_types(&admin_cap, DST_EID, option_types);

    let supported = dvn.supported_option_types(DST_EID);
    assert!(supported == option_types, 0);

    // Verify SetSupportedOptionTypesEvent
    let events = event::events_by_type<worker_common::SetSupportedOptionTypesEvent>();
    assert!(vector::length(&events) == 1, 1);
    let expected_event = worker_common::create_set_supported_option_types_event(
        dvn.test_worker(),
        DST_EID,
        option_types,
    );
    assert!(events[0] == expected_event, 2);

    clean(dvn, admin_cap);
    scenario.end();
}

#[test]
fun test_set_worker_fee_lib() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    dvn.set_worker_fee_lib(&admin_cap, NEW_WORKER_FEE_LIB);
    assert!(dvn.worker_fee_lib() == NEW_WORKER_FEE_LIB, 0);

    // Verify SetWorkerFeeLibEvent
    let events = event::events_by_type<worker_common::SetWorkerFeeLibEvent>();
    assert!(vector::length(&events) == 1, 1);
    let expected_event = worker_common::create_set_worker_fee_lib_event(dvn.test_worker(), NEW_WORKER_FEE_LIB);
    assert!(events[0] == expected_event, 2);

    clean(dvn, admin_cap);
    scenario.end();
}

// === Admin with Signatures Functions Tests ===

#[test]
fun test_set_allowlist_with_signatures() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    let clock = create_test_clock(1000000, scenario.ctx());

    dvn.set_allowlist(
        &admin_cap,
        OAPP,
        true,
        TEST_EXPIRATION,
        sig_utils::sign_set_allowlist(OAPP, true, 1),
        &clock,
    );
    assert!(dvn.is_allowlisted(OAPP), 0);

    // Verify SetAllowlistEvent for adding
    let allowlist_events = event::events_by_type<worker_common::SetAllowlistEvent>();
    assert!(vector::length(&allowlist_events) == 1, 1);
    let expected_add_event = worker_common::create_set_allowlist_event(dvn.test_worker(), OAPP, true);
    assert!(allowlist_events[0] == expected_add_event, 2);

    // Test removal
    dvn.set_allowlist(
        &admin_cap,
        OAPP,
        false,
        TEST_EXPIRATION,
        sig_utils::sign_set_allowlist(OAPP, false, 1),
        &clock,
    );
    assert!(!dvn.is_allowlisted(OAPP), 3);

    // Verify SetAllowlistEvent for removal
    let allowlist_events2 = event::events_by_type<worker_common::SetAllowlistEvent>();
    assert!(vector::length(&allowlist_events2) == 2, 4);
    let expected_remove_event = worker_common::create_set_allowlist_event(dvn.test_worker(), OAPP, false);
    assert!(allowlist_events2[1] == expected_remove_event, 5);

    test_scenario::return_shared(dvn);
    test_scenario::return_to_address(ADMIN, admin_cap);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = dvn::EExpiredSignature)]
fun test_set_allowlist_expired_signature() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    let clock = create_test_clock(2000000, scenario.ctx()); // Current time > expiration

    // Using a signature that was created with past expiration
    // This will fail because current time (2000000) > expiration (1000)
    dvn.set_allowlist(&admin_cap, OAPP, true, 1000, sig_utils::sign_set_allowlist_expired(OAPP, true, 1), &clock);

    clean(dvn, admin_cap);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_set_denylist_with_signatures() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    let clock = create_test_clock(1000000, scenario.ctx());

    dvn.set_denylist(&admin_cap, OAPP, true, TEST_EXPIRATION, sig_utils::sign_set_denylist(OAPP, true, 1), &clock);
    assert!(dvn.is_denylisted(OAPP), 0);

    // Verify SetDenylistEvent for adding
    let denylist_events = event::events_by_type<worker_common::SetDenylistEvent>();
    assert!(vector::length(&denylist_events) == 1, 1);
    let expected_add_event = worker_common::create_set_denylist_event(dvn.test_worker(), OAPP, true);
    assert!(denylist_events[0] == expected_add_event, 2);

    // Test removal
    dvn.set_denylist(
        &admin_cap,
        OAPP,
        false,
        TEST_EXPIRATION,
        sig_utils::sign_set_denylist(OAPP, false, 1),
        &clock,
    );
    assert!(!dvn.is_denylisted(OAPP), 3);

    // Verify SetDenylistEvent for removal
    let denylist_events2 = event::events_by_type<worker_common::SetDenylistEvent>();
    assert!(vector::length(&denylist_events2) == 2, 4);
    let expected_remove_event = worker_common::create_set_denylist_event(dvn.test_worker(), OAPP, false);
    assert!(denylist_events2[1] == expected_remove_event, 5);

    clean(dvn, admin_cap);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_set_paused_with_signatures() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    let clock = create_test_clock(1000000, scenario.ctx());

    dvn.set_paused(&admin_cap, true, TEST_EXPIRATION, sig_utils::sign_set_paused(true, 1), &clock);
    assert!(dvn.is_paused(), 0);

    // Verify PausedEvent
    let paused_events = event::events_by_type<worker_common::PausedEvent>();
    assert!(vector::length(&paused_events) == 1, 1);
    let expected_paused_event = worker_common::create_paused_event(dvn.test_worker());
    assert!(paused_events[0] == expected_paused_event, 2);

    // Test unpause
    dvn.set_paused(&admin_cap, false, TEST_EXPIRATION, sig_utils::sign_set_paused(false, 1), &clock);
    assert!(!dvn.is_paused(), 3);

    // Verify UnpausedEvent
    let unpaused_events = event::events_by_type<worker_common::UnpausedEvent>();
    assert!(vector::length(&unpaused_events) == 1, 4);
    let expected_unpaused_event = worker_common::create_unpaused_event(dvn.test_worker());
    assert!(unpaused_events[0] == expected_unpaused_event, 5);

    clean(dvn, admin_cap);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_set_quorum_with_signatures() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    let clock = create_test_clock(1000000, scenario.ctx());

    dvn.set_quorum(&admin_cap, NEW_QUORUM, TEST_EXPIRATION, sig_utils::sign_set_quorum(NEW_QUORUM, 1), &clock);
    assert!(dvn.quorum() == NEW_QUORUM, 0);

    test_scenario::return_shared(dvn);
    test_scenario::return_to_address(ADMIN, admin_cap);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = multisig::ESignersSizeIsLessThanQuorum)]
fun test_set_quorum_too_high() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    let clock = create_test_clock(1000000, scenario.ctx());

    // Try to set quorum higher than number of signers (2)
    dvn.set_quorum(&admin_cap, 3, TEST_EXPIRATION, sig_utils::sign_set_quorum(3, 1), &clock);

    clean(dvn, admin_cap);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_set_signer_with_signatures() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    let clock = create_test_clock(1000000, scenario.ctx());

    // Add new signer
    dvn.set_dvn_signer(
        &admin_cap,
        signer3(),
        true,
        TEST_EXPIRATION,
        sig_utils::sign_set_signer(signer3(), true, 1),
        &clock,
    );
    assert!(dvn.is_signer(signer3()), 0);
    assert!(dvn.signer_count() == 3, 1);

    // Remove signer
    dvn.set_dvn_signer(
        &admin_cap,
        signer3(),
        false,
        TEST_EXPIRATION,
        sig_utils::sign_set_signer(signer3(), false, 1),
        &clock,
    );
    assert!(!dvn.is_signer(signer3()), 2);
    assert!(dvn.signer_count() == 2, 3);

    clean(dvn, admin_cap);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = dvn::EHashAlreadyUsed)]
fun test_signature_replay_protection() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    let clock = create_test_clock(1000000, scenario.ctx());

    // First call should succeed
    let sig = sig_utils::sign_set_allowlist(OAPP, true, 1);
    dvn.set_allowlist(&admin_cap, OAPP, true, TEST_EXPIRATION, sig, &clock);

    // Second call with same parameters should fail due to hash already used
    dvn.set_allowlist(&admin_cap, OAPP, true, TEST_EXPIRATION, sig, &clock);

    clean(dvn, admin_cap);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_verify_with_signatures() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);

    let packet_header = x"0123456789abcdef";
    let payload_hash = bytes32::from_bytes(x"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef");
    let confirmations = 15u64;
    let clock = create_test_clock(1000000, scenario.ctx());

    let uln302_address = @0x1234567890abcdef1234567890abcdef12345678;

    let verify_call = dvn.verify(
        &admin_cap,
        uln302_address,
        packet_header,
        payload_hash,
        confirmations,
        TEST_EXPIRATION,
        sig_utils::sign_verify(packet_header, payload_hash.to_bytes(), confirmations, uln302_address, 1),
        &clock,
        scenario.ctx(),
    );

    test_utils::destroy(verify_call);
    clean(dvn, admin_cap);
    clock.destroy_for_testing();
    scenario.end();
}

// === Message Library Management Tests ===

#[test]
fun test_set_supported_message_lib_basic() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    let clock = create_test_clock(1000000, scenario.ctx());

    let test_message_lib = @0x123456;

    // Initially the message lib should not be supported
    assert!(!dvn.test_worker().is_supported_message_lib(test_message_lib), 0);

    // Add the message lib using the actual function with signatures
    dvn.set_supported_message_lib(
        &admin_cap,
        test_message_lib,
        true,
        TEST_EXPIRATION,
        sig_utils::sign_set_supported_message_lib(test_message_lib, true, 1),
        &clock,
    );

    // Verify it's now supported
    assert!(dvn.test_worker().is_supported_message_lib(test_message_lib), 1);

    // Remove the message lib using the actual function with signatures
    dvn.set_supported_message_lib(
        &admin_cap,
        test_message_lib,
        false,
        TEST_EXPIRATION,
        sig_utils::sign_set_supported_message_lib(test_message_lib, false, 1),
        &clock,
    );

    // Verify it's no longer supported
    assert!(!dvn.test_worker().is_supported_message_lib(test_message_lib), 2);

    clean(dvn, admin_cap);
    clock.destroy_for_testing();
    scenario.end();
}

// === Signatures Only Functions Tests ===

#[test]
fun test_quorum_change_admin() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(OWNER); // Anyone can call this function
    let clock = create_test_clock(1000000, scenario.ctx());

    dvn.quorum_change_admin(
        ADMIN2,
        true,
        TEST_EXPIRATION,
        sig_utils::sign_quorum_change_admin(ADMIN2, true, 1),
        &clock,
        scenario.ctx(),
    );
    let admin2_cap = admin_cap_for(ADMIN2, &mut scenario);
    assert!(dvn.is_admin(&admin2_cap), 0);

    // Remove admin
    dvn.quorum_change_admin(
        ADMIN2,
        false,
        TEST_EXPIRATION,
        sig_utils::sign_quorum_change_admin(ADMIN2, false, 1),
        &clock,
        scenario.ctx(),
    );
    assert!(!dvn.is_admin(&admin2_cap), 1);

    clean(dvn, admin_cap);
    test_scenario::return_to_address(ADMIN2, admin2_cap);
    clock.destroy_for_testing();
    scenario.end();
}

// === View Functions Tests ===

#[test]
fun test_view_functions() {
    let mut scenario = setup_scenario();
    let (dvn, admin_cap) = create_test_dvn(&mut scenario);

    // Test allowlist size
    assert!(dvn.allowlist_size() == 0, 0);

    // Test has_acl (should return true when allowlist is empty)
    assert!(dvn.has_acl(OAPP), 1);

    // Test signers
    let signers = dvn.signers();
    assert!(signers.length() == 2, 2);
    let signer1_addr = signer1();
    let signer2_addr = signer2();
    assert!(signers.contains(&signer1_addr), 3);
    assert!(signers.contains(&signer2_addr), 4);

    clean(dvn, admin_cap);
    scenario.end();
}

// === Edge Cases and Error Conditions ===

#[test]
fun test_multiple_dst_configs() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);

    // Set multiple destination configs
    dvn.set_dst_config(&admin_cap, DST_EID, GAS, DST_MULTIPLIER_BPS, FLOOR_MARGIN_USD);
    let gas2 = GAS + 100000;
    let multiplier2 = DST_MULTIPLIER_BPS + 1000;
    let floor2 = FLOOR_MARGIN_USD + 500000;
    dvn.set_dst_config(&admin_cap, DST_EID_2, gas2, multiplier2, floor2);

    // Verify both configs exist
    let _config1 = dvn.dst_config(DST_EID);
    let _config2 = dvn.dst_config(DST_EID_2);

    // The fact that dst_config() doesn't abort means both configs were set successfully

    clean(dvn, admin_cap);
    scenario.end();
}

#[test]
fun test_acl_combinations() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    let clock = create_test_clock(1000000, scenario.ctx());

    // Initially, all addresses have ACL (empty allowlist)
    assert!(dvn.has_acl(OAPP), 0);
    assert!(dvn.has_acl(@0x999), 1);

    // Add to allowlist
    dvn.set_allowlist(
        &admin_cap,
        OAPP,
        true,
        TEST_EXPIRATION,
        sig_utils::sign_set_allowlist(OAPP, true, 1),
        &clock,
    );

    // Now only allowlisted addresses have ACL
    assert!(dvn.has_acl(OAPP), 2);
    assert!(!dvn.has_acl(@0x999), 3);

    // Add to denylist (should not affect allowlist behavior)
    dvn.set_denylist(
        &admin_cap,
        @0x888,
        true,
        TEST_EXPIRATION,
        sig_utils::sign_set_denylist(@0x888, true, 1),
        &clock,
    );

    // Denylisted address should not have ACL
    assert!(!dvn.has_acl(@0x888), 4);

    clean(dvn, admin_cap);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_admin_self_removal() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    // First add another admin
    scenario.next_tx(ADMIN);
    dvn.set_admin(&admin_cap, ADMIN2, true, scenario.ctx());
    let admin2_cap = admin_cap_for(ADMIN2, &mut scenario);

    // Now admin can remove themselves
    dvn.set_admin(&admin_cap, ADMIN, false, scenario.ctx());
    assert!(!dvn.is_admin(&admin_cap), 0);
    assert!(dvn.is_admin(&admin2_cap), 1);

    clean(dvn, admin_cap);
    test_scenario::return_to_address(ADMIN2, admin2_cap);
    scenario.end();
}

// === Multisig Specific Tests ===

#[test]
#[expected_failure(abort_code = multisig::EQuorumIsZero)]
fun test_set_quorum_zero() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);

    let clock = create_test_clock(1000000, scenario.ctx());

    dvn.set_quorum(&admin_cap, 0, TEST_EXPIRATION, sig_utils::sign_set_quorum(0, 1), &clock);

    test_scenario::return_shared(dvn);
    test_scenario::return_to_address(ADMIN, admin_cap);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = multisig::ESignerAlreadyExists)]
fun test_add_duplicate_signer() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    let clock = create_test_clock(1000000, scenario.ctx());

    // Try to add an existing signer
    dvn.set_dvn_signer(
        &admin_cap,
        signer1(),
        true,
        TEST_EXPIRATION,
        sig_utils::sign_set_signer(signer1(), true, 1),
        &clock,
    );

    clean(dvn, admin_cap);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = multisig::ESignerNotFound)]
fun test_remove_non_existent_signer() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    let clock = create_test_clock(1000000, scenario.ctx());

    // Try to remove a non-existent signer
    dvn.set_dvn_signer(
        &admin_cap,
        signer3(),
        false,
        TEST_EXPIRATION,
        sig_utils::sign_set_signer(signer3(), false, 1),
        &clock,
    );

    clean(dvn, admin_cap);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = multisig::ESignersSizeIsLessThanQuorum)]
fun test_remove_signer_below_quorum() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    let clock = create_test_clock(1000000, scenario.ctx());

    // First increase quorum to 2
    dvn.set_quorum(&admin_cap, 2, TEST_EXPIRATION, sig_utils::sign_set_quorum(2, 1), &clock);

    // Now try to remove a signer (would leave only 1 signer with quorum of 2)
    dvn.set_dvn_signer(
        &admin_cap,
        signer2(),
        false,
        TEST_EXPIRATION,
        sig_utils::sign_set_signer_multi(signer2(), false, vector[1, 2]),
        &clock,
    );

    clean(dvn, admin_cap);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = multisig::EInvalidSignerLength)]
fun test_invalid_signer_length() {
    let mut scenario = setup_scenario();

    scenario.next_tx(OWNER);

    let admins = vector[ADMIN];
    let supported_message_libs = vector[]; // Empty supported message libs for test
    let invalid_signer = x"1234"; // Too short
    let signers = vector[invalid_signer];
    let quorum = 1;
    let worker_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let mut worker_registry = worker_registry::init_for_test(scenario.ctx());

    dvn::create_dvn(
        worker_cap,
        VID,
        DEPOSIT_ADDRESS,
        supported_message_libs,
        PRICE_FEED,
        WORKER_FEE_LIB,
        DEFAULT_MULTIPLIER_BPS,
        admins,
        signers,
        quorum,
        &mut worker_registry,
        scenario.ctx(),
    );

    // This test is expected to fail before DVN is created, so we won't reach here
    // But we need to consume the DVN to satisfy Move's type system
    test_utils::destroy(worker_registry);
    scenario.end();
}

// === Complex Scenario Tests ===

#[test]
fun test_full_lifecycle() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    scenario.next_tx(ADMIN);
    let clock = create_test_clock(1000000, scenario.ctx());

    // 1. Configure destination
    dvn.set_dst_config(&admin_cap, DST_EID, GAS, DST_MULTIPLIER_BPS, FLOOR_MARGIN_USD);

    // 2. Add new admin
    dvn.set_admin(&admin_cap, ADMIN2, true, scenario.ctx());
    let admin2_cap = admin_cap_for(ADMIN2, &mut scenario);

    // 3. Update multisig configuration
    dvn.set_dvn_signer(
        &admin_cap,
        signer3(),
        true,
        TEST_EXPIRATION,
        sig_utils::sign_set_signer(signer3(), true, 1),
        &clock,
    );

    dvn.set_quorum(&admin_cap, 2, TEST_EXPIRATION, sig_utils::sign_set_quorum(2, 1), &clock);

    // 4. Configure ACL (need 2 signatures now since quorum=2)
    let allowlist_payload = hashes::build_set_allowlist_payload(OAPP, true, VID, TEST_EXPIRATION);
    let allowlist_sig = sig_utils::sign_payload_with_multiple(
        allowlist_payload,
        vector[1, 2],
    );
    dvn.set_allowlist(&admin_cap, OAPP, true, TEST_EXPIRATION, allowlist_sig, &clock);

    // 5. Verify all configurations
    assert!(dvn.is_admin(&admin2_cap), 0);
    assert!(dvn.signer_count() == 3, 1);
    assert!(dvn.quorum() == 2, 2);
    assert!(dvn.is_allowlisted(OAPP), 3);

    let _config = dvn.dst_config(DST_EID);
    // The fact that dst_config() doesn't abort means the config exists

    clean(dvn, admin_cap);
    test_scenario::return_to_address(ADMIN2, admin2_cap);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_multiple_operations_with_different_admins() {
    let mut scenario = setup_scenario();
    let (mut dvn, admin_cap) = create_test_dvn(&mut scenario);

    // First admin sets up configuration
    scenario.next_tx(ADMIN);
    dvn.set_admin(&admin_cap, ADMIN2, true, scenario.ctx());
    let admin2_cap = admin_cap_for(ADMIN2, &mut scenario);
    dvn.set_dst_config(&admin2_cap, DST_EID, GAS, DST_MULTIPLIER_BPS, FLOOR_MARGIN_USD);

    // Second admin performs operations
    scenario.next_tx(ADMIN2);
    dvn.set_default_multiplier_bps(&admin2_cap, NEW_MULTIPLIER_BPS);
    dvn.set_price_feed(&admin2_cap, NEW_PRICE_FEED);

    // Verify both admins' changes
    assert!(dvn.default_multiplier_bps() == NEW_MULTIPLIER_BPS, 0);
    assert!(dvn.price_feed() == NEW_PRICE_FEED, 1);

    let _config = dvn.dst_config(DST_EID);
    // Cannot access private field directly

    clean(dvn, admin_cap);
    test_scenario::return_to_address(ADMIN2, admin2_cap);
    scenario.end();
}
