#[test_only]
module endpoint_v2::endpoint_v2_tests;

use call::{call, call_cap::{Self, CallCap}};
use endpoint_v2::{
    endpoint_quote,
    endpoint_send,
    endpoint_v2::{Self, EndpointV2, AdminCap},
    message_lib_manager,
    message_lib_send,
    message_lib_type,
    messaging_channel::{Self, MessagingChannel, LzReceiveAlertEvent},
    messaging_composer::{Self, LzComposeAlertEvent, ComposeQueue},
    messaging_fee,
    messaging_receipt,
    oapp_registry,
    utils
};
use std::ascii;
use iota::{clock, coin, event, iota::IOTA, test_scenario::{Self as ts, Scenario}, test_utils};
use utils::{buffer_writer, bytes32, hash};
use zro::zro;

const ADMIN: address = @0x0;
const REMOTE_EID: u32 = 1;
const REMOTE_OAPP: address = @0x1;

public struct ENDPOINT_V2_TESTS has drop {}

// === Test Helpers ===

fun setup(register_default_lib: bool): (Scenario, AdminCap, EndpointV2, MessagingChannel, CallCap) {
    let mut scenario = ts::begin(ADMIN);
    let clock = clock::create_for_testing(scenario.ctx());
    endpoint_v2::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let mut endpoint = scenario.take_shared<EndpointV2>();

    // Create a messaging channel for testing (use user cap to avoid witness conflicts)
    let oapp_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let oapp_address = oapp_cap.id();
    endpoint.register_oapp(&oapp_cap, b"lz_receive_info", scenario.ctx());
    let messaging_channel_address = messaging_channel::create(oapp_address, scenario.ctx());
    scenario.next_tx(ADMIN);
    let messaging_channel = scenario.take_shared_by_id<MessagingChannel>(
        object::id_from_address(messaging_channel_address),
    );

    if (register_default_lib) {
        let msg_lib = call_cap::new_package_cap_for_test(scenario.ctx());
        endpoint.register_library(
            &admin_cap,
            msg_lib.id(),
            message_lib_type::send_and_receive(),
        );
        endpoint.set_default_send_library(&admin_cap, REMOTE_EID, msg_lib.id());
        endpoint.set_default_receive_library(
            &admin_cap,
            REMOTE_EID,
            msg_lib.id(),
            0,
            &clock,
        );
        test_utils::destroy(msg_lib);
    };

    clock.destroy_for_testing();
    (scenario, admin_cap, endpoint, messaging_channel, oapp_cap)
}

fun clean(
    scenario: Scenario,
    admin_cap: AdminCap,
    endpoint: EndpointV2,
    messaging_channel: MessagingChannel,
    oapp_cap: CallCap,
) {
    ts::return_shared(endpoint);
    scenario.return_to_sender(admin_cap);
    test_utils::destroy(messaging_channel);
    test_utils::destroy(oapp_cap);
    scenario.end();
}

fun register_oapp(scenario: &mut Scenario, endpoint: &mut EndpointV2, oapp_cap: &CallCap) {
    endpoint.register_oapp(oapp_cap, b"lz_receive_info", scenario.ctx());
}

// === Tests ===

#[test]
fun test_init_eid() {
    let (scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(true);
    endpoint_v2::init_eid(&mut endpoint, &admin_cap, 1);
    assert!(endpoint.eid() == 1, 0);

    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = endpoint_v2::ENotInitialized)]
fun test_get_eid_without_init() {
    let (scenario, admin_cap, endpoint, messaging_channel, oapp_cap) = setup(true);
    endpoint.eid();
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = endpoint_v2::EAlreadyInitialized)]
fun test_init_eid_already_initialized() {
    let (scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(true);
    endpoint_v2::init_eid(&mut endpoint, &admin_cap, 1);
    endpoint_v2::init_eid(&mut endpoint, &admin_cap, 2);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = endpoint_v2::EInvalidEid)]
fun test_init_eid_invalid_eid() {
    let (scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(true);
    endpoint_v2::init_eid(&mut endpoint, &admin_cap, 0);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_init_channel() {
    let (mut scenario, admin_cap, mut endpoint, mut messaging_channel, oapp_cap) = setup(true);
    let remote_oapp_bytes32 = bytes32::from_address(REMOTE_OAPP);

    // Initially channel should not be inited
    assert!(!endpoint_v2::is_channel_inited(&messaging_channel, REMOTE_EID, remote_oapp_bytes32), 0);
    assert!(!endpoint_v2::initializable(&messaging_channel, REMOTE_EID, remote_oapp_bytes32), 0);

    // Init channel
    endpoint_v2::init_channel(
        &endpoint,
        &oapp_cap,
        &mut messaging_channel,
        REMOTE_EID,
        remote_oapp_bytes32,
        scenario.ctx(),
    );

    // Verify channel is now registered
    assert!(endpoint_v2::is_channel_inited(&messaging_channel, REMOTE_EID, remote_oapp_bytes32), 1);
    assert!(endpoint_v2::get_outbound_nonce(&messaging_channel, REMOTE_EID, remote_oapp_bytes32) == 0, 2);
    assert!(endpoint_v2::get_inbound_nonce(&messaging_channel, REMOTE_EID, remote_oapp_bytes32) == 0, 3);
    assert!(endpoint_v2::get_lazy_inbound_nonce(&messaging_channel, REMOTE_EID, remote_oapp_bytes32) == 0, 4);
    assert!(endpoint_v2::initializable(&messaging_channel, REMOTE_EID, remote_oapp_bytes32), 5);

    // Test delegate authorization for init_channel
    let delegate_cap = call_cap::new_individual_cap(scenario.ctx());
    let delegate_address = delegate_cap.id();
    let oapp_address = oapp_cap.id();
    let another_remote_eid = 2u32;
    let another_remote_oapp = bytes32::from_address(@0x999);

    // Set delegate for the oapp
    endpoint.set_delegate(&oapp_cap, delegate_address);
    assert!(endpoint.get_delegate(oapp_address) == delegate_address, 6);

    // Delegate should be able to init another channel
    endpoint_v2::init_channel(
        &endpoint,
        &delegate_cap,
        &mut messaging_channel,
        another_remote_eid,
        another_remote_oapp,
        scenario.ctx(),
    );
    assert!(endpoint_v2::is_channel_inited(&messaging_channel, another_remote_eid, another_remote_oapp), 7);

    test_utils::destroy(delegate_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_register_library() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);

    // Test registered_libraries_count before registration
    assert!(endpoint.registered_libraries_count() == 0, 0);

    // Register a send-and-receive library
    let msg_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_library(
        &admin_cap,
        msg_lib_cap.id(),
        message_lib_type::send_and_receive(),
    );
    let msg_lib_address = msg_lib_cap.id();
    assert!(endpoint.is_registered_library(msg_lib_address), 1);
    let registered_libraries = endpoint.registered_libraries(0, 10);
    assert!(registered_libraries.length() == 1, 2);
    assert!(registered_libraries[0] == msg_lib_address, 3);
    assert!(endpoint.get_library_type(msg_lib_address) == message_lib_type::send_and_receive(), 4);

    // Test additional view functions
    assert!(endpoint.registered_libraries_count() == 1, 5);
    // Library package tracking functions have been removed

    test_utils::destroy(msg_lib_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = message_lib_manager::EOnlyRegisteredLib)]
fun test_registered_library_type_unregistered() {
    let (scenario, admin_cap, endpoint, messaging_channel, oapp_cap) = setup(true);

    // Try to get type of unregistered library - should fail
    endpoint.get_library_type(@0x999);

    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_is_registered_library_false() {
    let (scenario, admin_cap, endpoint, messaging_channel, oapp_cap) = setup(true);

    // Check unregistered library
    assert!(!endpoint.is_registered_library(@0x999), 0);

    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_set_default_send_library() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);

    // Register a send library
    let send_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_library(&admin_cap, send_lib_cap.id(), message_lib_type::send());
    let send_lib_address = send_lib_cap.id();

    // Set default send library
    endpoint.set_default_send_library(&admin_cap, REMOTE_EID, send_lib_address);

    // Verify default send library is set
    let default_lib = endpoint.get_default_send_library(REMOTE_EID);
    assert!(default_lib == send_lib_address, 0);

    // Get send library for oapp (should return default)
    let (lib, is_default) = endpoint.get_send_library(@0x1, REMOTE_EID);
    assert!(lib == send_lib_address, 0);
    assert!(is_default, 1);

    test_utils::destroy(send_lib_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = message_lib_manager::EDefaultSendLibUnavailable)]
fun test_get_default_send_library_not_set() {
    let (scenario, admin_cap, endpoint, messaging_channel, oapp_cap) = setup(true);

    // Try to get default send library when none is set - should fail
    endpoint.get_default_send_library(999);

    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_set_default_receive_library() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);
    let clock = clock::create_for_testing(scenario.ctx());

    // Register a receive library
    let receive_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_library(
        &admin_cap,
        receive_lib_cap.id(),
        message_lib_type::receive(),
    );
    let receive_lib_address = receive_lib_cap.id();

    // Set default receive library
    endpoint.set_default_receive_library(&admin_cap, REMOTE_EID, receive_lib_address, 0, &clock);

    // Verify default receive library is set
    let default_lib = endpoint.get_default_receive_library(REMOTE_EID);
    assert!(default_lib == receive_lib_address, 0);

    // Get receive library for oapp (should return default)
    let (lib, is_default) = endpoint.get_receive_library(@0x1, REMOTE_EID);
    assert!(lib == receive_lib_address, 0);
    assert!(is_default, 1);

    test_utils::destroy(receive_lib_cap);
    clock.destroy_for_testing();
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = message_lib_manager::EDefaultReceiveLibUnavailable)]
fun test_get_default_receive_library_not_set() {
    let (scenario, admin_cap, endpoint, messaging_channel, oapp_cap) = setup(true);

    // Try to get default receive library when none is set - should fail
    endpoint.get_default_receive_library(999);

    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = message_lib_manager::EDefaultReceiveLibUnavailable)]
fun test_get_default_receive_library_timeout_not_set() {
    let (scenario, admin_cap, endpoint, messaging_channel, oapp_cap) = setup(true);

    // Try to get default receive library timeout when none is set - should fail
    endpoint.get_default_receive_library_timeout(999);

    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_set_send_library() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);
    let clock = clock::create_for_testing(scenario.ctx());
    let test_oapp_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let oapp_address = test_oapp_cap.id();
    register_oapp(&mut scenario, &mut endpoint, &test_oapp_cap);

    // Register a send library
    let send_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_library(&admin_cap, send_lib_cap.id(), message_lib_type::send());
    let send_lib_address = send_lib_cap.id();

    endpoint.set_default_send_library(&admin_cap, REMOTE_EID, send_lib_address);

    // Set send library
    endpoint.set_send_library(&test_oapp_cap, oapp_address, REMOTE_EID, send_lib_address);

    // Verify send library is set
    let (lib, is_default) = endpoint.get_send_library(oapp_address, REMOTE_EID);
    assert!(lib == send_lib_address, 0);
    assert!(!is_default, 1);

    // Test delegate authorization for set_send_library
    let delegate_cap = call_cap::new_individual_cap(scenario.ctx());
    let delegate_address = delegate_cap.id();
    let other_remote_eid = 999u32;

    // Set delegate for the oapp
    endpoint.set_delegate(&test_oapp_cap, delegate_address);
    assert!(endpoint.get_delegate(oapp_address) == delegate_address, 2);

    // Register another send library for delegate test
    let another_send_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_library(&admin_cap, another_send_lib_cap.id(), message_lib_type::send());
    let another_send_lib_address = another_send_lib_cap.id();
    endpoint.set_default_send_library(&admin_cap, other_remote_eid, another_send_lib_address);

    // Delegate should be able to set send library
    endpoint.set_send_library(&delegate_cap, oapp_address, other_remote_eid, another_send_lib_address);

    // Verify delegate operation succeeded
    let (delegate_lib, delegate_is_default) = endpoint.get_send_library(oapp_address, other_remote_eid);
    assert!(delegate_lib == another_send_lib_address, 3);
    assert!(!delegate_is_default, 4);

    test_utils::destroy(send_lib_cap);
    test_utils::destroy(another_send_lib_cap);
    test_utils::destroy(delegate_cap);
    test_utils::destroy(test_oapp_cap);
    clock.destroy_for_testing();
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_set_receive_library() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);
    let clock = clock::create_for_testing(scenario.ctx());
    let test_oapp_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let oapp_address = test_oapp_cap.id();
    register_oapp(&mut scenario, &mut endpoint, &test_oapp_cap);

    // Register a receive library
    let receive_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_library(
        &admin_cap,
        receive_lib_cap.id(),
        message_lib_type::receive(),
    );
    let receive_lib_address = receive_lib_cap.id();

    endpoint.set_default_receive_library(&admin_cap, REMOTE_EID, receive_lib_address, 0, &clock);

    // Test is_valid_receive_library
    assert!(endpoint.is_valid_receive_library(oapp_address, REMOTE_EID, receive_lib_address, &clock), 3);

    // Set receive library
    endpoint.set_receive_library(&test_oapp_cap, oapp_address, REMOTE_EID, receive_lib_address, 0, &clock);

    // Verify receive library is set
    let (lib, is_default) = endpoint.get_receive_library(oapp_address, REMOTE_EID);
    assert!(lib == receive_lib_address, 0);
    assert!(!is_default, 1);

    // Test get_receive_library_timeout (should be none for no timeout)
    let timeout_opt = endpoint.get_receive_library_timeout(oapp_address, REMOTE_EID);
    assert!(timeout_opt.is_none(), 2);

    // Test is_valid_receive_library
    assert!(endpoint.is_valid_receive_library(oapp_address, REMOTE_EID, receive_lib_address, &clock), 3);

    // Test delegate authorization for set_receive_library
    let delegate_cap = call_cap::new_individual_cap(scenario.ctx());
    let delegate_address = delegate_cap.id();
    let other_remote_eid = 999u32;

    // Set delegate for the oapp
    endpoint.set_delegate(&test_oapp_cap, delegate_address);
    assert!(endpoint.get_delegate(oapp_address) == delegate_address, 4);

    // Register another receive library for delegate test
    let another_receive_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_library(
        &admin_cap,
        another_receive_lib_cap.id(),
        message_lib_type::receive(),
    );
    let another_receive_lib_address = another_receive_lib_cap.id();
    endpoint.set_default_receive_library(&admin_cap, other_remote_eid, another_receive_lib_address, 0, &clock);

    // Delegate should be able to set receive library
    endpoint.set_receive_library(&delegate_cap, oapp_address, other_remote_eid, another_receive_lib_address, 0, &clock);

    // Verify delegate operation succeeded
    let (delegate_lib, delegate_is_default) = endpoint.get_receive_library(oapp_address, other_remote_eid);
    assert!(delegate_lib == another_receive_lib_address, 5);
    assert!(!delegate_is_default, 6);

    test_utils::destroy(receive_lib_cap);
    test_utils::destroy(another_receive_lib_cap);
    test_utils::destroy(delegate_cap);
    test_utils::destroy(test_oapp_cap);
    clock.destroy_for_testing();
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_quote() {
    let (mut scenario, admin_cap, mut endpoint, mut messaging_channel, oapp_cap) = setup(false);
    let receiver = bytes32::from_address(REMOTE_OAPP);
    let message = b"test message";
    let options = b"test options";
    let pay_in_zro = true;

    endpoint.init_eid(&admin_cap, 2);

    // Register message library
    let msg_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_library(&admin_cap, msg_lib_cap.id(), message_lib_type::send());
    let msg_lib_address = msg_lib_cap.id();
    endpoint.set_default_send_library(&admin_cap, REMOTE_EID, msg_lib_address);

    // Init channel
    endpoint_v2::init_channel(
        &endpoint,
        &oapp_cap,
        &mut messaging_channel,
        REMOTE_EID,
        bytes32::from_address(REMOTE_OAPP),
        scenario.ctx(),
    );

    // Create quote call
    let quote_param = endpoint_quote::create_param(REMOTE_EID, receiver, message, options, pay_in_zro);
    let mut call = call::create(&oapp_cap, endpoint.get_call_cap_ref().id(), false, quote_param, scenario.ctx());

    // Execute quote
    let mut message_lib_call = endpoint.quote(&messaging_channel, &mut call, scenario.ctx());

    // Simulate message lib result - complete the call
    let mock_fee = messaging_fee::create(100, 10);
    message_lib_call.complete(&msg_lib_cap, mock_fee);

    // Confirm quote
    endpoint.confirm_quote(&mut call, message_lib_call);

    // Extract result
    let (_, _, result) = call.destroy(&oapp_cap);
    assert!(result.native_fee() == 100, 0);
    assert!(result.zro_fee() == 10, 1);

    test_utils::destroy(msg_lib_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_set_config() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);

    // Register message library
    let msg_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_library(&admin_cap, msg_lib_cap.id(), message_lib_type::send());
    let msg_lib_address = msg_lib_cap.id();

    // Execute set config directly with the new signature
    let mut message_lib_call = endpoint.set_config(
        &oapp_cap,
        oapp_cap.id(),
        msg_lib_address,
        REMOTE_EID,
        1,
        b"test config",
        scenario.ctx(),
    );

    // Simulate message lib result - complete the call
    message_lib_call.complete(&msg_lib_cap, call::void());

    // Destroy the completed call (since it's a one-way call, callee can destroy it)
    let (_, _, _) = message_lib_call.destroy(&msg_lib_cap);

    // Test delegate authorization for set_config
    let delegate_cap = call_cap::new_individual_cap(scenario.ctx());
    let delegate_address = delegate_cap.id();
    let oapp_address = oapp_cap.id();

    // Set delegate for the oapp
    endpoint.set_delegate(&oapp_cap, delegate_address);
    assert!(endpoint.get_delegate(oapp_address) == delegate_address, 0);

    // Delegate should be able to execute set config
    let mut delegate_message_lib_call = endpoint.set_config(
        &delegate_cap,
        oapp_address,
        msg_lib_address,
        REMOTE_EID,
        2,
        b"delegate test config",
        scenario.ctx(),
    );

    // Simulate message lib result - complete the call
    delegate_message_lib_call.complete(&msg_lib_cap, call::void());

    // Destroy the completed delegate call
    let (_, _, _) = delegate_message_lib_call.destroy(&msg_lib_cap);

    test_utils::destroy(delegate_cap);
    test_utils::destroy(msg_lib_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_channel_operations() {
    let (mut scenario, admin_cap, mut endpoint, mut messaging_channel, oapp_cap) = setup(false);
    let sender = bytes32::from_address(REMOTE_OAPP);
    let receiver = oapp_cap.id();
    let message = b"test message";
    let clock = clock::create_for_testing(scenario.ctx());
    let guid1 = utils::compute_guid(1, 2, sender, REMOTE_EID, bytes32::from_address(receiver));
    let guid2 = utils::compute_guid(2, 2, sender, REMOTE_EID, bytes32::from_address(receiver));
    let mut writer = buffer_writer::create(guid1.to_bytes());
    writer.write_bytes(message);
    let payload1 = writer.to_bytes();
    let mut writer = buffer_writer::create(guid2.to_bytes());
    writer.write_bytes(message);
    let payload2 = writer.to_bytes();
    let payload_hash1 = hash::keccak256!(&payload1);
    let payload_hash2 = hash::keccak256!(&payload2);

    // Register message library
    let msg_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_library(
        &admin_cap,
        msg_lib_cap.id(),
        message_lib_type::receive(),
    );
    let msg_lib_address = msg_lib_cap.id();
    endpoint.set_default_receive_library(&admin_cap, REMOTE_EID, msg_lib_address, 0, &clock);

    // Register channel
    endpoint_v2::init_channel(&endpoint, &oapp_cap, &mut messaging_channel, REMOTE_EID, sender, scenario.ctx());

    assert!(endpoint_v2::get_inbound_nonce(&messaging_channel, REMOTE_EID, sender) == 0, 0);

    // Test has_inbound_payload_hash before verification
    assert!(!endpoint_v2::has_inbound_payload_hash(&messaging_channel, REMOTE_EID, sender, 1), 1);
    assert!(!endpoint_v2::has_inbound_payload_hash(&messaging_channel, REMOTE_EID, sender, 2), 2);

    // Verify 1,2
    endpoint_v2::verify(&endpoint, &msg_lib_cap, &mut messaging_channel, REMOTE_EID, sender, 1, payload_hash1, &clock);
    endpoint_v2::verify(&endpoint, &msg_lib_cap, &mut messaging_channel, REMOTE_EID, sender, 2, payload_hash2, &clock);

    assert!(endpoint_v2::get_inbound_nonce(&messaging_channel, REMOTE_EID, sender) == 2, 3);
    assert!(endpoint_v2::verifiable(&messaging_channel, REMOTE_EID, sender, 1), 4);
    assert!(endpoint_v2::verifiable(&messaging_channel, REMOTE_EID, sender, 2), 5);

    // Test has_inbound_payload_hash and get_inbound_payload_hash after verification
    assert!(endpoint_v2::has_inbound_payload_hash(&messaging_channel, REMOTE_EID, sender, 1), 6);
    assert!(endpoint_v2::has_inbound_payload_hash(&messaging_channel, REMOTE_EID, sender, 2), 7);
    assert!(endpoint_v2::get_inbound_payload_hash(&messaging_channel, REMOTE_EID, sender, 1) == payload_hash1, 8);
    assert!(endpoint_v2::get_inbound_payload_hash(&messaging_channel, REMOTE_EID, sender, 2) == payload_hash2, 9);

    // Clear 2
    endpoint_v2::clear(&endpoint, &oapp_cap, &mut messaging_channel, REMOTE_EID, sender, 2, guid2, message);

    assert!(endpoint_v2::get_lazy_inbound_nonce(&messaging_channel, REMOTE_EID, sender) == 2, 10);
    assert!(endpoint_v2::verifiable(&messaging_channel, REMOTE_EID, sender, 1), 11);
    assert!(!endpoint_v2::verifiable(&messaging_channel, REMOTE_EID, sender, 2), 12);

    // Test has_inbound_payload_hash after clearing
    assert!(!endpoint_v2::has_inbound_payload_hash(&messaging_channel, REMOTE_EID, sender, 2), 13);

    // Burn 1
    endpoint_v2::burn(&endpoint, &oapp_cap, &mut messaging_channel, REMOTE_EID, sender, 1, payload_hash1);

    assert!(!endpoint_v2::verifiable(&messaging_channel, REMOTE_EID, sender, 1), 14);
    assert!(!endpoint_v2::has_inbound_payload_hash(&messaging_channel, REMOTE_EID, sender, 1), 15);

    // Skip 3
    endpoint_v2::skip(&endpoint, &oapp_cap, &mut messaging_channel, REMOTE_EID, sender, 3);

    assert!(endpoint_v2::get_lazy_inbound_nonce(&messaging_channel, REMOTE_EID, sender) == 3, 16);
    assert!(endpoint_v2::get_inbound_nonce(&messaging_channel, REMOTE_EID, sender) == 3, 17);
    assert!(!endpoint_v2::verifiable(&messaging_channel, REMOTE_EID, sender, 3), 18);

    // Nilify 4
    endpoint_v2::nilify(&endpoint, &oapp_cap, &mut messaging_channel, REMOTE_EID, sender, 4, bytes32::zero_bytes32());

    assert!(endpoint_v2::get_inbound_nonce(&messaging_channel, REMOTE_EID, sender) == 4, 19);
    assert!(endpoint_v2::verifiable(&messaging_channel, REMOTE_EID, sender, 4), 20);

    // Test delegate authorization for channel operations
    let delegate_cap = call_cap::new_individual_cap(scenario.ctx());
    let delegate_address = delegate_cap.id();
    let receiver_address = oapp_cap.id();

    // Set delegate for the oapp
    endpoint.set_delegate(&oapp_cap, delegate_address);
    assert!(endpoint.get_delegate(receiver_address) == delegate_address, 21);

    // Verify another message for delegate tests
    let guid3 = utils::compute_guid(5, 2, sender, REMOTE_EID, bytes32::from_address(receiver_address));
    let mut writer = buffer_writer::create(guid3.to_bytes());
    writer.write_bytes(message);
    let payload3 = writer.to_bytes();
    let payload_hash3 = hash::keccak256!(&payload3);
    endpoint_v2::verify(&endpoint, &msg_lib_cap, &mut messaging_channel, REMOTE_EID, sender, 5, payload_hash3, &clock);

    // Delegate should be able to clear
    endpoint_v2::clear(&endpoint, &delegate_cap, &mut messaging_channel, REMOTE_EID, sender, 5, guid3, message);
    assert!(!endpoint_v2::has_inbound_payload_hash(&messaging_channel, REMOTE_EID, sender, 5), 22);

    // Verify message for skip test
    let guid4 = utils::compute_guid(6, 2, sender, REMOTE_EID, bytes32::from_address(receiver_address));
    let mut writer = buffer_writer::create(guid4.to_bytes());
    writer.write_bytes(message);
    let payload4 = writer.to_bytes();
    let payload_hash4 = hash::keccak256!(&payload4);
    endpoint_v2::verify(&endpoint, &msg_lib_cap, &mut messaging_channel, REMOTE_EID, sender, 6, payload_hash4, &clock);

    // Delegate should be able to skip
    endpoint_v2::skip(&endpoint, &delegate_cap, &mut messaging_channel, REMOTE_EID, sender, 7);
    assert!(endpoint_v2::get_lazy_inbound_nonce(&messaging_channel, REMOTE_EID, sender) == 7, 23);

    // Delegate should be able to burn
    endpoint_v2::burn(&endpoint, &delegate_cap, &mut messaging_channel, REMOTE_EID, sender, 6, payload_hash4);
    assert!(!endpoint_v2::verifiable(&messaging_channel, REMOTE_EID, sender, 6), 24);

    // Delegate should be able to nilify
    endpoint_v2::nilify(
        &endpoint,
        &delegate_cap,
        &mut messaging_channel,
        REMOTE_EID,
        sender,
        8,
        bytes32::zero_bytes32(),
    );
    assert!(endpoint_v2::verifiable(&messaging_channel, REMOTE_EID, sender, 8), 25);

    test_utils::destroy(delegate_cap);
    test_utils::destroy(msg_lib_cap);
    clock.destroy_for_testing();
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_send_and_clear_compose() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(true);
    let composer_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let composer = composer_cap.id();
    let oapp_address = oapp_cap.id();
    let guid = bytes32::from_bytes(b"guidguidguidguidguidguidguidguid");
    let message = b"test message";

    // Register composer first
    endpoint.register_composer(&composer_cap, b"lz_compose_info", scenario.ctx());
    scenario.next_tx(ADMIN);
    // Create messaging composer
    let mut messaging_composer = scenario.take_shared<ComposeQueue>();

    // Test get_composer function
    assert!(endpoint_v2::get_composer(&messaging_composer) == composer, 0);

    // Send compose 0,1
    endpoint_v2::send_compose(&oapp_cap, &mut messaging_composer, guid, 0, message);
    endpoint_v2::send_compose(&oapp_cap, &mut messaging_composer, guid, 1, message);

    assert!(
        endpoint_v2::get_compose_message_hash(&messaging_composer, oapp_address, guid, 0) == hash::keccak256!(&message),
        1,
    );
    assert!(
        endpoint_v2::get_compose_message_hash(&messaging_composer, oapp_address, guid, 1) == hash::keccak256!(&message),
        2,
    );

    // Clear compose
    messaging_composer.clear_compose(oapp_address, guid, 0, message);
    messaging_composer.clear_compose(oapp_address, guid, 1, message);

    assert!(
        endpoint_v2::get_compose_message_hash(&messaging_composer, oapp_address, guid, 0) == bytes32::ff_bytes32(),
        3,
    );
    assert!(
        endpoint_v2::get_compose_message_hash(&messaging_composer, oapp_address, guid, 1) == bytes32::ff_bytes32(),
        4,
    );

    test_utils::destroy(messaging_composer);
    test_utils::destroy(composer_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_lz_compose_alert() {
    let (scenario, admin_cap, endpoint, messaging_channel, oapp_cap) = setup(true);
    let guid = bytes32::from_bytes(b"guidguidguidguidguidguidguidguid");
    let extra_data = b"extra_data";
    let reason = ascii::string(b"reason");
    let oapp = @0x1;
    let to = @0x2;
    let index = 0;
    let message = b"test message";
    let gas = 100;
    let value = 100;

    endpoint_v2::lz_compose_alert(
        &oapp_cap,
        oapp,
        to,
        guid,
        index,
        gas,
        value,
        message,
        extra_data,
        reason,
    );
    let lz_compose_alert_event = messaging_composer::create_lz_compose_alert_event(
        oapp_cap.id(),
        oapp,
        to,
        guid,
        index,
        gas,
        value,
        message,
        extra_data,
        reason,
    );
    test_utils::assert_eq(event::events_by_type<LzComposeAlertEvent>()[0], lz_compose_alert_event);

    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_lz_receive_alert() {
    let (scenario, admin_cap, endpoint, messaging_channel, oapp_cap) = setup(true);
    let src_eid = 1u32;
    let sender = bytes32::from_address(REMOTE_OAPP);
    let nonce = 1;
    let receiver = @0x1;
    let guid = bytes32::from_bytes(b"guidguidguidguidguidguidguidguid");
    let gas = 100000u64;
    let value = 1000u64;
    let message = b"test message";
    let extra_data = b"extra_data";
    let reason = ascii::string(b"execution failed");

    endpoint_v2::lz_receive_alert(
        &oapp_cap,
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

    let lz_receive_alert_event = messaging_channel::create_lz_receive_alert_event(
        receiver,
        oapp_cap.id(),
        src_eid,
        sender,
        nonce,
        guid,
        gas,
        value,
        message,
        extra_data,
        reason,
    );
    test_utils::assert_eq(event::events_by_type<LzReceiveAlertEvent>()[0], lz_receive_alert_event);

    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_register_oapp() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);
    let new_oapp_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let oapp_address = new_oapp_cap.id();

    let lz_receive_info = b"lz_receive_v1_test_info";

    // Register new oapp
    endpoint.register_oapp(&new_oapp_cap, lz_receive_info, scenario.ctx());

    // Verify oapp was registered
    assert!(endpoint.is_oapp_registered(oapp_address), 0);
    // OApp package tracking functions have been removed
    assert!(endpoint.get_oapp_info(oapp_address) == lz_receive_info, 2);

    // Verify messaging channel was created
    let messaging_channel_address = endpoint.get_messaging_channel(oapp_address);
    assert!(messaging_channel_address != @0x0, 3);

    // Verify initial delegate is @0x0
    assert!(endpoint.get_delegate(oapp_address) == @0x0, 4);

    // Clean up
    test_utils::destroy(new_oapp_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = oapp_registry::EOAppRegistered)]
fun test_register_oapp_already_registered() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);

    let lz_receive_info = b"lz_receive_info";

    // Register oapp first time
    endpoint.register_oapp(&oapp_cap, lz_receive_info, scenario.ctx());

    // Try to register same oapp again - should fail
    endpoint.register_oapp(&oapp_cap, b"different_info", scenario.ctx());

    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_register_composer() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);
    let composer_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let composer_address = composer_cap.id();

    let lz_compose_info = b"lz_compose_v1_test_info";

    // Register composer
    endpoint.register_composer(&composer_cap, lz_compose_info, scenario.ctx());

    // Verify composer was registered
    assert!(endpoint.is_composer_registered(composer_address), 0);
    // Composer package tracking functions have been removed
    assert!(endpoint.get_composer_info(composer_address) == lz_compose_info, 2);

    // Verify messaging composer was created
    let compose_queue_address = endpoint.get_compose_queue(composer_address);
    assert!(compose_queue_address != @0x0, 3);

    // Clean up
    test_utils::destroy(composer_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = messaging_composer::EComposerRegistered)]
fun test_register_composer_already_registered() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);
    let composer_cap = call_cap::new_package_cap_for_test(scenario.ctx());

    let lz_compose_info = b"lz_compose_info";

    // Register composer first time
    endpoint.register_composer(&composer_cap, lz_compose_info, scenario.ctx());

    // Try to register same composer again - should fail
    endpoint.register_composer(&composer_cap, b"different_info", scenario.ctx());

    // Clean up
    test_utils::destroy(composer_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_call_cap() {
    let (scenario, admin_cap, endpoint, messaging_channel, oapp_cap) = setup(true);

    // Test call_cap reference is accessible
    let call_cap_ref = endpoint.get_call_cap_ref();

    // Verify it's a package cap (not a user cap)
    assert!(call_cap_ref.is_package(), 0);
    assert!(!call_cap_ref.is_individual(), 1);

    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_send_workflow() {
    let (mut scenario, admin_cap, mut endpoint, mut messaging_channel, oapp_cap) = setup(false);
    let sender = oapp_cap.id();
    let receiver = bytes32::from_address(REMOTE_OAPP);
    let message = b"test send message";
    let options = b"test send options";

    endpoint.init_eid(&admin_cap, 2);

    // Register and setup message library
    let send_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_library(
        &admin_cap,
        send_lib_cap.id(),
        message_lib_type::send(),
    );
    endpoint.set_default_send_library(&admin_cap, REMOTE_EID, send_lib_cap.id());

    // Init channel
    endpoint_v2::init_channel(
        &endpoint,
        &oapp_cap,
        &mut messaging_channel,
        REMOTE_EID,
        receiver,
        scenario.ctx(),
    );

    // Create send param with fees for testing confirm_send
    let native_fee_amount = 1000u64;
    let zro_fee_amount = 500u64;
    let native_fee = coin::mint_for_testing<IOTA>(native_fee_amount, scenario.ctx());
    let zro_fee = option::some(coin::mint_for_testing<zro::ZRO>(zro_fee_amount, scenario.ctx()));
    let refund_address = option::some(sender);

    let send_param = endpoint_send::create_param(
        REMOTE_EID,
        receiver,
        message,
        options,
        native_fee,
        zro_fee,
        refund_address,
    );

    // Create send call
    let mut endpoint_call = call::create(&oapp_cap, endpoint.get_call_cap_ref().id(), true, send_param, scenario.ctx());
    endpoint_call.enable_mutable_param(&oapp_cap);

    // Execute send - this should create a message lib call
    let mut message_lib_call = endpoint.send(&mut messaging_channel, &mut endpoint_call, scenario.ctx());

    // Verify the message lib call was created
    assert!(message_lib_call.caller() == endpoint.get_call_cap_ref().id(), 0);

    // Now test confirm_send - complete the message lib call that was created by send()
    // Create messaging fee and result (fees less than available)
    let messaging_fee = messaging_fee::create(800u64, 300u64); // 800 native, 300 ZRO
    let encoded_packet = b"encoded packet data";
    let message_lib_result = message_lib_send::create_result(encoded_packet, messaging_fee);

    // Complete the message lib call that was created by send()
    message_lib_call.complete(&send_lib_cap, message_lib_result);

    // Execute confirm_send using the same message lib call
    let (paid_native, paid_zro) = endpoint_v2::confirm_send(
        &endpoint,
        &send_lib_cap,
        &mut messaging_channel,
        &mut endpoint_call,
        message_lib_call,
        scenario.ctx(),
    );

    // Verify fee splitting worked correctly
    assert!(paid_native.value() == 800, 1); // Should match native fee in messaging_fee
    assert!(paid_zro.value() == 300, 2); // Should match ZRO fee in messaging_fee

    // Verify outbound nonce was incremented
    assert!(endpoint_v2::get_outbound_nonce(&messaging_channel, REMOTE_EID, receiver) == 1, 3);

    // Clean up
    coin::burn_for_testing(paid_native);
    coin::burn_for_testing(paid_zro);
    // message_lib_call is consumed by confirm_send
    test_utils::destroy(endpoint_call);
    test_utils::destroy(send_lib_cap);

    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_lz_receive() {
    let (mut scenario, admin_cap, mut endpoint, mut messaging_channel, oapp_cap) = setup(false);
    let src_eid = REMOTE_EID;
    let sender = bytes32::from_address(REMOTE_OAPP);
    let nonce = 1u64;
    let guid = bytes32::from_bytes(b"guidguidguidguidguidguidguidguid");
    let message = b"test lz_receive message";
    let extra_data = b"test extra data";
    let executor_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let value = option::some(coin::mint_for_testing<IOTA>(100, scenario.ctx()));

    // Init channel
    endpoint_v2::init_channel(
        &endpoint,
        &oapp_cap,
        &mut messaging_channel,
        src_eid,
        sender,
        scenario.ctx(),
    );

    // Verify the message first to set up the payload
    let receive_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());

    // Need to register the receive library first
    endpoint.register_library(
        &admin_cap,
        receive_lib_cap.id(),
        message_lib_type::receive(),
    );
    endpoint.set_default_receive_library(&admin_cap, src_eid, receive_lib_cap.id(), 0, &clock);
    let payload = utils::build_payload(guid, message);
    let payload_hash = hash::keccak256!(&payload);

    endpoint_v2::verify(
        &endpoint,
        &receive_lib_cap,
        &mut messaging_channel,
        src_eid,
        sender,
        nonce,
        payload_hash,
        &clock,
    );

    // Execute lz_receive
    let lz_receive_call = endpoint_v2::lz_receive(
        &endpoint,
        &executor_cap,
        &mut messaging_channel,
        src_eid,
        sender,
        nonce,
        guid,
        message,
        extra_data,
        value,
        scenario.ctx(),
    );

    // Verify call was created correctly
    assert!(lz_receive_call.caller() == endpoint.get_call_cap_ref().id(), 0);
    assert!(lz_receive_call.callee() == oapp_cap.id(), 1);

    // Verify payload was cleared
    assert!(!endpoint_v2::verifiable(&messaging_channel, src_eid, sender, nonce), 2);

    test_utils::destroy(lz_receive_call);
    test_utils::destroy(receive_lib_cap);
    test_utils::destroy(executor_cap);
    clock.destroy_for_testing();
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_lz_compose() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);
    let from = oapp_cap.id();
    let guid = bytes32::from_bytes(b"guidguidguidguidguidguidguidguid");
    let index = 0u16;
    let message = b"test compose message";
    let extra_data = b"test compose extra data";
    let executor_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let value = option::some(coin::mint_for_testing<IOTA>(200, scenario.ctx()));

    // Create messaging composer by registering the oapp as a composer
    let composer_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_composer(&composer_cap, b"lz_compose_info", scenario.ctx());
    let compose_queue_addr = endpoint.get_compose_queue(composer_cap.id());
    scenario.next_tx(ADMIN);
    let mut compose_queue = scenario.take_shared_by_id<ComposeQueue>(
        object::id_from_address(compose_queue_addr),
    );

    // Send compose message first
    endpoint_v2::send_compose(&oapp_cap, &mut compose_queue, guid, index, message);

    // Verify compose message exists
    assert!(endpoint_v2::has_compose_message_hash(&compose_queue, from, guid, index), 0);

    // Execute lz_compose
    let lz_compose_call = endpoint_v2::lz_compose(
        &endpoint,
        &executor_cap,
        &mut compose_queue,
        from,
        guid,
        index,
        message,
        extra_data,
        value,
        scenario.ctx(),
    );

    // Verify call was created correctly
    assert!(lz_compose_call.caller() == endpoint.get_call_cap_ref().id(), 1);
    assert!(lz_compose_call.callee() == composer_cap.id(), 2);

    // Compose message was cleared but still exists
    assert!(endpoint_v2::has_compose_message_hash(&compose_queue, from, guid, index), 3);

    test_utils::destroy(lz_compose_call);
    test_utils::destroy(compose_queue);
    test_utils::destroy(executor_cap);
    test_utils::destroy(composer_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_set_default_receive_library_timeout() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);
    let mut clock = clock::create_for_testing(scenario.ctx());
    let src_eid = REMOTE_EID;

    // Register two receive libraries
    let lib1_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let lib2_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_library(&admin_cap, lib1_cap.id(), message_lib_type::receive());
    endpoint.register_library(&admin_cap, lib2_cap.id(), message_lib_type::receive());
    let lib1_address = lib1_cap.id();
    let lib2_address = lib2_cap.id();

    // Set initial default receive library
    endpoint.set_default_receive_library(&admin_cap, src_eid, lib1_address, 0, &clock);

    // Initially no timeout
    let timeout_opt = endpoint.get_default_receive_library_timeout(src_eid);
    assert!(timeout_opt.is_none(), 0);

    // Change default library with grace period of 100 seconds
    clock.set_for_testing(1000 * 1000); // Set to 1000 seconds
    endpoint.set_default_receive_library(&admin_cap, src_eid, lib2_address, 100, &clock);

    // Should have timeout now
    let timeout_opt = endpoint.get_default_receive_library_timeout(src_eid);
    assert!(timeout_opt.is_some(), 1);
    let timeout = timeout_opt.destroy_some();
    assert!(timeout.expiry() == 1100, 2); // 1000 + 100
    assert!(timeout.fallback_lib() == lib1_address, 3);

    // Test is_valid_receive_library during timeout period
    assert!(endpoint.is_valid_receive_library(@0x999, src_eid, lib2_address, &clock), 4); // New library valid
    assert!(endpoint.is_valid_receive_library(@0x999, src_eid, lib1_address, &clock), 5); // Old library still valid

    // Set specific timeout
    endpoint.set_default_receive_library_timeout(&admin_cap, src_eid, lib1_address, 1200, &clock);
    let timeout_opt2 = endpoint.get_default_receive_library_timeout(src_eid);
    assert!(timeout_opt2.is_some(), 6);
    let timeout2 = timeout_opt2.destroy_some();
    assert!(timeout2.expiry() == 1200, 7);
    assert!(timeout2.fallback_lib() == lib1_address, 8);

    // Move clock past timeout
    clock.set_for_testing(1300 * 1000);
    assert!(endpoint.is_valid_receive_library(@0x999, src_eid, lib2_address, &clock), 9); // New library still valid
    assert!(!endpoint.is_valid_receive_library(@0x999, src_eid, lib1_address, &clock), 10); // Old library no longer valid

    // Remove timeout
    endpoint.set_default_receive_library_timeout(&admin_cap, src_eid, lib1_address, 0, &clock);
    let timeout_opt3 = endpoint.get_default_receive_library_timeout(src_eid);
    assert!(timeout_opt3.is_none(), 11);

    test_utils::destroy(lib1_cap);
    test_utils::destroy(lib2_cap);
    clock.destroy_for_testing();
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_set_oapp_info() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);
    let test_oapp_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let oapp_address = test_oapp_cap.id();
    let initial_info = b"initial_lz_receive_info_v1";
    let updated_info = b"updated_lz_receive_info_v2";

    // Register oapp first
    endpoint.register_oapp(&test_oapp_cap, initial_info, scenario.ctx());

    // Verify initial info
    assert!(endpoint.get_oapp_info(oapp_address) == initial_info, 0);

    // Update oapp_info
    endpoint.set_oapp_info(&test_oapp_cap, oapp_address, updated_info);

    // Verify info was updated
    assert!(endpoint.get_oapp_info(oapp_address) == updated_info, 1);

    // Verify other properties remain unchanged
    assert!(endpoint.is_oapp_registered(oapp_address), 2);
    // OApp package tracking functions have been removed

    // Test delegate functionality
    let delegate_cap = call_cap::new_individual_cap(scenario.ctx());
    let delegate_address = delegate_cap.id();

    // Initially delegate should be @0x0
    assert!(endpoint.get_delegate(oapp_address) == @0x0, 4);

    // Set delegate
    endpoint.set_delegate(&test_oapp_cap, delegate_address);
    assert!(endpoint.get_delegate(oapp_address) == delegate_address, 5);

    // Delegate should be able to update lz_receive_info
    let delegate_updated_info = b"delegate_updated_lz_receive_info";
    endpoint.set_oapp_info(&delegate_cap, oapp_address, delegate_updated_info);
    assert!(endpoint.get_oapp_info(oapp_address) == delegate_updated_info, 6);

    test_utils::destroy(test_oapp_cap);
    test_utils::destroy(delegate_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_set_composer_info() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);
    let composer_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let composer_address = composer_cap.id();
    let initial_info = b"initial_lz_compose_info_v1";
    let updated_info = b"updated_lz_compose_info_v2";

    // Register composer first
    endpoint.register_composer(&composer_cap, initial_info, scenario.ctx());

    // Verify initial info
    assert!(endpoint.get_composer_info(composer_address) == initial_info, 0);

    // Update composer_info
    endpoint.set_composer_info(&composer_cap, updated_info);

    // Verify info was updated
    assert!(endpoint.get_composer_info(composer_address) == updated_info, 1);

    // Verify other properties remain unchanged
    assert!(endpoint.is_composer_registered(composer_address), 2);
    // Composer package tracking functions have been removed

    test_utils::destroy(composer_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_set_receive_library_timeout() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);
    let mut clock = clock::create_for_testing(scenario.ctx());
    let test_oapp_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let oapp_address = test_oapp_cap.id();
    let src_eid = REMOTE_EID;
    register_oapp(&mut scenario, &mut endpoint, &test_oapp_cap);

    // Register two receive libraries
    let lib1_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let lib2_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_library(&admin_cap, lib1_cap.id(), message_lib_type::receive());
    endpoint.register_library(&admin_cap, lib2_cap.id(), message_lib_type::receive());
    let lib1_address = lib1_cap.id();
    let lib2_address = lib2_cap.id();

    // Set default receive library
    endpoint.set_default_receive_library(&admin_cap, src_eid, lib1_address, 0, &clock);

    // Set OApp-specific receive library
    endpoint.set_receive_library(&test_oapp_cap, oapp_address, src_eid, lib2_address, 0, &clock);

    // Initially no timeout for OApp
    let timeout_opt = endpoint.get_receive_library_timeout(oapp_address, src_eid);
    assert!(timeout_opt.is_none(), 0);

    // Set clock to 1000 seconds
    clock.set_for_testing(1000 * 1000);

    // Set timeout for the OApp's receive library
    endpoint.set_receive_library_timeout(&test_oapp_cap, oapp_address, src_eid, lib1_address, 1500, &clock);

    // Should have timeout now
    let timeout_opt = endpoint.get_receive_library_timeout(oapp_address, src_eid);
    assert!(timeout_opt.is_some(), 1);
    let timeout = timeout_opt.destroy_some();
    assert!(timeout.expiry() == 1500, 2);
    assert!(timeout.fallback_lib() == lib1_address, 3);

    // Test is_valid_receive_library with timeout
    assert!(endpoint.is_valid_receive_library(oapp_address, src_eid, lib2_address, &clock), 4); // Current library valid
    assert!(endpoint.is_valid_receive_library(oapp_address, src_eid, lib1_address, &clock), 5); // Timeout library valid

    // Move clock past timeout
    clock.set_for_testing(1600 * 1000);
    assert!(endpoint.is_valid_receive_library(oapp_address, src_eid, lib2_address, &clock), 6); // Current library still valid
    assert!(!endpoint.is_valid_receive_library(oapp_address, src_eid, lib1_address, &clock), 7); // Timeout library no longer valid

    // Remove timeout
    endpoint.set_receive_library_timeout(&test_oapp_cap, oapp_address, src_eid, lib1_address, 0, &clock);
    let timeout_opt2 = endpoint.get_receive_library_timeout(oapp_address, src_eid);
    assert!(timeout_opt2.is_none(), 8);

    // Test delegate authorization for set_receive_library_timeout
    let delegate_cap = call_cap::new_individual_cap(scenario.ctx());
    let delegate_address = delegate_cap.id();

    // Set delegate for the oapp
    endpoint.set_delegate(&test_oapp_cap, delegate_address);
    assert!(endpoint.get_delegate(oapp_address) == delegate_address, 9);

    // Reset clock for delegate test
    clock.set_for_testing(2000 * 1000);

    // Delegate should be able to set receive library timeout
    endpoint.set_receive_library_timeout(&delegate_cap, oapp_address, src_eid, lib2_address, 2500, &clock);

    // Verify delegate operation succeeded
    let timeout_opt3 = endpoint.get_receive_library_timeout(oapp_address, src_eid);
    assert!(timeout_opt3.is_some(), 10);
    let timeout3 = timeout_opt3.destroy_some();
    assert!(timeout3.expiry() == 2500, 11);
    assert!(timeout3.fallback_lib() == lib2_address, 12);

    test_utils::destroy(lib1_cap);
    test_utils::destroy(lib2_cap);
    test_utils::destroy(delegate_cap);
    test_utils::destroy(test_oapp_cap);
    clock.destroy_for_testing();
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test]
fun test_refund() {
    refund(option::some(@0xabcdef));
}

#[test, expected_failure(abort_code = endpoint_v2::ERefundAddressNotFound)]
fun test_refund_no_refund_address() {
    refund(option::none());
}

fun refund(refund_address_option: Option<address>) {
    let (mut scenario, admin_cap, endpoint, messaging_channel, oapp_cap) = setup(false);
    let receiver = bytes32::from_address(REMOTE_OAPP);
    let message = b"test refund message";
    let options = b"test refund options";
    let endpoint_cap = endpoint.get_call_cap_ref();

    // Create send param with refund address and tokens
    let native_fee_amount = 1000u64;
    let zro_fee_amount = 500u64;
    let receipt = messaging_receipt::create(bytes32::zero_bytes32(), 0, messaging_fee::create(100, 100));

    // Recreate the call for refund testing
    let native_coin = coin::mint_for_testing<IOTA>(native_fee_amount, scenario.ctx());
    let zro = option::some(coin::mint_for_testing<zro::ZRO>(zro_fee_amount, scenario.ctx()));
    let refund_send_param = endpoint_send::create_param(
        REMOTE_EID,
        receiver,
        message,
        options,
        native_coin,
        zro,
        refund_address_option,
    );
    let mut refund_call = call::create(
        &oapp_cap,
        endpoint.get_call_cap_ref().id(),
        true,
        refund_send_param,
        scenario.ctx(),
    );
    refund_call.complete(endpoint_cap, receipt);

    // Execute refund
    endpoint.refund(refund_call);

    // Advance to next transaction to see the effects
    scenario.next_tx(ADMIN);

    // Verify refund address received the tokens
    let refund_address = refund_address_option.destroy_some();
    assert!(ts::has_most_recent_for_address<coin::Coin<IOTA>>(refund_address), 2);
    assert!(ts::has_most_recent_for_address<coin::Coin<zro::ZRO>>(refund_address), 3);

    // Take and verify the refunded tokens
    let refunded_native = scenario.take_from_address<coin::Coin<IOTA>>(refund_address);
    let refunded_zro = scenario.take_from_address<coin::Coin<zro::ZRO>>(refund_address);
    assert!(refunded_native.value() == 1000, 4);
    assert!(refunded_zro.value() == 500, 5);

    // Clean up
    coin::burn_for_testing(refunded_native);
    coin::burn_for_testing(refunded_zro);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = endpoint_v2::EUnauthorizedOApp)]
fun test_unauthorized_set_oapp_info() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);
    let unauthorized_cap = call_cap::new_individual_cap(scenario.ctx());
    let oapp_address = oapp_cap.id();
    let updated_info = b"updated_info";

    // Unauthorized caller should not be able to set oapp_info
    endpoint.set_oapp_info(&unauthorized_cap, oapp_address, updated_info);

    test_utils::destroy(unauthorized_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = endpoint_v2::EUnauthorizedOApp)]
fun test_unauthorized_init_channel() {
    let (mut scenario, admin_cap, endpoint, mut messaging_channel, oapp_cap) = setup(true);
    let unauthorized_cap = call_cap::new_individual_cap(scenario.ctx());
    let remote_oapp_bytes32 = bytes32::from_address(REMOTE_OAPP);

    // Unauthorized caller should not be able to init channel
    endpoint_v2::init_channel(
        &endpoint,
        &unauthorized_cap,
        &mut messaging_channel,
        REMOTE_EID,
        remote_oapp_bytes32,
        scenario.ctx(),
    );

    test_utils::destroy(unauthorized_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = endpoint_v2::EUnauthorizedOApp)]
fun test_unauthorized_clear() {
    let (mut scenario, admin_cap, endpoint, mut messaging_channel, oapp_cap) = setup(false);
    let unauthorized_cap = call_cap::new_individual_cap(scenario.ctx());
    let sender = bytes32::from_address(REMOTE_OAPP);
    let guid = bytes32::from_bytes(b"guidguidguidguidguidguidguidguid");
    let message = b"test message";

    // Unauthorized caller should not be able to clear
    endpoint_v2::clear(&endpoint, &unauthorized_cap, &mut messaging_channel, REMOTE_EID, sender, 1, guid, message);

    test_utils::destroy(unauthorized_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = endpoint_v2::EUnauthorizedOApp)]
fun test_unauthorized_skip() {
    let (mut scenario, admin_cap, endpoint, mut messaging_channel, oapp_cap) = setup(false);
    let unauthorized_cap = call_cap::new_individual_cap(scenario.ctx());
    let sender = bytes32::from_address(REMOTE_OAPP);

    // Unauthorized caller should not be able to skip
    endpoint_v2::skip(&endpoint, &unauthorized_cap, &mut messaging_channel, REMOTE_EID, sender, 1);

    test_utils::destroy(unauthorized_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = endpoint_v2::EUnauthorizedOApp)]
fun test_unauthorized_burn() {
    let (mut scenario, admin_cap, endpoint, mut messaging_channel, oapp_cap) = setup(false);
    let unauthorized_cap = call_cap::new_individual_cap(scenario.ctx());
    let sender = bytes32::from_address(REMOTE_OAPP);
    let payload_hash = bytes32::zero_bytes32();

    // Unauthorized caller should not be able to burn
    endpoint_v2::burn(&endpoint, &unauthorized_cap, &mut messaging_channel, REMOTE_EID, sender, 1, payload_hash);

    test_utils::destroy(unauthorized_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = endpoint_v2::EUnauthorizedOApp)]
fun test_unauthorized_nilify() {
    let (mut scenario, admin_cap, endpoint, mut messaging_channel, oapp_cap) = setup(false);
    let unauthorized_cap = call_cap::new_individual_cap(scenario.ctx());
    let sender = bytes32::from_address(REMOTE_OAPP);
    let payload_hash = bytes32::zero_bytes32();

    // Unauthorized caller should not be able to nilify
    endpoint_v2::nilify(&endpoint, &unauthorized_cap, &mut messaging_channel, REMOTE_EID, sender, 1, payload_hash);

    test_utils::destroy(unauthorized_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = endpoint_v2::EUnauthorizedOApp)]
fun test_unauthorized_set_send_library() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);
    let unauthorized_cap = call_cap::new_individual_cap(scenario.ctx());
    let oapp_address = oapp_cap.id();

    // Register a send library first
    let send_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_library(&admin_cap, send_lib_cap.id(), message_lib_type::send());
    let send_lib_address = send_lib_cap.id();

    // Unauthorized caller should not be able to set send library
    endpoint.set_send_library(&unauthorized_cap, oapp_address, REMOTE_EID, send_lib_address);

    test_utils::destroy(unauthorized_cap);
    test_utils::destroy(send_lib_cap);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = endpoint_v2::EUnauthorizedOApp)]
fun test_unauthorized_set_receive_library() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);
    let unauthorized_cap = call_cap::new_individual_cap(scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    let oapp_address = oapp_cap.id();

    // Register a receive library first
    let receive_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_library(
        &admin_cap,
        receive_lib_cap.id(),
        message_lib_type::receive(),
    );
    let receive_lib_address = receive_lib_cap.id();

    // Unauthorized caller should not be able to set receive library
    endpoint.set_receive_library(&unauthorized_cap, oapp_address, REMOTE_EID, receive_lib_address, 0, &clock);

    test_utils::destroy(unauthorized_cap);
    test_utils::destroy(receive_lib_cap);
    clock.destroy_for_testing();
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = endpoint_v2::EUnauthorizedOApp)]
fun test_unauthorized_set_receive_library_timeout() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);
    let unauthorized_cap = call_cap::new_individual_cap(scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    let oapp_address = oapp_cap.id();

    // Register a receive library first
    let receive_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_library(
        &admin_cap,
        receive_lib_cap.id(),
        message_lib_type::receive(),
    );
    let receive_lib_address = receive_lib_cap.id();

    // Unauthorized caller should not be able to set receive library timeout
    endpoint.set_receive_library_timeout(
        &unauthorized_cap,
        oapp_address,
        REMOTE_EID,
        receive_lib_address,
        1000,
        &clock,
    );

    test_utils::destroy(unauthorized_cap);
    test_utils::destroy(receive_lib_cap);
    clock.destroy_for_testing();
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}

#[test, expected_failure(abort_code = endpoint_v2::EUnauthorizedOApp)]
fun test_unauthorized_set_config() {
    let (mut scenario, admin_cap, mut endpoint, messaging_channel, oapp_cap) = setup(false);
    let unauthorized_cap = call_cap::new_individual_cap(scenario.ctx());
    let oapp_address = oapp_cap.id();

    // Register message library
    let msg_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_library(&admin_cap, msg_lib_cap.id(), message_lib_type::send());
    let msg_lib_address = msg_lib_cap.id();

    // Unauthorized caller should not be able to execute set config
    // This will abort before creating the call due to authorization check
    let message_lib_call = endpoint.set_config(
        &unauthorized_cap,
        oapp_address,
        msg_lib_address,
        REMOTE_EID,
        1,
        b"test config",
        scenario.ctx(),
    );

    test_utils::destroy(unauthorized_cap);
    test_utils::destroy(msg_lib_cap);
    test_utils::destroy(message_lib_call);
    clean(scenario, admin_cap, endpoint, messaging_channel, oapp_cap);
}
