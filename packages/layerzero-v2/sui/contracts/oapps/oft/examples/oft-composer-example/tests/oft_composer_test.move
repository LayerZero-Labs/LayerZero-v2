#[test_only]
module oft_composer_example::oft_composer_test;

use call::call_cap;
use endpoint_v2::{
    endpoint_v2::EndpointV2,
    messaging_channel::{PacketSentEvent, get_encoded_packet_from_packet_sent_event},
    messaging_composer::{ComposeSentEvent, ComposeQueue}
};
use oapp::oapp;
use oft::{deployments::{Self, Deployments}, oft::OFT, oft_test_helper, test_coin::TEST_COIN, test_helper_with_sml};
use oft_common::{compose_transfer::ComposeTransfer, oft_composer_manager::OFTComposerManager};
use oft_composer_example::{custom_compose_codec, oft_composer::{Self, OFTComposer}};
use sui::{clock::{Self, Clock}, coin, event, sui::SUI, test_scenario::{Self, Scenario}, test_utils};

// === Test Constants ===

const SENDER: address = @0xb0b;
const RECIPIENT: address = @0xa11ce;
const SRC_EID: u32 = 1;
const DST_EID: u32 = 2;

// Test amounts
const SEND_AMOUNT: u64 = 1000000000000000000; // 1 token (18 decimals)

// === Error Codes ===

const E_EVENT_NOT_CREATED: u64 = 1;
const E_INVALID_RECIPIENT_BALANCE: u64 = 2; // Reserved for future balance verification

// === Tests ===

#[test]
fun test_oft_compose() {
    let (mut scenario, test_clock, deployments) = setup_test_environment(SENDER, vector[SRC_EID, DST_EID]);

    scenario.next_tx(SENDER);
    let target_composer = deployments.take_shared_object<OFTComposer>(&mut scenario, DST_EID);
    let composer_address = target_composer.composer_cap().id();
    test_scenario::return_shared(target_composer);

    // Get initial recipient balance (should be 0)
    let recipient_initial_balance = get_test_coin_balance(&mut scenario, RECIPIENT);

    // Create compose message containing the recipient address
    let compose_msg = custom_compose_codec::encode(RECIPIENT);

    // Send OFT message with compose functionality
    send_message_with_compose(
        &mut scenario,
        SENDER,
        composer_address,
        &deployments,
        SRC_EID,
        DST_EID,
        SEND_AMOUNT,
        compose_msg,
    );

    // Verify the message and get the encoded packet
    let encoded_packet = verify_message(&mut scenario, &test_clock, SENDER, &deployments, DST_EID);

    // Handle message receive (this will trigger compose)
    handle_message_receive(&mut scenario, SENDER, &deployments, DST_EID, encoded_packet);

    // Get the ComposeSentEvent that was triggered
    let compose_sent_events = event::events_by_type<ComposeSentEvent>();
    assert!(compose_sent_events.length() > 0, E_EVENT_NOT_CREATED);
    let compose_sent_event = compose_sent_events[0];

    // Execute the compose operation using OFTComposer
    execute_compose(&mut scenario, SENDER, &deployments, DST_EID, compose_sent_event);

    let recipient_final_balance = get_test_coin_balance(&mut scenario, RECIPIENT);
    assert!(recipient_final_balance == recipient_initial_balance + SEND_AMOUNT, E_INVALID_RECIPIENT_BALANCE);

    clean(scenario, test_clock, deployments);
}

// === Helper Functions ===

/// Initialize complete test environment with scenario and clock
/// Returns: (scenario, test_clock, deployments)
fun setup_test_environment(sender: address, eids: vector<u32>): (Scenario, Clock, Deployments) {
    let mut scenario = test_scenario::begin(sender);
    let test_clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let mut deployments = deployments::new(test_scenario::ctx(&mut scenario));

    // Setup endpoint and SML
    test_helper_with_sml::setup_endpoint_with_sml(&mut scenario, sender, eids, &mut deployments, &test_clock);

    // Setup OFT
    oft_test_helper::setup_oft(&mut scenario, sender, eids, &mut deployments);

    // Setup OFT Composer
    setup_composer(&mut scenario, sender, eids, &mut deployments);

    // Configure OFT to use the composer
    configure_oft_composer(&mut scenario, sender, &mut deployments, eids);

    (scenario, test_clock, deployments)
}

public fun setup_composer(scenario: &mut Scenario, sender: address, eids: vector<u32>, deployments: &mut Deployments) {
    // Deploy one OFTComposer per EID (simulating separate deployments on different chains)
    eids.do!(|eid| {
        scenario.next_tx(sender);

        // Initialize a new OFTComposer instance for this EID
        oft_composer::init_for_testing(scenario.ctx());

        // Get the created OFTComposer and store it in deployments for this specific EID
        scenario.next_tx(sender);
        let oft_composer = scenario.take_shared<OFTComposer>();
        let admin_cap = test_scenario::take_from_sender<oft_composer_example::oft_composer::AdminCap>(scenario);

        deployments.set_deployment<OFTComposer>(eid, object::id_address(&oft_composer));
        deployments.set_deployment<oft_composer_example::oft_composer::AdminCap>(eid, object::id_address(&admin_cap));

        // Return the composer back to shared state
        test_scenario::return_shared(oft_composer);
        scenario.return_to_sender<oft_composer_example::oft_composer::AdminCap>(admin_cap);
    });
}

/// Configure OFT to use the composer for compose messages
fun configure_oft_composer(scenario: &mut Scenario, sender: address, deployments: &mut Deployments, eids: vector<u32>) {
    eids.do!(|eid| {
        scenario.next_tx(sender);
        let oft = deployments.take_shared_object<OFT<TEST_COIN>>(scenario, eid);
        let admin_cap = deployments.take_owned_object<oapp::AdminCap>(scenario, eid);
        let mut endpoint = deployments.take_shared_object<EndpointV2>(scenario, eid);
        let mut oft_composer = deployments.take_shared_object<OFTComposer>(scenario, eid);
        let mut composer_registry = deployments.take_shared_object<OFTComposerManager>(scenario, eid);
        let composer_admin_cap = deployments.take_owned_object<oft_composer_example::oft_composer::AdminCap>(
            scenario,
            eid,
        );

        // Register the composer with the endpoint to create ComposeQueue
        let lz_compose_info = b"oft_composer_lz_compose_info"; // Simple mock info for testing
        oft_composer.register_composer_for_test(&composer_admin_cap, &mut endpoint, lz_compose_info, scenario.ctx());

        // Register the composer's deposit address to the composer object
        composer_registry.set_deposit_address(oft_composer.composer_cap(), object::id_address(&oft_composer));

        // Get the ComposeQueue address and store it in deployments
        let compose_queue_address = endpoint.get_compose_queue(oft_composer.composer_cap().id());
        deployments.set_deployment<ComposeQueue>(eid, compose_queue_address);

        test_scenario::return_shared<OFT<TEST_COIN>>(oft);
        test_scenario::return_shared<EndpointV2>(endpoint);
        test_scenario::return_shared<OFTComposer>(oft_composer);
        test_scenario::return_shared<OFTComposerManager>(composer_registry);
        scenario.return_to_sender<oft_composer_example::oft_composer::AdminCap>(composer_admin_cap);
        scenario.return_to_sender<oapp::AdminCap>(admin_cap);
    });
}

/// Send OFT message with compose functionality
fun send_message_with_compose(
    scenario: &mut Scenario,
    sender: address,
    to: address,
    deployments: &Deployments,
    src_eid: u32,
    dst_eid: u32,
    amount_ld: u64,
    compose_msg: vector<u8>,
) {
    let native_fee = coin::mint_for_testing<SUI>(1000000, scenario.ctx()); // 0.001 SUI

    let (oft_sender, send_call, oft_receipt_with_sender) = oft_test_helper::send(
        scenario,
        sender,
        to,
        sender, // refund_address
        deployments,
        src_eid,
        dst_eid,
        amount_ld,
        native_fee,
        option::none<coin::Coin<zro::zro::ZRO>>(),
        compose_msg,
        true,
    );

    // Execute the send call through the SML
    test_helper_with_sml::execute_send_call<TEST_COIN>(
        scenario,
        oft_sender,
        oft_receipt_with_sender,
        deployments,
        src_eid,
        send_call,
    );
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
    let packet_sent_events = event::events_by_type<PacketSentEvent>();
    assert!(packet_sent_events.length() > 0, E_EVENT_NOT_CREATED);
    let packet_sent_event = packet_sent_events[0];
    let encoded_packet = get_encoded_packet_from_packet_sent_event(&packet_sent_event);

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
    oft_test_helper::lz_receive(scenario, sender, deployments, dst_eid, encoded_packet, value, true);
}

/// Execute the compose operation using OFTComposer
fun execute_compose(
    scenario: &mut Scenario,
    sender: address,
    deployments: &Deployments,
    dst_eid: u32,
    compose_sent_event: ComposeSentEvent,
) {
    scenario.next_tx(sender);
    let mut oft_composer = deployments.take_shared_object<OFTComposer>(scenario, dst_eid);
    let dst_oft = deployments.take_shared_object<OFT<TEST_COIN>>(scenario, dst_eid);
    let dst_endpoint = deployments.take_shared_object<EndpointV2>(scenario, dst_eid);
    let mut compose_queue = deployments.take_shared_object<ComposeQueue>(scenario, dst_eid);

    // Create a mock executor CallCap
    let executor_cap = call_cap::new_individual_cap(scenario.ctx());

    // Create compose call using endpoint.lz_compose() similar to counter test
    let compose_value = coin::zero<SUI>(scenario.ctx());
    let compose_call = dst_endpoint.lz_compose(
        &executor_cap,
        &mut compose_queue,
        compose_sent_event.get_compose_sent_event_from(),
        compose_sent_event.get_compose_sent_event_guid(),
        compose_sent_event.get_compose_sent_event_index(),
        compose_sent_event.get_compose_sent_event_message(),
        vector::empty<u8>(),
        option::some(compose_value),
        scenario.ctx(),
    );

    let payment_handler = test_scenario::most_recent_receiving_ticket<ComposeTransfer<TEST_COIN>>(
        &object::id(&oft_composer),
    );

    // Execute lz_compose
    oft_composer.lz_compose<TEST_COIN>(payment_handler, compose_call, scenario.ctx());

    // Clean up resources
    test_scenario::return_shared<OFTComposer>(oft_composer);
    test_scenario::return_shared<OFT<TEST_COIN>>(dst_oft);
    test_scenario::return_shared<EndpointV2>(dst_endpoint);
    test_scenario::return_shared<ComposeQueue>(compose_queue);
    test_utils::destroy(executor_cap);
}

/// Get TEST_COIN balance for an address
fun get_test_coin_balance(scenario: &mut Scenario, addr: address): u64 {
    scenario.next_tx(addr);
    // Get all TEST_COIN coin IDs for the address
    let coin_ids = test_scenario::ids_for_address<coin::Coin<TEST_COIN>>(addr);
    let mut total_balance = 0u64;

    // Iterate through all coins and sum their values
    let mut i = 0;
    while (i < coin_ids.length()) {
        let coin_id = coin_ids[i];
        let coin = test_scenario::take_from_address_by_id<coin::Coin<TEST_COIN>>(scenario, addr, coin_id);
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
