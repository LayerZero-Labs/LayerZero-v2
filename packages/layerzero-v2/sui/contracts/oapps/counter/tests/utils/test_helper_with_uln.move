// This module will be shared with other oapp test modules.
#[test_only]
module counter::test_helper_with_uln;

use call::{call::Call, call_cap};
use counter::{deployments::Deployments, scenario_utils};
use dvn::{dvn::DVN, hashes as dvn_hashes};
use dvn_fee_lib::dvn_fee_lib::DvnFeeLib;
use endpoint_v2::{
    endpoint_quote::QuoteParam as EndpointQuoteParam,
    endpoint_send::SendParam as EndpointSendParam,
    endpoint_v2::{Self, EndpointV2, AdminCap},
    message_lib_type,
    messaging_channel::MessagingChannel,
    messaging_fee::MessagingFee,
    messaging_receipt::MessagingReceipt,
    utils
};
use executor::{executor_type, executor_worker::Executor};
use executor_fee_lib::executor_fee_lib::ExecutorFeeLib;
use message_lib_common::packet_v1_codec::{Self, PacketHeader};
use price_feed::price_feed::{PriceFeed, OwnerCap, PriceUpdaterCap};
use sui::{address, clock::{Self, Clock}, ecdsa_k1, test_scenario::{Self, Scenario}, test_utils};
use treasury::treasury::{Treasury, AdminCap as TreasuryAdminCap};
use uln_302::{executor_config, receive_uln::Verification, uln_302::{Self, Uln302, AdminCap as UlnAdminCap}, uln_config};
use utils::{buffer_reader, bytes32::Bytes32, hash};
use worker_common::worker_common::AdminCap as WorkerAdminCap;
use worker_registry::worker_registry;

const TREASURY_ZRO_FEE: u64 = 1000000;
const TREASURY_NATIVE_FEE_BP: u64 = 100; // 1%
const DVN_DEFAULT_MULTIPLIER_BPS: u16 = 10000; // 100%
const DVN_GAS: u256 = 100000;
const DVN_MULTIPLER_BPS: u16 = 10000;
const DVN_FLOOR_MARGIN_USD: u128 = 1000000000000000000;
const EXECUTOR_DEFAULT_MULTIPLIER_BPS: u16 = 10000; // 100%
const EXECUTOR_LZ_RECEIVE_BASE_GAS: u64 = 100000;
const EXECUTOR_LZ_COMPOSE_BASE_GAS: u64 = 100000;
const EXECUTOR_MULTIPLER_BPS: u16 = 10000;
const EXECUTOR_FLOOR_MARGIN_USD: u128 = 1000000000000000000;
const EXECUTOR_NATIVE_CAP: u128 = 1000000000000000000;
const PRICE_FEED_RATIO: u128 = 1000000000000000000;
const PRICE_FEED_GAS_PRICE_IN_UNIT: u64 = 10000000;
const PRICE_FEED_GAS_PER_BYTE: u32 = 100;

// === Helper Functions ===

// common usage pass `x"dvn"` as prefix
public fun create_address(prefix: vector<u8>, index: u8): address {
    assert!(prefix.length() <= 31, 100);
    let mut addr_bytes = vector::empty<u8>();
    let prefix_length = prefix.length();

    // Add your prefix pattern (e.g., 0xd0 for "dvn")
    prefix.do!(|e| {
        vector::push_back(&mut addr_bytes, e);
    });

    // Add zeros for padding
    let mut i = 0;
    while (i < (31 - prefix_length)) {
        vector::push_back(&mut addr_bytes, 0x00);
        i = i + 1;
    };

    // Add the index as the last byte
    vector::push_back(&mut addr_bytes, index);

    // Convert to address
    address::from_bytes(addr_bytes)
}

/// Generate a test keypair from an index value
/// Creates a 32-byte seed by padding the index value with zeros
public fun generate_test_keypair_from_index(index: u64): ecdsa_k1::KeyPair {
    // Create a 32-byte seed from the index parameter
    let mut seed = vector::empty<u8>();

    // Pad with zeros (31 bytes)
    let mut i = 0;
    while (i < 31) {
        vector::push_back(&mut seed, 0u8);
        i = i + 1;
    };

    // Add the index as the last byte (assuming index is small enough to fit in one byte)
    vector::push_back(&mut seed, (index as u8));

    ecdsa_k1::secp256k1_keypair_from_seed(&seed)
}

// === Public Functions ===

/// Setup a single endpoint
public fun setup_endpoint(scenario: &mut Scenario, sender: address, eid: u32, deployments: &mut Deployments) {
    endpoint_v2::init_for_test(scenario.ctx());
    scenario.next_tx(sender);
    let endpoint_admin_cap = scenario.take_from_sender<AdminCap>();
    let mut endpoint = scenario.take_shared<EndpointV2>();
    endpoint.init_eid(&endpoint_admin_cap, eid);

    deployments.set_deployment<EndpointV2>(eid, object::id_address(&endpoint));
    deployments.set_deployment<AdminCap>(eid, object::id_address(&endpoint_admin_cap));

    test_scenario::return_shared<EndpointV2>(endpoint);
    scenario.return_to_sender<AdminCap>(endpoint_admin_cap);
}

/// Setup Treasury for ULN302
public fun setup_treasury(scenario: &mut Scenario, sender: address, eid: u32, deployments: &mut Deployments) {
    setup_treasury_with_config(scenario, sender, eid, deployments, false);
}

/// Setup Treasury with configurable ZRO fee
public fun setup_treasury_with_config(
    scenario: &mut Scenario,
    sender: address,
    eid: u32,
    deployments: &mut Deployments,
    enable_zro_fee: bool,
) {
    scenario.next_tx(sender);
    treasury::treasury::init_for_test(scenario.ctx());

    scenario.next_tx(sender);
    let mut treasury = scenario.take_shared<Treasury>();
    let treasury_admin_cap = scenario.take_from_sender<TreasuryAdminCap>();

    let fee_recipient = create_address(b"treasury", 0);
    treasury.set_fee_recipient(&treasury_admin_cap, fee_recipient);

    // Configure treasury based on enable_zro_fee parameter
    if (enable_zro_fee) {
        treasury.set_fee_enabled(&treasury_admin_cap, true);
        treasury.set_zro_enabled(&treasury_admin_cap, true);
        treasury.set_zro_fee(&treasury_admin_cap, TREASURY_ZRO_FEE); // 0.001 ZRO
        treasury.set_native_fee_bp(&treasury_admin_cap, 0); // No native fee when using ZRO
    } else {
        treasury.set_fee_enabled(&treasury_admin_cap, true);
        treasury.set_zro_enabled(&treasury_admin_cap, false);
        treasury.set_native_fee_bp(&treasury_admin_cap, TREASURY_NATIVE_FEE_BP); // 1% native fee
    };

    deployments.set_deployment<Treasury>(eid, object::id_address(&treasury));

    test_scenario::return_shared<Treasury>(treasury);
    scenario.return_to_sender<TreasuryAdminCap>(treasury_admin_cap);
}

/// Setup PriceFeed for the specified endpoint
public fun setup_price_feed(
    scenario: &mut Scenario,
    sender: address,
    eid: u32,
    remote_eids: vector<u32>,
    price_ratio: u128,
    gas_price_in_unit: u64,
    gas_per_byte: u32,
    deployments: &mut Deployments,
): address {
    scenario.next_tx(sender);
    price_feed::price_feed::init_for_test(scenario.ctx());

    scenario.next_tx(sender);
    let price_feed_owner_cap = scenario.take_from_sender<OwnerCap>();
    let mut price_feed = scenario.take_shared<PriceFeed>();

    let price_feed_callcap = price_feed.get_call_cap().id();

    // Set sender as price updater
    price_feed.set_price_updater(&price_feed_owner_cap, sender, true, scenario.ctx());

    deployments.set_deployment<PriceFeed>(eid, object::id_address(&price_feed));
    deployments.set_deployment<OwnerCap>(eid, object::id_address(&price_feed_owner_cap));

    test_scenario::return_to_sender(scenario, price_feed_owner_cap);
    test_scenario::return_shared(price_feed);

    // Get the price updater capability and set prices
    scenario.next_tx(sender);
    let updater_cap = scenario.take_from_sender<PriceUpdaterCap>();
    let mut price_feed = scenario.take_shared<PriceFeed>();

    // Set default prices for all chains (needed for fee calculation)
    // Create price updates for test chains
    // Test uses EID 1 and 2 which remain as 1 and 2 after % 30000
    remote_eids.do!(|dst_eid| {
        if (dst_eid != eid) {
            price_feed.set_price(
                &updater_cap,
                dst_eid % 30000,
                price_feed::price_feed::create_price(price_ratio, gas_price_in_unit, gas_per_byte),
            );
        }
    });

    test_scenario::return_to_sender(scenario, updater_cap);

    test_scenario::return_shared<PriceFeed>(price_feed);

    price_feed_callcap
}

/// Setup DVN and DVN Fee Library with ULN302 address
public fun setup_dvn_with_uln(
    scenario: &mut Scenario,
    sender: address,
    eid: u32,
    index: u64,
    remote_eids: vector<u32>,
    price_feed_address: address,
    uln302_address: address,
    deployments: &mut Deployments,
): address {
    // Return worker cap address
    // Setup DVN Fee Library first
    scenario.next_tx(sender);
    dvn_fee_lib::dvn_fee_lib::init_for_test(scenario.ctx());

    scenario.next_tx(sender);
    let dvn_fee_lib = scenario.take_shared<DvnFeeLib>();

    // Create DVN
    scenario.next_tx(sender);
    let vid = 1; // DVN ID
    let deposit_address = create_address(b"dvn", index as u8);
    let worker_fee_lib_cap = dvn_fee_lib.get_call_cap().id();
    let default_multiplier_bps = DVN_DEFAULT_MULTIPLIER_BPS; // 100%
    let admins = vector[sender];

    // Create a test keypair for DVN signing using the index
    let test_keypair = generate_test_keypair_from_index(index);
    // KeyPair.public_key() returns compressed pubkey (33 bytes), decompress to get 65 bytes
    let uncompressed_pubkey = ecdsa_k1::decompress_pubkey(test_keypair.public_key());
    // Remove the first byte (0x04 prefix for uncompressed) to get 64 bytes
    let signer_pubkey = vector::tabulate!(64, |i| uncompressed_pubkey[i + 1]);

    let initial_signers = vector[signer_pubkey]; // Use real pubkey for testing
    let quorum = 1;

    let dvn_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let supported_message_libs = vector[uln302_address]; // Support ULN302
    let mut worker_registry = worker_registry::init_for_test(scenario.ctx());

    dvn::dvn::create_dvn(
        dvn_cap,
        vid,
        deposit_address,
        supported_message_libs,
        price_feed_address,
        worker_fee_lib_cap,
        default_multiplier_bps,
        admins,
        initial_signers,
        quorum,
        &mut worker_registry,
        scenario.ctx(),
    );

    test_utils::destroy(worker_registry);
    scenario.next_tx(sender);
    let mut dvn = scenario.take_shared<DVN>();
    let admin_cap = scenario.take_from_sender<WorkerAdminCap>();

    // Get worker cap address before setting in fee library
    let dvn_worker_cap_address = dvn.worker_cap_address();

    remote_eids.do!(|dst_eid| {
        if (dst_eid != eid) {
            dvn.set_dst_config(&admin_cap, dst_eid, DVN_GAS, DVN_MULTIPLER_BPS, DVN_FLOOR_MARGIN_USD);
        };
    });

    deployments.set_indexed_deployment<DVN>(eid, index, object::id_address(&dvn));
    deployments.set_indexed_deployment<DvnFeeLib>(eid, index, object::id_address(&dvn_fee_lib));

    test_scenario::return_shared<DVN>(dvn);
    test_scenario::return_shared<DvnFeeLib>(dvn_fee_lib);
    scenario.return_to_sender<WorkerAdminCap>(admin_cap);

    // Return the worker cap address for ULN configuration
    dvn_worker_cap_address
}

/// Setup Executor and Executor Fee Library with ULN302 address
public fun setup_executor_with_uln(
    scenario: &mut Scenario,
    sender: address,
    eid: u32,
    remote_eids: vector<u32>,
    price_feed_address: address,
    uln302_address: address,
    deployments: &mut Deployments,
): address {
    // Return worker cap address
    // Setup Executor Fee Library first
    scenario.next_tx(sender);
    executor_fee_lib::executor_fee_lib::init_for_test(scenario.ctx());

    scenario.next_tx(sender);
    let executor_fee_lib = scenario.take_shared<ExecutorFeeLib>();

    // Create Executor
    scenario.next_tx(sender);
    let deposit_address = create_address(b"executor", 0);
    let worker_fee_lib_cap = executor_fee_lib.get_call_cap().id();
    let default_multiplier_bps = EXECUTOR_DEFAULT_MULTIPLIER_BPS; // 100%
    let role_admin = sender;
    let admins = vector[sender];

    //create a executpr cap for executor

    let executor_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let supported_message_libs = vector[uln302_address]; // Support ULN302
    let mut worker_registry = worker_registry::init_for_test(scenario.ctx());

    executor::executor_worker::create_executor(
        executor_cap,
        deposit_address,
        supported_message_libs,
        price_feed_address,
        worker_fee_lib_cap,
        default_multiplier_bps,
        role_admin,
        admins,
        &mut worker_registry,
        scenario.ctx(),
    );

    test_utils::destroy(worker_registry);

    scenario.next_tx(sender);
    let mut executor = scenario.take_shared<Executor>();
    let admin_cap = scenario.take_from_sender<WorkerAdminCap>();

    // Set destination configurations for each remote endpoint
    remote_eids.do!(|dst_eid| {
        if (dst_eid != eid) {
            let dst_config = executor_type::create_dst_config(
                EXECUTOR_LZ_RECEIVE_BASE_GAS,
                EXECUTOR_LZ_COMPOSE_BASE_GAS,
                EXECUTOR_MULTIPLER_BPS,
                EXECUTOR_FLOOR_MARGIN_USD,
                EXECUTOR_NATIVE_CAP,
            );
            executor.set_dst_config(&admin_cap, dst_eid, dst_config);
        }
    });

    // Get worker cap address
    let executor_worker_cap_address = executor.worker_cap_address();

    deployments.set_deployment<Executor>(eid, object::id_address(&executor));
    deployments.set_deployment<ExecutorFeeLib>(eid, object::id_address(&executor_fee_lib));

    test_scenario::return_shared<Executor>(executor);
    test_scenario::return_shared<ExecutorFeeLib>(executor_fee_lib);
    scenario.return_to_sender<WorkerAdminCap>(admin_cap);

    // Return the worker cap address for ULN configuration
    executor_worker_cap_address
}

/// Setup ULN302 only (without worker configuration)
public fun setup_uln_only(
    scenario: &mut Scenario,
    sender: address,
    eid: u32,
    remote_eids: vector<u32>,
    deployments: &mut Deployments,
    test_clock: &Clock,
): address {
    scenario.next_tx(sender);
    let endpoint_admin_cap = scenario_utils::take_from_sender_by_address<AdminCap>(
        scenario,
        deployments.get_deployment<AdminCap>(eid),
    );
    let mut endpoint = scenario_utils::take_shared_by_address<EndpointV2>(
        scenario,
        deployments.get_deployment<EndpointV2>(eid),
    );

    // Initialize ULN302
    uln_302::init_for_test(scenario.ctx());

    scenario.next_tx(sender);
    let uln_admin_cap = scenario.take_from_sender<UlnAdminCap>();
    let uln = scenario.take_shared<Uln302>();

    let message_lib_id = uln.get_call_cap().id();
    // Register library with endpoint
    endpoint.register_library(
        &endpoint_admin_cap,
        message_lib_id,
        message_lib_type::send_and_receive(),
    );

    // Set up default library configurations for remote endpoints
    remote_eids.do!(|dst_eid| {
        if (dst_eid != endpoint.eid()) {
            // Configure the endpoint to use ULN302
            endpoint_v2::set_default_send_library(&mut endpoint, &endpoint_admin_cap, dst_eid, message_lib_id);
            endpoint_v2::set_default_receive_library(
                &mut endpoint,
                &endpoint_admin_cap,
                dst_eid,
                message_lib_id,
                0,
                test_clock,
            );
        };
    });

    deployments.set_deployment<Uln302>(eid, object::id_address(&uln));

    scenario.return_to_sender<AdminCap>(endpoint_admin_cap);
    scenario.return_to_sender<UlnAdminCap>(uln_admin_cap);
    test_scenario::return_shared<EndpointV2>(endpoint);
    test_scenario::return_shared<Uln302>(uln);

    message_lib_id
}

/// Configure ULN302 with worker addresses and settings
public fun configure_uln_workers(
    scenario: &mut Scenario,
    sender: address,
    eid: u32,
    remote_eids: vector<u32>,
    required_dvn_cap_addresses: vector<address>,
    optional_dvn_cap_addresses: vector<address>,
    optional_dvn_threshold: u8,
    executor_worker_cap_address: address,
    deployments: &mut Deployments,
) {
    scenario.next_tx(sender);
    let uln_admin_cap = scenario.take_from_sender<UlnAdminCap>();
    let mut uln = scenario_utils::take_shared_by_address<Uln302>(
        scenario,
        deployments.get_deployment<Uln302>(eid),
    );

    // Set up worker configurations for remote endpoints using worker cap addresses
    remote_eids.do!(|dst_eid| {
        if (dst_eid != eid) {
            // Set default executor config with worker cap address
            let executor_config = executor_config::create(1000000, executor_worker_cap_address); // max_message_size, executor
            uln.set_default_executor_config(&uln_admin_cap, dst_eid, executor_config);

            // Set default ULN config for sending with DVN worker cap address
            let uln_config = uln_config::create(
                1, // confirmations
                required_dvn_cap_addresses, // required_dvns using worker cap address
                if (optional_dvn_threshold == 0) {
                    vector[]
                } else {
                    optional_dvn_cap_addresses
                }, // optional_dvns using worker cap address
                optional_dvn_threshold, // optional_dvn_threshold
            );
            uln.set_default_send_uln_config(&uln_admin_cap, dst_eid, uln_config);

            // Also set default ULN config for receiving from this endpoint
            // Using the same config for receiving as for sending
            uln.set_default_receive_uln_config(&uln_admin_cap, dst_eid, uln_config);
        };
    });

    scenario.return_to_sender<UlnAdminCap>(uln_admin_cap);
    test_scenario::return_shared<Uln302>(uln);
}

/// Setup multiple endpoints with corresponding ULN302 and workers with configurable treasury
public fun setup_endpoint_with_uln_and_treasury(
    scenario: &mut Scenario,
    required_dvns: u64,
    optional_dvns: u64,
    optional_dvn_threshold: u8,
    sender: address,
    eids: vector<u32>,
    deployments: &mut Deployments,
    test_clock: &Clock,
    enable_zro_fee: bool,
) {
    eids.do!(|eid| {
        setup_endpoint(scenario, sender, eid, deployments);
        setup_treasury_with_config(scenario, sender, eid, deployments, enable_zro_fee);
        let price_feed_callcap = setup_price_feed(
            scenario,
            sender,
            eid,
            eids,
            PRICE_FEED_RATIO, // price_ratio
            PRICE_FEED_GAS_PRICE_IN_UNIT, // gas_price_in_unit
            PRICE_FEED_GAS_PER_BYTE, // gas_per_byte
            deployments,
        );
        let uln302_address = setup_uln_only(scenario, sender, eid, eids, deployments, test_clock);
        let executor_worker_cap_address = setup_executor_with_uln(
            scenario,
            sender,
            eid,
            eids,
            price_feed_callcap,
            uln302_address,
            deployments,
        );

        let required_dvn_cap_addresses = vector::tabulate!(required_dvns, |i| {
            setup_dvn_with_uln(
                scenario,
                sender,
                eid,
                i,
                eids,
                price_feed_callcap,
                uln302_address,
                deployments,
            )
        });
        let optional_dvn_cap_addresses = vector::tabulate!(optional_dvns, |i| {
            setup_dvn_with_uln(
                scenario,
                sender,
                eid,
                i + required_dvns,
                eids,
                price_feed_callcap,
                uln302_address,
                deployments,
            )
        });
        configure_uln_workers(
            scenario,
            sender,
            eid,
            eids,
            required_dvn_cap_addresses,
            optional_dvn_cap_addresses,
            optional_dvn_threshold,
            executor_worker_cap_address,
            deployments,
        );
    });
}

/// Quote function for ULN302 workflow
public fun quote(
    endpoint: &EndpointV2,
    uln: &Uln302,
    treasury: &Treasury,
    messaging_channel: &MessagingChannel,
    executor: &Executor,
    executor_fee_lib: &ExecutorFeeLib,
    price_feed: &PriceFeed,
    dvns: &vector<DVN>,
    dvn_fee_libs: &vector<DvnFeeLib>,
    quote_call: &mut Call<EndpointQuoteParam, MessagingFee>,
    ctx: &mut TxContext,
) {
    // Step 1: Endpoint processes quote and creates message lib call
    let mut message_lib_call = endpoint.quote(messaging_channel, quote_call, ctx);

    // Step 2: ULN302 processes the quote and creates worker calls
    let (mut executor_call, mut dvn_multi_call) = uln.quote(&mut message_lib_call, ctx);

    // Step 3: Handle Executor fee calculation
    // Executor -> ExecutorFeeLib -> PriceFeed

    // Executor calls its fee lib
    let mut executor_feelib_call = executor.get_fee(&mut executor_call, ctx);

    // ExecutorFeeLib calls PriceFeed
    let mut executor_price_feed_call = executor_fee_lib.get_fee(&mut executor_feelib_call, ctx);

    // PriceFeed processes the call
    price_feed.estimate_fee_by_eid(&mut executor_price_feed_call);

    // Results flow back: PriceFeed -> ExecutorFeeLib -> Executor
    executor_fee_lib.confirm_get_fee(&mut executor_feelib_call, executor_price_feed_call);
    executor.confirm_get_fee(&mut executor_call, executor_feelib_call);

    // Step 4: Handle DVN fee calculations (for each DVN)
    // Each DVN -> DvnFeeLib -> PriceFeed

    dvns.length().do!(|i| {
        let dvn = dvns.borrow(i);
        let dvn_fee_lib = dvn_fee_libs.borrow(i);
        // Check using the DVN's worker cap address, not the object address
        let mut dvn_fee_call = dvn.get_fee(&mut dvn_multi_call, ctx);
        let mut dvn_fee_lib_call = dvn_fee_lib.get_fee(&mut dvn_fee_call, ctx);
        price_feed.estimate_fee_by_eid(&mut dvn_fee_lib_call);
        dvn_fee_lib.confirm_get_fee(&mut dvn_fee_call, dvn_fee_lib_call);
        dvn.confirm_get_fee(&mut dvn_multi_call, dvn_fee_call);
    });

    // Step 5: Complete ULN quote
    uln.confirm_quote(treasury, &mut message_lib_call, executor_call, dvn_multi_call);

    // Step 6: Endpoint confirms quote
    endpoint.confirm_quote(quote_call, message_lib_call);
}

/// Execute the complete send call chain: endpoint.send -> ULN302.send -> Workers
public fun execute_send_call(
    scenario: &mut Scenario,
    sender: address,
    deployments: &Deployments,
    dvn_indexes: vector<u64>, // with this, we can control the DVNs we want to use, so we can test good cases and bad cases
    src_eid: u32,
    mut counter_call: Call<EndpointSendParam, MessagingReceipt>,
) {
    scenario.next_tx(sender); // Advance transaction to ensure shared objects are available
    let endpoint = scenario_utils::take_shared_by_address<EndpointV2>(
        scenario,
        deployments.get_deployment<EndpointV2>(src_eid),
    );
    let uln = scenario_utils::take_shared_by_address<Uln302>(
        scenario,
        deployments.get_deployment<Uln302>(src_eid),
    );
    let treasury = scenario_utils::take_shared_by_address<Treasury>(
        scenario,
        deployments.get_deployment<Treasury>(src_eid),
    );
    let mut messaging_channel = scenario_utils::take_shared_by_address<MessagingChannel>(
        scenario,
        deployments.get_deployment<MessagingChannel>(src_eid),
    );

    // Step 1: Endpoint processes the counter call and returns ULN302 call
    let mut uln_call = endpoint.send(&mut messaging_channel, &mut counter_call, scenario.ctx());

    // Step 2: ULN302 processes the call and creates worker calls
    let (mut executor_call, mut dvn_multi_call) = uln.send(&mut uln_call, scenario.ctx());

    // Step 3: Handle Executor job assignment and fee calculation
    // Executor -> ExecutorFeeLib -> PriceFeed
    let executor = scenario_utils::take_shared_by_address<Executor>(
        scenario,
        deployments.get_deployment<Executor>(src_eid),
    );
    let executor_fee_lib = scenario_utils::take_shared_by_address<ExecutorFeeLib>(
        scenario,
        deployments.get_deployment<ExecutorFeeLib>(src_eid),
    );
    let price_feed = scenario_utils::take_shared_by_address<PriceFeed>(
        scenario,
        deployments.get_deployment<PriceFeed>(src_eid),
    );

    // Executor assigns job and calls its fee lib
    let mut executor_feelib_call = executor.assign_job(&mut executor_call, scenario.ctx());

    // ExecutorFeeLib calls PriceFeed
    let mut executor_price_feed_call = executor_fee_lib.get_fee(&mut executor_feelib_call, scenario.ctx());

    // PriceFeed processes the call
    price_feed.estimate_fee_by_eid(&mut executor_price_feed_call);

    // Results flow back: PriceFeed -> ExecutorFeeLib -> Executor
    executor_fee_lib.confirm_get_fee(&mut executor_feelib_call, executor_price_feed_call);
    executor.confirm_assign_job(&mut executor_call, executor_feelib_call);

    let mut dvns = vector::tabulate!(dvn_indexes.length(), |i| {
        scenario_utils::take_shared_by_address<DVN>(
            scenario,
            deployments.get_indexed_deployment<DVN>(src_eid, dvn_indexes[i]),
        )
    });
    let mut dvn_fee_libs = vector::tabulate!(dvn_indexes.length(), |i| {
        scenario_utils::take_shared_by_address<DvnFeeLib>(
            scenario,
            deployments.get_indexed_deployment<DvnFeeLib>(src_eid, dvn_indexes[i]),
        )
    });
    dvns.length().do!(|i| {
        let dvn = dvns.borrow_mut(i);
        let dvn_fee_lib = dvn_fee_libs.borrow_mut(i);
        // Check using the DVN's worker cap address, not the object address
        let mut dvn_job_call = dvn.assign_job(&mut dvn_multi_call, scenario.ctx());
        let mut dvn_fee_lib_call = dvn_fee_lib.get_fee(&mut dvn_job_call, scenario.ctx());
        price_feed.estimate_fee_by_eid(&mut dvn_fee_lib_call);
        dvn_fee_lib.confirm_get_fee(&mut dvn_job_call, dvn_fee_lib_call);
        dvn.confirm_assign_job(&mut dvn_multi_call, dvn_job_call);
    });

    // Step 5: ULN302 confirms send with worker results
    uln.confirm_send(
        &endpoint,
        &treasury,
        &mut messaging_channel,
        &mut counter_call,
        uln_call,
        executor_call,
        dvn_multi_call,
        scenario.ctx(),
    );

    // Step 6: Endpoint refund
    endpoint.refund(counter_call);

    // Return shared objects
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
}

/// Verify message packet with ULN302 and DVN verification
public fun verify_message(
    scenario: &mut Scenario,
    sender: address,
    dvn_indexes: vector<u64>,
    encoded_packet: vector<u8>,
    deployments: &Deployments,
    eid: u32,
    test_clock: &Clock,
) {
    scenario.next_tx(sender);
    let endpoint = scenario_utils::take_shared_by_address<EndpointV2>(
        scenario,
        deployments.get_deployment<EndpointV2>(eid),
    );
    let uln = scenario_utils::take_shared_by_address<Uln302>(
        scenario,
        deployments.get_deployment<Uln302>(eid),
    );
    let mut dvns = vector::tabulate!(dvn_indexes.length(), |i| {
        scenario_utils::take_shared_by_address<DVN>(
            scenario,
            deployments.get_indexed_deployment<DVN>(eid, dvn_indexes[i]),
        )
    });
    // Get AdminCaps for DVN verification
    let admin_caps = vector::tabulate!(dvn_indexes.length(), |i| {
        let dvn = dvns.borrow_mut(i);
        scenario_utils::take_from_sender_by_address<WorkerAdminCap>(scenario, dvn.admin_cap_id(sender))
    });
    let mut messaging_channel = scenario_utils::take_shared_by_address<MessagingChannel>(
        scenario,
        deployments.get_deployment<MessagingChannel>(eid),
    );

    let (header, guid, message) = decode_packet_for_test(encoded_packet);
    let payload_hash = hash::keccak256!(&utils::build_payload(guid, message));

    // Get the shared verification object created during ULN302 initialization
    let mut verification = scenario_utils::take_shared_by_address<Verification>(
        scenario,
        uln.get_verification(),
    );

    // DVN verifies the packet with proper test signatures
    let confirmations = 1;
    let expiration = clock::timestamp_ms(test_clock) + 3600000; // 1 hour from now

    // Create the same payload that DVN will verify
    let vid = 1; // DVN ID (must match the one used in setup_dvn_with_uln)

    // The DVN verification target should be the ULN302 call cap address (consistent with registration)
    let dvn_uln302_address = uln.get_call_cap().id();

    let payload = dvn_hashes::build_verify_payload(
        header.encode_header(),
        payload_hash.to_bytes(),
        confirmations,
        dvn_uln302_address,
        vid,
        expiration,
    );

    // Create signatures using the same test keypair used in DVN setup
    dvn_indexes.length().do!(|i| {
        let dvn = dvns.borrow_mut(i);
        let admin_cap = admin_caps.borrow(i);
        let dvn_index = dvn_indexes[i];

        let test_keypair = generate_test_keypair_from_index(dvn_index);
        let signature = ecdsa_k1::secp256k1_sign(
            test_keypair.private_key(),
            &payload,
            0, // KECCAK256 hash function
            true, // recoverable signature (65 bytes with recovery id)
        );

        let verification_call = dvn.verify(
            admin_cap,
            dvn_uln302_address,
            header.encode_header(),
            payload_hash,
            confirmations,
            expiration,
            signature,
            test_clock,
            scenario.ctx(),
        );
        uln.verify(&mut verification, verification_call);
    });

    // ULN302 commits verification
    uln.commit_verification(
        &mut verification,
        &endpoint,
        &mut messaging_channel,
        header.encode_header(),
        payload_hash,
        test_clock,
    );

    // Return the shared verification object
    test_scenario::return_shared<Verification>(verification);
    test_scenario::return_shared<EndpointV2>(endpoint);
    test_scenario::return_shared<Uln302>(uln);
    dvns.do!(|dvn| {
        test_scenario::return_shared<DVN>(dvn);
    });
    admin_caps.do!(|admin_cap| {
        scenario.return_to_sender<WorkerAdminCap>(admin_cap);
    });
    test_scenario::return_shared<MessagingChannel>(messaging_channel);
}

fun decode_packet_for_test(encoded: vector<u8>): (PacketHeader, Bytes32, vector<u8>) {
    let mut reader = buffer_reader::create(encoded);
    let header = packet_v1_codec::decode_header(reader.read_fixed_len_bytes(81));
    let guid = reader.read_bytes32();
    let message = reader.read_bytes_until_end();
    (header, guid, message)
}
