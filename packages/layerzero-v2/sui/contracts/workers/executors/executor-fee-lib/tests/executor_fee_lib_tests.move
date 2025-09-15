#[test_only]
module executor_fee_lib::executor_fee_lib_tests;

use call::call;
use executor_call_type::executor_feelib_get_fee;
use executor_fee_lib::{executor_fee_lib::{Self, ExecutorFeeLib}, executor_option};
use sui::{test_scenario as ts, test_utils};
use utils::{buffer_writer, bytes32};

// === Test Constants ===

const EXECUTOR: address = @0x1111;
const PRICE_FEED: address = @0x2222;
const SENDER: address = @0x3333;

// EID constants
const V2_EID: u32 = 30001; // >= 30000

// Gas constants
const BASE_LZ_RECEIVE_GAS: u64 = 100;
const BASE_LZ_COMPOSE_GAS: u64 = 200;
const ADDITIONAL_GAS: u128 = 50;

// Fee constants
const DEFAULT_MULTIPLIER_BPS: u16 = 10500; // 5% premium (105%)
const NATIVE_CAP: u128 = 1000000000; // 1e9
const FLOOR_MARGIN_USD: u128 = 100;
const CALL_DATA_SIZE: u64 = 1000;

// === Tests ===

#[test]
fun test_init() {
    let mut scenario = setup();

    init_executor_fee_lib_for_test(&mut scenario);

    scenario.next_tx(EXECUTOR);
    {
        let executor_fee_lib = ts::take_shared<ExecutorFeeLib>(&scenario);
        // Verify the fee lib was created successfully
        let _call_cap = executor_fee_lib::get_call_cap(&executor_fee_lib);
        ts::return_shared(executor_fee_lib);
    };

    clean(scenario);
}

#[test]
fun test_get_fee_basic() {
    let mut scenario = setup();

    init_executor_fee_lib_for_test(&mut scenario);

    scenario.next_tx(EXECUTOR);
    {
        let executor_fee_lib = ts::take_shared<ExecutorFeeLib>(&scenario);

        // Create basic executor options
        let options = create_basic_executor_options(ADDITIONAL_GAS, 200);

        // Create fee lib parameter
        let param = executor_feelib_get_fee::create_param(
            SENDER,
            V2_EID,
            CALL_DATA_SIZE,
            options,
            PRICE_FEED,
            DEFAULT_MULTIPLIER_BPS,
            BASE_LZ_RECEIVE_GAS,
            BASE_LZ_COMPOSE_GAS,
            FLOOR_MARGIN_USD,
            NATIVE_CAP,
            0, // multiplier_bps (will use default)
        );

        // Create call
        let mut call = call::create(
            executor_fee_lib.get_call_cap(),
            @0x0, // callee
            false, // one_way
            param,
            scenario.ctx(),
        );

        // Get fee estimate - this creates a child call to the price feed
        let price_feed_call = executor_fee_lib.get_fee(&mut call, scenario.ctx());

        // Verify the price feed call was created and the parent call is waiting
        assert!(call.status().is_waiting(), 0);
        assert!(price_feed_call.callee() == PRICE_FEED, 1);

        // For this test, we'll just verify the call was set up correctly
        // and clean up without completing the full flow since that would
        // require a real price feed interaction

        // Clean up - destroy the child call and parent call
        test_utils::destroy(price_feed_call);
        test_utils::destroy(call);
        ts::return_shared(executor_fee_lib);
    };

    clean(scenario);
}

#[test]
fun test_is_v1_eid() {
    // Test V1 EIDs (< 30000)
    assert!(
        executor_option::parse_executor_options(
            create_basic_executor_options(100, 0), // No value for V1
            true, // is_v1_eid
            NATIVE_CAP
        ).total_gas() > 0,
        0,
    );

    // Test V2 EIDs (>= 30000)
    assert!(
        executor_option::parse_executor_options(
            create_basic_executor_options(100, 200), // With value for V2
            false, // is_v1_eid
            NATIVE_CAP
        ).total_value() == 200,
        1,
    );
}

#[test]
fun test_parse_basic_executor_options() {
    let options = create_basic_executor_options(ADDITIONAL_GAS, 200);
    let agg_options = executor_option::parse_executor_options(options, false, NATIVE_CAP);

    assert!(agg_options.total_gas() == ADDITIONAL_GAS, 0);
    assert!(agg_options.total_value() == 200, 1);
    assert!(!agg_options.ordered(), 2);
    assert!(agg_options.num_lz_compose() == 0, 3);
}

#[test]
fun test_parse_native_drop_options() {
    let mut writer = buffer_writer::new();

    // First add basic lz_receive option (required)
    writer.write_u8(1); // Worker ID
    writer.write_u16(17); // Size (1 + 16, no value)
    writer.write_u8(1); // Type: LZRECEIVE
    writer.write_u128(100); // Gas

    // Add native drop option
    writer.write_u8(1); // Worker ID
    writer.write_u16(49); // Size
    writer.write_u8(2); // Type: NATIVE_DROP
    writer.write_u128(500); // Amount
    writer.write_bytes32(bytes32::from_address(@0x1234)); // Receiver

    let options = writer.to_bytes();
    let agg_options = executor_option::parse_executor_options(options, false, NATIVE_CAP);

    assert!(agg_options.total_gas() == 100, 0);
    assert!(agg_options.total_value() == 500, 1); // Only native drop value
    assert!(!agg_options.ordered(), 2);
    assert!(agg_options.num_lz_compose() == 0, 3);
}

#[test]
fun test_parse_lz_compose_options() {
    let mut writer = buffer_writer::new();

    // First add basic lz_receive option (required)
    writer.write_u8(1); // Worker ID
    writer.write_u16(17); // Size (1 + 16, no value)
    writer.write_u8(1); // Type: LZRECEIVE
    writer.write_u128(100); // Gas

    // Add lz_compose option
    writer.write_u8(1); // Worker ID
    writer.write_u16(35); // Size
    writer.write_u8(3); // Type: LZCOMPOSE
    writer.write_u16(0); // Index
    writer.write_u128(200); // Gas
    writer.write_u128(300); // Value

    let options = writer.to_bytes();
    let agg_options = executor_option::parse_executor_options(options, false, NATIVE_CAP);

    assert!(agg_options.total_gas() == 300, 0); // 100 (lz_receive) + 200 (lz_compose)
    assert!(agg_options.total_value() == 300, 1); // Only lz_compose value
    assert!(!agg_options.ordered(), 2);
    assert!(agg_options.num_lz_compose() == 1, 3);
}

#[test]
fun test_parse_ordered_execution_option() {
    let mut writer = buffer_writer::new();

    // Add basic lz_receive option (required)
    writer.write_u8(1); // Worker ID
    writer.write_u16(17); // Size
    writer.write_u8(1); // Type: LZRECEIVE
    writer.write_u128(100); // Gas

    // Add ordered execution option
    writer.write_u8(1); // Worker ID
    writer.write_u16(1); // Size (just type)
    writer.write_u8(4); // Type: ORDERED_EXECUTION

    let options = writer.to_bytes();
    let agg_options = executor_option::parse_executor_options(options, false, NATIVE_CAP);

    assert!(agg_options.total_gas() == 100, 0);
    assert!(agg_options.total_value() == 0, 1);
    assert!(agg_options.ordered(), 2); // Should be true now
    assert!(agg_options.num_lz_compose() == 0, 3);
}

#[test]
fun test_parse_multiple_options() {
    let options = create_multiple_options();
    let agg_options = executor_option::parse_executor_options(options, false, NATIVE_CAP);

    // Total gas: 100 (lz_receive) + 150 (lz_compose) = 250
    assert!(agg_options.total_gas() == 250, 0);
    // Total value: 200 (lz_receive) + 50 (native_drop) + 300 (lz_compose) = 550
    assert!(agg_options.total_value() == 550, 1);
    assert!(!agg_options.ordered(), 2);
    assert!(agg_options.num_lz_compose() == 1, 3);
}

#[test]
#[expected_failure(abort_code = 1, location = executor_option)]
fun test_parse_empty_options_should_fail() {
    let empty_options = vector<u8>[];
    executor_option::parse_executor_options(empty_options, false, NATIVE_CAP);
}

#[test]
#[expected_failure(abort_code = 3, location = executor_option)]
fun test_parse_zero_lz_receive_gas_should_fail() {
    let options = create_basic_executor_options(0, 0); // Zero gas
    executor_option::parse_executor_options(options, false, NATIVE_CAP);
}

#[test]
#[expected_failure(abort_code = 5, location = executor_option)]
fun test_parse_native_amount_exceeds_cap_should_fail() {
    let options = create_basic_executor_options(100, NATIVE_CAP + 1); // Exceeds cap
    executor_option::parse_executor_options(options, false, NATIVE_CAP);
}

#[test]
#[expected_failure(abort_code = 2, location = executor_option)]
fun test_v1_eid_with_lz_receive_value_should_fail() {
    let options = create_basic_executor_options(100, 200); // With value
    executor_option::parse_executor_options(options, true, NATIVE_CAP); // V1 EID
}

#[test]
#[expected_failure(abort_code = 2, location = executor_option)]
fun test_v1_eid_with_lz_compose_should_fail() {
    let mut writer = buffer_writer::new();

    // Add basic lz_receive option (required)
    writer.write_u8(1); // Worker ID
    writer.write_u16(17); // Size
    writer.write_u8(1); // Type: LZRECEIVE
    writer.write_u128(100); // Gas

    // Add lz_compose option (not supported in V1)
    writer.write_u8(1); // Worker ID
    writer.write_u16(19); // Size
    writer.write_u8(3); // Type: LZCOMPOSE
    writer.write_u16(0); // Index
    writer.write_u128(200); // Gas

    let options = writer.to_bytes();
    executor_option::parse_executor_options(options, true, NATIVE_CAP); // V1 EID
}

#[test]
#[expected_failure(abort_code = 4, location = executor_option)]
fun test_zero_lz_compose_gas_should_fail() {
    let mut writer = buffer_writer::new();

    // Add basic lz_receive option (required)
    writer.write_u8(1); // Worker ID
    writer.write_u16(17); // Size
    writer.write_u8(1); // Type: LZRECEIVE
    writer.write_u128(100); // Gas

    // Add lz_compose option with zero gas
    writer.write_u8(1); // Worker ID
    writer.write_u16(19); // Size
    writer.write_u8(3); // Type: LZCOMPOSE
    writer.write_u16(0); // Index
    writer.write_u128(0); // Zero gas - should fail

    let options = writer.to_bytes();
    executor_option::parse_executor_options(options, false, NATIVE_CAP);
}

#[test]
#[expected_failure(abort_code = 1, location = executor_fee_lib)]
fun test_zero_lz_receive_base_gas_should_fail() {
    let mut scenario = setup();

    init_executor_fee_lib_for_test(&mut scenario);

    scenario.next_tx(EXECUTOR);
    {
        let executor_fee_lib = ts::take_shared<ExecutorFeeLib>(&scenario);
        let options = create_basic_executor_options(100, 0);

        let param = executor_feelib_get_fee::create_param(
            SENDER,
            V2_EID,
            CALL_DATA_SIZE,
            options,
            PRICE_FEED,
            DEFAULT_MULTIPLIER_BPS,
            0, // Zero base gas - should fail
            BASE_LZ_COMPOSE_GAS,
            FLOOR_MARGIN_USD,
            NATIVE_CAP,
            0,
        );

        let mut call = call::create(
            executor_fee_lib.get_call_cap(),
            @0x0,
            false,
            param,
            scenario.ctx(),
        );

        // This should fail
        let price_feed_call = executor_fee_lib.get_fee(&mut call, scenario.ctx());

        // Clean up - these won't actually execute due to expected failure
        test_utils::destroy(price_feed_call);
        test_utils::destroy(call);
        ts::return_shared(executor_fee_lib);
    };

    clean(scenario);
}

#[test]
fun test_fee_calculation_components() {
    // Test the individual components that confirm_get_fee uses

    // Test basic parameter creation and validation
    let options = create_basic_executor_options(ADDITIONAL_GAS, 200);
    let param = executor_feelib_get_fee::create_param(
        SENDER,
        V2_EID,
        CALL_DATA_SIZE,
        options,
        PRICE_FEED,
        DEFAULT_MULTIPLIER_BPS,
        BASE_LZ_RECEIVE_GAS,
        BASE_LZ_COMPOSE_GAS,
        FLOOR_MARGIN_USD,
        NATIVE_CAP,
        0, // multiplier_bps (will use default)
    );

    // Verify parameter values
    assert!(param.dst_eid() == V2_EID, 0);
    assert!(param.default_multiplier_bps() == DEFAULT_MULTIPLIER_BPS, 1);
    assert!(param.floor_margin_usd() == FLOOR_MARGIN_USD, 2);
    assert!(param.native_cap() == NATIVE_CAP, 3);

    // Test that multiplier_bps defaults to default_multiplier_bps when 0
    let multiplier_bps = if (param.multiplier_bps() == 0) {
        param.default_multiplier_bps()
    } else {
        param.multiplier_bps()
    };
    assert!(multiplier_bps == DEFAULT_MULTIPLIER_BPS, 4);
}

#[test]
fun test_apply_premium_to_gas_uses_multiplier_if_gt_fee_with_margin() {
    let fee = executor_fee_lib::test_apply_premium_to_gas(
        20000,
        10500,
        1,
        1000000000, // Large price to make margin fee small
    );
    // fee_with_multiplier = 20000 * 10500 / 10000 = 21000
    // fee_with_margin = (1 * 1000000000 / 1000000000) + 20000 = 1 + 20000 = 20001
    // Returns max(21000, 20001) = 21000 (multiplier wins)
    assert!(fee == 21000, 0);
}

#[test]
fun test_apply_premium_to_gas_uses_margin_if_gt_fee_with_multiplier() {
    let fee = executor_fee_lib::test_apply_premium_to_gas(
        20000,
        10500,
        6000,
        2000,
    );
    // fee_with_multiplier = 20000 * 10500 / 10000 = 21000
    // fee_with_margin = (6000 * 1000000000 / 2000) + 20000 = 3000000000 + 20000 = 3000020000
    // Returns max(21000, 3000020000) = 3000020000
    assert!(fee == 3000020000, 0);
}

#[test]
fun test_apply_premium_to_gas_uses_margin_if_native_price_used_is_0() {
    let fee = executor_fee_lib::test_apply_premium_to_gas(
        20000,
        10500,
        6000,
        0,
    );
    assert!(fee == 21000, 0); // 20000 * 10500 / 10000;
}

#[test]
fun test_apply_premium_to_gas_uses_multiplier_if_margin_usd_is_0() {
    let fee = executor_fee_lib::test_apply_premium_to_gas(
        20000,
        10500,
        0,
        1,
    );
    assert!(fee == 21000, 0); // 20000 * 10500 / 10000
}

#[test]
fun test_convert_and_apply_premium_to_value() {
    let fee = executor_fee_lib::test_convert_and_apply_premium_to_value(
        9512000,
        123,
        1_000,
        600, // 6%
    );
    assert!(fee == 70198, 0); // (((9512000*123)/1000) * 600) / 10000;
}

#[test]
fun test_convert_and_apply_premium_to_value_returns_0_if_value_is_0() {
    let fee = executor_fee_lib::test_convert_and_apply_premium_to_value(
        0,
        112312323,
        1,
        1000, // 10%
    );
    assert!(fee == 0, 0);
}

// === Test Helper Functions ===

// Helper function to setup test scenario
fun setup(): ts::Scenario {
    ts::begin(EXECUTOR)
}

// Helper function to clean up test scenario
fun clean(scenario: ts::Scenario) {
    ts::end(scenario);
}

// Helper function to initialize the executor fee lib for testing
fun init_executor_fee_lib_for_test(scenario: &mut ts::Scenario) {
    scenario.next_tx(EXECUTOR);
    {
        executor_fee_lib::init_for_test(scenario.ctx());
    };
}

// Helper function to create basic executor options with lz_receive
fun create_basic_executor_options(gas: u128, value: u128): vector<u8> {
    let mut writer = buffer_writer::new();
    // Worker ID (1 byte)
    writer.write_u8(1);
    // Option size (2 bytes) - 1 (type) + 16 (gas) + 16 (value) = 33
    writer.write_u16(33);
    // Option type: LZRECEIVE (1 byte)
    writer.write_u8(1);
    // Gas (16 bytes)
    writer.write_u128(gas);
    // Value (16 bytes)
    writer.write_u128(value);
    writer.to_bytes()
}

// Helper function to create multiple options
fun create_multiple_options(): vector<u8> {
    let mut writer = buffer_writer::new();

    // First option: LZ_RECEIVE
    writer.write_u8(1); // Worker ID
    writer.write_u16(33); // Size
    writer.write_u8(1); // Type: LZRECEIVE
    writer.write_u128(100); // Gas
    writer.write_u128(200); // Value

    // Second option: NATIVE_DROP
    writer.write_u8(1); // Worker ID
    writer.write_u16(49); // Size
    writer.write_u8(2); // Type: NATIVE_DROP
    writer.write_u128(50); // Amount
    writer.write_bytes32(bytes32::from_address(@0x1234)); // Receiver

    // Third option: LZ_COMPOSE
    writer.write_u8(1); // Worker ID
    writer.write_u16(35); // Size
    writer.write_u8(3); // Type: LZCOMPOSE
    writer.write_u16(0); // Index
    writer.write_u128(150); // Gas
    writer.write_u128(300); // Value

    writer.to_bytes()
}
