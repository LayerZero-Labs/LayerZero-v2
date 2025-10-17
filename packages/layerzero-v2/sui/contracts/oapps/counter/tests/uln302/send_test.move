#[test_only]
module counter::uln302_send_test;

use counter::{
    multi_dvn_helper,
    options_builder,
    uln302_test_common::{
        setup_test_environment,
        quote,
        clean,
        send_message_with_dvns,
        snapshot_balances,
        assert_worker_treasury_received_fees,
        VANILLA_TYPE,
        default_config
    }
};
use sui::{coin::{Self, Coin}, sui::SUI, test_scenario};
use zro::zro::ZRO;

#[test]
fun test_send_with_executor_options_with_correct_gas_application() {
    let config = default_config();
    let (mut scenario, test_clock, deployments) = setup_test_environment(
        &config,
        vector[config.src_eid(), config.dst_eid()],
        false,
    );
    let (snapshot1, snapshot2) = {
        // Get messaging fee
        scenario.next_tx(config.user());
        // Standard executor options: 200,000 gas, no additional value
        let options = options_builder::new_builder().add_executor_lz_receive_option(200000, 0).build();

        // Quote with native fee (pay_in_zro = false)
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

        // Take snapshot of initial balances (both BOB and ALICE)
        let initial_bob_snapshot = snapshot_balances(
            &config,
            &mut scenario,
            &deployments,
            config.user(),
            config.src_eid(),
        );

        // Create fee coins with exact quoted amount
        scenario.next_tx(config.user());
        // Take the coin that was transferred to BOB
        let mut sender_sui = scenario.take_from_address<Coin<SUI>>(config.user());
        let native_fee_coin = sender_sui.split(messaging_fee.native_fee(), test_scenario::ctx(&mut scenario));
        test_scenario::return_to_address(config.user(), sender_sui);
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

        // Take snapshot of final balances (both BOB and ALICE)
        let final_bob_snapshot = snapshot_balances(
            &config,
            &mut scenario,
            &deployments,
            config.user(),
            config.src_eid(),
        );

        (initial_bob_snapshot, final_bob_snapshot)
    };

    let (snapshot3, snapshot4) = {
        // Get messaging fee
        scenario.next_tx(config.user());
        // Standard executor options: 1,000,000 gas, no additional value
        let options = options_builder::new_builder().add_executor_lz_receive_option(1000000, 0).build();

        // Quote with native fee (pay_in_zro = false)
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

        // Take snapshot of initial balances (both BOB and ALICE)
        let initial_bob_snapshot = snapshot_balances(
            &config,
            &mut scenario,
            &deployments,
            config.user(),
            config.src_eid(),
        );

        // Create fee coins with exact quoted amount
        scenario.next_tx(config.user());
        // Take the coin that was transferred to BOB
        let mut sender_sui = scenario.take_from_address<Coin<SUI>>(config.user());
        let native_fee_coin = sender_sui.split(messaging_fee.native_fee(), test_scenario::ctx(&mut scenario));
        test_scenario::return_to_address(config.user(), sender_sui);
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

        let final_bob_snapshot = snapshot_balances(
            &config,
            &mut scenario,
            &deployments,
            config.user(),
            config.src_eid(),
        );

        (initial_bob_snapshot, final_bob_snapshot)
    };
    let (snapshot5, snapshot6) = {
        // Get messaging fee
        scenario.next_tx(config.user());
        // Standard executor options: 1,000,000 gas, no additional value
        let options = options_builder::new_builder()
            .add_executor_lz_receive_option(200000, 0)
            // .add_dvn_option(0, 0, vector[])
            .build();

        // Quote with native fee (pay_in_zro = false)
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
        // Take snapshot of initial balance
        let initial_bob_snapshot = snapshot_balances(
            &config,
            &mut scenario,
            &deployments,
            config.user(),
            config.src_eid(),
        );

        // Create fee coins with exact quoted amount
        scenario.next_tx(config.user());
        // Take the coin that was transferred to BOB
        let mut sender_sui = scenario.take_from_address<Coin<SUI>>(config.user());
        let native_fee_coin = sender_sui.split(messaging_fee.native_fee(), test_scenario::ctx(&mut scenario));
        test_scenario::return_to_address(config.user(), sender_sui);
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

        // Take snapshot of final balances (both BOB and ALICE)
        let final_bob_snapshot = snapshot_balances(
            &config,
            &mut scenario,
            &deployments,
            config.user(),
            config.src_eid(),
        );

        (initial_bob_snapshot, final_bob_snapshot)
    };

    let executor_diff1 = snapshot2.executor_sui() - snapshot1.executor_sui();
    let executor_diff2 = snapshot4.executor_sui() - snapshot3.executor_sui();
    assert!(executor_diff2 > executor_diff1, 105);

    // no change for executor fee and dvn fee, even though there are dvn options but dvn options aren't participating in
    // the fee calculation
    let executor_fee_options1 = snapshot2.executor_sui() - snapshot1.executor_sui();
    let executor_fee_options3 = snapshot6.executor_sui() - snapshot5.executor_sui();
    assert!(executor_fee_options3 == executor_fee_options1, 106);
    let mut i = 0;
    while (i < snapshot2.dvn_sui_balances().length()) {
        assert!(
            snapshot2.dvn_sui_balances()[i] - snapshot1.dvn_sui_balances()[i] == snapshot6.dvn_sui_balances()[i] - snapshot5.dvn_sui_balances()[i],
            107,
        );
        i = i + 1;
    };

    clean(scenario, test_clock, deployments);
}

#[test]
fun test_send_with_fee_receipt_verification() {
    let config = default_config();
    let (mut scenario, test_clock, deployments) = setup_test_environment(
        &config,
        vector[config.src_eid(), config.dst_eid()],
        true,
    );

    // Get messaging fee
    scenario.next_tx(config.user());
    // Standard executor options: 200,000 gas, no additional value
    let options = options_builder::new_builder().add_executor_lz_receive_option(200000, 0).build();

    // Quote with ZRO fee (pay_in_zro = true)
    let messaging_fee = quote(
        &config,
        &mut scenario,
        &deployments,
        config.src_eid(),
        config.dst_eid(),
        VANILLA_TYPE!(),
        options,
        true,
    );

    // When paying in ZRO mode, workers still need native fees, only treasury fee is in ZRO
    assert!(messaging_fee.native_fee() > 0, 200);
    assert!(messaging_fee.zro_fee() > 0, 201);

    // Take snapshot of initial balances (both BOB and ALICE)
    let initial_bob_snapshot = snapshot_balances(&config, &mut scenario, &deployments, config.user(), config.src_eid());

    // Create fee coins with exact quoted amount
    // When paying in ZRO mode, we need both native (for workers) and ZRO (for treasury)
    scenario.next_tx(config.user());
    let mut sender_sui = scenario.take_from_address<Coin<SUI>>(config.user());
    let native_fee_coin = sender_sui.split(messaging_fee.native_fee(), test_scenario::ctx(&mut scenario));
    test_scenario::return_to_address(config.user(), sender_sui);

    let mut sender_zro = scenario.take_from_address<Coin<ZRO>>(config.user());
    let zro_fee_coin = option::some(sender_zro.split(messaging_fee.zro_fee(), test_scenario::ctx(&mut scenario)));
    test_scenario::return_to_address(config.user(), sender_zro);

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

    // Take snapshot of final balances (both BOB and ALICE)
    let final_bob_snapshot = snapshot_balances(&config, &mut scenario, &deployments, config.user(), config.src_eid());

    // When paying in ZRO mode, workers still get paid in native, treasury fee is in ZRO
    // Verify BOB's balance decreased by both native fee (for workers) and ZRO fee (for treasury)
    assert!(initial_bob_snapshot.sender_sui() == final_bob_snapshot.sender_sui() + messaging_fee.native_fee(), 202);
    assert!(initial_bob_snapshot.sender_zro() == final_bob_snapshot.sender_zro() + messaging_fee.zro_fee(), 203);

    assert_worker_treasury_received_fees(&final_bob_snapshot, true);

    clean(scenario, test_clock, deployments);
}

#[test]
#[expected_failure(abort_code = call::call::ECallNotCompleted)]
fun test_send_insufficient_dvns() {
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
        vector[0, 1], // All configured DVNs (3 required + 2 optional)
    );

    clean(scenario, test_clock, deployments);
}

#[test, expected_failure]
fun test_send_with_invalid_dvns() {
    // Test with a DVN index that doesn't exist at all (should fail)
    let config = default_config();
    let (mut scenario, test_clock, deployments) = setup_test_environment(
        &config,
        vector[config.src_eid(), config.dst_eid()],
        false,
    );

    scenario.next_tx(config.user());

    // Total deployed DVNs: 7 (indices 0-6)
    // Using index 10 which doesn't exist should cause a failure
    let non_existent_dvn_index = 10u8;
    let options = multi_dvn_helper::construct_options_with_dvn_indices(
        200000, // execution_gas
        vector[non_existent_dvn_index], // Non-existent DVN index
        vector[1000], // Custom data for the DVN
    );

    // Get messaging fee - this might succeed since it's just calculating fees
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

    // Create fee coins
    let native_fee_coin = coin::mint_for_testing<SUI>(messaging_fee.native_fee(), test_scenario::ctx(&mut scenario));
    let zro_fee_coin = option::none<Coin<ZRO>>();

    // This should fail when trying to send the message with non-existent DVN index
    // The failure will occur when trying to get the DVN deployment with index 10
    // which doesn't exist (deployments.get_indexed_deployment<DVN>(src_eid, 10) will fail)
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
        vector[non_existent_dvn_index as u64], // Pass the non-existent index to execute_send_call
    );

    // The test should fail before reaching this point
    clean(scenario, test_clock, deployments);
}

#[test, expected_failure]
fun test_send_with_low_fee() {
    // ALICE deploys contracts, BOB sends messages
    let config = default_config();
    let (mut scenario, test_clock, deployments) = setup_test_environment(
        &config,
        vector[config.src_eid(), config.dst_eid()],
        false,
    );

    // Get messaging fee
    scenario.next_tx(config.user());
    // Standard executor options: 200,000 gas, no additional value
    let options = options_builder::new_builder().add_executor_lz_receive_option(200000, 0).build();

    // Quote with native fee (pay_in_zro = false)
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

    // Verify quote returns native fee only (no ZRO fee when paying in native)
    assert!(messaging_fee.native_fee() > 0, 100);
    assert!(messaging_fee.zro_fee() == 0, 101);

    // Create fee coins with exact quoted amount
    scenario.next_tx(config.user());
    // Take the coin that was transferred to BOB
    let mut sender_sui = scenario.take_from_address<Coin<SUI>>(config.user());
    let native_fee_coin = sender_sui.split(messaging_fee.native_fee() - 50, test_scenario::ctx(&mut scenario));
    test_scenario::return_to_address(config.user(), sender_sui);
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

    clean(scenario, test_clock, deployments);
}

#[test]
fun test_send_with_refund_with_zro_disabled() {
    // ALICE deploys contracts, BOB sends messages
    let config = default_config();
    let (mut scenario, test_clock, deployments) = setup_test_environment(
        &config,
        vector[config.src_eid(), config.dst_eid()],
        false,
    );

    // Get messaging fee
    scenario.next_tx(config.user());
    // Standard executor options: 200,000 gas, no additional value
    let options = options_builder::new_builder().add_executor_lz_receive_option(200000, 0).build();

    // Quote with native fee (pay_in_zro = false)
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

    // Verify quote returns native fee only (no ZRO fee when paying in native)
    assert!(messaging_fee.native_fee() > 0, 100);
    assert!(messaging_fee.zro_fee() == 0, 101);

    // Take snapshot of initial balances (both BOB and ALICE)
    let initial_bob_snapshot = snapshot_balances(&config, &mut scenario, &deployments, config.user(), config.src_eid());

    // Create fee coins with exact quoted amount
    scenario.next_tx(config.user());
    // Take the coin that was transferred to BOB
    let mut sender_sui = scenario.take_from_address<Coin<SUI>>(config.user());
    // Pay 1,000,000 more than the fee to trigger refund
    let native_fee_coin = sender_sui.split(messaging_fee.native_fee() + 333, test_scenario::ctx(&mut scenario));
    test_scenario::return_to_address(config.user(), sender_sui);
    let zro_fee_coin = option::none();

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

    // Take snapshot of final balances (both BOB and ALICE)
    let final_bob_snapshot = snapshot_balances(&config, &mut scenario, &deployments, config.user(), config.src_eid());

    // Verify BOB's balance decreased by the fee amount
    assert!(initial_bob_snapshot.sender_sui() == final_bob_snapshot.sender_sui() + messaging_fee.native_fee(), 202);
    assert!(initial_bob_snapshot.sender_zro() == final_bob_snapshot.sender_zro(), 203);

    clean(scenario, test_clock, deployments);
}

#[test]
fun test_send_with_refund_with_zro_enabled() {
    // ALICE deploys contracts, BOB sends messages
    let config = default_config();
    let (mut scenario, test_clock, deployments) = setup_test_environment(
        &config,
        vector[config.src_eid(), config.dst_eid()],
        true,
    );

    // Get messaging fee
    scenario.next_tx(config.user());
    // Standard executor options: 200,000 gas, no additional value
    let options = options_builder::new_builder().add_executor_lz_receive_option(200000, 0).build();

    // Quote with native fee (pay_in_zro = false)
    let messaging_fee = quote(
        &config,
        &mut scenario,
        &deployments,
        config.src_eid(),
        config.dst_eid(),
        VANILLA_TYPE!(),
        options,
        true,
    );

    // Verify quote returns native fee only (no ZRO fee when paying in native)
    assert!(messaging_fee.native_fee() > 0, 100);
    assert!(messaging_fee.zro_fee() > 0, 101);

    // Take snapshot of initial balances (both BOB and ALICE)
    let initial_bob_snapshot = snapshot_balances(&config, &mut scenario, &deployments, config.user(), config.src_eid());

    // Create fee coins with exact quoted amount
    scenario.next_tx(config.user());
    // Take the coin that was transferred to BOB
    let mut sender_sui = scenario.take_from_address<Coin<SUI>>(config.user());
    let mut sender_zro = scenario.take_from_address<Coin<ZRO>>(config.user());
    // Pay 1,000,000 more than the fee to trigger refund
    let native_fee_coin = sender_sui.split(messaging_fee.native_fee() + 333, test_scenario::ctx(&mut scenario));
    test_scenario::return_to_address(config.user(), sender_sui);
    let zro_fee_coin = option::some(sender_zro.split(messaging_fee.zro_fee() + 444, test_scenario::ctx(&mut scenario)));
    test_scenario::return_to_address(config.user(), sender_zro);

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

    // Take snapshot of final balances (both BOB and ALICE)
    let final_bob_snapshot = snapshot_balances(&config, &mut scenario, &deployments, config.user(), config.src_eid());

    // Verify BOB's balance decreased by the fee amount
    assert!(initial_bob_snapshot.sender_sui() == final_bob_snapshot.sender_sui() + messaging_fee.native_fee(), 202);
    assert!(initial_bob_snapshot.sender_zro() == final_bob_snapshot.sender_zro() + messaging_fee.zro_fee(), 203);

    clean(scenario, test_clock, deployments);
}
