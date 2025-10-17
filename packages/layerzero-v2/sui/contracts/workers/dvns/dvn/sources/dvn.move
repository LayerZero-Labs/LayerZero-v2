/// DVN (Decentralized Verification Network) implementation for LayerZero v2
module dvn::dvn;

use call::{call::{Self, Call, Void}, call_cap::CallCap};
use dvn::{dvn_info_v1, hashes, multisig::{Self, MultiSig}};
use dvn_call_type::dvn_feelib_get_fee::{Self, FeelibGetFeeParam};
use message_lib_common::fee_recipient::{Self, FeeRecipient};
use msglib_ptb_builder_call_types::set_worker_ptb::{Self, SetWorkerPtbParam};
use multi_call::multi_call::MultiCall;
use ptb_move_call::move_call::MoveCall;
use sui::{clock::Clock, event, table::{Self, Table}, vec_set::VecSet};
use uln_common::{dvn_assign_job::AssignJobParam, dvn_get_fee::GetFeeParam, dvn_verify::{Self, VerifyParam}};
use utils::{bytes32::Bytes32, hash, table_ext};
use worker_common::{worker_common::{Self, Worker, OwnerCap, AdminCap}, worker_info_v1};
use worker_registry::worker_registry::WorkerRegistry;

// === Constants ===

const DVN_WORKER_ID: u8 = 2;

// === Errors ===

const EExpiredSignature: u64 = 1;
const EEidNotSupported: u64 = 2;
const EHashAlreadyUsed: u64 = 3;
const EPtbBuilderAlreadyInitialized: u64 = 4;

// === Events ===

public struct SetDstConfigEvent has copy, drop {
    dvn: address,
    dst_eid: u32,
    gas: u256,
    multiplier_bps: u16,
    floor_margin_usd: u128,
}

// === Structs ===

/// DVN configuration and state
public struct DVN has key {
    id: UID,
    /// Unique DVN identifier: endpoint v1 eid if available, otherwise endpoint v2 eid % 30,000
    vid: u32,
    /// Worker object (contains worker_cap)
    worker: Worker,
    /// Destination configurations
    dst_configs: Table<u32, DstConfig>,
    /// Multisig configuration and state
    multisig: MultiSig,
    /// Used hashes to prevent replay attacks
    used_hashes: Table<Bytes32, bool>,
    /// Owner cap
    owner_cap: OwnerCap,
    /// Flag to track if PTB builder move calls have been initialized
    ptb_builder_initialized: bool,
}

/// Destination configuration stored in state
public struct DstConfig has copy, drop, store {
    /// Gas limit for destination operations
    gas: u256,
    /// Multiplier in basis points for fee calculation
    multiplier_bps: u16,
    /// Floor margin in USD with precision
    floor_margin_usd: u128,
}

// === Initialization ===

/// Initialize a new DVN
public fun create_dvn(
    worker_cap: CallCap,
    vid: u32,
    deposit_address: address,
    supported_message_libs: vector<address>,
    price_feed: address,
    worker_fee_lib: address,
    default_multiplier_bps: u16,
    admins: vector<address>,
    signers: vector<vector<u8>>,
    quorum: u64,
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

    // Create multisig with initial signers and quorum
    let multisig = multisig::new(signers, quorum);
    let dvn = DVN {
        id: object::new(ctx),
        vid,
        worker,
        dst_configs: table::new(ctx),
        multisig,
        used_hashes: table::new(ctx),
        owner_cap,
        ptb_builder_initialized: false,
    };
    let dvn_object_address = object::id_address(&dvn);
    let dvn_info_bytes = dvn_info_v1::create(dvn_object_address).encode();
    let worker_info_bytes = worker_info_v1::create(DVN_WORKER_ID, dvn_info_bytes).encode();
    worker_registry.set_worker_info(dvn.worker.worker_cap(), worker_info_bytes);

    transfer::share_object(dvn);
    dvn_object_address
}

// === Admin Only Functions ===

/// Set admin capability (admin only)
public fun set_admin(self: &mut DVN, admin_cap: &AdminCap, admin: address, active: bool, ctx: &mut TxContext) {
    self.worker.assert_admin(admin_cap);
    self.worker.set_admin(&self.owner_cap, admin, active, ctx);
}

/// Set default multiplier bps (admin only)
public fun set_default_multiplier_bps(self: &mut DVN, admin_cap: &AdminCap, multiplier_bps: u16) {
    self.worker.set_default_multiplier_bps(admin_cap, multiplier_bps);
}

/// Set deposit address (admin only)
public fun set_deposit_address(self: &mut DVN, admin_cap: &AdminCap, deposit_address: address) {
    self.worker.set_deposit_address(admin_cap, deposit_address);
}

/// Set price feed (admin only)
public fun set_price_feed(self: &mut DVN, admin_cap: &AdminCap, price_feed: address) {
    self.worker.set_price_feed(admin_cap, price_feed);
}

/// Set supported option types (admin only)
public fun set_supported_option_types(self: &mut DVN, admin_cap: &AdminCap, dst_eid: u32, option_types: vector<u8>) {
    self.worker.set_supported_option_types(admin_cap, dst_eid, option_types);
}

/// Set worker fee lib (admin only)
public fun set_worker_fee_lib(self: &mut DVN, admin_cap: &AdminCap, worker_fee_lib: address) {
    self.worker.set_worker_fee_lib(admin_cap, worker_fee_lib);
}

/// Set destination configuration (admin only)
public fun set_dst_config(
    self: &mut DVN,
    admin_cap: &AdminCap,
    dst_eid: u32,
    gas: u256,
    multiplier_bps: u16,
    floor_margin_usd: u128,
) {
    self.worker.assert_admin(admin_cap);

    let dst_config = DstConfig { gas, multiplier_bps, floor_margin_usd };
    table_ext::upsert!(&mut self.dst_configs, dst_eid, dst_config);

    event::emit(SetDstConfigEvent {
        dvn: self.worker.worker_cap_address(),
        dst_eid,
        gas,
        multiplier_bps,
        floor_margin_usd,
    });
}

/// Set PTB builder move calls (admin only) - can only be called once
public fun init_ptb_builder_move_calls(
    self: &mut DVN,
    admin_cap: &AdminCap,
    target_ptb_builder: address,
    get_fee_move_calls: vector<MoveCall>,
    assign_job_move_calls: vector<MoveCall>,
    ctx: &mut TxContext,
): Call<SetWorkerPtbParam, Void> {
    assert!(!self.ptb_builder_initialized, EPtbBuilderAlreadyInitialized);
    self.set_ptb_builder_move_calls_internal(
        admin_cap,
        target_ptb_builder,
        get_fee_move_calls,
        assign_job_move_calls,
        ctx,
    )
}

// === Admin with Signatures Functions ===

/// Set supported message library (admin with signatures)
public fun set_supported_message_lib(
    self: &mut DVN,
    admin_cap: &AdminCap,
    message_lib: address,
    supported: bool,
    expiration: u64,
    signatures: vector<u8>,
    clock: &Clock,
) {
    self.worker.assert_admin(admin_cap);

    let payload = hashes::build_set_supported_message_lib_payload(message_lib, supported, self.vid, expiration);
    self.assert_all_and_add_to_history(&signatures, expiration, payload, clock);

    self.worker.set_supported_message_lib(&self.owner_cap, message_lib, supported);
}

/// Set allowlist for an oapp sender (admin with signatures)
public fun set_allowlist(
    self: &mut DVN,
    admin_cap: &AdminCap,
    oapp: address,
    allowed: bool,
    expiration: u64,
    signatures: vector<u8>,
    clock: &Clock,
) {
    self.worker.assert_admin(admin_cap);

    let payload = hashes::build_set_allowlist_payload(oapp, allowed, self.vid, expiration);
    self.assert_all_and_add_to_history(&signatures, expiration, payload, clock);

    self.worker.set_allowlist(&self.owner_cap, oapp, allowed);
}

/// Set denylist for an oapp sender (admin with signatures)
public fun set_denylist(
    self: &mut DVN,
    admin_cap: &AdminCap,
    oapp: address,
    denied: bool,
    expiration: u64,
    signatures: vector<u8>,
    clock: &Clock,
) {
    self.worker.assert_admin(admin_cap);

    let payload = hashes::build_set_denylist_payload(oapp, denied, self.vid, expiration);
    self.assert_all_and_add_to_history(&signatures, expiration, payload, clock);

    self.worker.set_denylist(&self.owner_cap, oapp, denied);
}

/// Set paused state (admin with signatures)
public fun set_paused(
    self: &mut DVN,
    admin_cap: &AdminCap,
    paused: bool,
    expiration: u64,
    signatures: vector<u8>,
    clock: &Clock,
) {
    self.worker.assert_admin(admin_cap);

    let payload = hashes::build_set_pause_payload(paused, self.vid, expiration);
    self.assert_all_and_add_to_history(&signatures, expiration, payload, clock);

    self.worker.set_paused(&self.owner_cap, paused);
}

/// Set quorum (admin with signatures)
public fun set_quorum(
    self: &mut DVN,
    admin_cap: &AdminCap,
    quorum: u64,
    expiration: u64,
    signatures: vector<u8>,
    clock: &Clock,
) {
    self.worker.assert_admin(admin_cap);

    let payload = hashes::build_set_quorum_payload(quorum, self.vid, expiration);
    self.assert_all_and_add_to_history(&signatures, expiration, payload, clock);

    let dvn = self.worker_cap_address();
    self.multisig.set_quorum(dvn, quorum);
}

/// Set DVN signer (admin with signatures)
public fun set_dvn_signer(
    self: &mut DVN,
    admin_cap: &AdminCap,
    signer: vector<u8>,
    active: bool,
    expiration: u64,
    signatures: vector<u8>,
    clock: &Clock,
) {
    self.worker.assert_admin(admin_cap);

    let payload = hashes::build_set_dvn_signer_payload(signer, active, self.vid, expiration);
    self.assert_all_and_add_to_history(&signatures, expiration, payload, clock);

    let dvn = self.worker_cap_address();
    self.multisig.set_signer(dvn, signer, active);
}

/// Verify a packet with DVN signatures (admin with signatures)
public fun verify(
    self: &mut DVN,
    admin_cap: &AdminCap,
    target_message_lib: address,
    packet_header: vector<u8>,
    payload_hash: Bytes32,
    confirmations: u64,
    expiration: u64,
    signatures: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
): Call<VerifyParam, Void> {
    self.worker.assert_admin(admin_cap);

    let payload = hashes::build_verify_payload(
        packet_header,
        payload_hash.to_bytes(),
        confirmations,
        target_message_lib,
        self.vid,
        expiration,
    );
    self.assert_all_and_add_to_history(&signatures, expiration, payload, clock);

    let param = dvn_verify::create_param(packet_header, payload_hash, confirmations);
    call::create(self.worker.worker_cap(), target_message_lib, true, param, ctx)
}

/// Set PTB builder move calls (admin with signatures)
public fun set_ptb_builder_move_calls(
    self: &mut DVN,
    admin_cap: &AdminCap,
    target_ptb_builder: address,
    get_fee_move_calls: vector<MoveCall>,
    assign_job_move_calls: vector<MoveCall>,
    expiration: u64,
    signatures: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
): Call<SetWorkerPtbParam, Void> {
    let payload = hashes::build_set_ptb_builder_move_calls_payload(
        target_ptb_builder,
        get_fee_move_calls,
        assign_job_move_calls,
        self.vid,
        expiration,
    );
    self.assert_all_and_add_to_history(&signatures, expiration, payload, clock);

    self.set_ptb_builder_move_calls_internal(
        admin_cap,
        target_ptb_builder,
        get_fee_move_calls,
        assign_job_move_calls,
        ctx,
    )
}

/// Set worker info (admin with signatures)
public fun set_worker_info(
    self: &mut DVN,
    admin_cap: &AdminCap,
    worker_registry: &mut WorkerRegistry,
    worker_info: vector<u8>,
    expiration: u64,
    signatures: vector<u8>,
    clock: &Clock,
) {
    self.worker.assert_admin(admin_cap);

    let payload = hashes::build_set_worker_info_payload(worker_info, self.vid, expiration);
    self.assert_all_and_add_to_history(&signatures, expiration, payload, clock);

    worker_registry.set_worker_info(self.worker.worker_cap(), worker_info);
}

// === Job Assignment and Fee Functions ===

/// Assign job for DVN (called via PTB with MultiCall created by send function in ULN302)
public fun assign_job(
    self: &DVN,
    dvn_multi_call: &mut MultiCall<AssignJobParam, FeeRecipient>,
    ctx: &mut TxContext,
): Call<FeelibGetFeeParam, u64> {
    let dvn_call = dvn_multi_call.borrow_next(self.worker.worker_cap(), false);
    let param = *dvn_call.param().base();
    self.create_feelib_get_fee_call(dvn_call, param, ctx)
}

/// Confirm assign job
public fun confirm_assign_job(
    self: &DVN,
    dvn_multi_call: &mut MultiCall<AssignJobParam, FeeRecipient>,
    feelib_call: Call<FeelibGetFeeParam, u64>,
) {
    let dvn_call = dvn_multi_call.borrow_next(self.worker.worker_cap(), true);
    let (_, _, fee) = dvn_call.destroy_child(self.worker.worker_cap(), feelib_call);
    dvn_call.complete(self.worker.worker_cap(), fee_recipient::create(fee, self.worker.deposit_address()));
}

/// Get fee for verification (using MultiCall created by quote function in ULN302)
public fun get_fee(
    self: &DVN,
    dvn_multi_call: &mut MultiCall<GetFeeParam, u64>,
    ctx: &mut TxContext,
): Call<FeelibGetFeeParam, u64> {
    let dvn_call = dvn_multi_call.borrow_next(self.worker.worker_cap(), false);
    let param = *dvn_call.param();
    self.create_feelib_get_fee_call(dvn_call, param, ctx)
}

/// Confirm get fee
public fun confirm_get_fee(
    self: &DVN,
    dvn_multi_call: &mut MultiCall<GetFeeParam, u64>,
    feelib_call: Call<FeelibGetFeeParam, u64>,
) {
    let dvn_call = dvn_multi_call.borrow_next(self.worker.worker_cap(), true);
    let (_, _, fee) = dvn_call.destroy_child(self.worker.worker_cap(), feelib_call);
    dvn_call.complete(self.worker.worker_cap(), fee);
}

// === Only Signatures Functions ===

/// Change admin using multisig (signatures only)
public fun quorum_change_admin(
    self: &mut DVN,
    admin: address,
    active: bool,
    expiration: u64,
    signatures: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let payload = hashes::build_quorum_change_admin_payload(admin, active, self.vid, expiration);
    self.assert_all_and_add_to_history(&signatures, expiration, payload, clock);

    self.worker.set_admin(&self.owner_cap, admin, active, ctx);
}

// === View Functions ===

/// Get allowlist size
public fun allowlist_size(self: &DVN): u64 {
    self.worker.allowlist_size()
}

/// Get default multiplier basis points
public fun default_multiplier_bps(self: &DVN): u16 {
    self.worker.default_multiplier_bps()
}

/// Get deposit address
public fun deposit_address(self: &DVN): address {
    self.worker.deposit_address()
}

/// Get destination configuration
public fun dst_config(self: &DVN, dst_eid: u32): DstConfig {
    assert!(self.dst_configs.contains(dst_eid), EEidNotSupported);
    *self.dst_configs.borrow(dst_eid)
}

/// Check if an address has ACL permission
public fun has_acl(self: &DVN, account: address): bool {
    self.worker.has_acl(account)
}

/// Get the admin addresses
public fun admins(self: &DVN): VecSet<address> {
    self.worker.admins()
}

/// Check if admin cap is valid for this DVN
public fun is_admin(self: &DVN, admin_cap: &AdminCap): bool {
    self.worker.is_admin(admin_cap)
}

/// Check if an address is admin
public fun is_admin_address(self: &DVN, admin: address): bool {
    self.worker.is_admin_address(admin)
}

/// Check if a message library is supported
public fun is_supported_message_lib(self: &DVN, message_lib: address): bool {
    self.worker.is_supported_message_lib(message_lib)
}

/// Check if an address is in the allowlist
public fun is_allowlisted(self: &DVN, account: address): bool {
    self.worker.is_on_allowlist(account)
}

/// Check if an address is in the denylist
public fun is_denylisted(self: &DVN, account: address): bool {
    self.worker.is_on_denylist(account)
}

/// Check if worker is paused
public fun is_paused(self: &DVN): bool {
    self.worker.is_paused()
}

/// Check if address is signer
public fun is_signer(self: &DVN, signer: vector<u8>): bool {
    self.multisig.is_signer(signer)
}

/// Get price feed
public fun price_feed(self: &DVN): address {
    self.worker.price_feed()
}

/// Get quorum
public fun quorum(self: &DVN): u64 {
    self.multisig.quorum()
}

/// Get number of signers
public fun signer_count(self: &DVN): u64 {
    self.multisig.signer_count()
}

/// Get all signers as a vector
public fun signers(self: &DVN): vector<vector<u8>> {
    self.multisig.get_signers()
}

/// Get supported option types for a destination EID
public fun supported_option_types(self: &DVN, dst_eid: u32): vector<u8> {
    self.worker.get_supported_option_types(dst_eid)
}

/// Get VID
public fun vid(self: &DVN): u32 {
    self.vid
}

/// Get worker cap address for authentication
public fun worker_cap_address(self: &DVN): address {
    self.worker.worker_cap_address()
}

/// Get fee library object ID
public fun worker_fee_lib(self: &DVN): address {
    self.worker.worker_fee_lib()
}

/// Get admin cap ID from admin address
public fun admin_cap_id(self: &DVN, admin: address): address {
    self.worker.get_admin_cap_id(admin)
}

/// Check if PTB builder has been initialized
public fun is_ptb_builder_initialized(self: &DVN): bool {
    self.ptb_builder_initialized
}

// === Internal Functions ===

/// Verify signatures and mark hash as used
fun assert_all_and_add_to_history(
    self: &mut DVN,
    signatures: &vector<u8>,
    expiration: u64,
    payload: vector<u8>,
    clock: &Clock,
) {
    let current_time = sui::clock::timestamp_ms(clock) / 1000;
    assert!(expiration > current_time, EExpiredSignature);

    let hash = hash::keccak256!(&payload);
    assert!(!self.used_hashes.contains(hash), EHashAlreadyUsed);

    self.multisig.assert_signatures_verified(payload, signatures);

    self.used_hashes.add(hash, true);
}

fun create_feelib_get_fee_call<Param, Result>(
    self: &DVN,
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

    let get_fee_param = dvn_feelib_get_fee::create_param(
        param.sender(),
        param.dst_eid(),
        param.confirmations(),
        *param.options(),
        self.multisig.quorum(),
        self.worker.price_feed(),
        self.worker.default_multiplier_bps(),
        dst_config.gas,
        dst_config.multiplier_bps,
        dst_config.floor_margin_usd,
    );

    call.create_single_child(self.worker.worker_cap(), self.worker.worker_fee_lib(), get_fee_param, ctx)
}

/// Set PTB builder move calls
fun set_ptb_builder_move_calls_internal(
    self: &mut DVN,
    admin_cap: &AdminCap,
    target_ptb_builder: address,
    get_fee_move_calls: vector<MoveCall>,
    assign_job_move_calls: vector<MoveCall>,
    ctx: &mut TxContext,
): Call<SetWorkerPtbParam, Void> {
    self.worker.assert_admin(admin_cap);
    self.ptb_builder_initialized = true;
    let param = set_worker_ptb::create_param(get_fee_move_calls, assign_job_move_calls);
    call::create(self.worker.worker_cap(), target_ptb_builder, true, param, ctx)
}

// === Test Only Functions ===

#[test_only]
public(package) fun test_worker(self: &DVN): &Worker {
    &self.worker
}

#[test_only]
public(package) fun create_test_set_dst_config_event(
    dvn: address,
    dst_eid: u32,
    gas: u256,
    multiplier_bps: u16,
    floor_margin_usd: u128,
): SetDstConfigEvent {
    SetDstConfigEvent {
        dvn,
        dst_eid,
        gas,
        multiplier_bps,
        floor_margin_usd,
    }
}
