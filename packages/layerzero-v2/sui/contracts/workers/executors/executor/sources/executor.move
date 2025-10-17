/// Executor implementation for LayerZero v2
module executor::executor_worker;

use call::{call::{Self, Call, Void}, call_cap::CallCap};
use endpoint_v2::{
    endpoint_v2::{Self, EndpointV2},
    lz_compose::LzComposeParam,
    lz_receive::LzReceiveParam,
    messaging_channel::MessagingChannel,
    messaging_composer::ComposeQueue,
    utils
};
use executor::{executor_info_v1, executor_type::DstConfig, native_drop_type::NativeDropParams};
use executor_call_type::executor_feelib_get_fee::{Self, FeelibGetFeeParam};
use message_lib_common::fee_recipient::{Self, FeeRecipient};
use msglib_ptb_builder_call_types::set_worker_ptb::{Self, SetWorkerPtbParam};
use ptb_move_call::move_call::MoveCall;
use std::ascii::String;
use sui::{coin::Coin, event, sui::SUI, table::{Self, Table}, vec_set::VecSet};
use uln_common::{executor_assign_job::AssignJobParam, executor_get_fee::GetFeeParam};
use utils::{bytes32::Bytes32, table_ext};
use worker_common::{worker_common::{Self, Worker, OwnerCap, AdminCap}, worker_info_v1};
use worker_registry::worker_registry::WorkerRegistry;

// === Constants ===

const EXECUTOR_WORKER_ID: u8 = 1;

// === Errors ===

const EEidNotSupported: u64 = 1;
const EInvalidNativeDropAmount: u64 = 2;

// === Structs ===

public struct Executor has key {
    id: UID,
    worker: Worker,
    dst_configs: Table<u32, DstConfig>,
}

// === Events ===

public struct DstConfigSetEvent has copy, drop {
    executor: address,
    dst_eid: u32,
    config: DstConfig,
}

public struct NativeDropAppliedEvent has copy, drop {
    executor: address,
    src_eid: u32,
    sender: Bytes32,
    dst_eid: u32,
    oapp: address,
    nonce: u64,
    params: vector<NativeDropParams>,
    success: vector<bool>,
}

// === Creation ===

/// Create a new Executor
public fun create_executor(
    worker_cap: CallCap,
    deposit_address: address,
    supported_message_libs: vector<address>,
    price_feed: address,
    worker_fee_lib: address,
    default_multiplier_bps: u16,
    owner: address,
    admins: vector<address>,
    worker_registry: &mut WorkerRegistry,
    ctx: &mut TxContext,
): address {
    let (worker, owner_cap) = worker_common::create_worker(
        worker_cap,
        deposit_address,
        supported_message_libs,
        price_feed,
        worker_fee_lib,
        default_multiplier_bps,
        admins,
        ctx,
    );

    let executor = Executor {
        id: object::new(ctx),
        worker,
        dst_configs: table::new(ctx),
    };

    transfer::public_transfer(owner_cap, owner);
    // Create executor info and register with worker registry
    let executor_object_address = object::id_address(&executor);
    let executor_info_bytes = executor_info_v1::create(executor_object_address).encode();
    let worker_info_bytes = worker_info_v1::create(EXECUTOR_WORKER_ID, executor_info_bytes).encode();
    worker_registry.set_worker_info(executor.worker.worker_cap(), worker_info_bytes);

    transfer::share_object(executor);
    executor_object_address
}

// === Core Functions of Send Side ===

/// Assign job for Executor (called via PTB with Call created by send function in ULN302)
public fun assign_job(
    self: &Executor,
    call: &mut Call<AssignJobParam, FeeRecipient>,
    ctx: &mut TxContext,
): Call<FeelibGetFeeParam, u64> {
    let param = *call.param().base();
    self.create_feelib_get_fee_call(call, param, ctx)
}

/// Confirm assign job
public fun confirm_assign_job(
    self: &Executor,
    executor_call: &mut Call<AssignJobParam, FeeRecipient>,
    feelib_call: Call<FeelibGetFeeParam, u64>,
) {
    let (_, _, fee) = executor_call.destroy_child(self.worker.worker_cap(), feelib_call);
    executor_call.complete(self.worker.worker_cap(), fee_recipient::create(fee, self.worker.deposit_address()));
}

/// Get fee for execution (using Call created by quote function in ULN302)
public fun get_fee(
    self: &Executor,
    call: &mut Call<GetFeeParam, u64>,
    ctx: &mut TxContext,
): Call<FeelibGetFeeParam, u64> {
    let param = *call.param();
    self.create_feelib_get_fee_call(call, param, ctx)
}

/// Confirm get fee
public fun confirm_get_fee(
    self: &Executor,
    executor_call: &mut Call<GetFeeParam, u64>,
    feelib_call: Call<FeelibGetFeeParam, u64>,
) {
    let (_, _, fee) = executor_call.destroy_child(self.worker.worker_cap(), feelib_call);
    executor_call.complete(self.worker.worker_cap(), fee);
}

// === Core Functions of Receive Side ===

/// Execute LZ receive (admin only)
public fun execute_lz_receive(
    self: &Executor,
    admin_cap: &AdminCap,
    endpoint: &EndpointV2,
    messaging_channel: &mut MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    guid: Bytes32,
    message: vector<u8>,
    extra_data: vector<u8>,
    value: Option<Coin<SUI>>,
    ctx: &mut TxContext,
): Call<LzReceiveParam, Void> {
    self.worker.assert_admin(admin_cap);
    endpoint.lz_receive(
        self.worker.worker_cap(),
        messaging_channel,
        src_eid,
        sender,
        nonce,
        guid,
        message,
        extra_data,
        value,
        ctx,
    )
}

/// Execute LZ compose (admin only)
public fun execute_lz_compose(
    self: &Executor,
    admin_cap: &AdminCap,
    endpoint: &EndpointV2,
    compose_queue: &mut ComposeQueue,
    from: address,
    guid: Bytes32,
    index: u16,
    message: vector<u8>,
    extra_data: vector<u8>,
    value: Option<Coin<SUI>>,
    ctx: &mut TxContext,
): Call<LzComposeParam, Void> {
    self.worker.assert_admin(admin_cap);
    endpoint.lz_compose(
        self.worker.worker_cap(),
        compose_queue,
        from,
        guid,
        index,
        message,
        extra_data,
        value,
        ctx,
    )
}

/// Native drop function (admin only)
/// Takes a Coin<SUI> from caller and distributes it to recipients according to params
#[allow(lint(self_transfer))]
public fun native_drop(
    self: &Executor,
    admin_cap: &AdminCap,
    src_eid: u32,
    sender: Bytes32,
    dst_eid: u32,
    oapp: address,
    nonce: u64,
    native_drop_params: vector<NativeDropParams>,
    mut payment_coin: Coin<SUI>,
    ctx: &mut TxContext,
) {
    self.worker.assert_admin(admin_cap);

    // Perform native drop and return any remaining change
    self.native_drop_internal(
        src_eid,
        sender,
        dst_eid,
        oapp,
        nonce,
        native_drop_params,
        &mut payment_coin,
        ctx,
    );

    // Transfer any remaining change to the caller
    utils::transfer_coin(payment_coin, ctx.sender());
}

/// Records a failed lz_receive execution for off-chain processing (admin only)
public fun lz_receive_alert(
    self: &Executor,
    admin_cap: &AdminCap,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    receiver: address,
    guid: Bytes32,
    gas: u64,
    value: u64,
    message: vector<u8>,
    extra_data: vector<u8>,
    reason: String,
) {
    self.worker.assert_admin(admin_cap);
    endpoint_v2::lz_receive_alert(
        self.worker.worker_cap(),
        src_eid,
        sender,
        nonce,
        receiver,
        guid,
        gas,
        value,
        message,
        extra_data,
        reason,
    );
}

/// Records a failed lz_compose execution for off-chain processing (admin only)
public fun lz_compose_alert(
    self: &Executor,
    admin_cap: &AdminCap,
    from: address,
    to: address,
    guid: Bytes32,
    index: u16,
    gas: u64,
    value: u64,
    message: vector<u8>,
    extra_data: vector<u8>,
    reason: String,
) {
    self.worker.assert_admin(admin_cap);
    endpoint_v2::lz_compose_alert(
        self.worker.worker_cap(),
        from,
        to,
        guid,
        index,
        gas,
        value,
        message,
        extra_data,
        reason,
    );
}

// === Admin Configuration Functions ===

/// Set default multiplier bps (admin only)
public fun set_default_multiplier_bps(self: &mut Executor, admin_cap: &AdminCap, multiplier_bps: u16) {
    self.worker.set_default_multiplier_bps(admin_cap, multiplier_bps);
}

/// Set deposit address (admin only)
public fun set_deposit_address(self: &mut Executor, admin_cap: &AdminCap, deposit_address: address) {
    self.worker.set_deposit_address(admin_cap, deposit_address);
}

/// Set destination configuration (admin only)
public fun set_dst_config(self: &mut Executor, admin_cap: &AdminCap, dst_eid: u32, config: DstConfig) {
    self.worker.assert_admin(admin_cap);

    table_ext::upsert!(&mut self.dst_configs, dst_eid, config);

    event::emit(DstConfigSetEvent { executor: self.worker_cap_address(), dst_eid, config });
}

/// Set price feed (admin only)
public fun set_price_feed(self: &mut Executor, admin_cap: &AdminCap, price_feed: address) {
    self.worker.set_price_feed(admin_cap, price_feed);
}

/// Set supported option types (admin only)
public fun set_supported_option_types(
    self: &mut Executor,
    admin_cap: &AdminCap,
    dst_eid: u32,
    option_types: vector<u8>,
) {
    self.worker.set_supported_option_types(admin_cap, dst_eid, option_types);
}

/// Set worker fee lib (admin only)
public fun set_worker_fee_lib(self: &mut Executor, admin_cap: &AdminCap, worker_fee_lib: address) {
    self.worker.set_worker_fee_lib(admin_cap, worker_fee_lib);
}

// === Owner Functions ===

/// Set admin capability (owner only)
public fun set_admin(self: &mut Executor, owner_cap: &OwnerCap, admin: address, active: bool, ctx: &mut TxContext) {
    self.worker.set_admin(owner_cap, admin, active, ctx);
}

/// Set supported message library (owner only)
public fun set_supported_message_lib(self: &mut Executor, owner_cap: &OwnerCap, message_lib: address, supported: bool) {
    self.worker.set_supported_message_lib(owner_cap, message_lib, supported);
}

/// Set allowlist for an oapp sender (owner only)
public fun set_allowlist(self: &mut Executor, owner_cap: &OwnerCap, oapp: address, allowed: bool) {
    self.worker.set_allowlist(owner_cap, oapp, allowed);
}

/// Set denylist for an oapp sender (owner only)
public fun set_denylist(self: &mut Executor, owner_cap: &OwnerCap, oapp: address, denied: bool) {
    self.worker.set_denylist(owner_cap, oapp, denied);
}

/// Set worker paused state (owner only)
public fun set_paused(self: &mut Executor, owner_cap: &OwnerCap, paused: bool) {
    self.worker.set_paused(owner_cap, paused);
}

/// Set PTB builder move calls (owner only)
public fun set_ptb_builder_move_calls(
    self: &mut Executor,
    owner_cap: &OwnerCap,
    target_ptb_builder: address,
    get_fee_move_calls: vector<MoveCall>,
    assign_job_move_calls: vector<MoveCall>,
    ctx: &mut TxContext,
): Call<SetWorkerPtbParam, Void> {
    self.worker.assert_owner(owner_cap);
    let param = set_worker_ptb::create_param(get_fee_move_calls, assign_job_move_calls);
    call::create(self.worker.worker_cap(), target_ptb_builder, true, param, ctx)
}

/// Set worker info (owner only)
public fun set_worker_info(
    self: &Executor,
    owner_cap: &OwnerCap,
    worker_registry: &mut WorkerRegistry,
    worker_info: vector<u8>,
) {
    self.worker.assert_owner(owner_cap);
    worker_registry.set_worker_info(self.worker.worker_cap(), worker_info);
}

// === View Functions ===

/// Get allowlist size
public fun allowlist_size(self: &Executor): u64 {
    self.worker.allowlist_size()
}

/// Get default multiplier bps
public fun default_multiplier_bps(self: &Executor): u16 {
    self.worker.default_multiplier_bps()
}

/// Get deposit address
public fun deposit_address(self: &Executor): address {
    self.worker.deposit_address()
}

/// Get destination configuration
public fun dst_config(self: &Executor, dst_eid: u32): &DstConfig {
    table_ext::borrow_or_abort!(&self.dst_configs, dst_eid, EEidNotSupported)
}

/// Check if an address has ACL permission
public fun has_acl(self: &Executor, account: address): bool {
    self.worker.has_acl(account)
}

/// Get the admin addresses
public fun admins(self: &Executor): VecSet<address> {
    self.worker.admins()
}

/// Check if admin cap is valid for this executor
public fun is_admin(self: &Executor, admin_cap: &AdminCap): bool {
    self.worker.is_admin(admin_cap)
}

public fun is_admin_address(self: &Executor, admin: address): bool {
    self.worker.is_admin_address(admin)
}

/// Check if a message library is supported
public fun is_supported_message_lib(self: &Executor, message_lib: address): bool {
    self.worker.is_supported_message_lib(message_lib)
}

/// Check if an address is in the allowlist
public fun is_allowlisted(self: &Executor, account: address): bool {
    self.worker.is_on_allowlist(account)
}

/// Check if an address is in the denylist
public fun is_denylisted(self: &Executor, account: address): bool {
    self.worker.is_on_denylist(account)
}

/// Check if worker is paused
public fun is_paused(self: &Executor): bool {
    self.worker.is_paused()
}

/// Get price feed ID
public fun price_feed(self: &Executor): address {
    self.worker.price_feed()
}

/// Get supported option types
public fun supported_option_types(self: &Executor, dst_eid: u32): vector<u8> {
    self.worker.get_supported_option_types(dst_eid)
}

/// Get worker cap address for authentication
public fun worker_cap_address(self: &Executor): address {
    self.worker.worker_cap_address()
}

/// Get worker fee lib
public fun worker_fee_lib(self: &Executor): address {
    self.worker.worker_fee_lib()
}

/// Get admin cap ID from admin address
public fun admin_cap_id(self: &Executor, admin: address): address {
    self.worker.get_admin_cap_id(admin)
}

// === Internal Functions ===

fun create_feelib_get_fee_call<Param, Result>(
    self: &Executor,
    call: &mut Call<Param, Result>,
    param: GetFeeParam,
    ctx: &mut TxContext,
): Call<FeelibGetFeeParam, u64> {
    // Perform all validation in one place
    self.worker.assert_supported_message_lib(call.caller());
    self.worker.assert_acl(param.sender());
    self.worker.assert_worker_unpaused();

    // Get destination config
    let dst_config = self.dst_config(param.dst_eid());
    // Create Call to ExecutorFeeLib
    let feelib_param = executor_feelib_get_fee::create_param(
        param.sender(),
        param.dst_eid(),
        param.calldata_size(),
        *param.options(),
        self.worker.price_feed(),
        self.worker.default_multiplier_bps(),
        dst_config.lz_receive_base_gas(),
        dst_config.lz_compose_base_gas(),
        dst_config.floor_margin_usd(),
        dst_config.native_cap(),
        dst_config.multiplier_bps(),
    );
    call.create_single_child(self.worker.worker_cap(), self.worker.worker_fee_lib(), feelib_param, ctx)
}

/// Internal native drop implementation
/// Distributes coins to recipients and returns remaining change
fun native_drop_internal(
    self: &Executor,
    src_eid: u32,
    sender: Bytes32,
    dst_eid: u32,
    oapp: address,
    nonce: u64,
    native_drop_params: vector<NativeDropParams>,
    payment_coin: &mut Coin<SUI>,
    ctx: &mut TxContext,
) {
    let mut success = vector[];

    // Process each native drop parameter
    let mut i = 0;
    while (i < native_drop_params.length()) {
        let param = &native_drop_params[i];

        let amount = param.amount();
        // Validate drop amount
        assert!(amount > 0, EInvalidNativeDropAmount);

        // Check if we have enough balance in the payment coin
        let drop_successful = if (payment_coin.value() >= amount) {
            // Split the required amount and transfer to receiver
            let drop_coin = payment_coin.split(amount, ctx);
            transfer::public_transfer(drop_coin, param.receiver());
            true
        } else {
            false
        };

        success.push_back(drop_successful);
        i = i + 1;
    };

    // Emit native drop applied event
    event::emit(NativeDropAppliedEvent {
        executor: self.worker_cap_address(),
        src_eid,
        sender,
        dst_eid,
        oapp,
        nonce,
        params: native_drop_params,
        success,
    });
}

// === Test Helper Functions ===

#[test_only]
public(package) fun create_dst_config_set_event(executor: address, dst_eid: u32, config: DstConfig): DstConfigSetEvent {
    DstConfigSetEvent { executor, dst_eid, config }
}

#[test_only]
public(package) fun create_native_drop_applied_event(
    executor: address,
    src_eid: u32,
    sender: Bytes32,
    dst_eid: u32,
    oapp: address,
    nonce: u64,
    params: vector<NativeDropParams>,
    success: vector<bool>,
): NativeDropAppliedEvent {
    NativeDropAppliedEvent {
        executor,
        src_eid,
        sender,
        dst_eid,
        oapp,
        nonce,
        params,
        success,
    }
}

#[test_only]
public(package) fun get_worker_for_testing(self: &Executor): &Worker {
    &self.worker
}
