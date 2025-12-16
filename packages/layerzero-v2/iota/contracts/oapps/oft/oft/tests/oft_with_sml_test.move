#[test_only]
module oft::oft_with_sml_test;

use endpoint_v2::messaging_channel::{PacketSentEvent, get_encoded_packet_from_packet_sent_event};
use oft::{
    deployments::{Self, Deployments},
    oft::OFT,
    oft_test_helper,
    scenario_utils,
    test_coin::TEST_COIN,
    test_helper_with_sml
};
use iota::{clock::{Self, Clock}, coin, event, iota::IOTA, test_scenario::{Self, Scenario}, test_utils};

// === Test Constants ===

const SENDER: address = @0xb0b;
const RECIPIENT: address = @0xa11ce;
const SRC_EID: u32 = 1;
const DST_EID: u32 = 2;

// Test amounts
const SEND_AMOUNT: u64 = 1000000000000000000; // 1 token (18 decimals)

// === Error Codes ===

const E_EVENT_NOT_CREATED: u64 = 1;
const E_INVALID_BALANCE: u64 = 2;
const E_INVALID_VERSION: u64 = 3;
const E_INVALID_DST_EID: u64 = 4;
const E_INVALID_SENDER: u64 = 5;
const E_INVALID_RECIPIENT_BALANCE: u64 = 6;

// === Tests ===

#[test]
fun test_oft_send_vanilla() {
    let (mut scenario, test_clock, deployments) = setup_test_environment(SENDER, vector[SRC_EID, DST_EID]);

    // Verify OFT setup completed successfully
    scenario.next_tx(SENDER);
    let oft = scenario_utils::take_shared_by_address<OFT<TEST_COIN>>(
        &mut scenario,
        deployments.get_deployment<OFT<TEST_COIN>>(SRC_EID),
    );

    // Verify OFT version
    let (version_hash, version_number) = oft.oft_version();
    assert!(version_hash == 1 && version_number == 1, E_INVALID_VERSION);

    test_scenario::return_shared<OFT<TEST_COIN>>(oft);

    // Execute real OFT send operation
    let native_fee = iota::coin::mint_for_testing<iota::iota::IOTA>(1000000, scenario.ctx()); // 0.001 IOTA
    let (oft_sender, send_call, oft_receipt_with_sender) = oft_test_helper::send(
        &mut scenario,
        SENDER,
        RECIPIENT,
        SENDER,
        &deployments,
        SRC_EID,
        DST_EID,
        SEND_AMOUNT,
        native_fee,
        option::none<iota::coin::Coin<zro::zro::ZRO>>(),
        vector::empty<u8>(),
        false,
    );

    // Execute the send call through the SML to complete the message sending
    test_helper_with_sml::execute_send_call<TEST_COIN>(
        &mut scenario,
        oft_sender,
        oft_receipt_with_sender,
        &deployments,
        SRC_EID,
        send_call,
    );

    // Verify the OFT event was created after the send call completes (after SML execution)
    let oft_sent_events = event::events_by_type<oft::oft::OFTSentEvent>();
    assert!(oft_sent_events.length() > 0, E_EVENT_NOT_CREATED);

    let oft_sent_event = &oft_sent_events[0];
    let (_guid, dst_eid, from_address, amount_sent_ld, _amount_received_ld) = oft::oft::destruct_oft_sent_event(
        *oft_sent_event,
    );

    // Verify OFT event data
    assert!(dst_eid == DST_EID, E_INVALID_DST_EID);
    assert!(from_address == SENDER, E_INVALID_SENDER);
    assert!(amount_sent_ld == SEND_AMOUNT, E_INVALID_BALANCE);

    // Get PacketSentEvent and extract encoded packet (must do this before next_tx calls)
    let packet_sent_events = event::events_by_type<PacketSentEvent>();
    assert!(packet_sent_events.length() > 0, E_EVENT_NOT_CREATED);
    let packet_sent_event = packet_sent_events[0];
    let encoded_packet = get_encoded_packet_from_packet_sent_event(&packet_sent_event);

    // Get initial recipient balance (should be 0)
    let recipient_initial_balance = get_test_coin_balance<TEST_COIN>(&mut scenario, RECIPIENT);

    // Verify the message
    verify_message(&mut scenario, &test_clock, SENDER, &deployments, DST_EID, encoded_packet);

    // Handle message receive (this will trigger lz_receive on destination)
    handle_message_receive(&mut scenario, SENDER, &deployments, DST_EID, encoded_packet, false);

    // Check recipient received the expected amount
    let recipient_final_balance = get_test_coin_balance<TEST_COIN>(&mut scenario, RECIPIENT);
    assert!(recipient_final_balance == recipient_initial_balance + SEND_AMOUNT, E_INVALID_RECIPIENT_BALANCE);

    clean(scenario, test_clock, deployments);
}

#[test]
#[expected_failure(abort_code = oft::oft::EComposeMsgRequired)]
fun test_oft_lz_receive_compose_without_compose_msg() {
    let (mut scenario, test_clock, deployments) = setup_test_environment(SENDER, vector[SRC_EID, DST_EID]);
    let encoded_packet = oft_test_helper::create_inbound_packet(
        &mut scenario,
        &deployments,
        SENDER,
        SRC_EID,
        DST_EID,
        SEND_AMOUNT,
        vector::empty<u8>(),
    );

    // try trigger lz_receive but apparently it will fail
    verify_message(&mut scenario, &test_clock, SENDER, &deployments, DST_EID, encoded_packet);
    handle_message_receive(&mut scenario, SENDER, &deployments, DST_EID, encoded_packet, true);

    clean(scenario, test_clock, deployments);
}

#[test]
#[expected_failure(abort_code = oft::oft::EComposeMsgNotAllowed)]
fun test_oft_lz_receive_with_compose_msg() {
    let (mut scenario, test_clock, deployments) = setup_test_environment(SENDER, vector[SRC_EID, DST_EID]);
    let encoded_packet = oft_test_helper::create_inbound_packet(
        &mut scenario,
        &deployments,
        SENDER,
        SRC_EID,
        DST_EID,
        SEND_AMOUNT,
        b"compose msg",
    );

    // try trigger lz_receive but apparently it will fail
    verify_message(&mut scenario, &test_clock, SENDER, &deployments, DST_EID, encoded_packet);
    handle_message_receive(&mut scenario, SENDER, &deployments, DST_EID, encoded_packet, false);

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

    oft_test_helper::setup_oft(&mut scenario, sender, eids, &mut deployments);

    (scenario, test_clock, deployments)
}

/// Verify message using provided encoded packet
fun verify_message(
    scenario: &mut Scenario,
    test_clock: &Clock,
    sender: address,
    deployments: &Deployments,
    dst_eid: u32,
    encoded_packet: vector<u8>,
) {
    test_helper_with_sml::verify_message(scenario, sender, encoded_packet, deployments, dst_eid, test_clock);
}

/// Handle message receive
fun handle_message_receive(
    scenario: &mut Scenario,
    sender: address,
    deployments: &Deployments,
    dst_eid: u32,
    encoded_packet: vector<u8>,
    with_compose: bool,
) {
    let value = coin::zero<IOTA>(test_scenario::ctx(scenario));
    oft_test_helper::lz_receive(scenario, sender, deployments, dst_eid, encoded_packet, value, with_compose);
}

/// Get TEST_COIN balance for an address
fun get_test_coin_balance<T>(scenario: &mut Scenario, addr: address): u64 {
    scenario.next_tx(addr);
    // Get all TEST_COIN coin IDs for the address
    let coin_ids = test_scenario::ids_for_address<coin::Coin<T>>(addr);
    let mut total_balance = 0u64;

    // Iterate through all coins and sum their values
    let mut i = 0;
    while (i < coin_ids.length()) {
        let coin_id = coin_ids[i];
        let coin = test_scenario::take_from_address_by_id<coin::Coin<T>>(scenario, addr, coin_id);
        total_balance = total_balance + coin.value();
        test_scenario::return_to_address(addr, coin);
        i = i + 1;
    };

    total_balance
}

/// Clean up test resources
fun clean(scenario: Scenario, clock: Clock, deployments: Deployments) {
    test_scenario::end(scenario);
    clock::destroy_for_testing(clock);
    test_utils::destroy(deployments);
}
