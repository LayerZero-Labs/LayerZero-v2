#[test_only]
module counter::counter_with_sml_test;

use counter::{
    counter::Counter,
    counter_test_helper,
    deployments::{Self, Deployments},
    scenario_utils,
    test_helper_with_sml
};
use endpoint_v2::{
    endpoint_v2::EndpointV2,
    messaging_channel::{Self, MessagingChannel, PacketSentEvent},
    messaging_composer::ComposeSentEvent,
    messaging_fee::MessagingFee
};
use oapp::oapp::OApp;
use simple_message_lib::simple_message_lib::SimpleMessageLib;
use sui::{clock::{Self, Clock}, coin::{Self, Coin}, event, sui::SUI, test_scenario::{Self, Scenario}, test_utils};
use zro::zro::ZRO;

// === Test Constants ===

const SENDER: address = @0xb0b;
const SRC_EID: u32 = 1;
const DST_EID: u32 = 2;

// Message types
const VANILLA_TYPE: u8 = 1;
const COMPOSE_TYPE: u8 = 2;

// Expected fees
const EXPECTED_NATIVE_FEE: u64 = 100;
const EXPECTED_ZRO_FEE: u64 = 99;

// === Error Codes ===

const E_INVALID_NATIVE_FEE: u64 = 0;
const E_INVALID_ZRO_FEE: u64 = 1;
const E_INVALID_OUTBOUND_COUNT: u64 = 2;
const E_INVALID_INBOUND_COUNT: u64 = 3;
const E_INVALID_COUNT: u64 = 4;
const E_INVALID_COMPOSED_COUNT_AFTER: u64 = 6;

// === Tests ===

#[test]
fun test_quote() {
    let (mut scenario, test_clock, deployments) = setup_test_environment(SENDER, vector[SRC_EID, DST_EID]);

    let options = vector::empty<u8>();

    // Test vanilla message quote
    scenario.next_tx(SENDER);
    let vanilla_messaging_fee = quote(&mut scenario, &deployments, SRC_EID, DST_EID, VANILLA_TYPE, options, true);

    // Verify vanilla message fees
    assert!(vanilla_messaging_fee.native_fee() == EXPECTED_NATIVE_FEE, E_INVALID_NATIVE_FEE);
    assert!(vanilla_messaging_fee.zro_fee() == EXPECTED_ZRO_FEE, E_INVALID_ZRO_FEE);

    // Test compose message quote
    scenario.next_tx(SENDER);
    let compose_messaging_fee = quote(&mut scenario, &deployments, SRC_EID, DST_EID, COMPOSE_TYPE, options, true);

    // Verify compose message fees
    assert!(compose_messaging_fee.native_fee() == EXPECTED_NATIVE_FEE, E_INVALID_NATIVE_FEE);
    assert!(compose_messaging_fee.zro_fee() == EXPECTED_ZRO_FEE, E_INVALID_ZRO_FEE);

    clean(scenario, test_clock, deployments);
}

#[test]
fun test_counter_vanilla() {
    let (mut scenario, test_clock, deployments) = setup_test_environment(SENDER, vector[SRC_EID, DST_EID]);

    // Get messaging fee
    scenario.next_tx(SENDER);
    let options = vector::empty<u8>();
    let messaging_fee = quote(&mut scenario, &deployments, SRC_EID, DST_EID, VANILLA_TYPE, options, true);

    // Create fee coins
    let native_fee_coin = coin::mint_for_testing<SUI>(messaging_fee.native_fee(), test_scenario::ctx(&mut scenario));
    let zro_fee_coin = option::some(
        coin::mint_for_testing<ZRO>(messaging_fee.zro_fee(), test_scenario::ctx(&mut scenario)),
    );

    // Send message
    send_message(&mut scenario, SENDER, &deployments, SRC_EID, DST_EID, VANILLA_TYPE, native_fee_coin, zro_fee_coin);

    // verify message
    let encoded_packet = verify_message(&mut scenario, &test_clock, SENDER, &deployments, DST_EID);

    // Handle message receive
    handle_message_receive(&mut scenario, SENDER, &deployments, DST_EID, encoded_packet);

    // Verify state
    assert_counter_state(&mut scenario, SENDER, &deployments, SRC_EID, DST_EID, 1, 1, 1);

    clean(scenario, test_clock, deployments);
}

#[test]
fun test_counter_compose() {
    let (mut scenario, test_clock, deployments) = setup_test_environment(SENDER, vector[SRC_EID, DST_EID]);

    // Get messaging fee
    scenario.next_tx(SENDER);
    let options = vector::empty<u8>();
    let messaging_fee = quote(&mut scenario, &deployments, SRC_EID, DST_EID, COMPOSE_TYPE, options, true);

    // Create fee coins
    let native_fee_coin = coin::mint_for_testing<SUI>(messaging_fee.native_fee(), test_scenario::ctx(&mut scenario));
    let zro_fee_coin = option::some(
        coin::mint_for_testing<ZRO>(messaging_fee.zro_fee(), test_scenario::ctx(&mut scenario)),
    );

    // Send message
    send_message(&mut scenario, SENDER, &deployments, SRC_EID, DST_EID, COMPOSE_TYPE, native_fee_coin, zro_fee_coin);

    // verify message
    let encoded_packet = verify_message(&mut scenario, &test_clock, SENDER, &deployments, DST_EID);

    // Handle message receive
    handle_message_receive(&mut scenario, SENDER, &deployments, DST_EID, encoded_packet);
    let compose_sent_event = event::events_by_type<ComposeSentEvent>()[0];

    // Verify basic state
    assert_counter_state(&mut scenario, SENDER, &deployments, SRC_EID, DST_EID, 1, 1, 1);

    // Verify compose count (before execution)
    assert_compose_count(&mut scenario, SENDER, &deployments, DST_EID, 0);

    // Execute compose operation
    let compose_value = coin::zero<SUI>(test_scenario::ctx(&mut scenario));

    counter_test_helper::lz_compose(&mut scenario, SENDER, &deployments, DST_EID, compose_sent_event, compose_value);

    // Verify compose count (after execution)
    assert_compose_count(&mut scenario, SENDER, &deployments, DST_EID, 1);

    clean(scenario, test_clock, deployments);
}

// === Helper Functions ===

/// Initialize complete test environment with scenario and clock
/// Returns: (scenario, test_clock, deployments)
fun setup_test_environment(sender: address, eids: vector<u32>): (Scenario, Clock, Deployments) {
    let mut scenario = test_scenario::begin(sender);
    let test_clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let mut deployments = deployments::new(test_scenario::ctx(&mut scenario));

    test_helper_with_sml::setup_endpoint_with_sml(&mut scenario, sender, eids, &mut deployments, &test_clock);

    counter_test_helper::setup_counter(&mut scenario, sender, eids, &mut deployments);

    (scenario, test_clock, deployments)
}

/// Clean up test resources
fun clean(scenario: Scenario, clock: Clock, deployments: Deployments) {
    test_scenario::end(scenario);
    clock::destroy_for_testing(clock);
    test_utils::destroy(deployments);
}

/// Get messaging fee quote
fun quote(
    scenario: &mut Scenario,
    deployments: &Deployments,
    src_eid: u32,
    dst_eid: u32,
    msg_type: u8,
    options: vector<u8>,
    pay_in_zro: bool,
): MessagingFee {
    let counter = scenario_utils::take_shared_by_address<Counter>(
        scenario,
        deployments.get_deployment<Counter>(src_eid),
    );
    let endpoint = scenario_utils::take_shared_by_address<EndpointV2>(
        scenario,
        deployments.get_deployment<EndpointV2>(src_eid),
    );
    let sml = scenario_utils::take_shared_by_address<SimpleMessageLib>(
        scenario,
        deployments.get_deployment<SimpleMessageLib>(src_eid),
    );
    let messaging_channel = scenario_utils::take_shared_by_address<MessagingChannel>(
        scenario,
        deployments.get_deployment<MessagingChannel>(src_eid),
    );
    let oapp = scenario_utils::take_shared_by_address<OApp>(
        scenario,
        deployments.get_deployment<OApp>(src_eid),
    );

    // Step 1: Counter creates quote call
    let mut quote_call = counter.quote(
        &oapp,
        dst_eid,
        msg_type,
        options,
        pay_in_zro,
        scenario.ctx(),
    );

    // Steps 2 & 3: Use helper function to process endpoint.quote -> SML.quote
    test_helper_with_sml::quote(&endpoint, &sml, &messaging_channel, &mut quote_call, scenario.ctx());

    let result = *quote_call.result();
    let messaging_fee = result.destroy_some();

    // Step 4: Clean up quote call
    test_utils::destroy(quote_call);

    // Clean up resources
    test_scenario::return_shared<Counter>(counter);
    test_scenario::return_shared<OApp>(oapp);
    test_scenario::return_shared<EndpointV2>(endpoint);
    test_scenario::return_shared<SimpleMessageLib>(sml);
    test_scenario::return_shared<MessagingChannel>(messaging_channel);

    messaging_fee
}

/// Send message and return encoded packet
fun send_message(
    scenario: &mut Scenario,
    sender: address,
    deployments: &Deployments,
    src_eid: u32,
    dst_eid: u32,
    msg_type: u8,
    native_fee_coin: Coin<SUI>,
    zro_fee_coin: Option<Coin<ZRO>>,
) {
    let options = vector::empty<u8>();

    // Send message
    let send_call = counter_test_helper::increment(
        scenario,
        sender,
        sender,
        deployments,
        src_eid,
        dst_eid,
        msg_type,
        options,
        native_fee_coin,
        zro_fee_coin,
    );

    test_helper_with_sml::execute_send_call(scenario, sender, deployments, src_eid, send_call)
}

/// Verify message and return packet
fun verify_message(
    scenario: &mut Scenario,
    test_clock: &Clock,
    sender: address,
    deployments: &Deployments,
    dst_eid: u32,
): vector<u8> {
    // Get and verify message packet
    let packet_sent_event = event::events_by_type<PacketSentEvent>()[0];
    let encoded_packet = messaging_channel::get_encoded_packet_from_packet_sent_event(&packet_sent_event);

    test_helper_with_sml::verify_message(scenario, sender, encoded_packet, deployments, dst_eid, test_clock);

    encoded_packet
}

/// Handle message receive
fun handle_message_receive(
    scenario: &mut Scenario,
    sender: address,
    deployments: &Deployments,
    dst_eid: u32,
    encoded_packet: vector<u8>,
) {
    let value = coin::zero<SUI>(test_scenario::ctx(scenario));
    counter_test_helper::lz_receive(scenario, sender, deployments, dst_eid, encoded_packet, value);
}

/// Verify counter state with flexible expected values
fun assert_counter_state(
    scenario: &mut Scenario,
    sender: address,
    deployments: &Deployments,
    src_eid: u32,
    dst_eid: u32,
    expected_count: u64,
    expected_outbound_count: u64,
    expected_inbound_count: u64,
) {
    scenario.next_tx(sender);
    let counter_src = scenario_utils::take_shared_by_address<Counter>(
        scenario,
        deployments.get_deployment<Counter>(src_eid),
    );
    let counter_dst = scenario_utils::take_shared_by_address<Counter>(
        scenario,
        deployments.get_deployment<Counter>(dst_eid),
    );

    // Verify state
    assert!(counter_src.get_outbound_count(dst_eid) == expected_outbound_count, E_INVALID_OUTBOUND_COUNT);
    assert!(counter_dst.get_inbound_count(src_eid) == expected_inbound_count, E_INVALID_INBOUND_COUNT);
    assert!(counter_dst.get_count() == expected_count, E_INVALID_COUNT);

    test_scenario::return_shared<Counter>(counter_src);
    test_scenario::return_shared<Counter>(counter_dst);
}

/// Verify compose count with flexible expected value
fun assert_compose_count(
    scenario: &mut Scenario,
    sender: address,
    deployments: &Deployments,
    dst_eid: u32,
    expected_compose_count: u64,
) {
    scenario.next_tx(sender);
    let counter_dst = scenario_utils::take_shared_by_address<Counter>(
        scenario,
        deployments.get_deployment<Counter>(dst_eid),
    );
    assert!(counter_dst.get_composed_count() == expected_compose_count, E_INVALID_COMPOSED_COUNT_AFTER);
    test_scenario::return_shared<Counter>(counter_dst);
}
