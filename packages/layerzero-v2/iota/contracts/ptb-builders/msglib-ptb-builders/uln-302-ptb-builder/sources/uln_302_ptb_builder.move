/// ULN 302 Programmable Transaction Block (PTB) Builder Module
///
/// This module provides the infrastructure for building PTBs (Programmable Transaction Blocks)
/// for the ULN 302 message library in the LayerZero protocol.
module uln_302_ptb_builder::uln_302_ptb_builder;

use call::{call::{Call, Void}, call_cap::{Self, CallCap}};
use endpoint_ptb_builder::{endpoint_ptb_builder, msglib_ptb_builder_info::{Self, MsglibPtbBuilderInfo}};
use endpoint_v2::{
    endpoint_v2::EndpointV2,
    message_lib_quote::QuoteParam,
    message_lib_send::{SendParam, SendResult},
    messaging_fee::MessagingFee
};
use message_lib_common::fee_recipient::FeeRecipient;
use msglib_ptb_builder_call_types::set_worker_ptb::SetWorkerPtbParam;
use multi_call::multi_call::MultiCall;
use ptb_move_call::{argument, move_call::{Self, MoveCall}, move_calls_builder};
use std::type_name;
use iota::table;
use treasury::treasury::Treasury;
use uln_302::uln_302::Uln302;
use uln_common::{
    dvn_assign_job::AssignJobParam as DvnAssignJobParam,
    dvn_get_fee::GetFeeParam as DvnGetFeeParam,
    executor_assign_job::AssignJobParam as ExecutorAssignJobParam,
    executor_get_fee::GetFeeParam as ExecutorGetFeeParam
};
use utils::{bytes32::Bytes32, hash, package, table_ext};

// === Errors ===

const EWorkerPtbsNotFound: u64 = 1;

// === Structs ===

/// One time witness for the ULN 302 PTB builder
public struct ULN_302_PTB_BUILDER has drop {}

/// The main PTB builder for ULN 302 message library operations
///
/// This shared object manages the construction of PTBs for the ULN 302 protocol.
/// It maintains a registry of worker PTB configurations.
public struct Uln302PtbBuilder has key {
    id: UID,
    call_cap: CallCap,
    worker_ptbs: table::Table<address, WorkerPtbs>,
}

/// Worker PTB configuration containing move calls for fee and job operations
///
/// This struct encapsulates the PTB move calls that a worker (DVN or Executor)
/// provides to integrate with the ULN 302 message library. Each worker must
/// provide both fee calculation and job assignment PTB sequences.
public struct WorkerPtbs has copy, drop, store {
    get_fee_ptb: vector<MoveCall>,
    assign_job_ptb: vector<MoveCall>,
}

// === Initialization ===

/// Initializes and shares the ULN 302 PTB builder
fun init(witness: ULN_302_PTB_BUILDER, ctx: &mut TxContext) {
    transfer::share_object(Uln302PtbBuilder {
        id: object::new(ctx),
        call_cap: call_cap::new_package_cap(&witness, ctx),
        worker_ptbs: table::new(ctx),
    });
}

// === Worker Registration ===

/// Registers or updates PTB configurations for a worker
///
/// This function allows workers (DVNs or Executors) to register their PTB
/// configurations with the builder. The worker provides both fee calculation
/// and job assignment PTB sequences that will be used when constructing
/// transaction blocks for message operations.
public fun set_worker_ptbs(self: &mut Uln302PtbBuilder, call: Call<SetWorkerPtbParam, Void>) {
    let worker = call.caller();
    let param = call.complete_and_destroy(&self.call_cap);
    let (get_fee_ptb, assign_job_ptb) = param.unpack();
    table_ext::upsert!(&mut self.worker_ptbs, worker, WorkerPtbs { get_fee_ptb, assign_job_ptb });
}

// === PTB Builder Info ===

/// Gets comprehensive PTB builder information for builder registration
///
/// This function creates a complete configuration object that contains all the
/// necessary PTB move calls for integrating with the ULN 302 message library.
/// It provides the endpoint PTB builder with the information needed to
/// construct quote, send, and configuration PTBs.
public fun get_ptb_builder_info(
    self: &Uln302PtbBuilder,
    uln: &Uln302,
    treasury: &Treasury,
    endpoint: &EndpointV2,
): MsglibPtbBuilderInfo {
    let uln_builder_module_name = b"uln_302_ptb_builder".to_ascii_string();
    let uln_builder_object_address = object::id_address(self);
    let endpoint_object_address = object::id_address(endpoint);
    let uln_object_address = object::id_address(uln);
    let treasury_object_address = object::id_address(treasury);

    let quote_move_calls = vector[
        // uln_302_ptb_builder::build_quote_ptb(uln_302_ptb_builder, uln, treasury, message_lib_quote_call)
        move_call::create(
            self.call_cap.id(),
            uln_builder_module_name,
            b"build_quote_ptb".to_ascii_string(),
            vector[
                argument::create_object(uln_builder_object_address),
                argument::create_object(uln_object_address),
                argument::create_object(treasury_object_address),
                argument::create_id(endpoint_ptb_builder::message_lib_quote_call_id()),
            ],
            vector[],
            true,
            vector[],
        ),
    ];
    let send_move_calls = vector[
        // uln_302_ptb_builder::build_send_ptb(uln_302_ptb_builder, uln, treasury, endpoint, message_lib_send_call)
        move_call::create(
            self.call_cap.id(),
            uln_builder_module_name,
            b"build_send_ptb".to_ascii_string(),
            vector[
                argument::create_object(uln_builder_object_address),
                argument::create_object(uln_object_address),
                argument::create_object(treasury_object_address),
                argument::create_object(endpoint_object_address),
                argument::create_id(endpoint_ptb_builder::message_lib_send_call_id()),
            ],
            vector[],
            true,
            vector[],
        ),
    ];
    let set_config_move_calls = build_set_config_ptb(uln);

    msglib_ptb_builder_info::create(
        package::original_package_of_type<Uln302>(),
        self.call_cap.id(),
        quote_move_calls,
        send_move_calls,
        set_config_move_calls,
    )
}

// === PTB Construction Functions ===

/// Builds a PTB for quote operations (fee estimation)
///
/// This function constructs a complete PTB sequence for estimating fees for a
/// cross-chain message. It coordinates between the ULN 302 library, executors,
/// and DVNs to calculate the total cost of message verification and execution.
///
/// PTB Flow:
/// 1. `uln::quote()` - Starts quote process, returns worker call objects
/// 2. Worker get_fee PTBs - Each configured worker calculates their fees
/// 3. `uln::confirm_quote()` - Aggregates fees and returns final result
public fun build_quote_ptb(
    self: &Uln302PtbBuilder,
    uln: &Uln302,
    treasury: &Treasury,
    call: &Call<QuoteParam, MessagingFee>,
): vector<MoveCall> {
    let uln_package = package::original_package_of_type<Uln302>();
    let uln_object_address = object::id_address(uln);
    let treasury_object_address = object::id_address(treasury);
    let packet = call.param().packet();
    let mut move_calls_builder = move_calls_builder::new();

    // Step 1: Initiate quote process in ULN 302
    // This creates call objects for the executor and DVNs to provide fee estimates
    let uln_quote_result = move_calls_builder.add(
        // uln_302::quote(uln, message_lib_quote_call) -> (executor_get_fee_call, dvn_get_fee_multi_call)
        move_call::create(
            uln_package,
            b"uln_302".to_ascii_string(),
            b"quote".to_ascii_string(),
            vector[
                argument::create_object(uln_object_address),
                argument::create_id(endpoint_ptb_builder::message_lib_quote_call_id()),
            ],
            vector[],
            false,
            vector[executor_get_fee_call_id(), dvn_get_fee_multi_call_id()],
        ),
    );

    // Step 2: Add executor fee calculation PTB
    // The executor calculates fees for message execution on the destination chain
    let executor = uln.get_effective_executor_config(packet.sender(), packet.dst_eid()).executor();
    let executor_ptbs = self.get_worker_ptbs(executor);
    move_calls_builder.append(*executor_ptbs.get_fee_ptb());

    // Step 3: Add DVN fee calculation PTBs
    // Each DVN calculates fees for message verification services
    let uln_config = uln.get_effective_send_uln_config(packet.sender(), packet.dst_eid());
    let dvns = vector::flatten(vector[*uln_config.required_dvns(), *uln_config.optional_dvns()]);
    dvns.do_ref!(|dvn| {
        let dvn_ptbs = self.get_worker_ptbs(*dvn);
        move_calls_builder.append(*dvn_ptbs.get_fee_ptb());
    });

    // Step 4: Confirm and aggregate all fees
    // ULN 302 collects all worker fee estimates and returns the total messaging fee
    move_calls_builder.add(
        // uln_302::confirm_quote(uln, treasury, message_lib_quote_call, executor_get_fee_call, dvn_get_fee_multi_call)
        move_call::create(
            uln_package,
            b"uln_302".to_ascii_string(),
            b"confirm_quote".to_ascii_string(),
            vector[
                argument::create_object(uln_object_address),
                argument::create_object(treasury_object_address),
                argument::create_id(endpoint_ptb_builder::message_lib_quote_call_id()),
                uln_quote_result.to_nested_result_arg(0), // executor_call
                uln_quote_result.to_nested_result_arg(1), // dvn_multi_call
            ],
            vector[],
            false,
            vector[],
        ),
    );

    move_calls_builder.build()
}

/// Builds a PTB for send operations
///
/// This function constructs a complete PTB sequence for sending a cross-chain
/// message. It coordinates between the ULN 302 library, executors, and DVNs
/// to transmit the message and assign verification/execution jobs.
///
/// PTB Flow:
/// 1. `uln::send()` - Starts send process, creates job assignment calls
/// 2. Worker assign_job PTBs - Each worker accepts their job assignment
/// 3. `uln::confirm_send()` - Finalizes send and emits the message
public fun build_send_ptb(
    self: &Uln302PtbBuilder,
    uln: &Uln302,
    treasury: &Treasury,
    endpoint: &EndpointV2,
    call: &Call<SendParam, SendResult>,
): vector<MoveCall> {
    let uln_package = package::original_package_of_type<Uln302>();
    let uln_object_address = object::id_address(uln);
    let treasury_object_address = object::id_address(treasury);
    let endpoint_object_address = object::id_address(endpoint);
    let packet = call.param().base().packet();
    let messaging_channel = endpoint.get_messaging_channel(packet.sender());
    let mut move_calls_builder = move_calls_builder::new();

    // Step 1: Initiate send process in ULN 302
    // This creates job assignment call objects for the executor and DVNs
    let uln_send_result = move_calls_builder.add(
        // uln_302::send(uln, message_lib_send_call) -> (executor_assign_job_call, dvn_assign_job_multi_call)
        move_call::create(
            uln_package,
            b"uln_302".to_ascii_string(),
            b"send".to_ascii_string(),
            vector[
                argument::create_object(uln_object_address),
                argument::create_id(endpoint_ptb_builder::message_lib_send_call_id()),
            ],
            vector[],
            false,
            vector[executor_assign_job_call_id(), dvn_assign_job_multi_call_id()],
        ),
    );

    // Step 2: Add executor job assignment PTB
    // The executor accepts the job and receives fee payment for message execution
    let executor = uln.get_effective_executor_config(packet.sender(), packet.dst_eid()).executor();
    let executor_ptbs = self.get_worker_ptbs(executor);
    move_calls_builder.append(*executor_ptbs.get_assign_job_ptb());

    // Step 3: Add DVN job assignment PTBs
    // Each DVN accepts their verification job and receives fee payment
    let uln_config = uln.get_effective_send_uln_config(packet.sender(), packet.dst_eid());
    let dvns = vector::flatten(vector[*uln_config.required_dvns(), *uln_config.optional_dvns()]);
    dvns.do_ref!(|dvn| {
        let dvn_ptbs = self.get_worker_ptbs(*dvn);
        move_calls_builder.append(*dvn_ptbs.get_assign_job_ptb());
    });

    // Step 4: Confirm send - ULN 302 finalizes the send process
    move_calls_builder.add(
        // uln_302::confirm_send(
        //      uln,
        //      endpoint,
        //      treasury,
        //      messaging_channel,
        //      endpoint_send_call,
        //      message_lib_send_call,
        //      executor_assign_job_call,
        //      dvn_assign_job_multi_call
        // )
        move_call::create(
            uln_package,
            b"uln_302".to_ascii_string(),
            b"confirm_send".to_ascii_string(),
            vector[
                argument::create_object(uln_object_address),
                argument::create_object(endpoint_object_address),
                argument::create_object(treasury_object_address),
                argument::create_object(messaging_channel),
                argument::create_id(endpoint_ptb_builder::endpoint_send_call_id()),
                argument::create_id(endpoint_ptb_builder::message_lib_send_call_id()),
                uln_send_result.to_nested_result_arg(0), // executor_call
                uln_send_result.to_nested_result_arg(1), // dvn_multi_call
            ],
            vector[],
            false,
            vector[],
        ),
    );

    move_calls_builder.build()
}

/// Builds a PTB for configuration operations
///
/// This function constructs a PTB sequence for setting ULN 302 configuration
/// parameters.
public fun build_set_config_ptb(uln: &Uln302): vector<MoveCall> {
    let uln_package = package::original_package_of_type<Uln302>();
    let uln_object_address = object::id_address(uln);

    let mut move_calls_builder = move_calls_builder::new();
    move_calls_builder.add(
        // uln_302::set_config(uln, message_lib_set_config_call)
        move_call::create(
            uln_package,
            b"uln_302".to_ascii_string(),
            b"set_config".to_ascii_string(),
            vector[
                argument::create_object(uln_object_address),
                argument::create_id(endpoint_ptb_builder::message_lib_set_config_call_id()),
            ],
            vector[],
            false,
            vector[],
        ),
    );
    move_calls_builder.build()
}

// === Call Object Type IDs ===

/// Generates the type ID for executor fee calculation calls
public fun executor_get_fee_call_id(): Bytes32 {
    hash::keccak256!(type_name::get_with_original_ids<Call<ExecutorGetFeeParam, u64>>().into_string().as_bytes())
}

/// Generates the type ID for DVN fee calculation multi-calls
public fun dvn_get_fee_multi_call_id(): Bytes32 {
    hash::keccak256!(type_name::get_with_original_ids<MultiCall<DvnGetFeeParam, u64>>().into_string().as_bytes())
}

/// Generates the type ID for executor job assignment calls
public fun executor_assign_job_call_id(): Bytes32 {
    hash::keccak256!(
        type_name::get_with_original_ids<Call<ExecutorAssignJobParam, FeeRecipient>>().into_string().as_bytes(),
    )
}

/// Generates the type ID for DVN job assignment multi-calls
public fun dvn_assign_job_multi_call_id(): Bytes32 {
    hash::keccak256!(
        type_name::get_with_original_ids<MultiCall<DvnAssignJobParam, FeeRecipient>>().into_string().as_bytes(),
    )
}

// === View Functions ===

/// Checks if a worker has registered their PTB configurations
public fun is_worker_ptbs_set(self: &Uln302PtbBuilder, worker: address): bool {
    self.worker_ptbs.contains(worker)
}

/// Gets the PTB configurations for a specific worker
public fun get_worker_ptbs(self: &Uln302PtbBuilder, worker: address): &WorkerPtbs {
    table_ext::borrow_or_abort!(&self.worker_ptbs, worker, EWorkerPtbsNotFound)
}

// === Worker PTB Accessors ===

/// Gets the fee calculation PTB from worker configurations
public fun get_fee_ptb(self: &WorkerPtbs): &vector<MoveCall> {
    &self.get_fee_ptb
}

/// Gets the job assignment PTB from worker configurations
public fun get_assign_job_ptb(self: &WorkerPtbs): &vector<MoveCall> {
    &self.assign_job_ptb
}

// === Test Only Functions ===

#[test_only]
public(package) fun init_for_testing(ctx: &mut TxContext) {
    init(ULN_302_PTB_BUILDER {}, ctx)
}
