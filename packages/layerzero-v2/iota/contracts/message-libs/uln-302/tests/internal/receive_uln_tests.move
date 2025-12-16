#[test_only]
module uln_302::receive_uln_tests;

use iota::{event, test_scenario::{Self as ts, Scenario}, test_utils};
use uln_302::{
    oapp_uln_config,
    receive_uln::{Self, ReceiveUln, Verification, DefaultUlnConfigSetEvent, UlnConfigSetEvent, PayloadVerifiedEvent},
    uln_config::{Self, UlnConfig}
};
use utils::{buffer_writer, bytes32::{Self, Bytes32}};

// === Test Constants ===
const ADMIN: address = @0x0;
const SRC_EID: u32 = 1;
const DST_EID: u32 = 2;
const RECEIVER: address = @0x123;
const DVN1: address = @0x999;
const DVN2: address = @0x888;
const DVN3: address = @0x777;
const CONFIRMATIONS: u64 = 10;

// === Helper Functions ===

fun setup_test_environment(): (Scenario, ReceiveUln, Verification) {
    let mut scenario = ts::begin(ADMIN);
    let receive_uln = receive_uln::new_receive_uln(scenario.ctx());
    scenario.next_tx(ADMIN);
    let verification = scenario.take_shared<Verification>();
    (scenario, receive_uln, verification)
}

fun create_test_uln_config(): UlnConfig {
    uln_config::create(
        CONFIRMATIONS, // confirmations
        vector[DVN1, DVN2], // required_dvns
        vector[DVN3], // optional_dvns
        1, // optional_dvn_threshold
    )
}

fun create_test_packet_header(): vector<u8> {
    // Create a properly formatted packet header using buffer_writer
    // Header format: version(1) + nonce(8) + src_eid(4) + sender(32) + dst_eid(4) + receiver(32) = 81 bytes
    let mut writer = buffer_writer::new();
    writer
        .write_u8(1)
        .write_u64(12345)
        .write_u32(SRC_EID)
        .write_bytes32(bytes32::from_address(@0x456))
        .write_u32(DST_EID)
        .write_bytes32(bytes32::from_address(RECEIVER));
    writer.to_bytes()
}

fun create_test_payload_hash(): Bytes32 {
    bytes32::from_address(@0xdeadbeef)
}

fun cleanup_test_environment(scenario: Scenario, receive_uln: ReceiveUln, verification: Verification) {
    test_utils::destroy(receive_uln);
    ts::return_shared(verification);
    scenario.end();
}

// === End Helper Functions ===

#[test]
fun test_configuration_management_comprehensive() {
    let (scenario, mut receive_uln, verification) = setup_test_environment();

    // Test 1: Initial state - no configurations should exist
    assert!(!receive_uln.is_supported_eid(SRC_EID), 0);

    // Test 2: Set and verify default config
    let config = create_test_uln_config();
    receive_uln.set_default_uln_config(SRC_EID, config);

    // Verify config was set correctly
    let retrieved_config = receive_uln.get_default_uln_config(SRC_EID);
    assert!(retrieved_config.required_dvns() == vector[DVN1, DVN2], 1);
    assert!(retrieved_config.optional_dvns() == vector[DVN3], 2);
    assert!(retrieved_config.optional_dvn_threshold() == 1, 3);
    assert!(retrieved_config.confirmations() == CONFIRMATIONS, 4);

    // Verify EID is now supported
    assert!(receive_uln.is_supported_eid(SRC_EID), 5);

    // Verify event was emitted
    let events = event::events_by_type<DefaultUlnConfigSetEvent>();
    assert!(events.length() == 1, 6);

    let expected_event = receive_uln::create_default_uln_config_set_event(SRC_EID, config);
    assert!(events[0] == expected_event, 7);

    cleanup_test_environment(scenario, receive_uln, verification);
}

#[test]
fun test_set_oapp_uln_config() {
    let (scenario, mut receive_uln, verification) = setup_test_environment();

    // First set default config (required)
    let default_config = create_test_uln_config();
    receive_uln.set_default_uln_config(SRC_EID, default_config);

    // Set OApp-specific config
    let uln_config = uln_config::create(
        CONFIRMATIONS + 5, // confirmations
        vector[DVN1], // required_dvns
        vector[DVN2, DVN3], // optional_dvns
        2, // optional_dvn_threshold
    );
    let oapp_config = oapp_uln_config::create(
        false, // use_default_confirmations
        false, // use_default_required_dvns
        false, // use_default_optional_dvns
        uln_config,
    );
    receive_uln.set_uln_config(RECEIVER, SRC_EID, oapp_config);

    // Verify OApp config was set
    let retrieved_config = receive_uln.get_oapp_uln_config(RECEIVER, SRC_EID);
    assert!(!retrieved_config.use_default_required_dvns(), 0);
    assert!(!retrieved_config.use_default_optional_dvns(), 1);
    assert!(!retrieved_config.use_default_confirmations(), 2);
    assert!(retrieved_config.uln_config().confirmations() == CONFIRMATIONS + 5, 3);

    // Verify events were emitted (default config + oapp config)
    let default_events = event::events_by_type<DefaultUlnConfigSetEvent>();
    let oapp_events = event::events_by_type<UlnConfigSetEvent>();
    assert!(default_events.length() == 1, 4);
    assert!(oapp_events.length() == 1, 5);

    // Verify default config event content
    let expected_default_event = receive_uln::create_default_uln_config_set_event(SRC_EID, default_config);
    assert!(default_events[0] == expected_default_event, 6);

    // Verify OApp config event content
    let expected_oapp_event = receive_uln::create_uln_config_set_event(RECEIVER, SRC_EID, oapp_config);
    assert!(oapp_events[0] == expected_oapp_event, 7);

    cleanup_test_environment(scenario, receive_uln, verification);
}

#[test]
fun test_verify_and_reclaim_storage() {
    let (scenario, mut receive_uln, mut verification) = setup_test_environment();

    // Setup config
    let config = create_test_uln_config();
    receive_uln.set_default_uln_config(SRC_EID, config);

    // Create test data
    let packet_header = create_test_packet_header();
    let payload_hash = create_test_payload_hash();

    // Verify with all required DVNs
    verification.verify(DVN1, packet_header, payload_hash, CONFIRMATIONS);
    verification.verify(DVN2, packet_header, payload_hash, CONFIRMATIONS);
    verification.verify(DVN3, packet_header, payload_hash, CONFIRMATIONS);

    // Verify and reclaim storage
    let decoded_header = receive_uln.verify_and_reclaim_storage(
        &mut verification,
        DST_EID,
        packet_header,
        payload_hash,
    );

    // Verify decoded header is correct
    assert!(decoded_header.src_eid() == SRC_EID, 0);
    assert!(decoded_header.dst_eid() == DST_EID, 1);
    assert!(decoded_header.receiver().to_address() == RECEIVER, 2);

    cleanup_test_environment(scenario, receive_uln, verification);
}

#[test]
#[expected_failure(abort_code = receive_uln::EConfirmationsNotFound)]
fun test_confirmations_not_found_after_storage_reclamation() {
    let (scenario, mut receive_uln, mut verification) = setup_test_environment();

    // Setup config
    let config = create_test_uln_config();
    receive_uln.set_default_uln_config(SRC_EID, config);

    // Create test data
    let packet_header = create_test_packet_header();
    let payload_hash = create_test_payload_hash();
    let header_hash = utils::hash::keccak256!(&packet_header);

    // Verify with all required DVNs
    verification.verify(DVN1, packet_header, payload_hash, CONFIRMATIONS);
    verification.verify(DVN2, packet_header, payload_hash, CONFIRMATIONS);
    verification.verify(DVN3, packet_header, payload_hash, CONFIRMATIONS);

    // Verify and reclaim storage
    let _decoded_header = receive_uln.verify_and_reclaim_storage(
        &mut verification,
        DST_EID,
        packet_header,
        payload_hash,
    );

    // This should fail with EConfirmationsNotFound because storage was reclaimed
    let _confirmations = verification.get_confirmations(DVN1, header_hash, payload_hash);

    cleanup_test_environment(scenario, receive_uln, verification);
}

#[test]
#[expected_failure(abort_code = receive_uln::EDefaultUlnConfigNotFound)]
fun test_get_default_config_not_found() {
    let (scenario, receive_uln, verification) = setup_test_environment();

    // Try to get config for non-existent EID
    let _config = receive_uln.get_default_uln_config(999);

    cleanup_test_environment(scenario, receive_uln, verification);
}

#[test]
#[expected_failure(abort_code = receive_uln::EOAppUlnConfigNotFound)]
fun test_get_oapp_config_not_found() {
    let (scenario, mut receive_uln, verification) = setup_test_environment();

    // Set default config first
    let config = create_test_uln_config();
    receive_uln.set_default_uln_config(SRC_EID, config);

    // Try to get OApp config that doesn't exist
    let _config = receive_uln.get_oapp_uln_config(@0x999, SRC_EID);

    cleanup_test_environment(scenario, receive_uln, verification);
}

#[test]
fun test_verifiable_only_optional_dvns() {
    // Test case missing from IOTA: EVM test_verifyConditionMet_onlyOptionalDVNs()
    let (scenario, mut receive_uln, mut verification) = setup_test_environment();

    // Config with NO required DVNs, only optional DVNs with threshold = 1
    let config = uln_config::create(
        CONFIRMATIONS,
        vector[], // NO required DVNs
        vector[DVN1, DVN2], // 2 optional DVNs
        1, // threshold = 1 (need at least 1 optional DVN)
    );
    receive_uln.set_default_uln_config(SRC_EID, config);

    let packet_header = create_test_packet_header();
    let payload_hash = create_test_payload_hash();

    // Case 1: No DVN verifications → should NOT be verifiable
    let is_verifiable = receive_uln.verifiable(&verification, DST_EID, packet_header, payload_hash);
    assert!(!is_verifiable, 0);

    // Case 2: One optional DVN verifies → should be verifiable (meets threshold)
    verification.verify(DVN1, packet_header, payload_hash, CONFIRMATIONS);
    let is_verifiable = receive_uln.verifiable(&verification, DST_EID, packet_header, payload_hash);
    assert!(is_verifiable, 1);

    // Case 3: Both optional DVNs verify → still verifiable
    verification.verify(DVN2, packet_header, payload_hash, CONFIRMATIONS);
    let is_verifiable = receive_uln.verifiable(&verification, DST_EID, packet_header, payload_hash);
    assert!(is_verifiable, 2);

    cleanup_test_environment(scenario, receive_uln, verification);
}

#[test]
fun test_optional_dvn_threshold_edge_cases() {
    // Test various optional DVN threshold scenarios
    let (scenario, mut receive_uln, mut verification) = setup_test_environment();

    // Config: 1 required DVN + 3 optional DVNs with threshold = 2
    let config = uln_config::create(
        CONFIRMATIONS,
        vector[DVN1], // 1 required DVN
        vector[DVN2, DVN3, @0x666], // 3 optional DVNs
        2, // threshold = 2 (need at least 2 optional DVNs)
    );
    receive_uln.set_default_uln_config(SRC_EID, config);

    let packet_header = create_test_packet_header();
    let payload_hash = create_test_payload_hash();

    // Required DVN verifies but only 1 optional → NOT verifiable
    verification.verify(DVN1, packet_header, payload_hash, CONFIRMATIONS); // Required
    verification.verify(DVN2, packet_header, payload_hash, CONFIRMATIONS); // Optional 1/2
    let is_verifiable = receive_uln.verifiable(&verification, DST_EID, packet_header, payload_hash);
    assert!(!is_verifiable, 0);

    // Required + 2 optional DVNs → verifiable
    verification.verify(DVN3, packet_header, payload_hash, CONFIRMATIONS); // Optional 2/2
    let is_verifiable = receive_uln.verifiable(&verification, DST_EID, packet_header, payload_hash);
    assert!(is_verifiable, 1);

    cleanup_test_environment(scenario, receive_uln, verification);
}

#[test]
fun test_insufficient_confirmations() {
    // Test DVN verification with insufficient confirmations
    let (scenario, mut receive_uln, mut verification) = setup_test_environment();

    let config = create_test_uln_config(); // requires CONFIRMATIONS = 10
    receive_uln.set_default_uln_config(SRC_EID, config);

    let packet_header = create_test_packet_header();
    let payload_hash = create_test_payload_hash();

    // DVN1 verifies with insufficient confirmations
    verification.verify(DVN1, packet_header, payload_hash, CONFIRMATIONS - 1); // 9 < 10
    verification.verify(DVN2, packet_header, payload_hash, CONFIRMATIONS); // 10 = 10 ✓
    verification.verify(DVN3, packet_header, payload_hash, CONFIRMATIONS + 5); // 15 > 10 ✓

    // Should NOT be verifiable because DVN1 has insufficient confirmations
    let is_verifiable = receive_uln.verifiable(&verification, DST_EID, packet_header, payload_hash);
    assert!(!is_verifiable, 0);

    // Fix DVN1 confirmations
    verification.verify(DVN1, packet_header, payload_hash, CONFIRMATIONS);
    let is_verifiable = receive_uln.verifiable(&verification, DST_EID, packet_header, payload_hash);
    assert!(is_verifiable, 1);

    cleanup_test_environment(scenario, receive_uln, verification);
}

#[test]
#[expected_failure(abort_code = receive_uln::EInvalidEid)]
fun test_invalid_destination_eid() {
    // Test that verifiable fails with wrong destination EID
    let (scenario, mut receive_uln, verification) = setup_test_environment();

    let config = create_test_uln_config();
    receive_uln.set_default_uln_config(SRC_EID, config);

    let packet_header = create_test_packet_header(); // DST_EID = 2
    let payload_hash = create_test_payload_hash();

    // Try to verify with wrong local EID (should be DST_EID = 2)
    let _is_verifiable = receive_uln.verifiable(&verification, 999, packet_header, payload_hash);

    cleanup_test_environment(scenario, receive_uln, verification);
}

#[test]
fun test_dvn_verification_comprehensive() {
    // Comprehensive DVN verification test covering multiple scenarios
    let (scenario, mut receive_uln, mut verification) = setup_test_environment();

    let config = create_test_uln_config();
    receive_uln.set_default_uln_config(SRC_EID, config);

    let packet_header = create_test_packet_header();
    let payload_hash = create_test_payload_hash();
    let header_hash = utils::hash::keccak256!(&packet_header);

    // Test 1: Single DVN verification recording
    verification.verify(DVN1, packet_header, payload_hash, CONFIRMATIONS);
    let recorded_confirmations = verification.get_confirmations(DVN1, header_hash, payload_hash);
    assert!(recorded_confirmations == CONFIRMATIONS, 0);

    // Test 2: DVN verification overwriting
    verification.verify(DVN1, packet_header, payload_hash, CONFIRMATIONS + 5);
    let updated_confirmations = verification.get_confirmations(DVN1, header_hash, payload_hash);
    assert!(updated_confirmations == CONFIRMATIONS + 5, 1);

    // Test 3: Complete verification workflow
    verification.verify(DVN1, packet_header, payload_hash, CONFIRMATIONS); // Reset to normal
    verification.verify(DVN2, packet_header, payload_hash, CONFIRMATIONS); // Required
    verification.verify(DVN3, packet_header, payload_hash, CONFIRMATIONS); // Optional

    // Test 4: Verify packet is verifiable with all DVNs
    let is_verifiable = receive_uln.verifiable(&verification, DST_EID, packet_header, payload_hash);
    assert!(is_verifiable, 2);

    // Test 5: Verify PayloadVerifiedEvent was emitted for each DVN
    let payload_events = event::events_by_type<PayloadVerifiedEvent>();
    assert!(payload_events.length() == 5, 3); // DVN1(3x) + DVN2(1x) + DVN3(1x) = 5 events

    // Verify content of final events (DVN1 final, DVN2, DVN3)
    let expected_dvn1_event = receive_uln::create_payload_verified_event(
        DVN1,
        packet_header,
        CONFIRMATIONS,
        payload_hash,
    );
    let expected_dvn2_event = receive_uln::create_payload_verified_event(
        DVN2,
        packet_header,
        CONFIRMATIONS,
        payload_hash,
    );
    let expected_dvn3_event = receive_uln::create_payload_verified_event(
        DVN3,
        packet_header,
        CONFIRMATIONS,
        payload_hash,
    );

    // Check the last 3 events (latest verification for each DVN)
    assert!(payload_events[2] == expected_dvn1_event, 4); // DVN1 final verification
    assert!(payload_events[3] == expected_dvn2_event, 5); // DVN2 verification
    assert!(payload_events[4] == expected_dvn3_event, 6); // DVN3 verification

    cleanup_test_environment(scenario, receive_uln, verification);
}

#[test]
fun test_verifiable_internal_comprehensive() {
    let (scenario, mut receive_uln, mut verification) = setup_test_environment();

    let config = create_test_uln_config();
    receive_uln.set_default_uln_config(SRC_EID, config);

    let packet_header = create_test_packet_header();
    let payload_hash = create_test_payload_hash();
    let header_hash = utils::hash::keccak256!(&packet_header);

    // Test 1: No DVN verifications - should NOT be verifiable
    let is_verifiable = receive_uln::verifiable_internal_for_test(&verification, &config, header_hash, payload_hash);
    assert!(!is_verifiable, 0);

    // Test 2: Only some required DVNs verified - should NOT be verifiable
    verification.verify(DVN1, packet_header, payload_hash, CONFIRMATIONS);
    let is_verifiable = receive_uln::verifiable_internal_for_test(&verification, &config, header_hash, payload_hash);
    assert!(!is_verifiable, 1);

    // Test 3: All required DVNs verified but insufficient optional - should NOT be verifiable
    verification.verify(DVN2, packet_header, payload_hash, CONFIRMATIONS);
    let is_verifiable = receive_uln::verifiable_internal_for_test(&verification, &config, header_hash, payload_hash);
    assert!(!is_verifiable, 2);

    // Test 4: All required + sufficient optional DVNs - should be verifiable
    verification.verify(DVN3, packet_header, payload_hash, CONFIRMATIONS);
    let is_verifiable = receive_uln::verifiable_internal_for_test(&verification, &config, header_hash, payload_hash);
    assert!(is_verifiable, 3);

    cleanup_test_environment(scenario, receive_uln, verification);
}

#[test]
fun test_verified_internal_comprehensive() {
    let (scenario, receive_uln, mut verification) = setup_test_environment();

    let packet_header = create_test_packet_header();
    let payload_hash = create_test_payload_hash();
    let header_hash = utils::hash::keccak256!(&packet_header);

    // Test 1: DVN not verified - should return false
    let is_verified = receive_uln::verified_for_test(&verification, DVN1, header_hash, payload_hash, CONFIRMATIONS);
    assert!(!is_verified, 0);

    // Test 2: DVN verified with insufficient confirmations - should return false
    verification.verify(DVN1, packet_header, payload_hash, CONFIRMATIONS - 1);
    let is_verified = receive_uln::verified_for_test(&verification, DVN1, header_hash, payload_hash, CONFIRMATIONS);
    assert!(!is_verified, 1);

    // Test 3: DVN verified with exact confirmations - should return true
    verification.verify(DVN1, packet_header, payload_hash, CONFIRMATIONS);
    let is_verified = receive_uln::verified_for_test(&verification, DVN1, header_hash, payload_hash, CONFIRMATIONS);
    assert!(is_verified, 2);

    // Test 4: DVN verified with more confirmations - should return true
    verification.verify(DVN1, packet_header, payload_hash, CONFIRMATIONS + 5);
    let is_verified = receive_uln::verified_for_test(&verification, DVN1, header_hash, payload_hash, CONFIRMATIONS);
    assert!(is_verified, 3);

    cleanup_test_environment(scenario, receive_uln, verification);
}

#[test]
fun test_verify_and_reclaim_storage_internal_success() {
    let (scenario, mut receive_uln, mut verification) = setup_test_environment();

    let config = create_test_uln_config();
    receive_uln.set_default_uln_config(SRC_EID, config);

    let packet_header = create_test_packet_header();
    let payload_hash = create_test_payload_hash();
    let header_hash = utils::hash::keccak256!(&packet_header);

    // Setup: Verify with all required DVNs + optional DVN
    verification.verify(DVN1, packet_header, payload_hash, CONFIRMATIONS);
    verification.verify(DVN2, packet_header, payload_hash, CONFIRMATIONS);
    verification.verify(DVN3, packet_header, payload_hash, CONFIRMATIONS);

    // Verify confirmations exist before reclamation
    let confirmations_before = verification.get_confirmations(DVN1, header_hash, payload_hash);
    assert!(confirmations_before == CONFIRMATIONS, 0);

    // Test: Reclaim storage (should succeed and clean up confirmations)
    receive_uln.verify_and_reclaim_storage(&mut verification, DST_EID, packet_header, payload_hash);

    let is_verifiable_after = receive_uln::verifiable_internal_for_test(
        &verification,
        &config,
        header_hash,
        payload_hash,
    );
    assert!(!is_verifiable_after, 1);

    cleanup_test_environment(scenario, receive_uln, verification);
}

#[test]
#[expected_failure(abort_code = receive_uln::EVerifying)]
fun test_verify_and_reclaim_storage_internal_insufficient_verification() {
    let (scenario, mut receive_uln, mut verification) = setup_test_environment();

    let config = create_test_uln_config();
    receive_uln.set_default_uln_config(SRC_EID, config);

    let packet_header = create_test_packet_header();
    let payload_hash = create_test_payload_hash();

    // Setup: Only verify some DVNs (insufficient for verifiable_internal)
    verification.verify(DVN1, packet_header, payload_hash, CONFIRMATIONS);
    // Missing DVN2 (required) and DVN3 (optional but needed for threshold)

    // Test: Attempt to reclaim storage should fail with EVerifying
    receive_uln.verify_and_reclaim_storage(&mut verification, DST_EID, packet_header, payload_hash);

    cleanup_test_environment(scenario, receive_uln, verification);
}

#[test]
fun test_verify_events_comprehensive() {
    let (scenario, mut receive_uln, mut verification) = setup_test_environment();

    let config = create_test_uln_config();
    receive_uln.set_default_uln_config(SRC_EID, config);

    let packet_header = create_test_packet_header();
    let payload_hash = create_test_payload_hash();

    // Test PayloadVerifiedEvent emission for each DVN verification
    verification.verify(DVN1, packet_header, payload_hash, CONFIRMATIONS);
    verification.verify(DVN2, packet_header, payload_hash, CONFIRMATIONS + 5);
    verification.verify(DVN3, packet_header, payload_hash, CONFIRMATIONS + 10);

    // Verify exactly 3 PayloadVerifiedEvent were emitted
    let payload_events = event::events_by_type<PayloadVerifiedEvent>();
    assert!(payload_events.length() == 3, 0);

    // Verify event content for each DVN verification
    let expected_dvn1_event = receive_uln::create_payload_verified_event(
        DVN1,
        packet_header,
        CONFIRMATIONS,
        payload_hash,
    );
    let expected_dvn2_event = receive_uln::create_payload_verified_event(
        DVN2,
        packet_header,
        CONFIRMATIONS + 5,
        payload_hash,
    );
    let expected_dvn3_event = receive_uln::create_payload_verified_event(
        DVN3,
        packet_header,
        CONFIRMATIONS + 10,
        payload_hash,
    );

    assert!(payload_events[0] == expected_dvn1_event, 1);
    assert!(payload_events[1] == expected_dvn2_event, 2);
    assert!(payload_events[2] == expected_dvn3_event, 3);

    cleanup_test_environment(scenario, receive_uln, verification);
}

#[test]
fun test_verifiable_internal_optional_threshold_zero() {
    // Test the branch: all required DVNs verified AND optional_dvn_threshold = 0 → should return true
    let (scenario, mut receive_uln, mut verification) = setup_test_environment();

    // Create config with required DVNs but optional_dvn_threshold = 0
    let config = uln_config::create(
        CONFIRMATIONS,
        vector[DVN1, DVN2], // required DVNs
        vector[], // NO optional DVNs (required for threshold = 0)
        0, // optional_dvn_threshold = 0
    );
    receive_uln.set_default_uln_config(SRC_EID, config);

    let packet_header = create_test_packet_header();
    let payload_hash = create_test_payload_hash();
    let header_hash = utils::hash::keccak256!(&packet_header);

    // Test 1: Missing required DVNs - should return false
    let is_verifiable = receive_uln::verifiable_internal_for_test(&verification, &config, header_hash, payload_hash);
    assert!(!is_verifiable, 0);

    // Test 2: All required DVNs verified, optional threshold = 0 - should return true
    verification.verify(DVN1, packet_header, payload_hash, CONFIRMATIONS);
    verification.verify(DVN2, packet_header, payload_hash, CONFIRMATIONS);
    // Note: No optional DVNs configured, threshold = 0 means early return true
    let is_verifiable = receive_uln::verifiable_internal_for_test(&verification, &config, header_hash, payload_hash);
    assert!(is_verifiable, 1);

    cleanup_test_environment(scenario, receive_uln, verification);
}
