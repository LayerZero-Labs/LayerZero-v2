#[test_only]
module endpoint_ptb_builder::msglib_ptb_builder_info_tests;

use endpoint_ptb_builder::msglib_ptb_builder_info;
use ptb_move_call::{argument, move_call::{Self, MoveCall}};
use std::{ascii, type_name};
use sui::{test_scenario as ts, test_utils};
use utils::bytes32;

// === Test Constants ===

const MESSAGE_LIB_ADDRESS: address = @0x123;
const PTB_BUILDER_ADDRESS: address = @0x456;
const TEST_PACKAGE_ADDRESS: address = @0xabc;

// === Helper Functions ===

fun setup(): ts::Scenario {
    ts::begin(@0x1)
}

fun clean(scenario: ts::Scenario) {
    ts::end(scenario);
}

/// Create a sample MoveCall for testing
fun create_test_move_call(function_name: ascii::String): MoveCall {
    let arguments = vector[argument::create_object(@0x1), argument::create_id(bytes32::from_address(@0x2))];
    let type_arguments = vector[type_name::get<u64>()];

    move_call::create(
        TEST_PACKAGE_ADDRESS,
        ascii::string(b"test_module"),
        function_name,
        arguments,
        type_arguments,
        false, // is_builder_call
        vector[bytes32::from_address(@0x100)],
    )
}

/// Create test PTB templates for all operations
fun create_test_ptb_templates(): (vector<MoveCall>, vector<MoveCall>, vector<MoveCall>) {
    let quote_ptb = vector[
        create_test_move_call(ascii::string(b"quote_fee")),
        create_test_move_call(ascii::string(b"calculate_cost")),
    ];

    let send_ptb = vector[
        create_test_move_call(ascii::string(b"prepare_send")),
        create_test_move_call(ascii::string(b"execute_send")),
        create_test_move_call(ascii::string(b"emit_event")),
    ];

    let set_config_ptb = vector[
        create_test_move_call(ascii::string(b"validate_config")),
        create_test_move_call(ascii::string(b"update_config")),
    ];

    (quote_ptb, send_ptb, set_config_ptb)
}

// === Basic Tests ===

#[test]
fun test_create_msglib_ptb_builder_info() {
    let scenario = setup();

    let (quote_ptb, send_ptb, set_config_ptb) = create_test_ptb_templates();

    // Create MsglibPtbBuilderInfo with all parameters
    let info = msglib_ptb_builder_info::create(
        MESSAGE_LIB_ADDRESS,
        PTB_BUILDER_ADDRESS,
        quote_ptb,
        send_ptb,
        set_config_ptb,
    );

    // Verify all fields are set correctly through view functions
    assert!(info.message_lib() == MESSAGE_LIB_ADDRESS, 0);
    assert!(info.ptb_builder() == PTB_BUILDER_ADDRESS, 1);

    // Verify PTB templates have correct lengths
    assert!(info.quote_ptb().length() == 2, 3);
    assert!(info.send_ptb().length() == 3, 4);
    assert!(info.set_config_ptb().length() == 2, 5);

    test_utils::destroy(info);
    clean(scenario);
}
