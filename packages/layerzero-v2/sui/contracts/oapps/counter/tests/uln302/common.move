module counter::uln302_test_common;

use counter::{
    counter::Counter,
    counter_test_helper,
    deployments::{Self, Deployments},
    scenario_utils,
    test_helper_with_uln
};
use dvn::dvn::DVN;
use dvn_fee_lib::dvn_fee_lib::DvnFeeLib;
use endpoint_v2::{endpoint_v2::EndpointV2, messaging_channel::MessagingChannel, messaging_fee::MessagingFee};
use executor::executor_worker::Executor;
use executor_fee_lib::executor_fee_lib::ExecutorFeeLib;
use oapp::oapp::OApp;
use price_feed::price_feed::PriceFeed;
use sui::{clock::{Self, Clock}, coin::{Self, Coin}, sui::SUI, test_scenario::{Self, Scenario}, test_utils};
use treasury::treasury::Treasury;
use uln_302::uln_302::Uln302;
use zro::zro::ZRO;

// Message types (constants)
public macro fun VANILLA_TYPE(): u8 { 1 }
public macro fun COMPOSE_TYPE(): u8 { 2 }
public macro fun ABA_TYPE(): u8 { 3 }
public macro fun ABA_COMPOSE_TYPE(): u8 { 4 }

// Error codes (constants)
public macro fun E_INVALID_OUTBOUND_COUNT(): u64 { 2 }
public macro fun E_INVALID_INBOUND_COUNT(): u64 { 3 }
public macro fun E_INVALID_COUNT(): u64 { 4 }
public macro fun E_INVALID_COMPOSED_COUNT_AFTER(): u64 { 6 }

/// Configuration struct for test environment
public struct TestConfig has copy, drop {
    // Test addresses
    deployer: address, // Deployer and worker deposit address
    user: address, // Message sender
    // Endpoint IDs
    src_eid: u32,
    dst_eid: u32,
    // DVN configuration
    required_dvns: u64,
    optional_dvns: u64,
    optional_dvn_threshold: u8,
    additional_dvns: u64,
}

/// Create default test configuration
public fun default_config(): TestConfig {
    TestConfig {
        deployer: @0xa11ce,
        user: @0xb0b,
        src_eid: 30001,
        dst_eid: 30002,
        required_dvns: 3, // Indices 0, 1, 2
        optional_dvns: 2, // Indices 3, 4
        optional_dvn_threshold: 1, // Need at least 1 optional DVN to verify
        additional_dvns: 2, // Indices 5, 6, the DVNs that aren't configured in OApp(Counter)
    }
}

/// Create fully customizable test configuration
public fun custom_config(
    deployer: address,
    user: address,
    src_eid: u32,
    dst_eid: u32,
    required_dvns: u64,
    optional_dvns: u64,
    optional_dvn_threshold: u8,
    additional_dvns: u64,
): TestConfig {
    TestConfig {
        deployer,
        user,
        src_eid,
        dst_eid,
        required_dvns,
        optional_dvns,
        optional_dvn_threshold,
        additional_dvns,
    }
}

// Getter functions for TestConfig fields
public fun deployer(config: &TestConfig): address {
    config.deployer
}

public fun user(config: &TestConfig): address {
    config.user
}

public fun src_eid(config: &TestConfig): u32 {
    config.src_eid
}

public fun dst_eid(config: &TestConfig): u32 {
    config.dst_eid
}

public fun required_dvns(config: &TestConfig): u64 {
    config.required_dvns
}

public fun optional_dvns(config: &TestConfig): u64 {
    config.optional_dvns
}

public fun optional_dvn_threshold(config: &TestConfig): u8 {
    config.optional_dvn_threshold
}

public fun additional_dvns(config: &TestConfig): u64 {
    config.additional_dvns
}

/// Initialize complete test environment with scenario and clock
/// Returns: (scenario, test_clock, deployments)
public fun setup_test_environment(
    config: &TestConfig,
    eids: vector<u32>,
    enable_zro_fee: bool,
): (Scenario, Clock, Deployments) {
    let mut scenario = test_scenario::begin(config.deployer());
    let test_clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

    let mut deployments = deployments::new(test_scenario::ctx(&mut scenario));

    // Setup endpoints with ULN and configure treasury based on enable_zro_fee
    test_helper_with_uln::setup_endpoint_with_uln_and_treasury(
        &mut scenario,
        config.required_dvns,
        config.optional_dvns,
        config.optional_dvn_threshold,
        config.deployer(),
        eids,
        &mut deployments,
        &test_clock,
        enable_zro_fee,
    );

    counter_test_helper::setup_counter(&mut scenario, config.deployer(), eids, &mut deployments);

    // Mint initial balances for user (the message sender) - 1000 SUI and 1000 ZRO
    scenario.next_tx(config.deployer());
    let initial_sui = coin::mint_for_testing<SUI>(1000000000000000000, test_scenario::ctx(&mut scenario)); // 1000 SUI
    let initial_zro = coin::mint_for_testing<ZRO>(1000000000000000000, test_scenario::ctx(&mut scenario)); // 1000 ZRO
    transfer::public_transfer(initial_sui, config.user);
    transfer::public_transfer(initial_zro, config.user);

    (scenario, test_clock, deployments)
}

/// Clean up test resources
public fun clean(scenario: Scenario, clock: Clock, deployments: Deployments) {
    test_scenario::end(scenario);
    clock::destroy_for_testing(clock);
    test_utils::destroy(deployments);
}

/// Get messaging fee quote
public fun quote(
    config: &TestConfig,
    scenario: &mut Scenario,
    deployments: &Deployments,
    src_eid: u32,
    dst_eid: u32,
    msg_type: u8,
    options: vector<u8>,
    pay_in_zro: bool,
): MessagingFee {
    let counter = deployments.get_deployment_object<Counter>(scenario, src_eid);
    let oapp = deployments.get_deployment_object<OApp>(scenario, src_eid);
    let endpoint = deployments.get_deployment_object<EndpointV2>(scenario, src_eid);
    let uln = deployments.get_deployment_object<Uln302>(scenario, src_eid);
    let treasury = deployments.get_deployment_object<Treasury>(scenario, src_eid);
    let messaging_channel = deployments.get_deployment_object<MessagingChannel>(scenario, src_eid);
    let executor = deployments.get_deployment_object<Executor>(scenario, src_eid);
    let executor_fee_lib = deployments.get_deployment_object<ExecutorFeeLib>(scenario, src_eid);
    let price_feed = deployments.get_deployment_object<PriceFeed>(scenario, src_eid);
    let total_configured_dvns = config.required_dvns + config.optional_dvns;
    let dvns = vector::tabulate!(total_configured_dvns, |i| {
        deployments.get_deployment_object_indexed<DVN>(scenario, src_eid, i)
    });
    let dvn_fee_libs = vector::tabulate!(total_configured_dvns, |i| {
        deployments.get_deployment_object_indexed<DvnFeeLib>(scenario, src_eid, i)
    });

    // Step 1: Counter creates quote call
    let mut quote_call = counter.quote(
        &oapp,
        dst_eid,
        msg_type,
        options,
        pay_in_zro,
        scenario.ctx(),
    );

    // Steps 2-6: Use helper function to process the complete call chain:
    // endpoint.quote -> ULN302.quote -> Workers -> FeeLibs -> PriceFeed -> (reverse flow)
    test_helper_with_uln::quote(
        &endpoint,
        &uln,
        &treasury,
        &messaging_channel,
        &executor,
        &executor_fee_lib,
        &price_feed,
        &dvns,
        &dvn_fee_libs,
        &mut quote_call,
        scenario.ctx(),
    );

    let result = *quote_call.result();
    let messaging_fee = result.destroy_some();

    // Step 5: Clean up quote call
    test_utils::destroy(quote_call);

    // Clean up resources
    test_scenario::return_shared<Counter>(counter);
    test_scenario::return_shared<OApp>(oapp);
    test_scenario::return_shared<EndpointV2>(endpoint);
    test_scenario::return_shared<Uln302>(uln);
    test_scenario::return_shared<Treasury>(treasury);
    test_scenario::return_shared<MessagingChannel>(messaging_channel);
    test_scenario::return_shared<Executor>(executor);
    test_scenario::return_shared<ExecutorFeeLib>(executor_fee_lib);
    test_scenario::return_shared<PriceFeed>(price_feed);
    dvns.do!(|dvn| {
        test_scenario::return_shared<DVN>(dvn);
    });
    dvn_fee_libs.do!(|dvn_fee_lib| {
        test_scenario::return_shared<DvnFeeLib>(dvn_fee_lib);
    });

    messaging_fee
}

/// Send message with specific DVN indexes
public fun send_message_with_dvns(
    scenario: &mut Scenario,
    sender: address,
    deployments: &Deployments,
    src_eid: u32,
    dst_eid: u32,
    msg_type: u8,
    options: vector<u8>,
    native_fee_coin: Coin<SUI>,
    zro_fee_coin: Option<Coin<ZRO>>,
    dvn_indexes: vector<u64>,
) {
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
    test_helper_with_uln::execute_send_call(scenario, sender, deployments, dvn_indexes, src_eid, send_call);
}

/// Handle message receive
public fun handle_message_receive(
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
public fun assert_counter_state(
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
    assert!(counter_src.get_outbound_count(dst_eid) == expected_outbound_count, E_INVALID_OUTBOUND_COUNT!());
    assert!(counter_dst.get_inbound_count(src_eid) == expected_inbound_count, E_INVALID_INBOUND_COUNT!());
    assert!(counter_dst.get_count() == expected_count, E_INVALID_COUNT!());

    test_scenario::return_shared<Counter>(counter_src);
    test_scenario::return_shared<Counter>(counter_dst);
}

/// Verify compose count with flexible expected value
public fun assert_compose_count(
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
    assert!(counter_dst.get_composed_count() == expected_compose_count, E_INVALID_COMPOSED_COUNT_AFTER!());
    test_scenario::return_shared<Counter>(counter_dst);
}

/// Setup additional DVNs that are not configured in the ULN for the OApp
/// These DVNs exist on-chain but are not part of the security configuration
public fun setup_additional_dvns(
    config: &TestConfig,
    scenario: &mut Scenario,
    sender: address,
    eids: vector<u32>,
    deployments: &mut Deployments,
    _test_clock: &Clock,
) {
    eids.do!(|eid| {
        // Get the ULN302 call cap address for registering the DVNs
        let uln302_obj_address = deployments.get_deployment<Uln302>(eid);
        let uln302 = scenario_utils::take_shared_by_address<Uln302>(scenario, uln302_obj_address);
        let uln302_callcap = uln302.get_call_cap().id();
        test_scenario::return_shared<Uln302>(uln302);

        // Get the PriceFeed call cap address
        let price_feed_obj_address = deployments.get_deployment<PriceFeed>(eid);
        let price_feed = scenario_utils::take_shared_by_address<PriceFeed>(scenario, price_feed_obj_address);
        let price_feed_callcap = price_feed.get_call_cap().id();
        test_scenario::return_shared<PriceFeed>(price_feed);

        // Deploy additional DVNs with indices starting after required + optional DVNs
        // These DVNs will be deployed but NOT configured in the ULN config
        let start_index = config.required_dvns + config.optional_dvns;
        config.additional_dvns.do!(|i| {
            test_helper_with_uln::setup_dvn_with_uln(
                scenario,
                sender,
                eid,
                start_index + i, // DVN index: 5, 6 (after 0-2 required and 3-4 optional)
                eids,
                price_feed_callcap,
                uln302_callcap,
                deployments,
            );
        });
    });
}

/// Get balance of a coin type for an address
public fun get_balance<T>(scenario: &mut Scenario, addr: address): u64 {
    scenario.next_tx(addr);
    // Get all coin IDs for the address
    let coin_ids = test_scenario::ids_for_address<Coin<T>>(addr);
    let mut total_balance = 0u64;

    // Iterate through all coins and sum their values
    let mut i = 0;
    while (i < coin_ids.length()) {
        let coin_id = coin_ids[i];
        let coin = test_scenario::take_from_address_by_id<Coin<T>>(scenario, addr, coin_id);
        total_balance = total_balance + coin.value();
        test_scenario::return_to_address(addr, coin);
        i = i + 1;
    };

    total_balance
}

/// Get executor's balance (deposit address)
public fun get_executor_balance(scenario: &mut Scenario, deployments: &Deployments, eid: u32): u64 {
    let executor = scenario_utils::take_shared_by_address<Executor>(
        scenario,
        deployments.get_deployment<Executor>(eid),
    );
    let deposit_address = executor.deposit_address();
    test_scenario::return_shared(executor);
    get_balance<SUI>(scenario, deposit_address)
}

/// Get DVN balances for all configured DVNs
public fun get_dvn_balances(
    config: &TestConfig,
    scenario: &mut Scenario,
    deployments: &Deployments,
    eid: u32,
): vector<u64> {
    let total_configured_dvns = config.required_dvns + config.optional_dvns;
    let mut balances = vector[];
    let mut i = 0;
    while (i < total_configured_dvns) {
        let dvn = scenario_utils::take_shared_by_address<DVN>(
            scenario,
            deployments.get_indexed_deployment<DVN>(eid, i),
        );
        let deposit_address = dvn.deposit_address();
        test_scenario::return_shared(dvn);
        balances.push_back(get_balance<SUI>(scenario, deposit_address));
        i = i + 1;
    };
    balances
}

/// Track all balances before a transaction
public struct BalanceSnapshot has drop {
    sender_sui: u64,
    sender_zro: u64,
    executor_sui: u64,
    dvn_sui_balances: vector<u64>,
    treasury_sui: u64,
    treasury_zro: u64,
}

public fun sender_sui(self: &BalanceSnapshot): u64 {
    self.sender_sui
}

public fun sender_zro(self: &BalanceSnapshot): u64 {
    self.sender_zro
}

public fun executor_sui(self: &BalanceSnapshot): u64 {
    self.executor_sui
}

public fun dvn_sui_balances(self: &BalanceSnapshot): vector<u64> {
    self.dvn_sui_balances
}

public fun treasury_sui(self: &BalanceSnapshot): u64 {
    self.treasury_sui
}

public fun treasury_zro(self: &BalanceSnapshot): u64 {
    self.treasury_zro
}

/// Take a snapshot of all relevant balances
public fun snapshot_balances(
    config: &TestConfig,
    scenario: &mut Scenario,
    deployments: &Deployments,
    sender: address,
    eid: u32,
): BalanceSnapshot {
    scenario.next_tx(sender);
    let treasury = scenario_utils::take_shared_by_address<Treasury>(
        scenario,
        deployments.get_deployment<Treasury>(eid),
    );
    let treasury_address = treasury.fee_recipient();
    test_scenario::return_shared(treasury);

    BalanceSnapshot {
        sender_sui: get_balance<SUI>(scenario, sender),
        sender_zro: get_balance<ZRO>(scenario, sender),
        executor_sui: get_executor_balance(scenario, deployments, eid),
        dvn_sui_balances: get_dvn_balances(config, scenario, deployments, eid),
        treasury_sui: get_balance<SUI>(scenario, treasury_address),
        treasury_zro: get_balance<ZRO>(scenario, treasury_address),
    }
}

public fun assert_worker_treasury_received_fees(snapshot: &BalanceSnapshot, pay_in_zro: bool) {
    if (pay_in_zro) {
        assert!(snapshot.treasury_zro > 0, 100);
        assert!(snapshot.treasury_sui == 0, 101);
    } else {
        assert!(snapshot.treasury_sui > 0, 102);
        assert!(snapshot.treasury_zro == 0, 103);
    };

    assert!(snapshot.executor_sui > 0, 105);
    snapshot.dvn_sui_balances.do!(|balance| {
        assert!(balance > 0, 104);
    });
}
