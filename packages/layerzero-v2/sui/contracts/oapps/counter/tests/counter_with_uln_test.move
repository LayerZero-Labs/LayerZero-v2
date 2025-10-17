#[test_only]
module counter::counter_with_uln_test;

use counter::{
    counter_test_helper,
    options_builder,
    test_helper_with_uln,
    uln302_test_common::{
        setup_test_environment,
        quote,
        clean,
        assert_counter_state,
        assert_compose_count,
        send_message_with_dvns,
        handle_message_receive,
        VANILLA_TYPE,
        COMPOSE_TYPE,
        ABA_TYPE,
        ABA_COMPOSE_TYPE,
        default_config
    }
};
use endpoint_v2::{messaging_channel::{Self, PacketSentEvent}, messaging_composer::ComposeSentEvent};
use sui::{coin::{Self, Coin}, event, sui::SUI, test_scenario};
use zro::zro::ZRO;

// === Tests ===

#[test]
fun test_counter_vanilla() {
    let config = default_config();
    let (mut scenario, test_clock, deployments) = setup_test_environment(
        &config,
        vector[config.src_eid(), config.dst_eid()],
        false,
    );

    scenario.next_tx(config.user());
    // Standard executor options: 200,000 gas, no additional value
    let options = options_builder::new_builder().add_executor_lz_receive_option(200000, 0).build();
    let messaging_fee = quote(
        &config,
        &mut scenario,
        &deployments,
        config.src_eid(),
        config.dst_eid(),
        VANILLA_TYPE!(),
        options,
        false,
    );

    // Create fee coins by minting (for tests expected to fail during verification)
    let native_fee_coin = coin::mint_for_testing<SUI>(messaging_fee.native_fee(), test_scenario::ctx(&mut scenario));
    let zro_fee_coin = option::none<Coin<ZRO>>();

    // Send message with all configured DVNs
    send_message_with_dvns(
        &mut scenario,
        config.user(),
        &deployments,
        config.src_eid(),
        config.dst_eid(),
        VANILLA_TYPE!(),
        options,
        native_fee_coin,
        zro_fee_coin,
        vector[0, 1, 2, 3, 4], // All configured DVNs (3 required + 2 optional)
    );

    let packet_sent_event = event::events_by_type<PacketSentEvent>()[0];
    let encoded_packet = messaging_channel::get_encoded_packet_from_packet_sent_event(&packet_sent_event);

    test_helper_with_uln::verify_message(
        &mut scenario,
        config.deployer(),
        vector[0, 1, 2, 3, 4], // All configured DVNs (3 required + 2 optional)
        encoded_packet,
        &deployments,
        config.dst_eid(),
        &test_clock,
    );

    handle_message_receive(&mut scenario, config.deployer(), &deployments, config.dst_eid(), encoded_packet);
    assert_counter_state(&mut scenario, config.user(), &deployments, config.src_eid(), config.dst_eid(), 1, 1, 1);

    clean(scenario, test_clock, deployments);
}

#[test]
fun test_counter_compose() {
    let config = default_config();
    let (mut scenario, test_clock, deployments) = setup_test_environment(
        &config,
        vector[config.src_eid(), config.dst_eid()],
        false,
    );

    scenario.next_tx(config.user());
    // Standard executor options: 200,000 gas, no additional value
    let options = options_builder::new_builder().add_executor_lz_receive_option(200000, 0).build();
    let messaging_fee = quote(
        &config,
        &mut scenario,
        &deployments,
        config.src_eid(),
        config.dst_eid(),
        COMPOSE_TYPE!(),
        options,
        false,
    );

    // Create fee coins by minting (for tests expected to fail during verification)
    let native_fee_coin = coin::mint_for_testing<SUI>(messaging_fee.native_fee(), test_scenario::ctx(&mut scenario));
    let zro_fee_coin = option::none<Coin<ZRO>>();

    // Send message with all configured DVNs
    send_message_with_dvns(
        &mut scenario,
        config.user(),
        &deployments,
        config.src_eid(),
        config.dst_eid(),
        COMPOSE_TYPE!(),
        options,
        native_fee_coin,
        zro_fee_coin,
        vector[0, 1, 2, 3, 4], // All configured DVNs (3 required + 2 optional)
    );

    let packet_sent_event = event::events_by_type<PacketSentEvent>()[0];
    let encoded_packet = messaging_channel::get_encoded_packet_from_packet_sent_event(&packet_sent_event);

    test_helper_with_uln::verify_message(
        &mut scenario,
        config.deployer(),
        vector[0, 1, 2, 3, 4], // All configured DVNs (3 required + 2 optional)
        encoded_packet,
        &deployments,
        config.dst_eid(),
        &test_clock,
    );

    handle_message_receive(&mut scenario, config.deployer(), &deployments, config.dst_eid(), encoded_packet);

    let compose_sent_event = event::events_by_type<ComposeSentEvent>()[0];
    // check counter state before compose
    assert_counter_state(&mut scenario, config.user(), &deployments, config.src_eid(), config.dst_eid(), 1, 1, 1);
    assert_compose_count(&mut scenario, config.user(), &deployments, config.dst_eid(), 0);

    let compose_value = coin::zero<SUI>(test_scenario::ctx(&mut scenario));
    counter_test_helper::lz_compose(
        &mut scenario,
        config.deployer(),
        &deployments,
        config.dst_eid(),
        compose_sent_event,
        compose_value,
    );
    assert_compose_count(&mut scenario, config.user(), &deployments, config.dst_eid(), 1);

    clean(scenario, test_clock, deployments);
}

#[test]
fun test_counter_aba_no_compose() {
    let config = default_config();
    let (mut scenario, test_clock, deployments) = setup_test_environment(
        &config,
        vector[config.src_eid(), config.dst_eid()],
        false,
    );

    scenario.next_tx(config.user());
    // Standard executor options: 200,000 gas, no additional value
    let options = options_builder::new_builder().add_executor_lz_receive_option(200000, 0).build();
    let messaging_fee = quote(
        &config,
        &mut scenario,
        &deployments,
        config.src_eid(),
        config.dst_eid(),
        ABA_TYPE!(),
        options,
        false,
    );

    // Create fee coins by minting (for tests expected to fail during verification)
    let native_fee_coin = coin::mint_for_testing<SUI>(
        messaging_fee.native_fee() + 1000000,
        test_scenario::ctx(&mut scenario),
    );
    let zro_fee_coin = option::none<Coin<ZRO>>();

    // Send message with all configured DVNs
    send_message_with_dvns(
        &mut scenario,
        config.user(),
        &deployments,
        config.src_eid(),
        config.dst_eid(),
        ABA_TYPE!(),
        options,
        native_fee_coin,
        zro_fee_coin,
        vector[0, 1, 2, 3, 4], // All configured DVNs (3 required + 2 optional)
    );

    let packet_sent_event = event::events_by_type<PacketSentEvent>()[0];
    let encoded_packet = messaging_channel::get_encoded_packet_from_packet_sent_event(&packet_sent_event);

    test_helper_with_uln::verify_message(
        &mut scenario,
        config.deployer(),
        vector[0, 1, 2, 3, 4], // All configured DVNs (3 required + 2 optional)
        encoded_packet,
        &deployments,
        config.dst_eid(),
        &test_clock,
    );

    // fee on the destination chain should be similar but calldata increased so we pay excessive to prevent failure
    let value = coin::mint_for_testing<SUI>(messaging_fee.native_fee() + 1000000000, test_scenario::ctx(&mut scenario));
    let send_to_src_call = counter_test_helper::lz_receive_aba(
        &mut scenario,
        config.deployer(),
        &deployments,
        config.dst_eid(),
        encoded_packet,
        value,
    );

    assert_counter_state(&mut scenario, config.user(), &deployments, config.src_eid(), config.dst_eid(), 1, 1, 1);

    // On DST_EID
    // Execute the send to src call at DST_EID for incrementing on SRC_EID
    test_helper_with_uln::execute_send_call(
        &mut scenario,
        config.user(),
        &deployments,
        vector[0, 1, 2, 3, 4],
        config.dst_eid(),
        send_to_src_call,
    );

    let packet_sent_event_dst = event::events_by_type<PacketSentEvent>()[0];
    let encoded_packet_dst = messaging_channel::get_encoded_packet_from_packet_sent_event(&packet_sent_event_dst);

    test_helper_with_uln::verify_message(
        &mut scenario,
        config.deployer(),
        vector[0, 1, 2, 3, 4], // All configured DVNs (3 required + 2 optional)
        encoded_packet_dst,
        &deployments,
        config.src_eid(),
        &test_clock,
    );
    // receive 10 unit as the same specified in counter lz_receive_aba send options
    let value = coin::mint_for_testing<SUI>(10, test_scenario::ctx(&mut scenario));
    counter_test_helper::lz_receive(
        &mut scenario,
        config.deployer(),
        &deployments,
        config.src_eid(),
        encoded_packet_dst,
        value,
    );

    assert_counter_state(&mut scenario, config.user(), &deployments, config.src_eid(), config.dst_eid(), 1, 1, 1);
    assert_counter_state(&mut scenario, config.user(), &deployments, config.src_eid(), config.dst_eid(), 1, 1, 1);

    clean(scenario, test_clock, deployments);
}

#[test]
fun test_counter_aba_compose() {
    let config = default_config();
    let (mut scenario, test_clock, deployments) = setup_test_environment(
        &config,
        vector[config.src_eid(), config.dst_eid()],
        false,
    );

    scenario.next_tx(config.user());
    // Standard executor options: 200,000 gas, no additional value
    let options = options_builder::new_builder().add_executor_lz_receive_option(200000, 0).build();
    let messaging_fee = quote(
        &config,
        &mut scenario,
        &deployments,
        config.src_eid(),
        config.dst_eid(),
        ABA_COMPOSE_TYPE!(),
        options,
        false,
    );

    // Create fee coins by minting
    let native_fee_coin = coin::mint_for_testing<SUI>(
        messaging_fee.native_fee() + 1000000,
        test_scenario::ctx(&mut scenario),
    );
    let zro_fee_coin = option::none<Coin<ZRO>>();

    // Send message with all configured DVNs
    send_message_with_dvns(
        &mut scenario,
        config.user(),
        &deployments,
        config.src_eid(),
        config.dst_eid(),
        ABA_COMPOSE_TYPE!(),
        options,
        native_fee_coin,
        zro_fee_coin,
        vector[0, 1, 2, 3, 4], // All configured DVNs (3 required + 2 optional)
    );

    let packet_sent_event = event::events_by_type<PacketSentEvent>()[0];
    let encoded_packet = messaging_channel::get_encoded_packet_from_packet_sent_event(&packet_sent_event);

    test_helper_with_uln::verify_message(
        &mut scenario,
        config.deployer(),
        vector[0, 1, 2, 3, 4], // All configured DVNs (3 required + 2 optional)
        encoded_packet,
        &deployments,
        config.dst_eid(),
        &test_clock,
    );

    let value = coin::zero<SUI>(test_scenario::ctx(&mut scenario));
    counter_test_helper::lz_receive(
        &mut scenario,
        config.deployer(),
        &deployments,
        config.dst_eid(),
        encoded_packet,
        value,
    );

    let compose_sent_event = event::events_by_type<ComposeSentEvent>()[0];
    assert_counter_state(&mut scenario, config.user(), &deployments, config.src_eid(), config.dst_eid(), 1, 1, 1);
    assert_compose_count(&mut scenario, config.user(), &deployments, config.dst_eid(), 0);

    let compose_value = coin::mint_for_testing<SUI>(messaging_fee.native_fee() + 10, test_scenario::ctx(&mut scenario)); // 10 unit + the native fee as the same specified in counter lz_compose_aba send options + the amount of send cost
    let send_to_src_call = counter_test_helper::lz_compose_aba(
        &mut scenario,
        config.deployer(),
        &deployments,
        config.dst_eid(),
        compose_sent_event,
        compose_value,
    );

    assert_compose_count(&mut scenario, config.user(), &deployments, config.dst_eid(), 1);

    // On DST_EID
    // Execute the send to src call at DST_EID for incrementing on SRC_EID
    test_helper_with_uln::execute_send_call(
        &mut scenario,
        config.user(),
        &deployments,
        vector[0, 1, 2, 3, 4],
        config.dst_eid(),
        send_to_src_call,
    );

    let packet_sent_event_dst = event::events_by_type<PacketSentEvent>()[0];
    let encoded_packet_dst = messaging_channel::get_encoded_packet_from_packet_sent_event(&packet_sent_event_dst);

    test_helper_with_uln::verify_message(
        &mut scenario,
        config.deployer(),
        vector[0, 1, 2, 3, 4], // All configured DVNs (3 required + 2 optional)
        encoded_packet_dst,
        &deployments,
        config.src_eid(),
        &test_clock,
    );

    let value = coin::mint_for_testing<SUI>(messaging_fee.native_fee() + 10, test_scenario::ctx(&mut scenario)); // 10 unit + the native fee as the same specified in counter lz_receive_aba send options + the amount of send cost
    counter_test_helper::lz_receive(
        &mut scenario,
        config.deployer(),
        &deployments,
        config.src_eid(),
        encoded_packet_dst,
        value,
    );

    assert_counter_state(&mut scenario, config.user(), &deployments, config.src_eid(), config.dst_eid(), 1, 1, 1);
    assert_counter_state(&mut scenario, config.user(), &deployments, config.src_eid(), config.dst_eid(), 1, 1, 1);

    clean(scenario, test_clock, deployments);
}

#[test]
#[expected_failure(abort_code = uln_302::receive_uln::EVerifying)]
fun test_counter_receive_with_insufficient_dvns() {
    // Test with insufficient DVNs - missing required DVNs and optional threshold not met (should fail)
    let config = default_config();
    let (mut scenario, test_clock, deployments) = setup_test_environment(
        &config,
        vector[config.src_eid(), config.dst_eid()],
        false,
    );

    scenario.next_tx(config.user());
    // Standard executor options: 200,000 gas, no additional value
    let options = options_builder::new_builder().add_executor_lz_receive_option(200000, 0).build();
    let messaging_fee = quote(
        &config,
        &mut scenario,
        &deployments,
        config.src_eid(),
        config.dst_eid(),
        VANILLA_TYPE!(),
        options,
        false,
    );

    // Create fee coins by minting (for tests expected to fail during verification)
    let native_fee_coin = coin::mint_for_testing<SUI>(messaging_fee.native_fee(), test_scenario::ctx(&mut scenario));
    let zro_fee_coin = option::none<Coin<ZRO>>();

    // Send message with all configured DVNs
    send_message_with_dvns(
        &mut scenario,
        config.user(),
        &deployments,
        config.src_eid(),
        config.dst_eid(),
        VANILLA_TYPE!(),
        options,
        native_fee_coin,
        zro_fee_coin,
        vector[0, 1, 2, 3, 4], // All configured DVNs (3 required + 2 optional)
    );

    // Try to verify with insufficient DVNs (only 2 out of 3 required + missing optional DVN for threshold)
    let packet_sent_event = event::events_by_type<PacketSentEvent>()[0];
    let encoded_packet = messaging_channel::get_encoded_packet_from_packet_sent_event(&packet_sent_event);

    test_helper_with_uln::verify_message(
        &mut scenario,
        config.deployer(),
        vector[0, 1], // Only 2 DVNs verify (insufficient - needs all 3 required + at least 1 optional)
        encoded_packet,
        &deployments,
        config.dst_eid(),
        &test_clock,
    );

    // This should fail before reaching here
    handle_message_receive(&mut scenario, config.deployer(), &deployments, config.dst_eid(), encoded_packet);

    clean(scenario, test_clock, deployments);
}
