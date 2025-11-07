#[test_only]
module uln_302::send_uln_tests;

use endpoint_v2::{message_lib_quote::QuoteParam, message_lib_send::{Self, SendParam}, outbound_packet};
use message_lib_common::fee_recipient;
use iota::{coin, event, iota::IOTA, test_scenario::{Self, Scenario}, test_utils};
use treasury::treasury;
use uln_302::{
    executor_config::{Self, ExecutorConfig},
    oapp_uln_config,
    send_uln::{
        Self,
        SendUln,
        DefaultExecutorConfigSetEvent,
        ExecutorConfigSetEvent,
        DefaultUlnConfigSetEvent,
        UlnConfigSetEvent,
        ExecutorFeePaidEvent,
        DVNFeePaidEvent
    },
    uln_config::{Self, UlnConfig}
};
use uln_common::executor_get_fee;
use utils::bytes32;
use zro::zro::ZRO;

// Test constants
const ALICE: address = @0xa11ce;
const BOB: address = @0xb0b;

const DVN1: address = @0xd001;
const DVN2: address = @0xd002;
const EXECUTOR: address = @0xe001;

const SRC_EID: u32 = 101;
const DST_EID: u32 = 102;

// === Test Helper Functions ===

fun setup_scenario(): Scenario {
    test_scenario::begin(ALICE)
}

fun create_test_send_uln(scenario: &mut Scenario): SendUln {
    send_uln::new_send_uln(scenario.ctx())
}

fun create_test_uln_config(): UlnConfig {
    uln_config::create(
        64, // confirmations
        vector[DVN1], // required DVNs
        vector[DVN2], // optional DVNs
        1, // optional threshold
    )
}

fun create_test_executor_config(): ExecutorConfig {
    executor_config::create(
        1000, // max message size
        EXECUTOR,
    )
}

fun create_test_quote_param(): QuoteParam {
    let packet = outbound_packet::create_for_test(
        1, // nonce
        SRC_EID,
        ALICE, // sender
        DST_EID,
        bytes32::from_address(BOB), // receiver
        b"test message",
    );

    endpoint_v2::message_lib_quote::create_param_for_test(
        packet,
        x"0003", // OPTIONS_TYPE_3 with no worker options (empty type 3 options)
        false, // pay_in_zro
    )
}

fun create_test_send_param(): SendParam {
    let quote_param = create_test_quote_param();
    message_lib_send::create_param_for_test(quote_param)
}

// === Configuration Tests ===

#[test]
fun test_new_send_uln() {
    let mut scenario = setup_scenario();
    let send_uln = create_test_send_uln(&mut scenario);

    // Verify initial state
    assert!(!send_uln.is_supported_eid(DST_EID), 0);

    test_utils::destroy(send_uln);
    test_scenario::end(scenario);
}

#[test]
fun test_set_default_executor_config() {
    let mut scenario = setup_scenario();
    let mut send_uln = create_test_send_uln(&mut scenario);
    let config = create_test_executor_config();

    // Set default config
    send_uln.set_default_executor_config(DST_EID, config);

    // Verify config was set
    let retrieved_config = send_uln.get_default_executor_config(DST_EID);
    assert!(retrieved_config.executor() == EXECUTOR, 0);
    assert!(retrieved_config.max_message_size() == 1000, 1);

    // Verify event emission
    let events = event::events_by_type<DefaultExecutorConfigSetEvent>();
    assert!(events.length() == 1, 2);

    // Check event content
    let expected_event = send_uln::create_default_executor_config_set_event(DST_EID, config);
    assert!(events[0] == expected_event, 3);

    test_utils::destroy(send_uln);
    test_scenario::end(scenario);
}

#[test]
fun test_quote_basic() {
    let mut scenario = setup_scenario();
    let mut send_uln = create_test_send_uln(&mut scenario);

    // Setup basic configuration: 1 required + 1 optional DVN
    send_uln.set_default_executor_config(DST_EID, create_test_executor_config());
    send_uln.set_default_uln_config(DST_EID, create_test_uln_config());

    let quote_param = create_test_quote_param();
    let (executor, executor_param, dvns, dvn_params) = send_uln.quote(&quote_param);

    // Verify basic quote results
    assert!(executor == EXECUTOR, 0);
    assert!(dvns.length() == 2, 1); // required + optional DVNs
    assert!(dvns[0] == DVN1, 2); // required DVN first
    assert!(dvns[1] == DVN2, 3); // optional DVN second
    assert!(dvn_params.length() == 2, 4);

    // Verify executor param details
    assert!(executor_get_fee::sender(&executor_param) == ALICE, 5);
    assert!(executor_get_fee::dst_eid(&executor_param) == DST_EID, 6);

    test_utils::destroy(send_uln);
    test_scenario::end(scenario);
}

#[test]
fun test_quote_multiple_dvns() {
    let mut scenario = setup_scenario();
    let mut send_uln = create_test_send_uln(&mut scenario);

    // Setup complex configuration: 2 required + 2 optional DVNs
    let config = uln_config::create(
        10, // confirmations
        vector[DVN1, DVN2], // 2 required DVNs
        vector[@0x5001, @0x5002], // 2 optional DVNs
        1, // threshold = 1
    );
    send_uln.set_default_executor_config(DST_EID, create_test_executor_config());
    send_uln.set_default_uln_config(DST_EID, config);

    let quote_param = create_test_quote_param();
    let (executor, _executor_param, dvns, dvn_params) = send_uln.quote(&quote_param);

    // Verify multiple DVN results
    assert!(executor == EXECUTOR, 0);
    assert!(dvns.length() == 4, 1); // 2 required + 2 optional
    assert!(dvn_params.length() == 4, 2);

    // Verify DVN ordering (required first, then optional)
    assert!(dvns[0] == DVN1, 3); // first required DVN
    assert!(dvns[1] == DVN2, 4); // second required DVN
    assert!(dvns[2] == @0x5001, 5); // first optional DVN
    assert!(dvns[3] == @0x5002, 6); // second optional DVN

    test_utils::destroy(send_uln);
    test_scenario::end(scenario);
}

#[test]
fun test_confirm_quote_scenarios() {
    let mut scenario = setup_scenario();

    treasury::init_for_test(scenario.ctx());
    scenario.next_tx(ALICE);
    let treasury = scenario.take_shared<treasury::Treasury>();

    // Scenario 1: Complex fee calculation with multiple DVNs
    let quote_param = create_test_quote_param();
    let executor_fee = 100u64;
    let dvn_fees = vector[100u64, 200u64, 200u64, 100u64]; // Total: 600
    let messaging_fee = send_uln::confirm_quote(&quote_param, executor_fee, dvn_fees, &treasury);
    let expected_worker_fee = 700u64; // executor + all DVNs
    let (treasury_native_fee, treasury_zro_fee) = treasury.get_fee(expected_worker_fee, false);
    assert!(messaging_fee.native_fee() == expected_worker_fee + treasury_native_fee, 0);
    assert!(messaging_fee.zro_fee() == treasury_zro_fee, 1);

    // Scenario 2: ZRO payment mode
    let packet = outbound_packet::create_for_test(1, SRC_EID, ALICE, DST_EID, bytes32::from_address(BOB), b"test");
    let quote_param = endpoint_v2::message_lib_quote::create_param_for_test(packet, x"0003", true); // pay_in_zro = true
    let executor_fee = 200u64;
    let dvn_fees = vector[100u64]; // Single DVN
    let messaging_fee = send_uln::confirm_quote(&quote_param, executor_fee, dvn_fees, &treasury);
    let expected_worker_fee = 300u64; // 200 + 100
    let (treasury_native_fee, treasury_zro_fee) = treasury.get_fee(expected_worker_fee, true);
    assert!(messaging_fee.native_fee() == expected_worker_fee + treasury_native_fee, 2);
    assert!(messaging_fee.zro_fee() == treasury_zro_fee, 3);

    test_scenario::return_shared(treasury);
    test_scenario::end(scenario);
}

#[test]
fun test_send_derives_from_quote() {
    let mut scenario = setup_scenario();
    let mut send_uln = create_test_send_uln(&mut scenario);

    // Setup complex config with multiple required and optional DVNs
    let config = uln_config::create(
        64, // confirmations
        vector[DVN1, DVN2], // 2 required DVNs
        vector[@0x5001], // 1 optional DVN
        1, // threshold = 1
    );

    send_uln.set_default_executor_config(DST_EID, create_test_executor_config());
    send_uln.set_default_uln_config(DST_EID, config);

    // Test that send() produces consistent results with quote()
    let quote_param = create_test_quote_param();
    let (quote_executor, _quote_executor_param, quote_dvns, _quote_dvn_params) = send_uln.quote(&quote_param);

    let send_param = create_test_send_param();
    let (send_executor, _send_executor_param, send_dvns, send_dvn_params) = send_uln.send(&send_param);

    // Verify send results are consistent with quote results
    assert!(send_executor == quote_executor, 0);
    assert!(send_executor == EXECUTOR, 1);
    assert!(send_dvns.length() == quote_dvns.length(), 2);
    assert!(send_dvns.length() == 3, 3); // 2 required + 1 optional
    assert!(send_dvn_params.length() == 3, 4);

    // Verify DVN ordering is maintained (required first, then optional)
    assert!(send_dvns[0] == DVN1, 5); // first required
    assert!(send_dvns[1] == DVN2, 6); // second required
    assert!(send_dvns[2] == @0x5001, 7); // optional

    test_utils::destroy(send_uln);
    test_scenario::end(scenario);
}

#[test]
fun test_effective_config_precedence() {
    let mut scenario = setup_scenario();
    let mut send_uln = create_test_send_uln(&mut scenario);

    // Test configuration precedence: OApp-specific config overrides default
    let default_executor = create_test_executor_config();
    let default_uln_config = create_test_uln_config();
    let custom_executor = executor_config::create(2000, @0x7001); // Different executor

    send_uln.set_default_executor_config(DST_EID, default_executor);
    send_uln.set_default_uln_config(DST_EID, default_uln_config);

    // Before setting custom config, should use default
    let effective_before = send_uln.get_effective_executor_config(ALICE, DST_EID);
    assert!(effective_before.executor() == EXECUTOR, 0); // Default executor

    // After setting custom config for ALICE, should use custom
    send_uln.set_executor_config(ALICE, DST_EID, custom_executor);
    let effective_after = send_uln.get_effective_executor_config(ALICE, DST_EID);
    assert!(effective_after.executor() == @0x7001, 1); // Custom executor

    // Different OApp (BOB) should still use default
    let bob_config = send_uln.get_effective_executor_config(BOB, DST_EID);
    assert!(bob_config.executor() == EXECUTOR, 2); // Default executor

    // Verify event emissions (should have 3 events: 2 default configs + 1 executor config)
    let default_exec_events = event::events_by_type<DefaultExecutorConfigSetEvent>();
    let exec_events = event::events_by_type<ExecutorConfigSetEvent>();
    let default_uln_events = event::events_by_type<DefaultUlnConfigSetEvent>();

    assert!(default_exec_events.length() == 1, 3);
    assert!(exec_events.length() == 1, 4);
    assert!(default_uln_events.length() == 1, 5);

    // Check event content
    let expected_default_exec_event = send_uln::create_default_executor_config_set_event(DST_EID, default_executor);
    assert!(default_exec_events[0] == expected_default_exec_event, 6);

    let expected_exec_event = send_uln::create_executor_config_set_event(ALICE, DST_EID, custom_executor);
    assert!(exec_events[0] == expected_exec_event, 7);

    let expected_default_uln_event = send_uln::create_default_uln_config_set_event(DST_EID, default_uln_config);
    assert!(default_uln_events[0] == expected_default_uln_event, 8);

    test_utils::destroy(send_uln);
    test_scenario::end(scenario);
}

#[test]
fun test_edge_case_fee_scenarios() {
    let mut scenario = setup_scenario();

    treasury::init_for_test(scenario.ctx());
    scenario.next_tx(ALICE);
    let treasury = scenario.take_shared<treasury::Treasury>();
    let quote_param = create_test_quote_param();

    // Scenario 1: Only executor charges, DVNs are free
    let executor_fee = 500u64;
    let dvn_fees = vector[0u64, 0u64];
    let messaging_fee = send_uln::confirm_quote(&quote_param, executor_fee, dvn_fees, &treasury);
    let expected_worker_fee = 500u64;
    let (treasury_native_fee, _) = treasury.get_fee(expected_worker_fee, false);
    assert!(messaging_fee.native_fee() == expected_worker_fee + treasury_native_fee, 0);

    // Scenario 2: Everything is free
    let executor_fee = 0u64;
    let dvn_fees = vector[0u64];
    let messaging_fee = send_uln::confirm_quote(&quote_param, executor_fee, dvn_fees, &treasury);
    let expected_worker_fee = 0u64;
    let (treasury_native_fee, treasury_zro_fee) = treasury.get_fee(expected_worker_fee, false);
    assert!(messaging_fee.native_fee() == treasury_native_fee, 1);
    assert!(messaging_fee.zro_fee() == treasury_zro_fee, 2);

    test_scenario::return_shared(treasury);
    test_scenario::end(scenario);
}

#[test]
fun test_confirm_send_with_job_assignment() {
    let mut scenario = setup_scenario();

    treasury::init_for_test(scenario.ctx());
    scenario.next_tx(ALICE);
    let treasury = scenario.take_shared<treasury::Treasury>();

    let send_param = create_test_send_param();

    let executor_result = fee_recipient::create(100u64, EXECUTOR);

    // Shared DVN parameters for both function call and expected event
    let expected_dvns = vector[DVN1, DVN2, @0x5001, @0x5002];
    let expected_fees = vector[100, 200, 300, 400];

    let dvn_results = vector[
        fee_recipient::create(100u64, DVN1),
        fee_recipient::create(200u64, DVN2),
        fee_recipient::create(300u64, @0x5001),
        fee_recipient::create(400u64, @0x5002),
    ];

    // Total fees: 100 + 100 + 200 + 300 + 400 = 1100
    let send_result = send_uln::confirm_send(
        &send_param,
        EXECUTOR,
        executor_result,
        expected_dvns,
        dvn_results,
        &treasury,
    );

    let messaging_fee = message_lib_send::fee(&send_result);
    let expected_worker_fee = 1100u64;
    let (treasury_native_fee, _) = treasury.get_fee(expected_worker_fee, false);

    assert!(messaging_fee.native_fee() == expected_worker_fee + treasury_native_fee, 0);

    // Verify events were emitted
    let executor_events = event::events_by_type<ExecutorFeePaidEvent>();
    let dvn_events = event::events_by_type<DVNFeePaidEvent>();

    assert!(executor_events.length() == 1, 1);
    assert!(dvn_events.length() == 1, 2);

    // Compute the expected GUID based on packet parameters
    let expected_guid = endpoint_v2::utils::compute_guid(
        1, // nonce (first message)
        SRC_EID,
        bytes32::from_address(ALICE), // sender
        DST_EID,
        bytes32::from_address(BOB), // receiver
    );

    // Create expected events with the computed GUID
    let expected_executor_event = send_uln::create_executor_fee_paid_event(expected_guid, EXECUTOR, 100);
    assert!(executor_events[0] == expected_executor_event, 3);

    let expected_dvn_event = send_uln::create_dvn_fee_paid_event(expected_guid, expected_dvns, expected_fees);
    assert!(dvn_events[0] == expected_dvn_event, 4);

    test_scenario::return_shared(treasury);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = send_uln::EDefaultExecutorConfigNotFound)]
fun test_error_no_default_executor_config() {
    let mut scenario = setup_scenario();
    let send_uln = create_test_send_uln(&mut scenario);

    // Attempt to get executor config without setting it first
    let _config = send_uln.get_default_executor_config(DST_EID);

    test_utils::destroy(send_uln);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = send_uln::EDefaultUlnConfigNotFound)]
fun test_error_no_default_uln_config() {
    let mut scenario = setup_scenario();
    let send_uln = create_test_send_uln(&mut scenario);

    // Attempt to get ULN config without setting it first
    let _config = send_uln.get_default_uln_config(DST_EID);

    test_utils::destroy(send_uln);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = send_uln::EOAppUlnConfigNotFound)]
fun test_error_no_oapp_uln_config() {
    let mut scenario = setup_scenario();
    let send_uln = create_test_send_uln(&mut scenario);

    // Attempt to get OApp ULN config without setting it first
    let _config = send_uln.get_oapp_uln_config(ALICE, DST_EID);

    test_utils::destroy(send_uln);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = send_uln::EOAppExecutorConfigNotFound)]
fun test_error_no_oapp_executor_config() {
    let mut scenario = setup_scenario();
    let send_uln = create_test_send_uln(&mut scenario);

    // Attempt to get OApp executor config without setting it first
    let _config = send_uln.get_oapp_executor_config(ALICE, DST_EID);

    test_utils::destroy(send_uln);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = send_uln::EInvalidMessageSize)]
fun test_error_invalid_message_size_in_quote() {
    let mut scenario = setup_scenario();
    let mut send_uln = create_test_send_uln(&mut scenario);

    // Setup configuration with small max_message_size to trigger error
    let small_executor_config = executor_config::create(
        10, // max message size
        EXECUTOR,
    );
    send_uln.set_default_executor_config(DST_EID, small_executor_config);
    send_uln.set_default_uln_config(DST_EID, create_test_uln_config());

    // Create a message that exceeds the max_message_size (10 bytes)
    let large_message = b"this message is definitely longer than 10 bytes and should trigger EInvalidMessageSize";
    let packet = outbound_packet::create_for_test(
        1, // nonce
        SRC_EID,
        ALICE, // sender
        DST_EID,
        bytes32::from_address(BOB), // receiver
        large_message, // This message exceeds max_message_size of 10
    );

    let quote_param = endpoint_v2::message_lib_quote::create_param_for_test(
        packet,
        x"0003", // OPTIONS_TYPE_3
        false, // pay_in_zro
    );

    // fail with EInvalidMessageSize
    let (_executor, _executor_param, _dvns, _dvn_params) = send_uln.quote(&quote_param);

    test_utils::destroy(send_uln);
    test_scenario::end(scenario);
}

#[test]
fun test_supported_eid_combinations() {
    let mut scenario = setup_scenario();
    let mut send_uln = create_test_send_uln(&mut scenario);

    // Test various combinations of config presence
    assert!(!send_uln.is_supported_eid(DST_EID), 0); // No configs

    // Add only executor config
    send_uln.set_default_executor_config(DST_EID, create_test_executor_config());
    assert!(!send_uln.is_supported_eid(DST_EID), 1); // Still missing ULN config

    // Add ULN config
    send_uln.set_default_uln_config(DST_EID, create_test_uln_config());
    assert!(send_uln.is_supported_eid(DST_EID), 2); // Now fully supported

    // Test different EID
    assert!(!send_uln.is_supported_eid(DST_EID + 1), 3); // Different EID not supported

    test_utils::destroy(send_uln);
    test_scenario::end(scenario);
}

#[test]
fun test_set_uln_config_happy_flow() {
    let mut scenario = setup_scenario();
    let mut send_uln = create_test_send_uln(&mut scenario);

    // First set a default ULN config (required for OApp config validation)
    let default_config = create_test_uln_config();
    send_uln.set_default_uln_config(DST_EID, default_config);

    // Create an OApp ULN config that uses custom values
    let custom_uln_config = uln_config::create(
        128, // custom confirmations
        vector[@0x7001, @0x7002], // custom required DVNs
        vector[@0x8001], // custom optional DVNs
        1, // custom threshold
    );

    let oapp_uln_config = oapp_uln_config::create(
        false, // use_default_confirmations = false (use custom)
        false, // use_default_required_dvns = false (use custom)
        false, // use_default_optional_dvns = false (use custom)
        custom_uln_config,
    );

    // Set the OApp-specific ULN config
    send_uln.set_uln_config(ALICE, DST_EID, oapp_uln_config);

    // Verify the config was set correctly
    let retrieved_config = send_uln.get_oapp_uln_config(ALICE, DST_EID);
    assert!(retrieved_config.uln_config().confirmations() == 128, 0);
    assert!(retrieved_config.use_default_confirmations() == false, 1);
    assert!(retrieved_config.use_default_required_dvns() == false, 2);
    assert!(retrieved_config.use_default_optional_dvns() == false, 3);

    // Verify event emissions (should have DefaultUlnConfigSetEvent + UlnConfigSetEvent)
    let default_uln_events = event::events_by_type<DefaultUlnConfigSetEvent>();
    let uln_events = event::events_by_type<UlnConfigSetEvent>();

    assert!(default_uln_events.length() == 1, 4);
    assert!(uln_events.length() == 1, 5);

    // Check event content
    let expected_default_uln_event = send_uln::create_default_uln_config_set_event(DST_EID, default_config);
    assert!(default_uln_events[0] == expected_default_uln_event, 6);

    let expected_uln_event = send_uln::create_uln_config_set_event(ALICE, DST_EID, oapp_uln_config);
    assert!(uln_events[0] == expected_uln_event, 7);

    test_utils::destroy(send_uln);
    test_scenario::end(scenario);
}

#[test]
fun test_get_oapp_executor_config() {
    let mut scenario = setup_scenario();
    let mut send_uln = create_test_send_uln(&mut scenario);

    // Set a custom executor config for ALICE
    let custom_config = executor_config::create(2000, @0x9001);
    send_uln.set_executor_config(ALICE, DST_EID, custom_config);

    // Test get_oapp_executor_config
    let retrieved_config = send_uln.get_oapp_executor_config(ALICE, DST_EID);
    assert!(retrieved_config.max_message_size() == 2000, 0);
    assert!(retrieved_config.executor() == @0x9001, 1);

    test_utils::destroy(send_uln);
    test_scenario::end(scenario);
}

#[test]
fun test_get_oapp_uln_config() {
    let mut scenario = setup_scenario();
    let mut send_uln = create_test_send_uln(&mut scenario);

    // First set a default ULN config (required for OApp config validation)
    let default_config = create_test_uln_config();
    send_uln.set_default_uln_config(DST_EID, default_config);

    // Create and set an OApp ULN config
    let custom_uln_config = uln_config::create(256, vector[@0xa001], vector[@0xb001], 1);
    let oapp_config = oapp_uln_config::create(false, false, false, custom_uln_config);
    send_uln.set_uln_config(BOB, DST_EID, oapp_config);

    // Test get_oapp_uln_config
    let retrieved_config = send_uln.get_oapp_uln_config(BOB, DST_EID);
    assert!(retrieved_config.uln_config().confirmations() == 256, 0);
    assert!(retrieved_config.uln_config().required_dvns() == &vector[@0xa001], 1);
    assert!(retrieved_config.uln_config().optional_dvns() == &vector[@0xb001], 2);

    test_utils::destroy(send_uln);
    test_scenario::end(scenario);
}

#[test]
fun test_get_effective_uln_config() {
    let mut scenario = setup_scenario();
    let mut send_uln = create_test_send_uln(&mut scenario);

    // Set default ULN config
    let default_config = uln_config::create(64, vector[DVN1], vector[DVN2], 1);
    send_uln.set_default_uln_config(DST_EID, default_config);

    // Test effective config when no OApp-specific config exists (should use defaults)
    let effective_config = send_uln.get_effective_uln_config(ALICE, DST_EID);
    assert!(effective_config.confirmations() == 64, 0);
    assert!(effective_config.required_dvns() == &vector[DVN1], 1);

    // Set OApp-specific config that uses some defaults and some custom values
    let custom_uln_config = uln_config::create(
        0, // confirmations (will use default because use_default_confirmations = true)
        vector[], // required DVNs (will use default)
        vector[@0xc001], // custom optional DVNs
        1,
    );
    let oapp_config = oapp_uln_config::create(
        true, // use_default_confirmations = true
        true, // use_default_required_dvns = true
        false, // use_default_optional_dvns = false (use custom)
        custom_uln_config,
    );
    send_uln.set_uln_config(ALICE, DST_EID, oapp_config);

    // Test effective config with mixed default/custom values
    let mixed_effective = send_uln.get_effective_uln_config(ALICE, DST_EID);
    assert!(mixed_effective.confirmations() == 64, 2); // From default
    assert!(mixed_effective.required_dvns() == &vector[DVN1], 3); // From default
    assert!(mixed_effective.optional_dvns() == &vector[@0xc001], 4); // From custom

    test_utils::destroy(send_uln);
    test_scenario::end(scenario);
}

#[test]
fun test_handle_fees_basic() {
    let mut scenario = setup_scenario();

    treasury::init_for_test(scenario.ctx());
    scenario.next_tx(ALICE);
    let treasury = scenario.take_shared<treasury::Treasury>();
    let treasury_recipient = treasury.fee_recipient();

    // Test basic fee distribution with multiple workers
    let executor_fee = fee_recipient::create(100u64, EXECUTOR);
    let dvn_fees = vector[fee_recipient::create(50u64, DVN1), fee_recipient::create(75u64, DVN2)];
    let total_worker_fee = 100 + 50 + 75;
    let treasury_fee = 10;
    let native_coin = coin::mint_for_testing<IOTA>(total_worker_fee + treasury_fee, scenario.ctx());
    let zro_coin = coin::mint_for_testing<ZRO>(0, scenario.ctx());
    send_uln::handle_fees(&treasury, executor_fee, dvn_fees, native_coin, zro_coin, scenario.ctx());

    // Verify transfers happened with correct amounts
    scenario.next_tx(ALICE);
    assert!(test_scenario::has_most_recent_for_address<coin::Coin<IOTA>>(EXECUTOR), 0);
    assert!(test_scenario::has_most_recent_for_address<coin::Coin<IOTA>>(DVN1), 1);
    assert!(test_scenario::has_most_recent_for_address<coin::Coin<IOTA>>(DVN2), 2);
    assert!(test_scenario::has_most_recent_for_address<coin::Coin<IOTA>>(treasury_recipient), 3);

    // Verify exact amounts
    let executor_coin = scenario.take_from_address<coin::Coin<IOTA>>(EXECUTOR);
    let dvn1_coin = scenario.take_from_address<coin::Coin<IOTA>>(DVN1);
    let dvn2_coin = scenario.take_from_address<coin::Coin<IOTA>>(DVN2);
    let treasury_coin = scenario.take_from_address<coin::Coin<IOTA>>(treasury_recipient);
    assert!(executor_coin.value() == 100, 4);
    assert!(dvn1_coin.value() == 50, 5);
    assert!(dvn2_coin.value() == 75, 6);
    assert!(treasury_coin.value() == 10, 7);
    coin::burn_for_testing(executor_coin);
    coin::burn_for_testing(dvn1_coin);
    coin::burn_for_testing(dvn2_coin);
    coin::burn_for_testing(treasury_coin);

    test_scenario::return_shared(treasury);
    test_scenario::end(scenario);
}

#[test]
fun test_handle_fees_with_zro() {
    let mut scenario = setup_scenario();

    treasury::init_for_test(scenario.ctx());
    scenario.next_tx(ALICE);
    let treasury = scenario.take_shared<treasury::Treasury>();
    let treasury_recipient = treasury.fee_recipient();

    // Test fee distribution with ZRO payment
    let executor_fee = fee_recipient::create(200u64, EXECUTOR);
    let dvn_fees = vector[fee_recipient::create(100u64, DVN1)];
    let total_worker_fee = 200 + 100;
    let treasury_native_fee = 5;
    let treasury_zro_fee = 20;
    let native_coin = coin::mint_for_testing<IOTA>(total_worker_fee + treasury_native_fee, scenario.ctx());
    let zro_coin = coin::mint_for_testing<ZRO>(treasury_zro_fee, scenario.ctx());
    send_uln::handle_fees(&treasury, executor_fee, dvn_fees, native_coin, zro_coin, scenario.ctx());

    // Verify transfers happened with correct amounts
    scenario.next_tx(ALICE);
    assert!(test_scenario::has_most_recent_for_address<coin::Coin<IOTA>>(EXECUTOR), 0);
    assert!(test_scenario::has_most_recent_for_address<coin::Coin<IOTA>>(DVN1), 1);
    assert!(test_scenario::has_most_recent_for_address<coin::Coin<IOTA>>(treasury_recipient), 2);
    assert!(test_scenario::has_most_recent_for_address<coin::Coin<ZRO>>(treasury_recipient), 3);

    // Verify exact amounts
    let executor_coin = scenario.take_from_address<coin::Coin<IOTA>>(EXECUTOR);
    let dvn1_coin = scenario.take_from_address<coin::Coin<IOTA>>(DVN1);
    let treasury_native_coin = scenario.take_from_address<coin::Coin<IOTA>>(treasury_recipient);
    let treasury_zro_coin = scenario.take_from_address<coin::Coin<ZRO>>(treasury_recipient);
    assert!(executor_coin.value() == 200, 4);
    assert!(dvn1_coin.value() == 100, 5);
    assert!(treasury_native_coin.value() == 5, 6);
    assert!(treasury_zro_coin.value() == 20, 7);
    coin::burn_for_testing(executor_coin);
    coin::burn_for_testing(dvn1_coin);
    coin::burn_for_testing(treasury_native_coin);
    coin::burn_for_testing(treasury_zro_coin);

    test_scenario::return_shared(treasury);
    test_scenario::end(scenario);
}

#[test]
fun test_handle_fees_zero_worker_fees() {
    let mut scenario = setup_scenario();

    treasury::init_for_test(scenario.ctx());
    scenario.next_tx(ALICE);
    let treasury = scenario.take_shared<treasury::Treasury>();
    let treasury_recipient = treasury.fee_recipient();

    // Test fee distribution when workers charge zero fees
    let executor_fee = fee_recipient::create(0u64, EXECUTOR);
    let dvn_fees = vector[fee_recipient::create(0u64, DVN1)];
    let treasury_native_fee = 5;
    let native_coin = coin::mint_for_testing<IOTA>(treasury_native_fee, scenario.ctx());
    let zro_coin = coin::mint_for_testing<ZRO>(0, scenario.ctx());
    send_uln::handle_fees(&treasury, executor_fee, dvn_fees, native_coin, zro_coin, scenario.ctx());

    // Verify treasury received the coins, zero-value coins to workers are destroyed
    scenario.next_tx(ALICE);
    assert!(test_scenario::has_most_recent_for_address<coin::Coin<IOTA>>(treasury_recipient), 0);
    // Zero-value coins to workers should NOT exist (destroyed by utils::transfer_coin)
    assert!(!test_scenario::has_most_recent_for_address<coin::Coin<IOTA>>(EXECUTOR), 1);
    assert!(!test_scenario::has_most_recent_for_address<coin::Coin<IOTA>>(DVN1), 2);

    // Verify treasury received exactly the treasury fee
    let treasury_coin = scenario.take_from_address<coin::Coin<IOTA>>(treasury_recipient);
    assert!(treasury_coin.value() == 5, 3);
    coin::burn_for_testing(treasury_coin);

    test_scenario::return_shared(treasury);
    test_scenario::end(scenario);
}
