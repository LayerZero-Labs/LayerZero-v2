#[test_only]
module layerzero_views::layerzero_views_tests;

use call::call_cap;
use dvn::{dvn::{Self, DVN}, hashes as dvn_hashes};
use endpoint_v2::{
    endpoint_v2::{Self, EndpointV2, AdminCap as EndpointAdminCap},
    message_lib_type,
    messaging_channel::{Self, MessagingChannel},
    outbound_packet
};
use layerzero_views::{endpoint_views, uln_302_views};
use message_lib_common::packet_v1_codec;
use sui::{clock, ecdsa_k1, test_scenario, test_utils};
use uln_302::{executor_config, receive_uln::Verification, uln_302::{Self, Uln302, AdminCap as UlnAdminCap}, uln_config};
use utils::{bytes32, hash};
use worker_common::worker_common::AdminCap as WorkerAdminCap;
use worker_registry::worker_registry;

// === Imports ===

// === Test Constants ===

const ADMIN: address = @0x123;
const OAPP_ADDRESS: address = @0x456;
const REMOTE_EID: u32 = 1;
const LOCAL_EID: u32 = 2;
const CONFIRMATIONS: u64 = 1;
const EXPIRATION_OFFSET: u64 = 3600000; // 1 hour

// === State Constants ===

const STATE_NOT_EXECUTABLE: u8 = 0;
const STATE_VERIFIED_BUT_NOT_EXECUTABLE: u8 = 1;
const STATE_EXECUTABLE: u8 = 2;
const STATE_EXECUTED: u8 = 3;

const STATE_VERIFYING: u8 = 0;
const STATE_VERIFIABLE: u8 = 1;
const STATE_VERIFIED: u8 = 2;
const STATE_NOT_INITIALIZABLE: u8 = 3;

// === Helper Functions ===

/// Creates a simple test keypair using a deterministic seed
fun create_test_keypair(): ecdsa_k1::KeyPair {
    let seed = x"0000000000000000000000000000000000000000000000000000000000000001";
    ecdsa_k1::secp256k1_keypair_from_seed(&seed)
}

/// Extracts 64-byte public key from keypair (removes compression prefix)
fun get_public_key_64_bytes(keypair: &ecdsa_k1::KeyPair): vector<u8> {
    let uncompressed_pubkey = ecdsa_k1::decompress_pubkey(keypair.public_key());
    vector::tabulate!(64, |i| uncompressed_pubkey[i + 1])
}

/// Asserts both endpoint and ULN verification states
fun assert_verification_states(
    endpoint: &EndpointV2,
    messaging_channel: &MessagingChannel,
    uln: &Uln302,
    verification: &Verification,
    packet_header_bytes: vector<u8>,
    payload_hash_bytes: vector<u8>,
    sender: bytes32::Bytes32,
    nonce: u64,
    expected_exec_state: u8,
    expected_verify_state: u8,
    error_code: u64,
) {
    // Check endpoint executable state
    let exec_state = endpoint_views::executable(
        messaging_channel,
        REMOTE_EID,
        sender.to_bytes(),
        nonce,
    );
    assert!(exec_state == expected_exec_state, error_code);

    // Check ULN verification state
    let verify_state = uln_302_views::verifiable(
        uln,
        verification,
        endpoint,
        messaging_channel,
        packet_header_bytes,
        payload_hash_bytes,
    );
    assert!(verify_state == expected_verify_state, error_code + 100);
}

// === Main Test ===

#[test]
fun test_verifiable() {
    // === Test Setup ===

    let mut scenario = test_scenario::begin(ADMIN);
    let clock = clock::create_for_testing(scenario.ctx());

    // === Infrastructure Setup ===

    // Setup Endpoint V2
    endpoint_v2::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);
    let endpoint_admin_cap = scenario.take_from_sender<EndpointAdminCap>();
    let mut endpoint = scenario.take_shared<EndpointV2>();
    endpoint.init_eid(&endpoint_admin_cap, LOCAL_EID);

    // Setup OApp and Messaging Channel
    let oapp_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let oapp_address = oapp_cap.id();
    let messaging_channel_address = messaging_channel::create_for_testing(oapp_address, scenario.ctx());
    scenario.next_tx(ADMIN);
    let mut messaging_channel = scenario.take_shared_by_id<MessagingChannel>(
        object::id_from_address(messaging_channel_address),
    );

    // Setup ULN 302 Message Library
    uln_302::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);
    let uln_admin_cap = scenario.take_from_sender<UlnAdminCap>();
    let mut uln = scenario.take_shared<Uln302>();

    // Get Verification object from ULN
    let mut verification = scenario.take_shared_by_id<Verification>(
        object::id_from_address(uln.get_verification()),
    );
    let _uln_address = utils::package::package_of_type<Uln302>();
    let uln_call_cap_address = uln.get_call_cap().id();

    // === DVN Infrastructure Setup ===

    // Setup DVN Fee Library
    let dvn_worker_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let dvn_address = dvn_worker_cap.id();
    let mut worker_registry = worker_registry::init_for_test(scenario.ctx());
    // Create DVN with test keypair
    let dvn_fee_lib_address = @0x2;
    let test_keypair = create_test_keypair();
    let signer_pubkey = get_public_key_64_bytes(&test_keypair);

    dvn::create_dvn(
        dvn_worker_cap,
        1, // vid (DVN ID)
        @0x789, // deposit address
        vector[uln_call_cap_address], // supported_message_libs
        @0x999, // price feed address
        dvn_fee_lib_address,
        10000, // 100% multiplier
        vector[ADMIN],
        vector[signer_pubkey],
        1, // quorum
        &mut worker_registry,
        scenario.ctx(),
    );
    scenario.next_tx(ADMIN);
    let mut dvn = scenario.take_shared<DVN>();
    let admin_cap = scenario.take_from_sender<WorkerAdminCap>();

    // === Message Data Setup ===

    let sender = bytes32::from_address(OAPP_ADDRESS);
    let receiver = bytes32::from_address(oapp_address);
    let nonce = 1u64;

    // Create outbound packet and extract components
    let outbound_packet = outbound_packet::create_for_test(
        nonce,
        REMOTE_EID,
        OAPP_ADDRESS,
        LOCAL_EID,
        receiver,
        b"test_payload",
    );
    let packet_header = packet_v1_codec::create_packet_header_for_testing(
        1u8, // version
        outbound_packet.nonce(),
        REMOTE_EID,
        sender,
        LOCAL_EID,
        receiver,
    );
    let packet_header_bytes = packet_v1_codec::encode_header(&packet_header);
    let payload_hash = packet_v1_codec::payload_hash(&outbound_packet);

    // === Channel and Library Configuration ===
    // Should return STATE_NOT_INITIALIZABLE since channel for this sender is not initialized
    assert!(
        uln_302_views::verifiable(
        &uln,
        &verification,
        &endpoint,
        &messaging_channel,
        packet_header_bytes,
        payload_hash.to_bytes(),
    ) == STATE_NOT_INITIALIZABLE,
        0,
    );
    // Initialize communication channel
    endpoint.init_channel(&oapp_cap, &mut messaging_channel, REMOTE_EID, sender, scenario.ctx());

    // Register ULN as receive library
    endpoint.register_library(
        &endpoint_admin_cap,
        uln_call_cap_address,
        message_lib_type::receive(),
    );

    // Configure ULN as default and specific receive library
    endpoint.set_default_receive_library(&endpoint_admin_cap, REMOTE_EID, uln_call_cap_address, 0, &clock);

    // === Configure DVN in ULN ===

    let uln_config = uln_config::create(
        CONFIRMATIONS,
        vector[dvn_address], // required DVNs
        vector[], // optional DVNs
        0, // optional threshold
    );
    uln.set_default_receive_uln_config(&uln_admin_cap, REMOTE_EID, uln_config);

    // Also set up send ULN config and executor config to make REMOTE_EID fully supported
    let send_uln_config = uln_config::create(
        CONFIRMATIONS,
        vector[dvn_address], // required DVNs
        vector[], // optional DVNs
        0, // optional threshold
    );
    uln.set_default_send_uln_config(&uln_admin_cap, REMOTE_EID, send_uln_config);

    let executor_config = executor_config::create(65000u64, @0x999); // dummy executor
    uln.set_default_executor_config(&uln_admin_cap, REMOTE_EID, executor_config);

    // Verify initial states: both should be in initial state
    assert_verification_states(
        &endpoint,
        &messaging_channel,
        &uln,
        &verification,
        packet_header_bytes,
        payload_hash.to_bytes(),
        sender,
        nonce,
        STATE_NOT_EXECUTABLE,
        STATE_VERIFYING,
        1, // error codes 1 and 101
    );

    // === DVN Verification ===

    let expiration = clock::timestamp_ms(&clock) + EXPIRATION_OFFSET;
    let payload = dvn_hashes::build_verify_payload(
        packet_header_bytes,
        payload_hash.to_bytes(),
        CONFIRMATIONS,
        uln_call_cap_address,
        1, // vid (DVN ID, must match the one used in create_dvn)
        expiration,
    );

    let signature = ecdsa_k1::secp256k1_sign(
        test_keypair.private_key(),
        &payload,
        0, // KECCAK256 hash function
        true, // recoverable signature
    );

    let verify_call = dvn.verify(
        &admin_cap,
        uln_call_cap_address, // target_message_lib
        packet_header_bytes,
        payload_hash,
        CONFIRMATIONS,
        expiration,
        signature,
        &clock,
        scenario.ctx(),
    );
    uln.verify(&mut verification, verify_call);

    // === Assert States After DVN Verification ===

    assert_verification_states(
        &endpoint,
        &messaging_channel,
        &uln,
        &verification,
        packet_header_bytes,
        payload_hash.to_bytes(),
        sender,
        nonce,
        STATE_NOT_EXECUTABLE, // Still not executable until committed
        STATE_VERIFIABLE, // Now verifiable
        3, // error codes 3 and 103
    );

    // === Commit Verification ===

    uln.commit_verification(
        &mut verification,
        &endpoint,
        &mut messaging_channel,
        packet_header_bytes,
        payload_hash,
        &clock,
    );

    // === Assert States After Commit ===

    assert_verification_states(
        &endpoint,
        &messaging_channel,
        &uln,
        &verification,
        packet_header_bytes,
        payload_hash.to_bytes(),
        sender,
        nonce,
        STATE_EXECUTABLE, // Now executable
        STATE_VERIFIED, // Fully verified
        5, // error codes 5 and 105
    );

    // === Execute Message ===

    endpoint.clear(
        &oapp_cap,
        &mut messaging_channel,
        REMOTE_EID,
        sender,
        nonce,
        outbound_packet.guid(),
        *outbound_packet.message(),
    );

    // === Assert States After Execution ===

    assert_verification_states(
        &endpoint,
        &messaging_channel,
        &uln,
        &verification,
        packet_header_bytes,
        payload_hash.to_bytes(),
        sender,
        nonce,
        STATE_EXECUTED, // Message executed
        STATE_VERIFIED, // Still verified (verification state doesn't change)
        7, // error codes 7 and 107
    );

    // === Test STATE_VERIFIED_BUT_NOT_EXECUTABLE ===

    // Create and verify a message with a gap in nonces (nonce 3, skipping 2)
    // This will create STATE_VERIFIED_BUT_NOT_EXECUTABLE because nonce 3 > inbound_nonce (1)
    let future_nonce = nonce + 2; // Nonce 3 (skipping nonce 2)
    let future_packet_header = packet_v1_codec::create_packet_header_for_testing(
        1u8, // version
        future_nonce,
        REMOTE_EID,
        sender,
        LOCAL_EID,
        receiver,
    );
    let future_header_bytes = packet_v1_codec::encode_header(&future_packet_header);
    let future_payload_hash = hash::keccak256!(&b"future_test_payload");

    // Verify the future message through DVN and commit it
    let future_payload = dvn_hashes::build_verify_payload(
        future_header_bytes,
        future_payload_hash.to_bytes(),
        CONFIRMATIONS,
        uln_call_cap_address,
        1, // vid (DVN ID, must match the one used in create_dvn)
        expiration,
    );

    let future_signature = ecdsa_k1::secp256k1_sign(
        test_keypair.private_key(),
        &future_payload,
        0, // KECCAK256 hash function
        true, // recoverable signature
    );

    let future_verify_call = dvn.verify(
        &admin_cap,
        uln_call_cap_address, // target_message_lib
        future_header_bytes,
        future_payload_hash,
        CONFIRMATIONS,
        expiration,
        future_signature,
        &clock,
        scenario.ctx(),
    );
    uln.verify(&mut verification, future_verify_call);

    // Commit verification for the future message
    uln.commit_verification(
        &mut verification,
        &endpoint,
        &mut messaging_channel,
        future_header_bytes,
        future_payload_hash,
        &clock,
    );

    // Now test the executable state of the future message
    // It should be STATE_VERIFIED_BUT_NOT_EXECUTABLE because:
    // - has_payload_hash = true (verified and committed)
    // - nonce (3) > inbound_nonce (1, since nonce 2 is missing)
    let future_exec_state = endpoint_views::executable(
        &messaging_channel,
        REMOTE_EID,
        sender.to_bytes(),
        future_nonce,
    );
    assert!(future_exec_state == STATE_VERIFIED_BUT_NOT_EXECUTABLE, 8);

    // === Cleanup ===

    clock::destroy_for_testing(clock);
    test_scenario::return_to_sender(&scenario, endpoint_admin_cap);
    test_scenario::return_shared(endpoint);
    test_scenario::return_to_sender(&scenario, uln_admin_cap);
    test_scenario::return_shared(uln);
    // test_scenario::return_shared(dvn_fee_lib);
    test_scenario::return_shared(verification);
    test_scenario::return_shared(messaging_channel);
    test_utils::destroy(oapp_cap);
    test_utils::destroy(worker_registry);
    test_utils::destroy(dvn);
    test_utils::destroy(admin_cap);
    scenario.end();
}
