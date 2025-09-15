#[test_only]
module dvn_fee_lib::dvn_fee_lib_tests;

use call::call;
use dvn_call_type::dvn_feelib_get_fee;
use dvn_fee_lib::dvn_fee_lib::{Self, DvnFeeLib};
use sui::{test_scenario as ts, test_utils};

// === Test Constants ===

const DVN: address = @0x1111;
const PRICE_FEED: address = @0x2222;
const SENDER: address = @0x3333;

// EID constants
const V2_EID: u32 = 30001; // >= 30000

// Gas constants
const DEFAULT_GAS: u256 = 100000;

// Fee constants
const DEFAULT_MULTIPLIER_BPS: u16 = 10500; // 5% premium (105%)
const FLOOR_MARGIN_USD: u128 = 100;
const CONFIRMATIONS: u64 = 15;
const QUORUM: u64 = 3;

// === Tests ===

#[test]
fun test_init() {
    let mut scenario = setup();

    init_dvn_fee_lib_for_test(&mut scenario);

    scenario.next_tx(DVN);
    {
        let dvn_fee_lib = ts::take_shared<DvnFeeLib>(&scenario);
        // Verify the fee lib was created successfully
        let _call_cap = dvn_fee_lib::get_call_cap(&dvn_fee_lib);
        ts::return_shared(dvn_fee_lib);
    };

    clean(scenario);
}

#[test]
fun test_get_fee_basic() {
    let mut scenario = setup();

    init_dvn_fee_lib_for_test(&mut scenario);

    scenario.next_tx(DVN);
    {
        let dvn_fee_lib = ts::take_shared<DvnFeeLib>(&scenario);

        // Create fee lib parameter
        let param = dvn_feelib_get_fee::create_param(
            SENDER,
            V2_EID,
            CONFIRMATIONS,
            vector::empty<u8>(), // empty options
            QUORUM,
            PRICE_FEED,
            DEFAULT_MULTIPLIER_BPS,
            DEFAULT_GAS,
            0, // multiplier_bps (will use default)
            FLOOR_MARGIN_USD,
        );

        // Create call
        let mut call = call::create(
            dvn_fee_lib.get_call_cap(),
            @0x0, // callee
            false, // one_way
            param,
            scenario.ctx(),
        );

        // Get fee estimate - this creates a child call to the price feed
        let price_feed_call = dvn_fee_lib.get_fee(&mut call, scenario.ctx());

        // Verify the price feed call was created and the parent call is waiting
        assert!(call.status().is_waiting(), 0);
        assert!(price_feed_call.callee() == PRICE_FEED, 1);

        // Clean up - destroy the child call and parent call
        test_utils::destroy(price_feed_call);
        test_utils::destroy(call);
        ts::return_shared(dvn_fee_lib);
    };

    clean(scenario);
}

#[test]
fun test_fee_calculation_components() {
    // Test the individual components that confirm_get_fee uses

    // Test basic parameter creation and validation
    let param = dvn_feelib_get_fee::create_param(
        SENDER,
        V2_EID,
        CONFIRMATIONS,
        vector::empty<u8>(),
        QUORUM,
        PRICE_FEED,
        DEFAULT_MULTIPLIER_BPS,
        DEFAULT_GAS,
        0, // multiplier_bps (will use default)
        FLOOR_MARGIN_USD,
    );

    // Verify parameter values
    assert!(param.dst_eid() == V2_EID, 0);
    assert!(param.confirmations() == CONFIRMATIONS, 1);
    assert!(param.quorum() == QUORUM, 2);
    assert!(param.default_multiplier_bps() == DEFAULT_MULTIPLIER_BPS, 3);
    assert!(param.floor_margin_usd() == FLOOR_MARGIN_USD, 4);
    assert!(param.options().is_empty(), 5);

    // Test that multiplier_bps defaults to default_multiplier_bps when 0
    let multiplier_bps = if (param.multiplier_bps() == 0) {
        param.default_multiplier_bps()
    } else {
        param.multiplier_bps()
    };
    assert!(multiplier_bps == DEFAULT_MULTIPLIER_BPS, 6);
}

#[test]
fun test_apply_premium_uses_multiplier_when_gt_margin() {
    let fee = dvn_fee_lib::test_apply_premium(
        20000,
        10500,
        10000,
        1,
        1000000000, // Large price to make margin fee small
    );
    // fee_with_multiplier = 20000 * 10500 / 10000 = 21000
    // fee_with_margin = (1 * 1000000000 / 1000000000) + 20000 = 1 + 20000 = 20001
    // Returns max(21000, 20001) = 21000 (multiplier wins)
    assert!(fee == 21000, 0);
}

#[test]
fun test_apply_premium_uses_margin_when_gt_multiplier() {
    let fee = dvn_fee_lib::test_apply_premium(
        20000,
        10500,
        10000,
        6000,
        2000,
    );
    // fee_with_multiplier = 20000 * 10500 / 10000 = 21000
    // fee_with_margin = (6000 * 1000000000 / 2000) + 20000 = 3000000000 + 20000 = 3000020000
    // Returns max(21000, 3000020000) = 3000020000 (margin wins)
    assert!(fee == 3000020000, 0);
}

#[test]
fun test_apply_premium_uses_multiplier_when_native_price_is_0() {
    let fee = dvn_fee_lib::test_apply_premium(
        20000,
        10500,
        10000,
        6000,
        0, // native_price_usd = 0
    );
    // When native_price_usd = 0, should fall back to multiplier
    assert!(fee == 21000, 0); // 20000 * 10500 / 10000
}

#[test]
fun test_apply_premium_uses_multiplier_when_margin_is_0() {
    let fee = dvn_fee_lib::test_apply_premium(
        20000,
        10500,
        10000,
        0, // floor_margin_usd = 0
        1,
    );
    // When floor_margin_usd = 0, should fall back to multiplier
    assert!(fee == 21000, 0); // 20000 * 10500 / 10000
}

#[test]
fun test_apply_premium_uses_default_multiplier_when_zero() {
    let fee = dvn_fee_lib::test_apply_premium(
        20000,
        0, // multiplier_bps = 0, should use default
        10500,
        0,
        1,
    );
    // Should use default_multiplier_bps = 10500
    assert!(fee == 21000, 0); // 20000 * 10500 / 10000
}

#[test]
#[expected_failure(abort_code = dvn_fee_lib::EEidNotSupported)]
fun test_get_fee_zero_gas_should_fail() {
    let mut scenario = setup();

    init_dvn_fee_lib_for_test(&mut scenario);

    scenario.next_tx(DVN);
    {
        let dvn_fee_lib = ts::take_shared<DvnFeeLib>(&scenario);

        let param = dvn_feelib_get_fee::create_param(
            SENDER,
            V2_EID,
            CONFIRMATIONS,
            vector::empty<u8>(),
            QUORUM,
            PRICE_FEED,
            DEFAULT_MULTIPLIER_BPS,
            0, // Zero gas - should fail
            0,
            FLOOR_MARGIN_USD,
        );

        let mut call = call::create(
            dvn_fee_lib.get_call_cap(),
            @0x0,
            false,
            param,
            scenario.ctx(),
        );

        // This should fail
        let price_feed_call = dvn_fee_lib.get_fee(&mut call, scenario.ctx());

        // Clean up - these won't actually execute due to expected failure
        test_utils::destroy(price_feed_call);
        test_utils::destroy(call);
        ts::return_shared(dvn_fee_lib);
    };

    clean(scenario);
}

// === Test Helper Functions ===

// Helper function to setup test scenario
fun setup(): ts::Scenario {
    ts::begin(DVN)
}

// Helper function to clean up test scenario
fun clean(scenario: ts::Scenario) {
    ts::end(scenario);
}

// Helper function to initialize the dvn fee lib for testing
fun init_dvn_fee_lib_for_test(scenario: &mut ts::Scenario) {
    scenario.next_tx(DVN);
    {
        dvn_fee_lib::init_for_test(scenario.ctx());
    };
}
