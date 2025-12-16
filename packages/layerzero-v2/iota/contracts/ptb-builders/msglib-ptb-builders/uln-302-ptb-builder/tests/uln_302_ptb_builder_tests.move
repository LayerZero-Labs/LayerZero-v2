#[test_only]
module uln_302_ptb_builder::uln_302_ptb_builder_tests;

use call::{call::{Self, Call, Void}, call_cap::{Self, CallCap}};
use endpoint_v2::{
    endpoint_v2::{Self, EndpointV2, AdminCap as EndpointAdminCap},
    message_lib_quote::{Self, QuoteParam},
    message_lib_send::{Self, SendParam, SendResult},
    messaging_fee::MessagingFee,
    outbound_packet
};
use msglib_ptb_builder_call_types::set_worker_ptb::{Self, SetWorkerPtbParam};
use ptb_move_call::{argument, move_call::{Self, MoveCall}};
use std::{ascii, bcs};
use iota::{test_scenario, test_utils};
use treasury::treasury::{Self, Treasury};
use uln_302::{executor_config, uln_302::{Self, Uln302, AdminCap as Uln302AdminCap}, uln_config};
use uln_302_ptb_builder::uln_302_ptb_builder::{Self, Uln302PtbBuilder};
use utils::{bytes32, package};

// === Test Constants ===

const ADMIN: address = @0xAD;
const WORKER1: address = @0x1111;
const WORKER2: address = @0x2222;

// EID constants
const SRC_EID: u32 = 101;
const DST_EID: u32 = 102;

// === Setup Functions ===

/// Setup test environment and return necessary objects
fun setup(): (test_scenario::Scenario, Uln302PtbBuilder) {
    let mut scenario = test_scenario::begin(ADMIN);

    // Initialize
    init_for_testing(test_scenario::ctx(&mut scenario));

    test_scenario::next_tx(&mut scenario, ADMIN);

    // Take shared objects
    let builder = test_scenario::take_shared<Uln302PtbBuilder>(&scenario);

    (scenario, builder)
}

/// Clean up test objects
fun clean(scenario: test_scenario::Scenario, builder: Uln302PtbBuilder) {
    test_scenario::return_shared(builder);
    test_scenario::end(scenario);
}

// === Helper Functions ===

/// Setup worker PTBs and return the worker's CallCap and address
fun setup_worker_ptbs(
    scenario: &mut test_scenario::Scenario,
    builder: &mut Uln302PtbBuilder,
    worker: address,
    get_fee_count: u64,
    assign_job_count: u64,
): (CallCap, address) {
    test_scenario::next_tx(scenario, worker);
    let worker_cap = call_cap::new_package_cap_for_test(test_scenario::ctx(scenario));
    let worker_address = worker_cap.id();

    let (get_fee_ptb, assign_job_ptb) = create_worker_ptbs(get_fee_count, assign_job_count);
    let call = mock_set_worker_ptb_call(
        &worker_cap,
        package::original_package_of_type<uln_302_ptb_builder::Uln302PtbBuilder>(),
        get_fee_ptb,
        assign_job_ptb,
        test_scenario::ctx(scenario),
    );

    builder.set_worker_ptbs(call);

    (worker_cap, worker_address)
}

/// Setup worker PTBs for integration tests - creates worker and immediately destroys cap
fun setup_worker_for_integration(
    scenario: &mut test_scenario::Scenario,
    builder: &mut Uln302PtbBuilder,
    get_fee_count: u64,
    assign_job_count: u64,
): address {
    let worker_cap = call_cap::new_package_cap_for_test(test_scenario::ctx(scenario));
    let worker_address = worker_cap.id();

    let (get_fee_ptb, assign_job_ptb) = create_worker_ptbs(get_fee_count, assign_job_count);
    let call = mock_set_worker_ptb_call(
        &worker_cap,
        package::original_package_of_type<uln_302_ptb_builder::Uln302PtbBuilder>(),
        get_fee_ptb,
        assign_job_ptb,
        test_scenario::ctx(scenario),
    );

    builder.set_worker_ptbs(call);
    test_utils::destroy(worker_cap);

    worker_address
}

fun create_test_move_calls(count: u64, prefix: vector<u8>): vector<MoveCall> {
    let mut calls = vector[];
    let mut i = 0;
    while (i < count) {
        calls.push_back(
            move_call::create(
                @0x123,
                ascii::string(prefix),
                ascii::string(b"test_function"),
                vector[argument::create_pure(bcs::to_bytes(&i))],
                vector[],
                false,
                vector[],
            ),
        );
        i = i + 1;
    };
    calls
}

fun create_worker_ptbs(fee_count: u64, job_count: u64): (vector<MoveCall>, vector<MoveCall>) {
    let get_fee_ptb = create_test_move_calls(fee_count, b"fee_module");
    let assign_job_ptb = create_test_move_calls(job_count, b"job_module");
    (get_fee_ptb, assign_job_ptb)
}

fun mock_set_worker_ptb_call(
    caller_cap: &CallCap,
    target: address,
    get_fee_ptb: vector<MoveCall>,
    assign_job_ptb: vector<MoveCall>,
    ctx: &mut tx_context::TxContext,
): Call<SetWorkerPtbParam, Void> {
    let param = set_worker_ptb::create_param(get_fee_ptb, assign_job_ptb);
    call::create(
        caller_cap,
        target, // This is the callee (builder)
        true, // one_way
        param,
        ctx,
    )
}

// === Test Only Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    uln_302_ptb_builder::init_for_testing(ctx)
}

// === Init Tests ===

#[test]
fun test_init_creates_shared_object() {
    let mut scenario = test_scenario::begin(ADMIN);

    // Initialize module
    init_for_testing(test_scenario::ctx(&mut scenario));

    // Need next_tx as share_object happens at end of transaction
    test_scenario::next_tx(&mut scenario, ADMIN);
    assert!(test_scenario::has_most_recent_shared<Uln302PtbBuilder>(), 0);
    let builder = test_scenario::take_shared<Uln302PtbBuilder>(&scenario);
    assert!(object::id_address(&builder) != @0x0, 1);
    test_scenario::return_shared(builder);

    test_scenario::end(scenario);
}

// === Set Worker PTBs Tests ===

#[test]
fun test_set_worker_ptbs_single_worker() {
    let (mut scenario, mut builder) = setup();

    // Worker sets their PTBs
    let (worker_cap, worker_address) = setup_worker_ptbs(&mut scenario, &mut builder, WORKER1, 2, 3);

    // Verify
    assert!(builder.is_worker_ptbs_set(worker_address), 0);
    let stored = builder.get_worker_ptbs(worker_address);
    assert!(stored.get_fee_ptb().length() == 2, 1);
    assert!(stored.get_assign_job_ptb().length() == 3, 2);

    test_utils::destroy(worker_cap);
    clean(scenario, builder);
}

#[test]
fun test_set_worker_ptbs_multiple_workers() {
    let (mut scenario, mut builder) = setup();

    // Worker1 sets PTBs
    let (worker1_cap, worker1_address) = setup_worker_ptbs(&mut scenario, &mut builder, WORKER1, 2, 2);
    test_utils::destroy(worker1_cap);
    test_scenario::return_shared(builder);

    // Worker2 sets PTBs
    test_scenario::next_tx(&mut scenario, WORKER2);
    let mut builder = test_scenario::take_shared<Uln302PtbBuilder>(&scenario);
    let (worker2_cap, worker2_address) = setup_worker_ptbs(&mut scenario, &mut builder, WORKER2, 3, 4);
    test_utils::destroy(worker2_cap);
    test_scenario::return_shared(builder);

    // Verify both workers
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let builder = test_scenario::take_shared<Uln302PtbBuilder>(&scenario);

        assert!(builder.is_worker_ptbs_set(worker1_address), 0);
        assert!(builder.is_worker_ptbs_set(worker2_address), 1);

        let worker1_ptbs = builder.get_worker_ptbs(worker1_address);
        assert!(worker1_ptbs.get_fee_ptb().length() == 2, 2);
        assert!(worker1_ptbs.get_assign_job_ptb().length() == 2, 3);

        let worker2_ptbs = builder.get_worker_ptbs(worker2_address);
        assert!(worker2_ptbs.get_fee_ptb().length() == 3, 4);
        assert!(worker2_ptbs.get_assign_job_ptb().length() == 4, 5);

        test_scenario::return_shared(builder);
    };

    test_scenario::end(scenario);
}

#[test]
fun test_set_worker_ptbs_update_existing() {
    let (mut scenario, mut builder) = setup();

    // Initial set
    let (worker_cap, _) = setup_worker_ptbs(&mut scenario, &mut builder, WORKER1, 2, 3);
    test_utils::destroy(worker_cap);
    test_scenario::return_shared(builder);

    // Update with new values
    test_scenario::next_tx(&mut scenario, WORKER1);
    let mut builder = test_scenario::take_shared<Uln302PtbBuilder>(&scenario);
    let (worker_cap, updated_address) = setup_worker_ptbs(&mut scenario, &mut builder, WORKER1, 5, 7);

    // Verify update
    let updated = builder.get_worker_ptbs(updated_address);
    assert!(updated.get_fee_ptb().length() == 5, 0);
    assert!(updated.get_assign_job_ptb().length() == 7, 1);

    test_utils::destroy(worker_cap);
    test_scenario::return_shared(builder);

    test_scenario::end(scenario);
}

#[test]
fun test_set_worker_ptbs_empty_vectors() {
    let (mut scenario, mut builder) = setup();

    // Set empty PTBs
    let (worker_cap, worker_address) = setup_worker_ptbs(&mut scenario, &mut builder, WORKER1, 0, 0);

    // Verify empty vectors stored
    assert!(builder.is_worker_ptbs_set(worker_address), 0);
    let stored = builder.get_worker_ptbs(worker_address);
    assert!(stored.get_fee_ptb().is_empty(), 1);
    assert!(stored.get_assign_job_ptb().is_empty(), 2);

    test_utils::destroy(worker_cap);
    clean(scenario, builder);
}

// === View Function Tests ===

#[test]
#[expected_failure(abort_code = uln_302_ptb_builder::EWorkerPtbsNotFound)]
fun test_get_worker_ptbs_not_found() {
    let (scenario, builder) = setup();

    // This should abort
    builder.get_worker_ptbs(@0x999999);

    clean(scenario, builder);
}

// === Helper Functions ===

fun setup_modules(scenario: &mut test_scenario::Scenario) {
    // Initialize all required modules
    endpoint_v2::init_for_test(scenario.ctx());
    uln_302::init_for_test(scenario.ctx());
    treasury::init_for_test(scenario.ctx());
    init_for_testing(scenario.ctx());
}

fun setup_uln_with_workers(
    _scenario: &mut test_scenario::Scenario,
    uln302: &mut Uln302,
    uln_admin_cap: &Uln302AdminCap,
    _endpoint: &EndpointV2,
    executor: address,
    required_dvns: vector<address>,
    dst_eid: u32,
) {
    // Set executor config
    let executor_config = executor_config::create(65000u64, executor);
    uln_302::set_default_executor_config(uln302, uln_admin_cap, dst_eid, executor_config);

    // Set send ULN config
    let send_uln_config = uln_config::create(15u64, required_dvns, vector[], 0);
    uln_302::set_default_send_uln_config(uln302, uln_admin_cap, dst_eid, send_uln_config);
}

// === Build Function Tests ===

#[test]
fun test_get_ptb_builder_info() {
    let mut scenario = test_scenario::begin(ADMIN);

    // Initialize all modules
    setup_modules(&mut scenario);

    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let endpoint_admin_cap = scenario.take_from_sender<EndpointAdminCap>();
        let uln_admin_cap = scenario.take_from_sender<Uln302AdminCap>();
        let builder = test_scenario::take_shared<Uln302PtbBuilder>(&scenario);
        let mut endpoint = test_scenario::take_shared<EndpointV2>(&scenario);
        let uln302 = test_scenario::take_shared<Uln302>(&scenario);
        let treasury = test_scenario::take_shared<Treasury>(&scenario);

        // Initialize endpoint with EID
        endpoint_v2::init_eid(&mut endpoint, &endpoint_admin_cap, SRC_EID);

        // Get PTB builder info
        let info = builder.get_ptb_builder_info(&uln302, &treasury, &endpoint);

        // Verify info structure
        assert!(info.message_lib() == package::original_package_of_type<uln_302::Uln302>(), 0);
        assert!(info.ptb_builder() == package::original_package_of_type<uln_302_ptb_builder::Uln302PtbBuilder>(), 1);

        // Verify PTBs structure
        assert!(info.quote_ptb().length() == 1, 3); // One builder call
        assert!(info.send_ptb().length() == 1, 4); // One builder call
        assert!(!info.set_config_ptb().is_empty(), 5); // Has set config calls

        // Verify the builder calls point to build functions
        let quote_call = &info.quote_ptb()[0];
        assert!(quote_call.is_builder_call(), 6);
        assert!(quote_call.function().function_name() == ascii::string(b"build_quote_ptb"), 7);

        let send_call = &info.send_ptb()[0];
        assert!(send_call.is_builder_call(), 8);
        assert!(send_call.function().function_name() == ascii::string(b"build_send_ptb"), 9);

        scenario.return_to_sender(endpoint_admin_cap);
        scenario.return_to_sender(uln_admin_cap);
        test_scenario::return_shared(builder);
        test_scenario::return_shared(endpoint);
        test_scenario::return_shared(uln302);
        test_scenario::return_shared(treasury);
    };

    test_scenario::end(scenario);
}

#[test]
fun test_build_quote_ptb() {
    let mut scenario = test_scenario::begin(ADMIN);

    setup_modules(&mut scenario);

    // Set up workers
    let executor_addr;
    let dvn1_addr;
    let dvn2_addr;

    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let mut builder = test_scenario::take_shared<Uln302PtbBuilder>(&scenario);

        // Set up workers
        executor_addr = setup_worker_for_integration(&mut scenario, &mut builder, 2, 2);
        dvn1_addr = setup_worker_for_integration(&mut scenario, &mut builder, 1, 1);
        dvn2_addr = setup_worker_for_integration(&mut scenario, &mut builder, 2, 2);

        test_scenario::return_shared(builder);
    };

    // Test build_quote_ptb
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let endpoint_admin_cap = scenario.take_from_sender<EndpointAdminCap>();
        let uln_admin_cap = scenario.take_from_sender<Uln302AdminCap>();
        let builder = test_scenario::take_shared<Uln302PtbBuilder>(&scenario);
        let mut endpoint = test_scenario::take_shared<EndpointV2>(&scenario);
        let mut uln302 = test_scenario::take_shared<Uln302>(&scenario);
        let treasury = test_scenario::take_shared<Treasury>(&scenario);

        // Initialize endpoint
        endpoint_v2::init_eid(&mut endpoint, &endpoint_admin_cap, 101u32);

        // Setup ULN with workers
        setup_uln_with_workers(
            &mut scenario,
            &mut uln302,
            &uln_admin_cap,
            &endpoint,
            executor_addr,
            vector[dvn1_addr, dvn2_addr],
            DST_EID,
        );

        // Create a mock quote call
        let oapp_cap = call_cap::new_package_cap_for_test(test_scenario::ctx(&mut scenario));
        let packet = outbound_packet::create_for_test(
            1u64, // nonce
            SRC_EID,
            @0x111, // sender
            DST_EID,
            bytes32::from_address(@0x222), // receiver
            b"test message",
        );
        let quote_param = message_lib_quote::create_param_for_test(
            packet,
            x"0003", // options
            false, // pay_in_zro
        );
        let quote_call = call::create<QuoteParam, MessagingFee>(
            &oapp_cap,
            package::original_package_of_type<uln_302::Uln302>(),
            false, // two-way
            quote_param,
            test_scenario::ctx(&mut scenario),
        );

        // Build quote PTB
        let quote_ptb = builder.build_quote_ptb(&uln302, &treasury, &quote_call);

        // Verify PTB structure:
        // 1 (uln quote) + 2 (executor) + 1 (dvn1) + 2 (dvn2) + 1 (confirm) = 7
        assert!(quote_ptb.length() == 7, 0);

        // Verify first call is uln::quote
        let first_call = &quote_ptb[0];
        assert!(first_call.function().module_name() == ascii::string(b"uln_302"), 1);
        assert!(first_call.function().function_name() == ascii::string(b"quote"), 2);
        assert!(!first_call.is_builder_call(), 3);
        assert!(first_call.result_ids().length() == 2, 4); // executor and dvn calls

        // Verify last call is uln::confirm_quote
        let last_call = &quote_ptb[quote_ptb.length() - 1];
        assert!(last_call.function().module_name() == ascii::string(b"uln_302"), 5);
        assert!(last_call.function().function_name() == ascii::string(b"confirm_quote"), 6);
        assert!(!last_call.is_builder_call(), 7);

        test_utils::destroy(oapp_cap);
        test_utils::destroy(quote_call);
        scenario.return_to_sender(endpoint_admin_cap);
        scenario.return_to_sender(uln_admin_cap);
        test_scenario::return_shared(builder);
        test_scenario::return_shared(endpoint);
        test_scenario::return_shared(uln302);
        test_scenario::return_shared(treasury);
    };

    test_scenario::end(scenario);
}

#[test]
fun test_build_send_ptb() {
    let mut scenario = test_scenario::begin(ADMIN);

    setup_modules(&mut scenario);

    // Set up workers
    let executor_addr;
    let dvn_addr;

    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let mut builder = test_scenario::take_shared<Uln302PtbBuilder>(&scenario);

        // Set up workers
        executor_addr = setup_worker_for_integration(&mut scenario, &mut builder, 1, 3);
        dvn_addr = setup_worker_for_integration(&mut scenario, &mut builder, 1, 2);

        test_scenario::return_shared(builder);
    };

    // Test build_send_ptb
    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let endpoint_admin_cap = scenario.take_from_sender<EndpointAdminCap>();
        let uln_admin_cap = scenario.take_from_sender<Uln302AdminCap>();
        let builder = test_scenario::take_shared<Uln302PtbBuilder>(&scenario);
        let mut endpoint = test_scenario::take_shared<EndpointV2>(&scenario);
        let mut uln302 = test_scenario::take_shared<Uln302>(&scenario);
        let treasury = test_scenario::take_shared<Treasury>(&scenario);

        // Initialize endpoint and create messaging channel
        endpoint_v2::init_eid(&mut endpoint, &endpoint_admin_cap, 101u32);
        let oapp_cap = call_cap::new_package_cap_for_test(test_scenario::ctx(&mut scenario));
        endpoint.register_oapp(&oapp_cap, b"lz_receive_info", test_scenario::ctx(&mut scenario));

        // Setup ULN with workers
        setup_uln_with_workers(
            &mut scenario,
            &mut uln302,
            &uln_admin_cap,
            &endpoint,
            executor_addr,
            vector[dvn_addr],
            DST_EID,
        );

        // Create a mock send call
        let packet = outbound_packet::create_for_test(
            1u64, // nonce
            SRC_EID,
            oapp_cap.id(), // sender
            DST_EID,
            bytes32::from_address(@0x222), // receiver
            b"test message",
        );
        let quote_param = message_lib_quote::create_param_for_test(
            packet,
            x"0003", // options
            false, // pay_in_zro
        );
        let send_param = message_lib_send::create_param_for_test(quote_param);
        let send_call = call::create<SendParam, SendResult>(
            &oapp_cap,
            package::original_package_of_type<uln_302::Uln302>(),
            false, // two-way
            send_param,
            test_scenario::ctx(&mut scenario),
        );

        // Build send PTB
        let send_ptb = builder.build_send_ptb(&uln302, &treasury, &endpoint, &send_call);

        // Verify PTB structure:
        // 1 (uln send) + 3 (executor) + 2 (dvn) + 1 (confirm) = 7
        assert!(send_ptb.length() == 7, 0);

        // Verify first call is uln::send
        let first_call = &send_ptb[0];
        assert!(first_call.function().module_name() == ascii::string(b"uln_302"), 1);
        assert!(first_call.function().function_name() == ascii::string(b"send"), 2);
        assert!(!first_call.is_builder_call(), 3);
        assert!(first_call.result_ids().length() == 2, 4); // executor and dvn calls

        // Verify last call is uln::confirm_send
        let last_call = &send_ptb[send_ptb.length() - 1];
        assert!(last_call.function().module_name() == ascii::string(b"uln_302"), 5);
        assert!(last_call.function().function_name() == ascii::string(b"confirm_send"), 6);
        assert!(!last_call.is_builder_call(), 7);

        test_utils::destroy(oapp_cap);
        test_utils::destroy(send_call);
        scenario.return_to_sender(endpoint_admin_cap);
        scenario.return_to_sender(uln_admin_cap);
        test_scenario::return_shared(builder);
        test_scenario::return_shared(endpoint);
        test_scenario::return_shared(uln302);
        test_scenario::return_shared(treasury);
    };

    test_scenario::end(scenario);
}

#[test]
fun test_build_set_config_ptb() {
    let mut scenario = test_scenario::begin(ADMIN);

    setup_modules(&mut scenario);

    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let uln_admin_cap = scenario.take_from_sender<Uln302AdminCap>();
        let builder = test_scenario::take_shared<Uln302PtbBuilder>(&scenario);
        let uln302 = test_scenario::take_shared<Uln302>(&scenario);

        // Build set config PTB
        let set_config_ptb = uln_302_ptb_builder::build_set_config_ptb(&uln302);

        // Verify PTB structure - should have exactly one move call
        assert!(set_config_ptb.length() == 1, 0);

        // Verify the call is uln::set_config
        let call = &set_config_ptb[0];
        assert!(call.function().module_name() == ascii::string(b"uln_302"), 1);
        assert!(call.function().function_name() == ascii::string(b"set_config"), 2);
        assert!(!call.is_builder_call(), 3);

        scenario.return_to_sender(uln_admin_cap);
        test_scenario::return_shared(builder);
        test_scenario::return_shared(uln302);
    };

    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = uln_302_ptb_builder::EWorkerPtbsNotFound)]
fun test_build_quote_ptb_without_set_worker_ptbs() {
    let mut scenario = test_scenario::begin(ADMIN);

    setup_modules(&mut scenario);

    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let endpoint_admin_cap = scenario.take_from_sender<EndpointAdminCap>();
        let uln_admin_cap = scenario.take_from_sender<Uln302AdminCap>();
        let builder = test_scenario::take_shared<Uln302PtbBuilder>(&scenario);
        let mut endpoint = test_scenario::take_shared<EndpointV2>(&scenario);
        let mut uln302 = test_scenario::take_shared<Uln302>(&scenario);
        let treasury = test_scenario::take_shared<Treasury>(&scenario);

        // Initialize endpoint and create messaging channel
        endpoint_v2::init_eid(&mut endpoint, &endpoint_admin_cap, 101u32);
        let oapp_cap = call_cap::new_package_cap_for_test(test_scenario::ctx(&mut scenario));
        endpoint.register_oapp(&oapp_cap, b"lz_receive_info", test_scenario::ctx(&mut scenario));

        // Setup ULN with workers but DON'T set their PTBs
        let executor_addr = @0x1111;
        let dvn_addr = @0x2222;
        setup_uln_with_workers(
            &mut scenario,
            &mut uln302,
            &uln_admin_cap,
            &endpoint,
            executor_addr,
            vector[dvn_addr],
            DST_EID,
        );

        // Create a quote call
        let quote_param = message_lib_quote::create_param_for_test(
            outbound_packet::create_for_test(1u64, SRC_EID, @0x111, DST_EID, bytes32::from_address(@0x222), b"message"),
            x"0003", // options
            false, // pay_in_zro
        );
        let quote_call = call::create<QuoteParam, MessagingFee>(
            &oapp_cap,
            package::original_package_of_type<uln_302::Uln302>(),
            true, // two-way
            quote_param,
            test_scenario::ctx(&mut scenario),
        );

        // This should fail because worker PTBs are not set
        builder.build_quote_ptb(&uln302, &treasury, &quote_call);

        // Clean up (won't reach here due to expected failure)
        test_utils::destroy(quote_call);
        test_utils::destroy(oapp_cap);
        scenario.return_to_sender(endpoint_admin_cap);
        scenario.return_to_sender(uln_admin_cap);
        test_scenario::return_shared(builder);
        test_scenario::return_shared(endpoint);
        test_scenario::return_shared(uln302);
        test_scenario::return_shared(treasury);
    };

    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = uln_302_ptb_builder::EWorkerPtbsNotFound)]
fun test_build_send_ptb_without_set_worker_ptbs() {
    let mut scenario = test_scenario::begin(ADMIN);

    setup_modules(&mut scenario);

    test_scenario::next_tx(&mut scenario, ADMIN);
    {
        let endpoint_admin_cap = scenario.take_from_sender<EndpointAdminCap>();
        let uln_admin_cap = scenario.take_from_sender<Uln302AdminCap>();
        let builder = test_scenario::take_shared<Uln302PtbBuilder>(&scenario);
        let mut endpoint = test_scenario::take_shared<EndpointV2>(&scenario);
        let mut uln302 = test_scenario::take_shared<Uln302>(&scenario);
        let treasury = test_scenario::take_shared<Treasury>(&scenario);

        // Initialize endpoint and create messaging channel
        endpoint_v2::init_eid(&mut endpoint, &endpoint_admin_cap, 101u32);
        let oapp_cap = call_cap::new_package_cap_for_test(test_scenario::ctx(&mut scenario));
        endpoint.register_oapp(&oapp_cap, b"lz_receive_info", test_scenario::ctx(&mut scenario));

        // Setup ULN with workers but DON'T set their PTBs
        let executor_addr = @0x1111;
        let dvn_addr = @0x2222;
        setup_uln_with_workers(
            &mut scenario,
            &mut uln302,
            &uln_admin_cap,
            &endpoint,
            executor_addr,
            vector[dvn_addr],
            DST_EID,
        );

        // Create a mock send call
        let packet = outbound_packet::create_for_test(
            1u64, // nonce
            SRC_EID,
            oapp_cap.id(), // sender
            DST_EID,
            bytes32::from_address(@0x222), // receiver
            b"test message",
        );
        let quote_param = message_lib_quote::create_param_for_test(
            packet,
            x"0003", // options
            false, // pay_in_zro
        );
        let send_param = message_lib_send::create_param_for_test(quote_param);
        let send_call = call::create<SendParam, SendResult>(
            &oapp_cap,
            package::original_package_of_type<uln_302::Uln302>(),
            false, // two-way
            send_param,
            test_scenario::ctx(&mut scenario),
        );

        // This should fail because worker PTBs are not set
        builder.build_send_ptb(&uln302, &treasury, &endpoint, &send_call);

        // Clean up (won't reach here due to expected failure)
        test_utils::destroy(send_call);
        test_utils::destroy(oapp_cap);
        scenario.return_to_sender(endpoint_admin_cap);
        scenario.return_to_sender(uln_admin_cap);
        test_scenario::return_shared(builder);
        test_scenario::return_shared(endpoint);
        test_scenario::return_shared(uln302);
        test_scenario::return_shared(treasury);
    };

    test_scenario::end(scenario);
}
