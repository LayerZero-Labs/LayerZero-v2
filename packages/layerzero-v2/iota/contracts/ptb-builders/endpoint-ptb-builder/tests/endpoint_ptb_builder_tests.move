#[test_only]
module endpoint_ptb_builder::endpoint_ptb_builder_tests;

use call::{call, call_cap::{Self, CallCap}};
use endpoint_ptb_builder::{endpoint_ptb_builder::{Self, EndpointPtbBuilder, AdminCap}, msglib_ptb_builder_info};
use endpoint_v2::{
    endpoint_quote,
    endpoint_send,
    endpoint_v2::{Self, EndpointV2, AdminCap as EndpointAdminCap},
    message_lib_type
};
use ptb_move_call::{argument, move_call::{Self, MoveCall}};
use std::{ascii, type_name};
use iota::{clock, coin, iota::IOTA, test_scenario as ts, test_utils, vec_set};
use utils::bytes32;
use zro::zro::ZRO;

// === Test Constants ===

const ADMIN: address = @0x0;

const MESSAGE_LIB_ADDRESS: address = @0x2;
const PTB_BUILDER_ADDRESS: address = @0x3;
const EID: u32 = 1;

// === Helper Functions ===

fun setup(): (ts::Scenario, AdminCap, EndpointAdminCap, EndpointPtbBuilder, EndpointV2, CallCap) {
    let mut scenario = ts::begin(ADMIN);

    // Initialize EndpointPtbBuilder
    endpoint_ptb_builder::init_for_test(scenario.ctx());

    // Initialize EndpointV2
    let clock = clock::create_for_testing(scenario.ctx());
    endpoint_v2::init_for_test(scenario.ctx());

    scenario.next_tx(ADMIN);

    // Take capabilities and shared objects
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let endpoint_admin_cap = scenario.take_from_sender<EndpointAdminCap>();
    let endpoint_ptb_builder = scenario.take_shared<EndpointPtbBuilder>();
    let mut endpoint = scenario.take_shared<EndpointV2>();

    // Initialize endpoint with EID
    endpoint.init_eid(&endpoint_admin_cap, EID);

    // Create OApp capability and register it (this creates the messaging channel automatically)
    let oapp_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    endpoint.register_oapp(&oapp_cap, b"lz_receive_info", scenario.ctx());

    // Register a test message library in endpoint
    let msg_lib_cap = call_cap::new_package_cap_with_address_for_test(scenario.ctx(), MESSAGE_LIB_ADDRESS);
    endpoint.register_library(
        &endpoint_admin_cap,
        MESSAGE_LIB_ADDRESS,
        message_lib_type::send_and_receive(),
    );
    // Set default send library for the endpoint (use the already registered library)
    endpoint.set_default_send_library(&endpoint_admin_cap, EID, MESSAGE_LIB_ADDRESS);
    test_utils::destroy(msg_lib_cap);

    clock.destroy_for_testing();
    (scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap)
}

fun clean(
    scenario: ts::Scenario,
    admin_cap: AdminCap,
    endpoint_admin_cap: EndpointAdminCap,
    endpoint_ptb_builder: EndpointPtbBuilder,
    endpoint: EndpointV2,
    oapp_cap: CallCap,
) {
    ts::return_shared(endpoint_ptb_builder);
    ts::return_shared(endpoint);
    scenario.return_to_sender(admin_cap);
    scenario.return_to_sender(endpoint_admin_cap);
    test_utils::destroy(oapp_cap);
    ts::end(scenario);
}

/// Create a test MoveCall for PTB templates
fun create_test_move_call(function_name: ascii::String): MoveCall {
    let arguments = vector[argument::create_object(@0x1), argument::create_id(bytes32::from_address(@0x2))];
    let type_arguments = vector[type_name::get<u64>()];

    move_call::create(
        @0xabc,
        ascii::string(b"test_module"),
        function_name,
        arguments,
        type_arguments,
        false, // is_builder_call
        vector[bytes32::from_address(@0x100)],
    )
}

/// Create test PTB templates for message library operations
fun create_test_ptb_templates(): (vector<MoveCall>, vector<MoveCall>, vector<MoveCall>) {
    let quote_ptb = vector[
        create_test_move_call(ascii::string(b"quote_fee")),
        create_test_move_call(ascii::string(b"msglib_quote")),
    ];

    let send_ptb = vector[
        create_test_move_call(ascii::string(b"sent")),
        create_test_move_call(ascii::string(b"msglib_send")),
    ];

    let set_config_ptb = vector[
        create_test_move_call(ascii::string(b"set_config")),
        create_test_move_call(ascii::string(b"msglib_set_config")),
    ];

    (quote_ptb, send_ptb, set_config_ptb)
}

/// Create a test MsglibPtbBuilderInfo
fun create_test_msglib_ptb_builder_info(): msglib_ptb_builder_info::MsglibPtbBuilderInfo {
    let (quote_ptb, send_ptb, set_config_ptb) = create_test_ptb_templates();

    msglib_ptb_builder_info::create(
        MESSAGE_LIB_ADDRESS,
        PTB_BUILDER_ADDRESS,
        quote_ptb,
        send_ptb,
        set_config_ptb,
    )
}

// === Tests for init function ===

#[test]
fun test_init_function() {
    let mut scenario = ts::begin(ADMIN);

    // Initialize EndpointPtbBuilder
    endpoint_ptb_builder::init_for_test(scenario.ctx());

    scenario.next_tx(ADMIN);

    // Verify AdminCap was transferred to sender (ADMIN)
    assert!(scenario.has_most_recent_for_sender<AdminCap>(), 0);
    let admin_cap = scenario.take_from_sender<AdminCap>();

    // Verify EndpointPtbBuilder shared object was created
    let endpoint_ptb_builder = scenario.take_shared<EndpointPtbBuilder>();

    // Verify initial state
    assert!(endpoint_ptb_builder.registered_msglib_ptb_builders_count() == 0, 2);

    // Clean up
    ts::return_shared(endpoint_ptb_builder);
    scenario.return_to_sender(admin_cap);
    ts::end(scenario);
}

// === Tests for register_msglib_ptb_builder ===

#[test]
fun test_register_msglib_ptb_builder_success() {
    let (scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    let builder_info = create_test_msglib_ptb_builder_info();

    // Verify builder is not registered initially
    assert!(!endpoint_ptb_builder.is_msglib_ptb_builder_registered(PTB_BUILDER_ADDRESS), 0);
    assert!(endpoint_ptb_builder.registered_msglib_ptb_builders_count() == 0, 1);

    // Register the PTB builder
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info);

    // Verify registration was successful
    assert!(endpoint_ptb_builder.is_msglib_ptb_builder_registered(PTB_BUILDER_ADDRESS), 2);
    assert!(endpoint_ptb_builder.registered_msglib_ptb_builders_count() == 1, 3);

    // Verify builder info can be retrieved
    let retrieved_info = endpoint_ptb_builder.get_msglib_ptb_builder_info(PTB_BUILDER_ADDRESS);
    assert!(retrieved_info.message_lib() == MESSAGE_LIB_ADDRESS, 4);
    assert!(retrieved_info.ptb_builder() == PTB_BUILDER_ADDRESS, 5);

    // Verify PTB templates are accessible
    assert!(retrieved_info.quote_ptb().length() == 2, 6);
    assert!(retrieved_info.send_ptb().length() == 2, 7);
    assert!(retrieved_info.set_config_ptb().length() == 2, 8);

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
#[expected_failure(abort_code = endpoint_ptb_builder::EBuilderRegistered)]
fun test_register_msglib_ptb_builder_already_registered() {
    let (scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    let builder_info1 = create_test_msglib_ptb_builder_info();
    let builder_info2 = create_test_msglib_ptb_builder_info();

    // Register the PTB builder first time
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info1);

    // Try to register the same builder again - should fail
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info2);

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
#[expected_failure(abort_code = endpoint_ptb_builder::EInvalidLibrary)]
fun test_register_msglib_ptb_builder_invalid_library() {
    let (scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    let (quote_ptb, send_ptb, set_config_ptb) = create_test_ptb_templates();

    // Create builder info with unregistered message library
    let unregistered_lib = @0xdead;
    let builder_info = msglib_ptb_builder_info::create(
        unregistered_lib,
        PTB_BUILDER_ADDRESS,
        quote_ptb,
        send_ptb,
        set_config_ptb,
    );

    // Try to register PTB builder with invalid library - should fail
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info);

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
#[expected_failure(abort_code = endpoint_ptb_builder::EInvalidBuilderAddress)]
fun test_register_msglib_ptb_builder_invalid_builder_address() {
    let (scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    let (quote_ptb, send_ptb, set_config_ptb) = create_test_ptb_templates();

    // Create builder info with @0x0 builder address
    let builder_info = msglib_ptb_builder_info::create(
        MESSAGE_LIB_ADDRESS,
        @0x0, // Invalid builder address
        quote_ptb,
        send_ptb,
        set_config_ptb,
    );

    // Try to register PTB builder with invalid builder address - should fail
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info);

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
fun test_register_multiple_ptb_builders_for_same_message_lib() {
    let (scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Create first builder info
    let builder_info1 = create_test_msglib_ptb_builder_info();

    // Create second builder info with different addresses
    let ptb_builder_2 = @0x6;
    let (quote_ptb2, send_ptb2, set_config_ptb2) = create_test_ptb_templates();
    let builder_info2 = msglib_ptb_builder_info::create(
        MESSAGE_LIB_ADDRESS,
        ptb_builder_2,
        quote_ptb2,
        send_ptb2,
        set_config_ptb2,
    );

    // Register both builders
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info1);
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info2);

    // Verify both are registered
    assert!(endpoint_ptb_builder.is_msglib_ptb_builder_registered(PTB_BUILDER_ADDRESS), 0);
    assert!(endpoint_ptb_builder.is_msglib_ptb_builder_registered(ptb_builder_2), 1);
    assert!(endpoint_ptb_builder.registered_msglib_ptb_builders_count() == 2, 2);

    // Verify both builder infos can be retrieved
    let retrieved_info1 = endpoint_ptb_builder.get_msglib_ptb_builder_info(PTB_BUILDER_ADDRESS);
    let retrieved_info2 = endpoint_ptb_builder.get_msglib_ptb_builder_info(ptb_builder_2);

    assert!(retrieved_info1.message_lib() == MESSAGE_LIB_ADDRESS, 3);
    assert!(retrieved_info2.message_lib() == MESSAGE_LIB_ADDRESS, 4);

    let first_page = endpoint_ptb_builder.registered_msglib_ptb_builders(0, 1);
    assert!(first_page.length() == 1, 5);
    assert!(first_page[0] == PTB_BUILDER_ADDRESS, 6);

    // Get last builder
    let second_page = endpoint_ptb_builder.registered_msglib_ptb_builders(1, 1);
    assert!(second_page.length() == 1, 8);
    assert!(second_page[0] == ptb_builder_2, 9);

    // Get all builders
    let all_builders = endpoint_ptb_builder.registered_msglib_ptb_builders(0, 10);
    assert!(all_builders.length() == 2, 6);

    // Verify both builders can be found by their builder addresses
    let retrieved_info1_by_builder = endpoint_ptb_builder.get_msglib_ptb_builder_info(PTB_BUILDER_ADDRESS);
    let retrieved_info2_by_builder = endpoint_ptb_builder.get_msglib_ptb_builder_info(ptb_builder_2);

    assert!(retrieved_info1_by_builder.ptb_builder() == PTB_BUILDER_ADDRESS, 10);
    assert!(retrieved_info2_by_builder.ptb_builder() == ptb_builder_2, 11);

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

// === Tests for set_default_msglib_ptb_builder ===

#[test]
fun test_set_default_msglib_ptb_builder_success() {
    let (scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Register two PTB builders for the same library
    let builder_info1 = create_test_msglib_ptb_builder_info();
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info1);

    let second_builder_address = @0x777;
    let (quote_ptb2, send_ptb2, set_config_ptb2) = create_test_ptb_templates();
    let builder_info2 = msglib_ptb_builder_info::create(
        MESSAGE_LIB_ADDRESS,
        second_builder_address,
        quote_ptb2,
        send_ptb2,
        set_config_ptb2,
    );
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info2);

    // Set first builder as default
    endpoint_ptb_builder.set_default_msglib_ptb_builder(
        &admin_cap,
        MESSAGE_LIB_ADDRESS,
        PTB_BUILDER_ADDRESS,
    );
    let oapp_address = oapp_cap.id();
    let default_builder = endpoint_ptb_builder.get_default_msglib_ptb_builder(MESSAGE_LIB_ADDRESS);
    assert!(default_builder == PTB_BUILDER_ADDRESS, 0);

    let effective_builder = endpoint_ptb_builder.get_effective_msglib_ptb_builder(oapp_address, MESSAGE_LIB_ADDRESS);
    assert!(effective_builder == PTB_BUILDER_ADDRESS, 1);

    // Update to second builder as default
    endpoint_ptb_builder.set_default_msglib_ptb_builder(
        &admin_cap,
        MESSAGE_LIB_ADDRESS,
        second_builder_address,
    );

    let updated_default = endpoint_ptb_builder.get_default_msglib_ptb_builder(MESSAGE_LIB_ADDRESS);
    assert!(updated_default == second_builder_address, 2);

    let effective_builder = endpoint_ptb_builder.get_effective_msglib_ptb_builder(oapp_address, MESSAGE_LIB_ADDRESS);
    assert!(effective_builder == second_builder_address, 3);

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
#[expected_failure(abort_code = endpoint_ptb_builder::EBuilderNotFound)]
fun test_set_default_msglib_ptb_builder_unregistered_builder() {
    let (scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Try to set default builder without registering it first - should fail
    endpoint_ptb_builder.set_default_msglib_ptb_builder(
        &admin_cap,
        MESSAGE_LIB_ADDRESS,
        PTB_BUILDER_ADDRESS,
    );

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
#[expected_failure(abort_code = endpoint_ptb_builder::EBuilderUnsupported)]
fun test_set_default_msglib_ptb_builder_wrong_library() {
    let (mut scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Register a second message library
    let msg_lib_cap2 = call_cap::new_package_cap_with_address_for_test(scenario.ctx(), MESSAGE_LIB_ADDRESS);
    let different_lib_address = @0x999;

    // Register a PTB builder for MESSAGE_LIB_ADDRESS
    let builder_info = create_test_msglib_ptb_builder_info();
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info);

    // Try to set the builder as default for a different library - should fail
    endpoint_ptb_builder.set_default_msglib_ptb_builder(
        &admin_cap,
        different_lib_address, // Different library
        PTB_BUILDER_ADDRESS, // Builder supports MESSAGE_LIB_ADDRESS, not different_lib_address
    );

    test_utils::destroy(msg_lib_cap2);
    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
fun test_set_default_msglib_ptb_builder_multiple_libraries() {
    let (mut scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, mut endpoint, oapp_cap) = setup();

    // Register a second message library
    let msg_lib_cap2 = call_cap::new_package_cap_for_test(scenario.ctx());
    let second_lib_address = @0x555;
    endpoint.register_library(
        &endpoint_admin_cap,
        second_lib_address,
        message_lib_type::send_and_receive(),
    );

    // Register PTB builders for both libraries
    let builder_info1 = create_test_msglib_ptb_builder_info();
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info1);

    let second_builder_address = @0x666;
    let (quote_ptb2, send_ptb2, set_config_ptb2) = create_test_ptb_templates();
    let builder_info2 = msglib_ptb_builder_info::create(
        second_lib_address,
        second_builder_address,
        quote_ptb2,
        send_ptb2,
        set_config_ptb2,
    );
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info2);

    // Set defaults for both libraries
    endpoint_ptb_builder.set_default_msglib_ptb_builder(
        &admin_cap,
        MESSAGE_LIB_ADDRESS,
        PTB_BUILDER_ADDRESS,
    );

    endpoint_ptb_builder.set_default_msglib_ptb_builder(
        &admin_cap,
        second_lib_address,
        second_builder_address,
    );

    // Verify both defaults are set correctly
    let default1 = endpoint_ptb_builder.get_default_msglib_ptb_builder(MESSAGE_LIB_ADDRESS);
    let default2 = endpoint_ptb_builder.get_default_msglib_ptb_builder(second_lib_address);

    assert!(default1 == PTB_BUILDER_ADDRESS, 0);
    assert!(default2 == second_builder_address, 1);

    test_utils::destroy(msg_lib_cap2);
    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

// === Tests for PTB build functions ===

#[test]
fun test_build_quote_ptb() {
    let (scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Register and set default PTB builder
    let builder_info = create_test_msglib_ptb_builder_info();
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info);
    endpoint_ptb_builder.set_default_msglib_ptb_builder(
        &admin_cap,
        MESSAGE_LIB_ADDRESS,
        PTB_BUILDER_ADDRESS,
    );

    let oapp_address = oapp_cap.id();

    // Build quote PTB
    let quote_ptb = endpoint_ptb_builder.build_quote_ptb(&endpoint, oapp_address, EID);

    // The PTB should contain:
    // 1. endpoint_v2::quote call
    // 2. message library specific quote calls (2 in our test template)
    // 3. endpoint_v2::confirm_quote call
    // Total: 1 + 2 + 1 = 4 calls
    assert!(quote_ptb.length() == 4, 1);

    // Assert first call: endpoint_v2::quote
    let first_call = &quote_ptb[0];
    assert!(first_call.function().module_name() == ascii::string(b"endpoint_v2"), 2);
    assert!(first_call.function().function_name() == ascii::string(b"quote"), 3);
    assert!(!first_call.is_builder_call(), 4);
    assert!(first_call.arguments().length() == 3, 5); // endpoint, messaging_channel, endpoint_quote_call
    assert!(first_call.result_ids().length() == 1, 6); // returns message_lib_quote_call

    // Assert second call: first msglib quote call (quote_fee)
    let second_call = &quote_ptb[1];
    assert!(second_call.function().module_name() == ascii::string(b"test_module"), 7);
    assert!(second_call.function().function_name() == ascii::string(b"quote_fee"), 8);
    assert!(!second_call.is_builder_call(), 9);

    // Assert third call: second msglib quote call (msglib_quote)
    let third_call = &quote_ptb[2];
    assert!(third_call.function().module_name() == ascii::string(b"test_module"), 10);
    assert!(third_call.function().function_name() == ascii::string(b"msglib_quote"), 11);
    assert!(!third_call.is_builder_call(), 12);

    // Assert fourth call: endpoint_v2::confirm_quote
    let fourth_call = &quote_ptb[3];
    assert!(fourth_call.function().module_name() == ascii::string(b"endpoint_v2"), 13);
    assert!(fourth_call.function().function_name() == ascii::string(b"confirm_quote"), 14);
    assert!(!fourth_call.is_builder_call(), 15);
    assert!(fourth_call.arguments().length() == 3, 16); // endpoint, endpoint_quote_call, message_lib_quote_call
    assert!(fourth_call.result_ids().length() == 0, 17); // no return value

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
fun test_build_send_ptb_with_refund() {
    let (scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Register and set default PTB builder
    let builder_info = create_test_msglib_ptb_builder_info();
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info);
    endpoint_ptb_builder.set_default_msglib_ptb_builder(
        &admin_cap,
        MESSAGE_LIB_ADDRESS,
        PTB_BUILDER_ADDRESS,
    );

    let oapp_address = oapp_cap.id();

    // Build send PTB with refund
    let send_ptb = endpoint_ptb_builder.build_send_ptb(&endpoint, oapp_address, EID, true);

    // The PTB should contain:
    // 1. endpoint_v2::send call
    // 2. message library specific send calls (2 in our test template)
    // 3. endpoint_v2::refund call (because refund = true)
    // Total: 1 + 2 + 1 = 4 calls
    assert!(send_ptb.length() == 4, 1);

    // Assert first call: endpoint_v2::send
    let first_call = &send_ptb[0];
    assert!(first_call.function().module_name() == ascii::string(b"endpoint_v2"), 2);
    assert!(first_call.function().function_name() == ascii::string(b"send"), 3);
    assert!(!first_call.is_builder_call(), 4);
    assert!(first_call.arguments().length() == 3, 5); // endpoint, messaging_channel, endpoint_send_call
    assert!(first_call.result_ids().length() == 1, 6); // returns message_lib_send_call

    // Assert second call: first msglib send call (sent)
    let second_call = &send_ptb[1];
    assert!(second_call.function().module_name() == ascii::string(b"test_module"), 7);
    assert!(second_call.function().function_name() == ascii::string(b"sent"), 8);
    assert!(!second_call.is_builder_call(), 9);

    // Assert third call: second msglib send call (msglib_send)
    let third_call = &send_ptb[2];
    assert!(third_call.function().module_name() == ascii::string(b"test_module"), 10);
    assert!(third_call.function().function_name() == ascii::string(b"msglib_send"), 11);
    assert!(!third_call.is_builder_call(), 12);

    // Assert fourth call: endpoint_v2::refund
    let fourth_call = &send_ptb[3];
    assert!(fourth_call.function().module_name() == ascii::string(b"endpoint_v2"), 13);
    assert!(fourth_call.function().function_name() == ascii::string(b"refund"), 14);
    assert!(!fourth_call.is_builder_call(), 15);
    assert!(fourth_call.arguments().length() == 2, 16); // endpoint, endpoint_send_call
    assert!(fourth_call.result_ids().length() == 0, 17); // no return value

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
fun test_build_send_ptb_without_refund() {
    let (scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Register and set default PTB builder
    let builder_info = create_test_msglib_ptb_builder_info();
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info);
    endpoint_ptb_builder.set_default_msglib_ptb_builder(
        &admin_cap,
        MESSAGE_LIB_ADDRESS,
        PTB_BUILDER_ADDRESS,
    );

    let oapp_address = oapp_cap.id();

    // Build send PTB without refund
    let send_ptb = endpoint_ptb_builder.build_send_ptb(&endpoint, oapp_address, EID, false);

    // The PTB should contain:
    // 1. endpoint_v2::send call
    // 2. message library specific send calls (2 in our test template)
    // No refund call (because refund = false)
    // Total: 1 + 2 = 3 calls
    assert!(send_ptb.length() == 3, 1);

    // Assert first call: endpoint_v2::send
    let first_call = &send_ptb[0];
    assert!(first_call.function().module_name() == ascii::string(b"endpoint_v2"), 2);
    assert!(first_call.function().function_name() == ascii::string(b"send"), 3);
    assert!(!first_call.is_builder_call(), 4);
    assert!(first_call.arguments().length() == 3, 5); // endpoint, messaging_channel, endpoint_send_call
    assert!(first_call.result_ids().length() == 1, 6); // returns message_lib_send_call

    // Assert second call: first msglib send call (sent)
    let second_call = &send_ptb[1];
    assert!(second_call.function().module_name() == ascii::string(b"test_module"), 7);
    assert!(second_call.function().function_name() == ascii::string(b"sent"), 8);
    assert!(!second_call.is_builder_call(), 9);

    // Assert third call: second msglib send call (msglib_send)
    let third_call = &send_ptb[2];
    assert!(third_call.function().module_name() == ascii::string(b"test_module"), 10);
    assert!(third_call.function().function_name() == ascii::string(b"msglib_send"), 11);
    assert!(!third_call.is_builder_call(), 12);

    // Verify no refund call exists (only 3 calls total)

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
fun test_build_set_config_ptb() {
    let (scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Register and set default PTB builder
    let builder_info = create_test_msglib_ptb_builder_info();
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info);
    endpoint_ptb_builder.set_default_msglib_ptb_builder(
        &admin_cap,
        MESSAGE_LIB_ADDRESS,
        PTB_BUILDER_ADDRESS,
    );

    let oapp_address = oapp_cap.id();

    // Build set_config PTB
    let set_config_ptb = endpoint_ptb_builder.build_set_config_ptb(oapp_address, MESSAGE_LIB_ADDRESS);

    // The PTB should contain:
    // 1. message library specific set_config calls (2 in our test template)
    // Total: 2 calls (simplified architecture - no endpoint orchestration)
    assert!(set_config_ptb.length() == 2, 1);

    // Assert first call: first msglib set_config call (set_config)
    let first_call = &set_config_ptb[0];
    assert!(first_call.function().module_name() == ascii::string(b"test_module"), 2);
    assert!(first_call.function().function_name() == ascii::string(b"set_config"), 3);
    assert!(!first_call.is_builder_call(), 4);

    // Assert second call: second msglib set_config call (msglib_set_config)
    let second_call = &set_config_ptb[1];
    assert!(second_call.function().module_name() == ascii::string(b"test_module"), 5);
    assert!(second_call.function().function_name() == ascii::string(b"msglib_set_config"), 6);
    assert!(!second_call.is_builder_call(), 7);

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
fun test_build_ptb_with_oapp_specific_builder() {
    let (scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Register two PTB builders
    let builder_info1 = create_test_msglib_ptb_builder_info();
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info1);

    // Create second builder with different template sizes
    let second_builder_address = @0x777;
    let quote_ptb2 = vector[create_test_move_call(ascii::string(b"custom_quote"))]; // Only 1 call
    let send_ptb2 = vector[create_test_move_call(ascii::string(b"custom_send"))]; // Only 1 call
    let set_config_ptb2 = vector[create_test_move_call(ascii::string(b"custom_config"))]; // Only 1 call
    let builder_info2 = msglib_ptb_builder_info::create(
        MESSAGE_LIB_ADDRESS,
        second_builder_address,
        quote_ptb2,
        send_ptb2,
        set_config_ptb2,
    );
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info2);

    // Set first builder as default
    endpoint_ptb_builder.set_default_msglib_ptb_builder(
        &admin_cap,
        MESSAGE_LIB_ADDRESS,
        PTB_BUILDER_ADDRESS,
    );

    // Set second builder for specific OApp
    let oapp_address = oapp_cap.id();
    endpoint_ptb_builder.set_msglib_ptb_builder(
        &oapp_cap,
        &endpoint,
        oapp_address,
        MESSAGE_LIB_ADDRESS,
        second_builder_address,
    );

    // Build quote PTB - should use OApp-specific builder (second builder)
    let quote_ptb = endpoint_ptb_builder.build_quote_ptb(&endpoint, oapp_address, EID);

    // Should use the OApp-specific builder with 1 msglib call instead of default's 2 calls
    // Total: 1 (endpoint::quote) + 1 (custom msglib call) + 1 (endpoint::confirm_quote) = 3
    assert!(quote_ptb.length() == 3, 0);

    // Assert first call: endpoint_v2::quote
    let first_call = &quote_ptb[0];
    assert!(first_call.function().module_name() == ascii::string(b"endpoint_v2"), 1);
    assert!(first_call.function().function_name() == ascii::string(b"quote"), 2);
    assert!(!first_call.is_builder_call(), 3);

    // Assert second call: OApp-specific custom quote call
    let second_call = &quote_ptb[1];
    assert!(second_call.function().module_name() == ascii::string(b"test_module"), 4);
    assert!(second_call.function().function_name() == ascii::string(b"custom_quote"), 5);
    assert!(!second_call.is_builder_call(), 6);

    // Assert third call: endpoint_v2::confirm_quote
    let third_call = &quote_ptb[2];
    assert!(third_call.function().module_name() == ascii::string(b"endpoint_v2"), 7);
    assert!(third_call.function().function_name() == ascii::string(b"confirm_quote"), 8);
    assert!(!third_call.is_builder_call(), 9);

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
#[expected_failure(abort_code = endpoint_ptb_builder::EBuilderNotFound)]
fun test_build_ptb_no_default_builder() {
    let (scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Don't register any PTB builder or set any defaults

    let oapp_address = oapp_cap.id();

    // Try to build quote PTB without any registered builders - should fail
    endpoint_ptb_builder.build_quote_ptb(&endpoint, oapp_address, EID);

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
fun test_build_quote_ptb_by_call() {
    let (mut scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Register and set default PTB builder
    let builder_info = create_test_msglib_ptb_builder_info();
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info);
    endpoint_ptb_builder.set_default_msglib_ptb_builder(
        &admin_cap,
        MESSAGE_LIB_ADDRESS,
        PTB_BUILDER_ADDRESS,
    );

    // Create endpoint quote call
    let quote_param = endpoint_quote::create_param(
        EID,
        bytes32::from_address(@0x123),
        b"test message",
        b"test options",
        false,
    );
    // Note: Cannot access endpoint's call_cap from external package, so we'll use a mock address
    let quote_call = call::create(&oapp_cap, @0x1234567890abcdef, false, quote_param, scenario.ctx());

    // Build quote PTB using the call object
    let quote_ptb = endpoint_ptb_builder.build_quote_ptb_by_call(&endpoint, &quote_call);

    // Verify PTB structure (same as direct build_quote_ptb)
    assert!(quote_ptb.length() == 4, 0);

    // Assert first call: endpoint_v2::quote
    let first_call = &quote_ptb[0];
    assert!(first_call.function().module_name() == ascii::string(b"endpoint_v2"), 1);
    assert!(first_call.function().function_name() == ascii::string(b"quote"), 2);

    // Assert msglib calls are included
    let second_call = &quote_ptb[1];
    assert!(second_call.function().function_name() == ascii::string(b"quote_fee"), 3);

    let third_call = &quote_ptb[2];
    assert!(third_call.function().function_name() == ascii::string(b"msglib_quote"), 4);

    // Assert final call: endpoint_v2::confirm_quote
    let fourth_call = &quote_ptb[3];
    assert!(fourth_call.function().function_name() == ascii::string(b"confirm_quote"), 5);

    test_utils::destroy(quote_call);
    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
fun test_build_send_ptb_by_call_with_refund() {
    let (mut scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Register and set default PTB builder
    let builder_info = create_test_msglib_ptb_builder_info();
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info);
    endpoint_ptb_builder.set_default_msglib_ptb_builder(
        &admin_cap,
        MESSAGE_LIB_ADDRESS,
        PTB_BUILDER_ADDRESS,
    );

    // Default send library is already set in setup()

    let oapp_address = oapp_cap.id();

    // Create endpoint send call (one-way = true for refund)
    let native_fee = coin::mint_for_testing<IOTA>(1000, scenario.ctx());
    let zro_fee = option::some(coin::mint_for_testing<ZRO>(500, scenario.ctx()));
    let send_param = endpoint_send::create_param(
        EID,
        bytes32::from_address(@0x123),
        b"test message",
        b"test options",
        native_fee,
        zro_fee,
        option::some(oapp_address),
    );
    // Note: Cannot access endpoint's call_cap from external package, so we'll use a mock address
    let send_call = call::create(&oapp_cap, @0x1234567890abcdef, true, send_param, scenario.ctx());

    // Build send PTB using the call object
    let send_ptb = endpoint_ptb_builder.build_send_ptb_by_call(&endpoint, &send_call);

    // Verify PTB structure (should include refund because call.one_way() == true)
    assert!(send_ptb.length() == 4, 0); // send + msglib calls + refund

    // Assert first call: endpoint_v2::send
    let first_call = &send_ptb[0];
    assert!(first_call.function().module_name() == ascii::string(b"endpoint_v2"), 1);
    assert!(first_call.function().function_name() == ascii::string(b"send"), 2);

    // Assert msglib calls are included
    let second_call = &send_ptb[1];
    assert!(second_call.function().function_name() == ascii::string(b"sent"), 3);

    let third_call = &send_ptb[2];
    assert!(third_call.function().function_name() == ascii::string(b"msglib_send"), 4);

    // Assert refund call is included (because one_way = true)
    let fourth_call = &send_ptb[3];
    assert!(fourth_call.function().function_name() == ascii::string(b"refund"), 5);

    test_utils::destroy(send_call);
    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
fun test_build_send_ptb_by_call_without_refund() {
    let (mut scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Register and set default PTB builder
    let builder_info = create_test_msglib_ptb_builder_info();
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info);
    endpoint_ptb_builder.set_default_msglib_ptb_builder(
        &admin_cap,
        MESSAGE_LIB_ADDRESS,
        PTB_BUILDER_ADDRESS,
    );

    // Default send library is already set in setup()

    let oapp_address = oapp_cap.id();

    // Create endpoint send call (one-way = false for no refund)
    let native_fee = coin::mint_for_testing<IOTA>(1000, scenario.ctx());
    let zro_fee = option::some(coin::mint_for_testing<ZRO>(500, scenario.ctx()));
    let send_param = endpoint_send::create_param(
        EID,
        bytes32::from_address(@0x123),
        b"test message",
        b"test options",
        native_fee,
        zro_fee,
        option::some(oapp_address),
    );
    // Note: Cannot access endpoint's call_cap from external package, so we'll use a mock address
    let send_call = call::create(&oapp_cap, @0x1234567890abcdef, false, send_param, scenario.ctx());

    // Build send PTB using the call object
    let send_ptb = endpoint_ptb_builder.build_send_ptb_by_call(&endpoint, &send_call);

    // Verify PTB structure (should NOT include refund because call.one_way() == false)
    assert!(send_ptb.length() == 3, 0); // send + msglib calls (no refund)

    // Assert first call: endpoint_v2::send
    let first_call = &send_ptb[0];
    assert!(first_call.function().module_name() == ascii::string(b"endpoint_v2"), 1);
    assert!(first_call.function().function_name() == ascii::string(b"send"), 2);

    // Assert msglib calls are included
    let second_call = &send_ptb[1];
    assert!(second_call.function().function_name() == ascii::string(b"sent"), 3);

    let third_call = &send_ptb[2];
    assert!(third_call.function().function_name() == ascii::string(b"msglib_send"), 4);

    // Verify no refund call (only 3 calls total)

    test_utils::destroy(send_call);
    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

// === Tests for call ID functions ===

#[test]
fun test_call_id_functions_generate_different_ids() {
    let scenario = ts::begin(ADMIN);

    // Create VecSet to collect all call IDs
    let mut call_ids = vec_set::empty();

    // Add all call IDs to the set
    call_ids.insert(endpoint_ptb_builder::endpoint_quote_call_id());
    call_ids.insert(endpoint_ptb_builder::endpoint_send_call_id());
    call_ids.insert(endpoint_ptb_builder::message_lib_quote_call_id());
    call_ids.insert(endpoint_ptb_builder::message_lib_send_call_id());
    call_ids.insert(endpoint_ptb_builder::message_lib_set_config_call_id());

    ts::end(scenario);
}

// === Tests for view functions ===

#[test]
#[expected_failure(abort_code = endpoint_ptb_builder::EBuilderNotFound)]
fun test_get_default_msglib_ptb_builder_not_found() {
    let (scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Try to get default builder for a library that has no default set
    let unregistered_lib = @0xdead;
    endpoint_ptb_builder.get_default_msglib_ptb_builder(unregistered_lib);

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
#[expected_failure(abort_code = endpoint_ptb_builder::EBuilderNotFound)]
fun test_get_oapp_msglib_ptb_builder_not_found() {
    let (scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    let oapp_address = oapp_cap.id();

    // Try to get OApp-specific builder when none is configured
    endpoint_ptb_builder.get_oapp_msglib_ptb_builder(oapp_address, MESSAGE_LIB_ADDRESS);

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
#[expected_failure(abort_code = endpoint_ptb_builder::EBuilderNotFound)]
fun test_get_default_msglib_ptb_builder_after_registration_but_no_default() {
    let (scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Register a PTB builder but don't set it as default
    let builder_info = create_test_msglib_ptb_builder_info();
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info);

    // Verify builder is registered
    assert!(endpoint_ptb_builder.is_msglib_ptb_builder_registered(PTB_BUILDER_ADDRESS), 0);

    // Try to get default for a different library (not MESSAGE_LIB_ADDRESS)
    let different_lib = @0xbeef;
    endpoint_ptb_builder.get_default_msglib_ptb_builder(different_lib);

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
#[expected_failure(abort_code = endpoint_ptb_builder::EInvalidBounds)]
fun test_registered_msglib_ptb_builders_invalid_bounds() {
    let (scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Try to get builders with invalid bounds (start > total count)
    endpoint_ptb_builder.registered_msglib_ptb_builders(10, 5);

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
#[expected_failure(abort_code = endpoint_ptb_builder::EBuilderNotFound)]
fun test_get_msglib_ptb_builder_info_not_found() {
    let (scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Try to get info for non-existent builder
    endpoint_ptb_builder.get_msglib_ptb_builder_info(@0xdead);

    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

// === Tests for set_msglib_ptb_builder authorization ===

#[test]
#[expected_failure(abort_code = endpoint_ptb_builder::EUnauthorized)]
fun test_set_msglib_ptb_builder_unauthorized_caller() {
    let (mut scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, endpoint, oapp_cap) = setup();

    // Register a PTB builder and set it as default
    let builder_info = create_test_msglib_ptb_builder_info();
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info);
    endpoint_ptb_builder.set_default_msglib_ptb_builder(&admin_cap, MESSAGE_LIB_ADDRESS, PTB_BUILDER_ADDRESS);

    // Create an unauthorized caller (different from OApp and not a delegate)
    let unauthorized_cap = call_cap::new_individual_cap(scenario.ctx());
    let oapp_address = oapp_cap.id();

    // Try to set PTB builder with unauthorized caller - should fail
    endpoint_ptb_builder.set_msglib_ptb_builder(
        &unauthorized_cap,
        &endpoint,
        oapp_address,
        MESSAGE_LIB_ADDRESS,
        PTB_BUILDER_ADDRESS,
    );

    test_utils::destroy(unauthorized_cap);
    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}

#[test]
fun test_set_msglib_ptb_builder_with_oapp_delegate() {
    let (mut scenario, admin_cap, endpoint_admin_cap, mut endpoint_ptb_builder, mut endpoint, oapp_cap) = setup();

    // Register a PTB builder and set it as default
    let builder_info = create_test_msglib_ptb_builder_info();
    endpoint_ptb_builder.register_msglib_ptb_builder(&admin_cap, &endpoint, builder_info);
    endpoint_ptb_builder.set_default_msglib_ptb_builder(&admin_cap, MESSAGE_LIB_ADDRESS, PTB_BUILDER_ADDRESS);

    // Create a delegate capability
    let delegate_cap = call_cap::new_individual_cap(scenario.ctx());
    let oapp_address = oapp_cap.id();
    let delegate_address = object::id_address(&delegate_cap);

    // Set the delegate for the OApp
    endpoint.set_delegate(&oapp_cap, delegate_address);

    // Verify delegate is set correctly
    assert!(endpoint.get_delegate(oapp_address) == delegate_address, 0);

    // Set PTB builder using the delegate - should succeed
    endpoint_ptb_builder.set_msglib_ptb_builder(
        &delegate_cap,
        &endpoint,
        oapp_address,
        MESSAGE_LIB_ADDRESS,
        PTB_BUILDER_ADDRESS,
    );

    // Verify the PTB builder was set successfully
    let oapp_builder = endpoint_ptb_builder.get_oapp_msglib_ptb_builder(oapp_address, MESSAGE_LIB_ADDRESS);
    assert!(oapp_builder == PTB_BUILDER_ADDRESS, 1);

    // Verify effective builder resolves correctly
    let effective_builder = endpoint_ptb_builder.get_effective_msglib_ptb_builder(oapp_address, MESSAGE_LIB_ADDRESS);
    assert!(effective_builder == PTB_BUILDER_ADDRESS, 2);

    test_utils::destroy(delegate_cap);
    clean(scenario, admin_cap, endpoint_admin_cap, endpoint_ptb_builder, endpoint, oapp_cap);
}
