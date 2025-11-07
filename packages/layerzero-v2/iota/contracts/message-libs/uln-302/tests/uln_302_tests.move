#[test_only]
module uln_302::uln_302_tests;

use call::{call::{Self, Call}, call_cap::{Self, CallCap}};
use endpoint_v2::{
    endpoint_v2::{Self, EndpointV2, AdminCap as EndpointAdminCap},
    message_lib_quote,
    message_lib_send,
    message_lib_set_config,
    messaging_channel::{Self, MessagingChannel},
    messaging_fee,
    outbound_packet
};
use message_lib_common::{fee_recipient::{Self, FeeRecipient}, packet_v1_codec};
use multi_call::multi_call;
use iota::{bcs, clock, test_scenario, test_utils};
use treasury::treasury::{Self, Treasury};
use uln_302::{executor_config, oapp_uln_config, receive_uln, uln_302::{Self, Uln302, AdminCap}, uln_config};
use uln_common::{
    dvn_assign_job,
    dvn_get_fee::GetFeeParam as DvnGetFeeParam,
    dvn_verify,
    executor_assign_job,
    executor_get_fee
};
use utils::{bytes32, hash, package};

// === TEST CONSTANTS ===

/// Test addresses and identifiers
const ADMIN: address = @0x123;
const DVN1_ADDRESS: address = @0x789;
const DVN2_ADDRESS: address = @0xabc;
const EXECUTOR_ADDRESS: address = @0xdef;

/// Test configuration values
const DEFAULT_CONFIRMATIONS: u64 = 15;
const CUSTOM_CONFIRMATIONS: u64 = 35;
const EXECUTOR_MAX_MESSAGE_SIZE: u64 = 50000;
const CUSTOM_EXECUTOR_SIZE: u64 = 9999;
const CUSTOM_EXECUTOR_ADDRESS: address = @0xabcd;

/// Config types (matching uln_302::uln_302 private constants)
const CONFIG_TYPE_EXECUTOR: u32 = 1;
const CONFIG_TYPE_SEND_ULN: u32 = 2;
const CONFIG_TYPE_RECEIVE_ULN: u32 = 3;

// === HELPER FUNCTIONS ===

/// Creates a standard test ULN config for default configurations
fun create_default_uln_config(): uln_config::UlnConfig {
    uln_config::create(
        DEFAULT_CONFIRMATIONS,
        vector[DVN1_ADDRESS, DVN2_ADDRESS],
        vector[], // optional dvns
        0, // optional threshold
    )
}

/// Creates a test executor config for default configurations
fun create_default_executor_config(): executor_config::ExecutorConfig {
    executor_config::create(EXECUTOR_MAX_MESSAGE_SIZE, EXECUTOR_ADDRESS)
}

/// Creates BCS-encoded bytes for executor config (used in set_config tests)
fun create_executor_config_bytes(): vector<u8> {
    let config = executor_config::create(CUSTOM_EXECUTOR_SIZE, CUSTOM_EXECUTOR_ADDRESS);
    bcs::to_bytes(&config)
}

/// Creates BCS-encoded bytes for OApp ULN config (used in set_config tests)
fun create_oapp_uln_config_bytes(): vector<u8> {
    let uln_config = uln_config::create(
        CUSTOM_CONFIRMATIONS,
        vector[@0xfeed, @0xbeef], // Custom DVNs for test verification
        vector[], // optional_dvns (empty)
        0, // optional_dvn_threshold
    );
    let oapp_config = oapp_uln_config::create(
        false, // use_default_confirmations - use custom value
        false, // use_default_required_dvns - use custom DVNs
        false, // use_default_optional_dvns - use custom (empty) optionals
        uln_config,
    );
    bcs::to_bytes(&oapp_config)
}

// === MOCK WORKER STRUCTURES ===

/// Mock Executor for testing worker call completion
public struct MockExecutor has key, store {
    id: UID,
    call_cap: CallCap,
}

/// Mock DVN for testing worker call completion
public struct MockDVN has key, store {
    id: UID,
    call_cap: CallCap,
}

// === MOCK WORKER HELPER FUNCTIONS ===

/// Creates a mock executor with its own CallCap
fun create_mock_executor(ctx: &mut TxContext): MockExecutor {
    MockExecutor {
        id: object::new(ctx),
        call_cap: call_cap::new_package_cap_for_test(ctx),
    }
}

/// Creates a mock DVN with its own CallCap
fun create_mock_dvn(ctx: &mut TxContext): MockDVN {
    MockDVN {
        id: object::new(ctx),
        call_cap: call_cap::new_package_cap_for_test(ctx),
    }
}

/// Mock executor get_fee implementation - completes the call with a mock fee
public fun executor_get_fee(
    executor: &MockExecutor,
    call: &mut Call<executor_get_fee::GetFeeParam, u64>,
    _ctx: &mut TxContext,
) {
    let mock_fee = 1000u64;
    call.complete(&executor.call_cap, mock_fee);
}

/// Mock DVN get_fee implementation - completes the call with a mock fee
public fun dvn_get_fee(dvn: &MockDVN, call: &mut Call<DvnGetFeeParam, u64>, _ctx: &mut TxContext) {
    let mock_fee = 500u64;
    call.complete(&dvn.call_cap, mock_fee);
}

/// Mock executor assign_job implementation - completes the call with a mock fee recipient
public fun executor_assign_job(
    executor: &MockExecutor,
    call: &mut Call<executor_assign_job::AssignJobParam, FeeRecipient>,
    _ctx: &mut TxContext,
) {
    let mock_fee = 1000u64;
    let mock_deposit_address = executor.call_cap.id();
    call.complete(&executor.call_cap, fee_recipient::create(mock_fee, mock_deposit_address));
}

/// Mock DVN assign_job implementation - completes the call with a mock fee recipient
public fun dvn_assign_job(
    dvn: &MockDVN,
    call: &mut Call<dvn_assign_job::AssignJobParam, FeeRecipient>,
    _ctx: &mut TxContext,
) {
    let mock_fee = 500u64;
    let mock_deposit_address = dvn.call_cap.id();
    call.complete(&dvn.call_cap, fee_recipient::create(mock_fee, mock_deposit_address));
}

/// Returns the address of the executor's CallCap
public fun executor_call_cap(executor: &MockExecutor): address {
    executor.call_cap.id()
}

/// Returns the address of the DVN's CallCap
public fun dvn_call_cap(dvn: &MockDVN): address {
    dvn.call_cap.id()
}

/// Returns a reference to the executor's CallCap (for sealing/completing calls)
public fun executor_call_cap_ref(executor: &MockExecutor): &CallCap {
    &executor.call_cap
}

/// Returns a reference to the DVN's CallCap (for sealing/completing calls)
public fun dvn_call_cap_ref(dvn: &MockDVN): &CallCap {
    &dvn.call_cap
}

// === TESTS ===

#[test]
fun test_uln302_initialization() {
    let mut scenario = test_scenario::begin(ADMIN);
    endpoint_v2::init_for_test(scenario.ctx());
    uln_302::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);

    let endpoint_admin_cap = scenario.take_from_sender<EndpointAdminCap>();
    let uln_admin_cap = scenario.take_from_sender<AdminCap>();
    let endpoint = scenario.take_shared<EndpointV2>();
    let uln302 = scenario.take_shared<Uln302>();

    // Test that ULN-302 is properly initialized
    let (major, minor, endpoint_version) = uln_302::version();
    assert!(major == 3, 0);
    assert!(minor == 0, 1);
    assert!(endpoint_version == 2, 2);

    scenario.return_to_sender(endpoint_admin_cap);
    scenario.return_to_sender(uln_admin_cap);
    test_scenario::return_shared(endpoint);
    test_scenario::return_shared(uln302);
    scenario.end();
}

#[test, expected_failure(abort_code = receive_uln::EInvalidEid)]
fun test_commit_verification_invalid_eid_should_fail() {
    let mut scenario = test_scenario::begin(ADMIN);
    endpoint_v2::init_for_test(scenario.ctx());
    uln_302::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);

    let endpoint_admin_cap = scenario.take_from_sender<EndpointAdminCap>();
    let uln_admin_cap = scenario.take_from_sender<AdminCap>();
    let mut endpoint = scenario.take_shared<EndpointV2>();
    let mut uln302 = scenario.take_shared<Uln302>();

    // Minimal setup - endpoint EID = 1
    endpoint.init_eid(&endpoint_admin_cap, 1);

    // Set up configs directly without endpoint complexity (copied from working test)
    let executor_config = create_default_executor_config();
    let uln_config = create_default_uln_config();
    uln_302::set_default_executor_config(&mut uln302, &uln_admin_cap, 1, executor_config);
    uln_302::set_default_send_uln_config(&mut uln302, &uln_admin_cap, 1, uln_config);
    uln_302::set_default_receive_uln_config(&mut uln302, &uln_admin_cap, 1, uln_config);

    // Create packet with dst_eid = 2 (different from endpoint EID = 1)
    let packet_header = packet_v1_codec::create_packet_header_for_testing(
        1, // version
        12345, // nonce
        1, // src_eid
        bytes32::from_address(@0x456), // sender
        2, // dst_eid = 2 (THIS WILL CAUSE EInvalidEid!)
        bytes32::from_address(@0x789), // receiver
    ).encode_header();
    let payload_hash = hash::keccak256!(&b"test_payload");

    // Create minimal verification and messaging channel
    let mut verification = receive_uln::create_verification_for_testing(scenario.ctx());
    let messaging_channel_address = messaging_channel::create_for_testing(@0x789, scenario.ctx());
    scenario.next_tx(@0x0);
    let mut messaging_channel = scenario.take_shared_by_id<MessagingChannel>(
        iota::object::id_from_address(messaging_channel_address),
    );
    let clock = clock::create_for_testing(scenario.ctx());

    // Pre-verify the packet with DVNs to get past the verification step
    // This allows us to reach the EID validation that we want to test
    receive_uln::verify(&mut verification, DVN1_ADDRESS, packet_header, payload_hash, 15);
    receive_uln::verify(&mut verification, DVN2_ADDRESS, packet_header, payload_hash, 15);

    // This should fail with EInvalidEid because packet.dst_eid (2) != endpoint.eid() (1)
    uln_302::commit_verification(
        &uln302,
        &mut verification,
        &endpoint,
        &mut messaging_channel,
        packet_header,
        payload_hash,
        &clock,
    );

    // Won't reach here due to expected failure
    test_utils::destroy(verification);
    test_utils::destroy(messaging_channel);
    test_utils::destroy(clock);
    scenario.return_to_sender(endpoint_admin_cap);
    scenario.return_to_sender(uln_admin_cap);
    test_scenario::return_shared(endpoint);
    test_scenario::return_shared(uln302);
    scenario.end();
}

#[test, expected_failure(abort_code = uln_302::EUnsupportedEid)]
fun test_set_config_unsupported_eid_should_fail() {
    let mut scenario = test_scenario::begin(ADMIN);
    uln_302::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);

    let uln_admin_cap = scenario.take_from_sender<AdminCap>();
    let mut uln302 = scenario.take_shared<Uln302>();

    let mock_endpoint_cap = call_cap::new_package_cap_with_address_for_test(scenario.ctx(), @0x0);

    // Don't set up any configs for EID 999 - this makes it unsupported

    // Create a direct message_lib_set_config call with unsupported EID
    let config_bytes = b"test_config";
    let set_config_param = message_lib_set_config::create_param_for_test(
        @0x123, // oapp address
        999, // unsupported EID
        1, // valid config type
        config_bytes,
    );

    let message_lib_call = call::create(
        &mock_endpoint_cap, // Mock endpoint creates the call
        uln_302::get_call_cap(&uln302).id(), // To ULN-302's CallCap
        true, // one_way
        set_config_param,
        scenario.ctx(),
    );

    // This should fail with EUnsupportedEid because EID 999 has no default configs
    uln_302::set_config(&mut uln302, message_lib_call);
    test_utils::destroy(mock_endpoint_cap);
    scenario.return_to_sender(uln_admin_cap);
    test_scenario::return_shared(uln302);
    scenario.end();
}

#[test, expected_failure(abort_code = uln_302::EInvalidConfigType)]
fun test_set_config_invalid_type_should_fail() {
    let mut scenario = test_scenario::begin(ADMIN);
    uln_302::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);

    let uln_admin_cap = scenario.take_from_sender<AdminCap>();
    let mut uln302 = scenario.take_shared<Uln302>();

    let mock_endpoint_cap = call_cap::new_package_cap_with_address_for_test(scenario.ctx(), @0x0);

    // Set up configs for EID 2 to make it supported (need both send and receive configs)
    let uln_config = create_default_uln_config();
    let executor_config = create_default_executor_config();
    uln_302::set_default_receive_uln_config(&mut uln302, &uln_admin_cap, 2, uln_config);
    uln_302::set_default_send_uln_config(&mut uln302, &uln_admin_cap, 2, uln_config);
    uln_302::set_default_executor_config(&mut uln302, &uln_admin_cap, 2, executor_config);

    // Create a direct message_lib_set_config call with invalid config type
    let config_bytes = b"test_config";
    let set_config_param = message_lib_set_config::create_param_for_test(
        @0x123, // oapp address
        2, // supported EID
        999, // INVALID config type (not 1, 2, or 3)
        config_bytes,
    );

    let message_lib_call = call::create(
        &mock_endpoint_cap, // Mock endpoint creates the call
        uln_302::get_call_cap(&uln302).id(), // To ULN-302's CallCap
        true, // one_way
        set_config_param,
        scenario.ctx(),
    );

    // This should fail with EInvalidConfigType because config type 999 is invalid
    uln_302::set_config(&mut uln302, message_lib_call);
    test_utils::destroy(mock_endpoint_cap);
    scenario.return_to_sender(uln_admin_cap);
    test_scenario::return_shared(uln302);
    scenario.end();
}

#[test, expected_failure(abort_code = uln_302::EInvalidMessagingChannel)]
fun test_commit_verification_invalid_receiver_should_fail() {
    let mut scenario = test_scenario::begin(ADMIN);
    endpoint_v2::init_for_test(scenario.ctx());
    uln_302::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);

    let endpoint_admin_cap = scenario.take_from_sender<EndpointAdminCap>();
    let uln_admin_cap = scenario.take_from_sender<AdminCap>();
    let mut endpoint = scenario.take_shared<EndpointV2>();
    let mut uln302 = scenario.take_shared<Uln302>();

    // Basic setup
    endpoint.init_eid(&endpoint_admin_cap, 1);
    // Set default configs
    let uln_config = create_default_uln_config();
    uln_302::set_default_receive_uln_config(&mut uln302, &uln_admin_cap, 1, uln_config);
    uln_302::set_default_send_uln_config(&mut uln302, &uln_admin_cap, 1, uln_config);
    let executor_config = create_default_executor_config();
    uln_302::set_default_executor_config(&mut uln302, &uln_admin_cap, 1, executor_config);

    // Create OApp and messaging channel
    let oapp_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let oapp_address = oapp_cap.id();
    endpoint.register_oapp(&oapp_cap, b"lz_receive_info", scenario.ctx());
    let messaging_channel_address = messaging_channel::create_for_testing(oapp_address, scenario.ctx());
    scenario.next_tx(@0x0);
    let mut messaging_channel = scenario.take_shared_by_id<MessagingChannel>(
        iota::object::id_from_address(messaging_channel_address),
    );

    // Create packet with WRONG receiver (different from oapp_address)
    let packet_header = packet_v1_codec::create_packet_header_for_testing(
        1,
        12345,
        1,
        bytes32::from_address(@0x456),
        1,
        bytes32::from_address(@0x9999), // Wrong receiver!
    ).encode_header();
    let payload_hash = hash::keccak256!(&b"test_payload");

    // Pre-verify the packet
    let mut verification = receive_uln::create_verification_for_testing(scenario.ctx());
    receive_uln::verify(&mut verification, DVN1_ADDRESS, packet_header, payload_hash, 15);
    receive_uln::verify(&mut verification, DVN2_ADDRESS, packet_header, payload_hash, 15);
    let clock = clock::create_for_testing(scenario.ctx());

    // This should fail with EInvalidReceiver because packet.receiver (@0x9999) != messaging_channel.oapp
    uln_302::commit_verification(
        &uln302,
        &mut verification,
        &endpoint,
        &mut messaging_channel,
        packet_header,
        payload_hash,
        &clock,
    );

    // Won't reach here due to expected failure
    test_utils::destroy(verification);
    test_utils::destroy(oapp_cap);
    test_utils::destroy(messaging_channel);
    clock.destroy_for_testing();
    scenario.return_to_sender(endpoint_admin_cap);
    scenario.return_to_sender(uln_admin_cap);
    test_scenario::return_shared(endpoint);
    test_scenario::return_shared(uln302);
    scenario.end();
}

#[test]
fun test_verification_and_verifiable() {
    let mut scenario = test_scenario::begin(ADMIN);
    uln_302::init_for_test(scenario.ctx());
    endpoint_v2::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);

    let uln_admin_cap = scenario.take_from_sender<AdminCap>();
    let endpoint_admin_cap = scenario.take_from_sender<EndpointAdminCap>();
    let mut uln302 = scenario.take_shared<Uln302>();
    let mut endpoint = scenario.take_shared<EndpointV2>();

    // Set up endpoint connection (no need for direct mocking here)
    endpoint.init_eid(&endpoint_admin_cap, 1);
    // Create DVN caps first so we can use their addresses in the config
    let dvn1_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let dvn2_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let dvn1_address = dvn1_cap.id();
    let dvn2_address = dvn2_cap.id();

    // Set up receive config for EID 1 with our DVN addresses
    let uln_config = uln_config::create(
        15, // confirmations
        vector[dvn1_address, dvn2_address], // Use our DVN addresses
        vector[], // optional dvns
        0, // optional threshold
    );
    uln_302::set_default_receive_uln_config(&mut uln302, &uln_admin_cap, 1, uln_config);

    // Create test packet header and payload hash
    let packet_header = packet_v1_codec::create_packet_header_for_testing(
        1,
        12345,
        1,
        bytes32::from_address(@0x456),
        1,
        bytes32::from_address(@0x789),
    ).encode_header();
    let payload_hash = hash::keccak256!(&b"test_payload");

    // Test the real verification flow
    let mut verification = receive_uln::create_verification_for_testing(scenario.ctx());

    // 1. First test - packet should NOT be verifiable initially (no DVN confirmations)
    let is_verifiable_before = uln_302::verifiable(
        &uln302,
        &verification,
        &endpoint,
        packet_header,
        payload_hash,
    );
    assert!(is_verifiable_before == false, 0);

    // 2. Now add DVN confirmations to make the packet verifiable
    // The test ULN config now uses our DVN addresses with 15 confirmations each
    // We use the uln_302 API (proper way to add DVN confirmations)
    let dvn_call1 = call::create(
        &dvn1_cap,
        uln_302::get_call_cap(&uln302).id(),
        true,
        dvn_verify::create_param(
            packet_header,
            payload_hash,
            15,
        ),
        scenario.ctx(),
    );
    uln302.verify(&mut verification, dvn_call1);
    let dvn_call2 = call::create(
        &dvn2_cap,
        uln_302::get_call_cap(&uln302).id(),
        true,
        dvn_verify::create_param(
            packet_header,
            payload_hash,
            15,
        ),
        scenario.ctx(),
    );
    uln302.verify(&mut verification, dvn_call2);

    // 3. Now the packet should be verifiable (all required DVNs have confirmed)
    let is_verifiable_after = uln_302::verifiable(
        &uln302,
        &verification,
        &endpoint,
        packet_header,
        payload_hash,
    );
    assert!(is_verifiable_after == true, 1);

    // 4. Test with different packet data - should still be FALSE (different packet, no confirmations)
    let different_packet_header = packet_v1_codec::create_packet_header_for_testing(
        1,
        54321, // Different nonce
        1,
        bytes32::from_address(@0x456),
        1,
        bytes32::from_address(@0x789),
    ).encode_header();

    // Different packet should have different payload
    let different_payload_hash = hash::keccak256!(&b"different_test_payload");

    let is_verifiable_different = uln_302::verifiable(
        &uln302,
        &verification,
        &endpoint,
        different_packet_header,
        different_payload_hash,
    );

    // Different packet should NOT be verifiable (no confirmations for this specific packet)
    assert!(is_verifiable_different == false, 2);

    // 5. Add confirmations for the different packet and verify it becomes verifiable too
    let dvn_call1 = call::create(
        &dvn1_cap,
        uln_302::get_call_cap(&uln302).id(),
        true,
        dvn_verify::create_param(
            different_packet_header,
            different_payload_hash,
            15,
        ),
        scenario.ctx(),
    );
    uln302.verify(&mut verification, dvn_call1);
    let dvn_call2 = call::create(
        &dvn2_cap,
        uln_302::get_call_cap(&uln302).id(),
        true,
        dvn_verify::create_param(
            different_packet_header,
            different_payload_hash,
            15,
        ),
        scenario.ctx(),
    );
    uln302.verify(&mut verification, dvn_call2);

    let is_verifiable_different_after = uln_302::verifiable(
        &uln302,
        &verification,
        &endpoint,
        different_packet_header,
        different_payload_hash,
    );

    // Now the different packet should also be verifiable
    assert!(is_verifiable_different_after == true, 3);

    // DVN verification completed successfully
    // Cleanup DVN caps
    test_utils::destroy(dvn1_cap);
    test_utils::destroy(dvn2_cap);

    // Test get_verification address function while we're here
    let verification_address = uln_302::get_verification(&uln302);
    assert!(verification_address != @0x0, 4);

    // Cleanup
    test_utils::destroy(verification);
    scenario.return_to_sender(endpoint_admin_cap);
    scenario.return_to_sender(uln_admin_cap);
    test_scenario::return_shared(endpoint);
    test_scenario::return_shared(uln302);
    scenario.end();
}

#[test]
fun test_version_and_utility() {
    let mut scenario = test_scenario::begin(ADMIN);
    uln_302::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);

    let uln_admin_cap = scenario.take_from_sender<AdminCap>();
    let mut uln302 = scenario.take_shared<Uln302>();

    let mock_endpoint_cap = call_cap::new_package_cap_with_address_for_test(scenario.ctx(), @0x0);

    // Test version function (same as before)
    let (major, minor, endpoint_version) = uln_302::version();
    assert!(major == 3, 0);
    assert!(minor == 0, 1);
    assert!(endpoint_version == 2, 2);

    let call_cap_ref = uln_302::get_call_cap(&uln302);
    assert!(call_cap_ref.is_package(), 3);

    // Test is_supported_eid (should be false initially)
    let is_supported_before = uln_302::is_supported_eid(&uln302, 999);
    assert!(!is_supported_before, 4);

    // Set up configs directly without endpoint complexity
    let executor_config = create_default_executor_config();
    let uln_config = create_default_uln_config();
    uln_302::set_default_executor_config(&mut uln302, &uln_admin_cap, 999, executor_config);
    uln_302::set_default_send_uln_config(&mut uln302, &uln_admin_cap, 999, uln_config);
    uln_302::set_default_receive_uln_config(&mut uln302, &uln_admin_cap, 999, uln_config);

    // Test is_supported_eid (should be true after configs)
    let is_supported_after = uln_302::is_supported_eid(&uln302, 999);
    assert!(is_supported_after, 5);

    // Cleanup
    test_utils::destroy(mock_endpoint_cap);
    scenario.return_to_sender(uln_admin_cap);
    test_scenario::return_shared(uln302);
    scenario.end();
}

#[test]
fun test_send_uln_view_functions() {
    let mut scenario = test_scenario::begin(ADMIN);
    endpoint_v2::init_for_test(scenario.ctx());
    uln_302::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);

    let endpoint_admin_cap = scenario.take_from_sender<EndpointAdminCap>();
    let uln_admin_cap = scenario.take_from_sender<AdminCap>();
    let endpoint = scenario.take_shared<EndpointV2>();
    let mut uln302 = scenario.take_shared<Uln302>();

    // Create an OApp for testing
    let oapp_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let oapp_address = oapp_cap.id();

    let test_eid = 42;
    let executor_config = create_default_executor_config();
    let uln_config = create_default_uln_config();

    // Set default configs
    uln_302::set_default_executor_config(&mut uln302, &uln_admin_cap, test_eid, executor_config);
    uln_302::set_default_send_uln_config(&mut uln302, &uln_admin_cap, test_eid, uln_config);

    // Test get_oapp_executor_config (returns effective config when no oapp-specific config set)
    // Note: This function may abort if no config is set, so we test the effective config instead

    // Test get_effective_executor_config (should return the effective config)
    let effective_executor_config = uln_302::get_effective_executor_config(&uln302, oapp_address, test_eid);
    assert!(executor_config::max_message_size(&effective_executor_config) == 50000, 0);

    // Test get_oapp_send_uln_config would abort without OApp-specific config, so skip it
    // Instead, test get_effective_send_uln_config which works with defaults
    let effective_send_uln_config = uln_302::get_effective_send_uln_config(&uln302, oapp_address, test_eid);
    assert!(uln_config::confirmations(&effective_send_uln_config) == 15, 1);

    // Cleanup
    test_utils::destroy(oapp_cap);
    scenario.return_to_sender(endpoint_admin_cap);
    scenario.return_to_sender(uln_admin_cap);
    test_scenario::return_shared(endpoint);
    test_scenario::return_shared(uln302);
    scenario.end();
}

#[test]
fun test_receive_uln_view_functions() {
    let mut scenario = test_scenario::begin(ADMIN);
    endpoint_v2::init_for_test(scenario.ctx());
    uln_302::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);

    let endpoint_admin_cap = scenario.take_from_sender<EndpointAdminCap>();
    let uln_admin_cap = scenario.take_from_sender<AdminCap>();
    let endpoint = scenario.take_shared<EndpointV2>();
    let mut uln302 = scenario.take_shared<Uln302>();

    // Create an OApp for testing
    let oapp_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let oapp_address = oapp_cap.id();

    let test_eid = 42;
    let uln_config = create_default_uln_config();

    // Set default receive config
    uln_302::set_default_receive_uln_config(&mut uln302, &uln_admin_cap, test_eid, uln_config);

    // Test get_oapp_receive_uln_config would abort without OApp-specific config, so skip it
    // Instead, test get_effective_receive_uln_config which works with defaults
    let effective_receive_uln_config = uln_302::get_effective_receive_uln_config(&uln302, oapp_address, test_eid);
    assert!(uln_config::confirmations(&effective_receive_uln_config) == 15, 0);

    // Test get_verification function
    let verification_address = uln_302::get_verification(&uln302);
    assert!(verification_address != @0x0, 1);

    // Cleanup
    test_utils::destroy(oapp_cap);
    scenario.return_to_sender(endpoint_admin_cap);
    scenario.return_to_sender(uln_admin_cap);
    test_scenario::return_shared(endpoint);
    test_scenario::return_shared(uln302);
    scenario.end();
}

#[test]
fun test_config_management() {
    let mut scenario = test_scenario::begin(ADMIN);
    uln_302::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);

    let uln_admin_cap = scenario.take_from_sender<AdminCap>();
    let mut uln302 = scenario.take_shared<Uln302>();

    let mock_endpoint_cap = call_cap::new_package_cap_with_address_for_test(scenario.ctx(), @0x0);

    let test_eid = 42;
    let executor_config = create_default_executor_config();
    let uln_config = create_default_uln_config();

    // Test all config setters and getters in one focused test
    uln_302::set_default_executor_config(&mut uln302, &uln_admin_cap, test_eid, executor_config);
    uln_302::set_default_send_uln_config(&mut uln302, &uln_admin_cap, test_eid, uln_config);
    uln_302::set_default_receive_uln_config(&mut uln302, &uln_admin_cap, test_eid, uln_config);

    // Test getters
    let retrieved_executor_config = uln_302::get_default_executor_config(&uln302, test_eid);
    let retrieved_send_config = uln_302::get_default_send_uln_config(&uln302, test_eid);
    let retrieved_receive_config = uln_302::get_default_receive_uln_config(&uln302, test_eid);

    // Verify config values
    assert!(executor_config::max_message_size(retrieved_executor_config) == 50000, 0);
    assert!(executor_config::executor(retrieved_executor_config) == EXECUTOR_ADDRESS, 1);
    assert!(uln_config::confirmations(retrieved_send_config) == 15, 2);
    assert!(uln_config::confirmations(retrieved_receive_config) == 15, 3);

    // Test EID support
    assert!(uln_302::is_supported_eid(&uln302, test_eid), 4);

    // Test verification getter
    let verification_address = uln_302::get_verification(&uln302);
    assert!(verification_address != @0x0, 5);

    // Cleanup
    test_utils::destroy(mock_endpoint_cap);
    scenario.return_to_sender(uln_admin_cap);
    test_scenario::return_shared(uln302);
    scenario.end();
}

#[test]
fun test_set_config_executor_type() {
    let mut scenario = test_scenario::begin(ADMIN);
    uln_302::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);

    let uln_admin_cap = scenario.take_from_sender<AdminCap>();
    let mut uln302 = scenario.take_shared<Uln302>();

    let mock_endpoint_cap = call_cap::new_package_cap_with_address_for_test(scenario.ctx(), @0x0);

    // Set up configs for EID 2 to make it supported
    let test_eid = 2;
    let uln_config = create_default_uln_config();
    let executor_config = create_default_executor_config();
    uln_302::set_default_receive_uln_config(&mut uln302, &uln_admin_cap, test_eid, uln_config);
    uln_302::set_default_send_uln_config(&mut uln302, &uln_admin_cap, test_eid, uln_config);
    uln_302::set_default_executor_config(&mut uln302, &uln_admin_cap, test_eid, executor_config);

    // Create a message_lib_set_config call with CONFIG_TYPE_EXECUTOR (1)
    // Using valid BCS-encoded executor config
    let config_bytes = create_executor_config_bytes();
    let set_config_param = message_lib_set_config::create_param_for_test(
        @0x123, // oapp address
        test_eid,
        CONFIG_TYPE_EXECUTOR,
        config_bytes,
    );

    let message_lib_call = call::create(
        &mock_endpoint_cap,
        uln_302::get_call_cap(&uln302).id(),
        true, // one_way
        set_config_param,
        scenario.ctx(),
    );

    // This should succeed and set the executor config for the OApp
    uln_302::set_config(&mut uln302, message_lib_call);

    // Verify the executor config was actually set by retrieving it
    let retrieved_config = uln_302::get_effective_executor_config(&uln302, @0x123, test_eid);
    assert!(executor_config::max_message_size(&retrieved_config) == 9999, 0);
    assert!(executor_config::executor(&retrieved_config) == @0xabcd, 1);

    // Cleanup (message_lib_call is consumed by set_config)
    test_utils::destroy(mock_endpoint_cap);
    scenario.return_to_sender(uln_admin_cap);
    test_scenario::return_shared(uln302);
    scenario.end();
}

#[test]
fun test_set_config_send_uln_type() {
    let mut scenario = test_scenario::begin(ADMIN);
    uln_302::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);

    let uln_admin_cap = scenario.take_from_sender<AdminCap>();
    let mut uln302 = scenario.take_shared<Uln302>();

    let mock_endpoint_cap = call_cap::new_package_cap_with_address_for_test(scenario.ctx(), @0x0);

    // Set up configs for EID 2 to make it supported
    let test_eid = 2;
    let uln_config = create_default_uln_config();
    let executor_config = create_default_executor_config();
    uln_302::set_default_receive_uln_config(&mut uln302, &uln_admin_cap, test_eid, uln_config);
    uln_302::set_default_send_uln_config(&mut uln302, &uln_admin_cap, test_eid, uln_config);
    uln_302::set_default_executor_config(&mut uln302, &uln_admin_cap, test_eid, executor_config);

    // Create a message_lib_set_config call with CONFIG_TYPE_SEND_ULN (2)
    // Using valid BCS-encoded OApp ULN config
    let config_bytes = create_oapp_uln_config_bytes();

    let set_config_param = message_lib_set_config::create_param_for_test(
        @0x123, // oapp address
        test_eid,
        CONFIG_TYPE_SEND_ULN,
        config_bytes,
    );

    let message_lib_call = call::create(
        &mock_endpoint_cap,
        uln_302::get_call_cap(&uln302).id(),
        true, // one_way
        set_config_param,
        scenario.ctx(),
    );

    // This should succeed and set the send ULN config for the OApp
    uln_302::set_config(&mut uln302, message_lib_call);

    // Verify the send ULN config was actually set by retrieving it
    let retrieved_config = uln_302::get_effective_send_uln_config(&uln302, @0x123, test_eid);
    assert!(uln_config::confirmations(&retrieved_config) == 35, 0);
    let required_dvns = uln_config::required_dvns(&retrieved_config);
    assert!(required_dvns.length() == 2, 1);
    assert!(required_dvns[0] == @0xfeed, 2);
    assert!(required_dvns[1] == @0xbeef, 3);

    // Cleanup
    // message_lib_call is consumed by set_config
    test_utils::destroy(mock_endpoint_cap);
    scenario.return_to_sender(uln_admin_cap);
    test_scenario::return_shared(uln302);
    scenario.end();
}

#[test]
fun test_set_config_receive_uln_type() {
    let mut scenario = test_scenario::begin(ADMIN);
    uln_302::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);

    let uln_admin_cap = scenario.take_from_sender<AdminCap>();
    let mut uln302 = scenario.take_shared<Uln302>();

    let mock_endpoint_cap = call_cap::new_package_cap_with_address_for_test(scenario.ctx(), @0x0);

    // Set up configs for EID 2 to make it supported
    let test_eid = 2;
    let uln_config = create_default_uln_config();
    let executor_config = create_default_executor_config();
    uln_302::set_default_receive_uln_config(&mut uln302, &uln_admin_cap, test_eid, uln_config);
    uln_302::set_default_send_uln_config(&mut uln302, &uln_admin_cap, test_eid, uln_config);
    uln_302::set_default_executor_config(&mut uln302, &uln_admin_cap, test_eid, executor_config);

    // Create a message_lib_set_config call with CONFIG_TYPE_RECEIVE_ULN (3)
    // Using valid BCS-encoded OApp ULN config
    let config_bytes = create_oapp_uln_config_bytes();

    let set_config_param = message_lib_set_config::create_param_for_test(
        @0x123, // oapp address
        test_eid,
        CONFIG_TYPE_RECEIVE_ULN,
        config_bytes,
    );

    let message_lib_call = call::create(
        &mock_endpoint_cap,
        uln_302::get_call_cap(&uln302).id(),
        true, // one_way
        set_config_param,
        scenario.ctx(),
    );

    // This should succeed and set the receive ULN config for the OApp
    uln_302::set_config(&mut uln302, message_lib_call);

    // Verify the receive ULN config was actually set by retrieving it
    let retrieved_config = uln_302::get_effective_receive_uln_config(&uln302, @0x123, test_eid);
    assert!(uln_config::confirmations(&retrieved_config) == 35, 0);
    let required_dvns = uln_config::required_dvns(&retrieved_config);
    assert!(required_dvns.length() == 2, 1);
    assert!(required_dvns[0] == @0xfeed, 2);
    assert!(required_dvns[1] == @0xbeef, 3);

    // Cleanup
    // message_lib_call is consumed by set_config
    test_utils::destroy(mock_endpoint_cap);
    scenario.return_to_sender(uln_admin_cap);
    test_scenario::return_shared(uln302);
    scenario.end();
}

#[test]
fun test_oapp_specific_config_getters() {
    let mut scenario = test_scenario::begin(ADMIN);
    uln_302::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);

    let uln_admin_cap = scenario.take_from_sender<AdminCap>();
    let mut uln302 = scenario.take_shared<Uln302>();

    let mock_endpoint_cap = call_cap::new_package_cap_with_address_for_test(scenario.ctx(), @0x0);

    // Set up default configs for EID 2 to make it supported
    let test_eid = 2;
    let default_uln_config = create_default_uln_config();
    let default_executor_config = create_default_executor_config();
    uln_302::set_default_receive_uln_config(&mut uln302, &uln_admin_cap, test_eid, default_uln_config);
    uln_302::set_default_send_uln_config(&mut uln302, &uln_admin_cap, test_eid, default_uln_config);
    uln_302::set_default_executor_config(&mut uln302, &uln_admin_cap, test_eid, default_executor_config);

    let oapp_address = @0x123;

    // === Test 1: Set and get OApp executor config ===
    let executor_config_bytes = create_executor_config_bytes();
    let set_executor_param = message_lib_set_config::create_param_for_test(
        oapp_address,
        test_eid,
        1, // CONFIG_TYPE_EXECUTOR
        executor_config_bytes,
    );

    let executor_call = call::create(
        &mock_endpoint_cap,
        uln_302::get_call_cap(&uln302).id(),
        true, // one_way
        set_executor_param,
        scenario.ctx(),
    );

    uln_302::set_config(&mut uln302, executor_call);

    // Now test get_oapp_executor_config
    let oapp_executor_config = uln_302::get_oapp_executor_config(&uln302, oapp_address, test_eid);
    assert!(executor_config::max_message_size(oapp_executor_config) == 9999, 0);
    assert!(executor_config::executor(oapp_executor_config) == @0xabcd, 1);

    // === Test 2: Set and get OApp send ULN config ===
    let send_uln_config_bytes = create_oapp_uln_config_bytes();
    let set_send_uln_param = message_lib_set_config::create_param_for_test(
        oapp_address,
        test_eid,
        2, // CONFIG_TYPE_SEND_ULN
        send_uln_config_bytes,
    );

    let send_uln_call = call::create(
        &mock_endpoint_cap,
        uln_302::get_call_cap(&uln302).id(),
        true, // one_way
        set_send_uln_param,
        scenario.ctx(),
    );

    uln_302::set_config(&mut uln302, send_uln_call);

    // Now test get_oapp_send_uln_config
    let oapp_send_uln_config = uln_302::get_oapp_send_uln_config(&uln302, oapp_address, test_eid);
    let uln_config = oapp_uln_config::uln_config(oapp_send_uln_config);
    assert!(uln_config::confirmations(uln_config) == 35, 2);
    let required_dvns = uln_config::required_dvns(uln_config);
    assert!(required_dvns.length() == 2, 3);
    assert!(required_dvns[0] == @0xfeed, 4);
    assert!(required_dvns[1] == @0xbeef, 5);

    // === Test 3: Set and get OApp receive ULN config ===
    let receive_uln_config_bytes = create_oapp_uln_config_bytes();
    let set_receive_uln_param = message_lib_set_config::create_param_for_test(
        oapp_address,
        test_eid,
        3, // CONFIG_TYPE_RECEIVE_ULN
        receive_uln_config_bytes,
    );

    let receive_uln_call = call::create(
        &mock_endpoint_cap,
        uln_302::get_call_cap(&uln302).id(),
        true, // one_way
        set_receive_uln_param,
        scenario.ctx(),
    );

    uln_302::set_config(&mut uln302, receive_uln_call);

    // Now test get_oapp_receive_uln_config
    let oapp_receive_uln_config = uln_302::get_oapp_receive_uln_config(&uln302, oapp_address, test_eid);
    let uln_config = oapp_uln_config::uln_config(oapp_receive_uln_config);
    assert!(uln_config::confirmations(uln_config) == 35, 6);
    let required_dvns = uln_config::required_dvns(uln_config);
    assert!(required_dvns.length() == 2, 7);
    assert!(required_dvns[0] == @0xfeed, 8);
    assert!(required_dvns[1] == @0xbeef, 9);

    // Cleanup
    // executor_call is consumed by set_config
    // send_uln_call is consumed by set_config
    // receive_uln_call is consumed by set_config
    test_utils::destroy(mock_endpoint_cap);
    scenario.return_to_sender(uln_admin_cap);
    test_scenario::return_shared(uln302);
    scenario.end();
}

#[test]
fun test_uln302_quote() {
    // SETUP: Initialize endpoint, ULN-302, treasury
    let mut scenario = test_scenario::begin(ADMIN);
    endpoint_v2::init_for_test(scenario.ctx());
    uln_302::init_for_test(scenario.ctx());
    treasury::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);

    let endpoint_admin_cap = scenario.take_from_sender<EndpointAdminCap>();
    let uln_admin_cap = scenario.take_from_sender<AdminCap>();
    let endpoint = scenario.take_shared<EndpointV2>();
    let mut uln302 = scenario.take_shared<Uln302>();
    let treasury = scenario.take_shared<Treasury>();

    // No endpoint EID initialization needed for quote testing

    // SETUP: Create mock workers and configure ULN
    let mock_executor = create_mock_executor(scenario.ctx());
    let mock_dvn1 = create_mock_dvn(scenario.ctx());
    let mock_dvn2 = create_mock_dvn(scenario.ctx());

    let mock_executor_addr = executor_call_cap(&mock_executor);
    let mock_dvn1_addr = dvn_call_cap(&mock_dvn1);
    let mock_dvn2_addr = dvn_call_cap(&mock_dvn2);

    // Configure ULN-302 with mock worker addresses
    let dst_eid = 40102u32; // Remote endpoint ID

    // Set default executor config for the destination
    let executor_config = executor_config::create(65000u64, mock_executor_addr);
    uln_302::set_default_executor_config(&mut uln302, &uln_admin_cap, dst_eid, executor_config);

    // Set default send ULN config with our mock DVNs
    let send_uln_config = uln_config::create(15u64, vector[mock_dvn1_addr, mock_dvn2_addr], vector[], 0);
    uln_302::set_default_send_uln_config(&mut uln302, &uln_admin_cap, dst_eid, send_uln_config);

    // SETUP: Create mock endpoint CallCap and message parameters
    // Create a CallCap that matches the endpoint package address for caller validation
    let mock_endpoint_cap = call_cap::new_package_cap_with_address_for_test(
        scenario.ctx(),
        package::original_package_of_type<EndpointV2>(),
    );

    // Create message parameters for testing
    let receiver_bytes = x"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"; // 32 bytes
    let message = b"Hello LayerZero V2!";
    let options = x"0003"; // Valid options
    let pay_in_zro = false;

    // Create the outbound packet and quote param
    let src_eid = 40101u32; // Source endpoint ID
    let packet = outbound_packet::create_for_test(
        1u64, // nonce
        src_eid,
        @0x111, // sender address
        dst_eid,
        bytes32::from_bytes(receiver_bytes),
        message,
    );
    let quote_param = message_lib_quote::create_param_for_test(
        packet,
        options,
        pay_in_zro,
    );

    // Create a mock call from endpoint to message lib (ULN-302)
    let mut message_lib_call = call::create<message_lib_quote::QuoteParam, messaging_fee::MessagingFee>(
        &mock_endpoint_cap,
        uln_302::get_call_cap(&uln302).id(),
        false, // two_way (not one_way)
        quote_param,
        scenario.ctx(),
    );

    // TEST ULN-302 QUOTE FUNCTION DIRECTLY
    let (mut executor_call, dvn_multicall) = uln_302::quote(&uln302, &mut message_lib_call, scenario.ctx());

    // Verify that ULN-302 created the worker calls correctly
    assert!(call::status(&message_lib_call).is_waiting(), 0);
    assert!(call::child_batch(&message_lib_call).length() == 3, 1); // 1 executor + 2 DVNs

    // Verify the executor call was created correctly
    assert!(call::callee(&executor_call) == mock_executor_addr, 2);
    assert!(call::status(&executor_call).is_active(), 3);

    // COMPLETE EXECUTOR CALL
    executor_get_fee(&mock_executor, &mut executor_call, scenario.ctx());
    assert!(call::status(&executor_call).is_completed(), 4);
    assert!(call::result(&executor_call).is_some(), 5);

    // COMPLETE DVN CALLS
    let dvn_calls = dvn_multicall.destroy(uln_302::get_call_cap(&uln302));
    assert!(dvn_calls.length() == 2, 6);

    // Process each DVN call and collect completed ones for recreation of MultiCall
    let mut completed_dvn_calls = vector::empty<Call<DvnGetFeeParam, u64>>();
    dvn_calls.do!(|mut dvn_call| {
        // Determine which DVN this call belongs to and get the appropriate CallCap
        let callee = call::callee(&dvn_call);
        let dvn_ref = if (callee == mock_dvn1_addr) {
            &mock_dvn1
        } else {
            &mock_dvn2
        };

        // Complete the DVN call
        dvn_get_fee(dvn_ref, &mut dvn_call, scenario.ctx());

        // Verify the call was completed
        assert!(call::status(&dvn_call).is_completed(), 7);
        assert!(call::result(&dvn_call).is_some(), 8);

        // Add completed call to the new vector
        completed_dvn_calls.push_back(dvn_call);
    });

    // RECREATE MULTICALL FROM COMPLETED DVN CALLS
    let completed_dvn_multicall = multi_call::create(uln_302::get_call_cap(&uln302), completed_dvn_calls);

    // TEST CONFIRM_QUOTE WITH COMPLETED CALLS
    uln_302::confirm_quote(
        &uln302,
        &treasury,
        &mut message_lib_call,
        executor_call,
        completed_dvn_multicall,
    );

    // VERIFY THAT THE MESSAGE LIB CALL WAS COMPLETED BY CONFIRM_QUOTE
    assert!(call::status(&message_lib_call).is_completed(), 9);
    assert!(call::result(&message_lib_call).is_some(), 10);

    // Extract and verify the messaging fee result
    let messaging_fee_result = call::result(&message_lib_call);
    assert!(messaging_fee_result.is_some(), 11);
    let messaging_fee_ref = messaging_fee_result.borrow();

    // Verify messaging fee contains expected values (1000 + 500 + 500 = 2000 native fee)
    let native_fee = messaging_fee::native_fee(messaging_fee_ref);
    assert!(native_fee == 2000, 12);

    // Cleanup
    let (_, _, _) = message_lib_call.destroy(&mock_endpoint_cap);
    test_utils::destroy(mock_endpoint_cap);
    test_utils::destroy(mock_executor);
    test_utils::destroy(mock_dvn1);
    test_utils::destroy(mock_dvn2);
    scenario.return_to_sender(endpoint_admin_cap);
    scenario.return_to_sender(uln_admin_cap);
    test_scenario::return_shared(endpoint);
    test_scenario::return_shared(uln302);
    test_scenario::return_shared(treasury);
    scenario.end();
}

#[test]
fun test_uln302_send() {
    // SETUP: Initialize endpoint, ULN-302, treasury
    let mut scenario = test_scenario::begin(ADMIN);
    endpoint_v2::init_for_test(scenario.ctx());
    uln_302::init_for_test(scenario.ctx());
    treasury::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);

    let endpoint_admin_cap = scenario.take_from_sender<EndpointAdminCap>();
    let uln_admin_cap = scenario.take_from_sender<AdminCap>();
    let endpoint = scenario.take_shared<EndpointV2>();
    let mut uln302 = scenario.take_shared<Uln302>();
    let treasury = scenario.take_shared<Treasury>();

    // No endpoint EID initialization needed for send testing

    // SETUP: Create mock workers and configure ULN
    let mock_executor = create_mock_executor(scenario.ctx());
    let mock_dvn1 = create_mock_dvn(scenario.ctx());
    let mock_dvn2 = create_mock_dvn(scenario.ctx());

    let mock_executor_addr = executor_call_cap(&mock_executor);
    let mock_dvn1_addr = dvn_call_cap(&mock_dvn1);
    let mock_dvn2_addr = dvn_call_cap(&mock_dvn2);

    // Configure ULN-302 with mock worker addresses
    let dst_eid = 40102u32; // Remote endpoint ID

    // Set default executor config for the destination
    let executor_config = executor_config::create(65000u64, mock_executor_addr);
    uln_302::set_default_executor_config(&mut uln302, &uln_admin_cap, dst_eid, executor_config);

    // Set default send ULN config with our mock DVNs
    let send_uln_config = uln_config::create(15u64, vector[mock_dvn1_addr, mock_dvn2_addr], vector[], 0);
    uln_302::set_default_send_uln_config(&mut uln302, &uln_admin_cap, dst_eid, send_uln_config);

    // Also set default receive ULN config to make the EID fully supported
    let receive_uln_config = uln_config::create(15u64, vector[mock_dvn1_addr, mock_dvn2_addr], vector[], 0);
    uln_302::set_default_receive_uln_config(&mut uln302, &uln_admin_cap, dst_eid, receive_uln_config);

    // SETUP: Create mock endpoint CallCap and message parameters
    let mock_endpoint_cap = call_cap::new_package_cap_with_address_for_test(
        scenario.ctx(),
        package::original_package_of_type<EndpointV2>(),
    );

    // Create message parameters for testing
    let receiver_bytes = x"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"; // 32 bytes
    let message = b"Hello LayerZero V2 Send!";
    let options = x"0003"; // Valid options
    let pay_in_zro = false;

    // Create the send param (which wraps a quote param)
    let src_eid = 40101u32; // Source endpoint ID
    let packet = outbound_packet::create_for_test(
        1u64, // nonce
        src_eid,
        @0x111, // sender address
        dst_eid,
        bytes32::from_bytes(receiver_bytes),
        message,
    );
    let quote_param = message_lib_quote::create_param_for_test(
        packet,
        options,
        pay_in_zro,
    );
    let send_param = message_lib_send::create_param_for_test(quote_param);

    // Create a mock call from endpoint to message lib (ULN-302)
    let mut message_lib_call = call::create<message_lib_send::SendParam, message_lib_send::SendResult>(
        &mock_endpoint_cap,
        uln_302::get_call_cap(&uln302).id(),
        false, // two_way (not one_way)
        send_param,
        scenario.ctx(),
    );

    // TEST ULN-302 SEND FUNCTION DIRECTLY
    let (mut executor_call, dvn_multicall) = uln_302::send(&uln302, &mut message_lib_call, scenario.ctx());

    // Note: message_lib_call is now in waiting status with child calls

    // Verify that ULN-302 created the worker calls correctly
    assert!(call::status(&message_lib_call).is_waiting(), 0);
    assert!(call::child_batch(&message_lib_call).length() == 3, 1); // 1 executor + 2 DVNs

    // Verify the executor call was created correctly
    assert!(call::callee(&executor_call) == mock_executor_addr, 2);
    assert!(call::status(&executor_call).is_active(), 3);

    // COMPLETE EXECUTOR CALL (assign_job instead of get_fee for send)
    executor_assign_job(&mock_executor, &mut executor_call, scenario.ctx());
    assert!(call::status(&executor_call).is_completed(), 4);
    assert!(call::result(&executor_call).is_some(), 5);

    // COMPLETE DVN CALLS (assign_job instead of get_fee for send)
    let dvn_calls = dvn_multicall.destroy(uln_302::get_call_cap(&uln302));
    assert!(dvn_calls.length() == 2, 6);

    // Process each DVN call and collect completed ones for recreation of MultiCall
    let mut completed_dvn_calls = vector::empty<Call<dvn_assign_job::AssignJobParam, FeeRecipient>>();
    dvn_calls.do!(|mut dvn_call| {
        // Determine which DVN this call belongs to and get the appropriate CallCap
        let callee = call::callee(&dvn_call);
        let dvn_ref = if (callee == mock_dvn1_addr) {
            &mock_dvn1
        } else {
            &mock_dvn2
        };

        // Complete the DVN call
        dvn_assign_job(dvn_ref, &mut dvn_call, scenario.ctx());

        // Verify the call was completed
        assert!(call::status(&dvn_call).is_completed(), 7);
        assert!(call::result(&dvn_call).is_some(), 8);

        // Add completed call to the new vector
        completed_dvn_calls.push_back(dvn_call);
    });

    // RECREATE MULTICALL FROM COMPLETED DVN CALLS
    let completed_dvn_multicall = multi_call::create(uln_302::get_call_cap(&uln302), completed_dvn_calls);

    // VERIFY SEND WORKFLOW COMPLETED SUCCESSFULLY

    // Verify executor result
    assert!(call::status(&executor_call).is_completed(), 16);
    assert!(call::result(&executor_call).is_some(), 17);

    // Extract and verify executor fee recipient
    let executor_result_opt = call::result(&executor_call);
    assert!(executor_result_opt.is_some(), 18);
    let executor_fee_recipient = executor_result_opt.borrow();
    assert!(fee_recipient::fee(executor_fee_recipient) == 1000, 19);
    assert!(fee_recipient::recipient(executor_fee_recipient) == mock_executor_addr, 20);

    // Verify DVN multicall results
    assert!(completed_dvn_multicall.length() == 2, 21);

    // Verify each DVN call was completed correctly
    let dvn_calls_for_verification = completed_dvn_multicall.destroy(uln_302::get_call_cap(&uln302));
    let mut verified_count = 0u64;
    dvn_calls_for_verification.do!(|dvn_call| {
        // Verify the call was completed
        assert!(call::status(&dvn_call).is_completed(), 22);
        assert!(call::result(&dvn_call).is_some(), 23);
        let dvn_fee_recipient = call::result(&dvn_call).borrow();
        assert!(fee_recipient::fee(dvn_fee_recipient) == 500, 24);
        verified_count = verified_count + 1;

        // Clean up the call
        let (_, _, dvn_fee_recipient_owned) = call::destroy_child(
            &mut message_lib_call,
            uln_302::get_call_cap(&uln302),
            dvn_call,
        );
        test_utils::destroy(dvn_fee_recipient_owned);
    });

    // Verify we checked both DVN calls
    assert!(verified_count == 2, 25);

    // Cleanup executor call
    let (_, _, executor_fee_recipient_owned) = call::destroy_child(
        &mut message_lib_call,
        uln_302::get_call_cap(&uln302),
        executor_call,
    );
    test_utils::destroy(executor_fee_recipient_owned);

    // After all child calls are destroyed, the parent call returns to Active status
    // We need to complete it before destroying
    assert!(call::status(&message_lib_call).is_active(), 26);

    // Complete the parent call with a mock result
    // Create a mock encoded packet and messaging fee
    let encoded_packet = x"0000000000000000000000000000000000000000000000000000000000000001";
    let messaging_fee = messaging_fee::create(10000u64, 0u64); // 10000 native fee, 0 zro fee
    let mock_result = message_lib_send::create_result(encoded_packet, messaging_fee);
    call::complete(&mut message_lib_call, uln_302::get_call_cap(&uln302), mock_result);

    // Now we can destroy the completed call
    let (_, _, _) = message_lib_call.destroy(&mock_endpoint_cap);
    test_utils::destroy(mock_endpoint_cap);
    test_utils::destroy(mock_executor);
    test_utils::destroy(mock_dvn1);
    test_utils::destroy(mock_dvn2);
    scenario.return_to_sender(endpoint_admin_cap);
    scenario.return_to_sender(uln_admin_cap);
    test_scenario::return_shared(endpoint);
    test_scenario::return_shared(uln302);
    test_scenario::return_shared(treasury);
    scenario.end();
}
