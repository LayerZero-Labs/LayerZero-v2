/// WorkerCommon provides shared functionality for LayerZero workers (DVN and Executor)
module worker_common::worker_common;

use call::call_cap::CallCap;
use iota::{event, table::{Self, Table}, vec_set::{Self, VecSet}};
use utils::table_ext;

// === Constants ===

/// IOTA native token decimals (IOTA has 9 decimals)
const IOTA_DECIMALS_RATE: u64 = 1000000000;

// === Errors ===

const EWorkerAdminAlreadyExists: u64 = 1;
const EWorkerAdminNotFound: u64 = 2;
const EWorkerAlreadyOnAllowlist: u64 = 3;
const EWorkerAlreadyOnDenylist: u64 = 4;
const EWorkerAttemptingToRemoveOnlyAdmin: u64 = 5;
const EWorkerInvalidDepositAddress: u64 = 6;
const EWorkerIsPaused: u64 = 7;
const EWorkerMessageLibAlreadySupported: u64 = 8;
const EWorkerMessageLibNotSupported: u64 = 9;
const EWorkerNoAdminsProvided: u64 = 10;
const EWorkerNotAllowed: u64 = 11;
const EWorkerNotOnAllowlist: u64 = 12;
const EWorkerNotOnDenylist: u64 = 13;
const EWorkerPauseStatusUnchanged: u64 = 14;
const EWorkerUnauthorized: u64 = 15;
const EWorkerUnsupportedMessageLib: u64 = 16;

// === Structs ===

/// Owner capability for worker management
public struct OwnerCap has key, store {
    id: UID,
}

/// Admin capability for worker management
public struct AdminCap has key {
    id: UID,
}

/// Admin registry
public struct AdminRegistry has store {
    /// Admin addresses
    active_admins: VecSet<address>,
    /// Admin address to admin cap ID mapping
    admin_to_admin_cap_id: Table<address, address>,
    /// Admin cap status
    admin_cap_status: Table<address, bool>,
}

/// Worker configuration and state
public struct Worker has store {
    /// Address where fees are deposited
    deposit_address: address,
    /// Message library package addresses
    message_libs: VecSet<address>,
    /// Fee library package address
    worker_fee_lib: address,
    /// Price feed package address
    price_feed: address,
    /// Default multiplier in basis points for fee calculation
    default_multiplier_bps: u16,
    /// Whether the worker is paused
    paused: bool,
    /// Allowlist of senders - if not empty, only senders on allowlist are allowed
    allowlist: VecSet<address>,
    /// Denylist of senders - senders on denylist are denied regardless of allowlist
    denylist: VecSet<address>,
    /// Supported option types per destination EID
    supported_option_types: Table<u32, vector<u8>>,
    /// Worker capability for message library interactions
    worker_cap: CallCap,
    /// Admin registry
    admin_registry: AdminRegistry,
    /// Owner Cap address
    owner_cap_id: address,
}

// === Events ===

public struct PausedEvent has copy, drop {
    worker: address,
}

public struct SetAdminEvent has copy, drop {
    worker: address,
    admin: address,
    active: bool,
}

public struct SetSupportedMessageLibEvent has copy, drop {
    worker: address,
    message_lib: address,
    supported: bool,
}

public struct SetAllowlistEvent has copy, drop {
    worker: address,
    oapp: address,
    allowed: bool,
}

public struct SetDefaultMultiplierBpsEvent has copy, drop {
    worker: address,
    multiplier_bps: u16,
}

public struct SetDenylistEvent has copy, drop {
    worker: address,
    oapp: address,
    denied: bool,
}

public struct SetDepositAddressEvent has copy, drop {
    worker: address,
    deposit_address: address,
}

public struct SetPriceFeedEvent has copy, drop {
    worker: address,
    price_feed: address,
}

public struct SetSupportedOptionTypesEvent has copy, drop {
    worker: address,
    dst_eid: u32,
    option_types: vector<u8>,
}

public struct SetWorkerFeeLibEvent has copy, drop {
    worker: address,
    fee_lib: address,
}

public struct UnpausedEvent has copy, drop {
    worker: address,
}

// === Initialization ===

/// Initialize a new worker with the given configuration
public fun create_worker(
    worker_cap: CallCap,
    deposit_address: address,
    supported_message_libs: vector<address>,
    price_feed: address,
    worker_fee_lib: address,
    default_multiplier_bps: u16,
    admins: vector<address>,
    ctx: &mut TxContext,
): (Worker, OwnerCap) {
    // Ensure at least one admin is provided
    assert!(!admins.is_empty(), EWorkerNoAdminsProvided);
    assert!(deposit_address != @0x0, EWorkerInvalidDepositAddress);

    // Create and transfer owner capability if owner is provided
    let owner_cap = OwnerCap { id: object::new(ctx) };
    let owner_cap_id = object::id_address(&owner_cap);

    // Create worker struct
    let mut worker = Worker {
        deposit_address,
        message_libs: vec_set::empty(),
        worker_fee_lib,
        price_feed,
        default_multiplier_bps,
        paused: false,
        allowlist: vec_set::empty(),
        denylist: vec_set::empty(),
        supported_option_types: table::new(ctx),
        worker_cap,
        admin_registry: AdminRegistry {
            active_admins: vec_set::empty(),
            admin_to_admin_cap_id: table::new(ctx),
            admin_cap_status: table::new(ctx),
        },
        owner_cap_id,
    };

    // Set admins
    admins.do!(|admin| worker.set_admin(&owner_cap, admin, true, ctx));

    // Set supported message libs
    supported_message_libs.do!(|lib| worker.set_supported_message_lib(&owner_cap, lib, true));

    (worker, owner_cap)
}

// === Owner Functions ===

/// Set admin status for the worker
public fun set_admin(worker: &mut Worker, owner_cap: &OwnerCap, admin: address, active: bool, ctx: &mut TxContext) {
    assert_owner(worker, owner_cap);
    let registry = &mut worker.admin_registry;
    if (active) {
        // Add admin - ensure not already active
        assert!(!registry.active_admins.contains(&admin), EWorkerAdminAlreadyExists);

        // Check if admin already has a capability (reactivation case)
        if (registry.admin_to_admin_cap_id.contains(admin)) {
            // Reactivate existing admin - just update status
            let admin_cap_id = *registry.admin_to_admin_cap_id.borrow(admin);
            *registry.admin_cap_status.borrow_mut(admin_cap_id) = true;
        } else {
            // New admin - create new capability
            let admin_cap = AdminCap { id: object::new(ctx) };
            let admin_cap_id = object::id_address(&admin_cap);
            registry.admin_to_admin_cap_id.add(admin, admin_cap_id);
            registry.admin_cap_status.add(admin_cap_id, true);
            transfer::transfer(admin_cap, admin);
        };
        registry.active_admins.insert(admin);
    } else {
        // Deactivate admin - ensure present
        assert!(registry.active_admins.contains(&admin), EWorkerAdminNotFound);
        registry.active_admins.remove(&admin);

        // Set admin capability status to false but keep the mapping
        let admin_cap_id = *registry.admin_to_admin_cap_id.borrow(admin);
        *registry.admin_cap_status.borrow_mut(admin_cap_id) = false;

        assert!(registry.active_admins.size() > 0, EWorkerAttemptingToRemoveOnlyAdmin);
    };

    event::emit(SetAdminEvent {
        worker: worker.worker_cap_address(),
        admin,
        active,
    });
}

/// Set supported message library
public fun set_supported_message_lib(worker: &mut Worker, owner_cap: &OwnerCap, message_lib: address, supported: bool) {
    assert_owner(worker, owner_cap);
    if (supported) {
        assert!(!worker.is_supported_message_lib(message_lib), EWorkerMessageLibAlreadySupported);
        worker.message_libs.insert(message_lib);
    } else {
        assert!(worker.is_supported_message_lib(message_lib), EWorkerMessageLibNotSupported);
        worker.message_libs.remove(&message_lib);
    };
    event::emit(SetSupportedMessageLibEvent { worker: worker.worker_cap_address(), message_lib, supported });
}

/// Set allowlist status for a sender
public fun set_allowlist(worker: &mut Worker, owner_cap: &OwnerCap, oapp: address, allowed: bool) {
    assert_owner(worker, owner_cap);
    if (allowed) {
        assert!(!worker.is_on_allowlist(oapp), EWorkerAlreadyOnAllowlist);
        worker.allowlist.insert(oapp);
    } else {
        assert!(worker.is_on_allowlist(oapp), EWorkerNotOnAllowlist);
        worker.allowlist.remove(&oapp);
    };

    event::emit(SetAllowlistEvent {
        worker: worker.worker_cap_address(),
        oapp,
        allowed,
    });
}

/// Set denylist status for a sender
public fun set_denylist(worker: &mut Worker, owner_cap: &OwnerCap, oapp: address, denied: bool) {
    assert_owner(worker, owner_cap);
    if (denied) {
        assert!(!worker.is_on_denylist(oapp), EWorkerAlreadyOnDenylist);
        worker.denylist.insert(oapp);
    } else {
        assert!(worker.is_on_denylist(oapp), EWorkerNotOnDenylist);
        worker.denylist.remove(&oapp);
    };

    event::emit(SetDenylistEvent {
        worker: worker.worker_cap_address(),
        oapp,
        denied,
    });
}

/// Set the paused state of the worker
public fun set_paused(worker: &mut Worker, owner_cap: &OwnerCap, paused: bool) {
    assert_owner(worker, owner_cap);
    // Ensure the pause state is actually changing
    assert!(worker.paused != paused, EWorkerPauseStatusUnchanged);

    worker.paused = paused;
    if (paused) {
        event::emit(PausedEvent {
            worker: worker.worker_cap_address(),
        });
    } else {
        event::emit(UnpausedEvent {
            worker: worker.worker_cap_address(),
        });
    };
}

// === Admin Functions ===

/// Set the default multiplier basis points (admin only)
public fun set_default_multiplier_bps(worker: &mut Worker, admin_cap: &AdminCap, multiplier_bps: u16) {
    assert_admin(worker, admin_cap);
    worker.default_multiplier_bps = multiplier_bps;
    event::emit(SetDefaultMultiplierBpsEvent {
        worker: worker.worker_cap_address(),
        multiplier_bps,
    });
}

/// Set the deposit address (admin only)
public fun set_deposit_address(worker: &mut Worker, admin_cap: &AdminCap, deposit_address: address) {
    assert_admin(worker, admin_cap);
    assert!(deposit_address != @0x0, EWorkerInvalidDepositAddress);
    worker.deposit_address = deposit_address;
    event::emit(SetDepositAddressEvent {
        worker: worker.worker_cap_address(),
        deposit_address,
    });
}

/// Set the price feed object ID (admin only)
public fun set_price_feed(worker: &mut Worker, admin_cap: &AdminCap, price_feed: address) {
    assert_admin(worker, admin_cap);
    worker.price_feed = price_feed;
    event::emit(SetPriceFeedEvent {
        worker: worker.worker_cap_address(),
        price_feed,
    });
}

/// Set supported option types for a destination EID (admin only)
public fun set_supported_option_types(
    worker: &mut Worker,
    admin_cap: &AdminCap,
    dst_eid: u32,
    option_types: vector<u8>,
) {
    assert_admin(worker, admin_cap);
    table_ext::upsert!(&mut worker.supported_option_types, dst_eid, option_types);
    event::emit(SetSupportedOptionTypesEvent {
        worker: worker.worker_cap_address(),
        dst_eid,
        option_types,
    });
}

/// Set the worker fee library object ID (admin only)
public fun set_worker_fee_lib(worker: &mut Worker, admin_cap: &AdminCap, worker_fee_lib: address) {
    assert_admin(worker, admin_cap);
    worker.worker_fee_lib = worker_fee_lib;
    event::emit(SetWorkerFeeLibEvent {
        worker: worker.worker_cap_address(),
        fee_lib: worker_fee_lib,
    });
}

// === View Functions ===

/// Check if a message library is supported
public fun is_supported_message_lib(worker: &Worker, message_lib: address): bool {
    worker.message_libs.contains(&message_lib)
}

/// Assert that a message library is supported
public fun assert_supported_message_lib(worker: &Worker, message_lib: address) {
    assert!(worker.is_supported_message_lib(message_lib), EWorkerUnsupportedMessageLib);
}

/// Get allowlist size
public fun allowlist_size(worker: &Worker): u64 {
    worker.allowlist.size()
}

/// Get the default multiplier basis points
public fun default_multiplier_bps(worker: &Worker): u16 {
    worker.default_multiplier_bps
}

/// Get the deposit address
public fun deposit_address(worker: &Worker): address {
    worker.deposit_address
}

/// Get the native decimals rate for the gas token on this chain (IOTA)
public fun get_native_decimals_rate(): u64 {
    IOTA_DECIMALS_RATE
}

/// Get supported option types for a destination EID
public fun get_supported_option_types(worker: &Worker, dst_eid: u32): vector<u8> {
    *table_ext::borrow_with_default!(&worker.supported_option_types, dst_eid, &vector::empty())
}

/// Check if an address has ACL permission
/// ACL logic:
/// 1) if address is in denylist -> deny
/// 2) else if address is in allowlist OR allowlist is empty -> allow
/// 3) else deny
public fun has_acl(worker: &Worker, sender: address): bool {
    if (worker.is_on_denylist(sender)) {
        false
    } else if (worker.allowlist.size() == 0 || worker.is_on_allowlist(sender)) {
        true
    } else {
        false
    }
}

/// Get the admin addresses
public fun admins(worker: &Worker): VecSet<address> {
    worker.admin_registry.active_admins
}

/// Get AdminCap ID from admin address
public fun get_admin_cap_id(worker: &Worker, admin: address): address {
    *table_ext::borrow_or_abort!(&worker.admin_registry.admin_to_admin_cap_id, admin, EWorkerAdminNotFound)
}

/// Check if admin cap is valid for this worker
public fun is_admin(worker: &Worker, admin_cap: &AdminCap): bool {
    let admin_cap_id = object::id_address(admin_cap);
    *table_ext::borrow_with_default!(&worker.admin_registry.admin_cap_status, admin_cap_id, &false)
}

/// Check if an address is admin
public fun is_admin_address(worker: &Worker, admin: address): bool {
    worker.admin_registry.active_admins.contains(&admin)
}

/// Check if an address is on the allowlist
public fun is_on_allowlist(worker: &Worker, sender: address): bool {
    worker.allowlist.contains(&sender)
}

/// Check if an address is on the denylist
public fun is_on_denylist(worker: &Worker, sender: address): bool {
    worker.denylist.contains(&sender)
}

/// Check if worker is paused
public fun is_paused(worker: &Worker): bool {
    worker.paused
}

/// Get the price feed object ID
public fun price_feed(worker: &Worker): address {
    worker.price_feed
}

/// Get the worker capability
public fun worker_cap(worker: &Worker): &CallCap {
    &worker.worker_cap
}

/// Get the address of the worker capability
public fun worker_cap_address(worker: &Worker): address {
    worker.worker_cap.id()
}

/// Get the worker fee library object ID
public fun worker_fee_lib(worker: &Worker): address {
    worker.worker_fee_lib
}

// === Assert Functions ===

/// Assert that sender has ACL permission
public fun assert_acl(worker: &Worker, sender: address) {
    assert!(worker.has_acl(sender), EWorkerNotAllowed);
}

/// Assert that the admin cap is valid for this worker
public fun assert_admin(worker: &Worker, admin_cap: &AdminCap) {
    assert!(worker.is_admin(admin_cap), EWorkerUnauthorized);
}

/// Assert that the provided OwnerCap is valid for this worker
public fun assert_owner(worker: &Worker, owner_cap: &OwnerCap) {
    assert!(worker.owner_cap_id == object::id_address(owner_cap), EWorkerUnauthorized);
}

/// Assert worker is not paused
public fun assert_worker_unpaused(worker: &Worker) {
    assert!(!worker.paused, EWorkerIsPaused);
}

// === Test Functions ===

#[test_only]
public fun create_paused_event(worker: &Worker): PausedEvent {
    PausedEvent {
        worker: worker.worker_cap_address(),
    }
}

#[test_only]
public fun create_unpaused_event(worker: &Worker): UnpausedEvent {
    UnpausedEvent {
        worker: worker.worker_cap_address(),
    }
}

#[test_only]
public fun create_set_admin_event(worker: &Worker, admin: address, active: bool): SetAdminEvent {
    SetAdminEvent {
        worker: worker.worker_cap_address(),
        admin,
        active,
    }
}

#[test_only]
public fun create_set_default_multiplier_bps_event(worker: &Worker, multiplier_bps: u16): SetDefaultMultiplierBpsEvent {
    SetDefaultMultiplierBpsEvent {
        worker: worker.worker_cap_address(),
        multiplier_bps,
    }
}

#[test_only]
public fun create_set_allowlist_event(worker: &Worker, oapp: address, allowed: bool): SetAllowlistEvent {
    SetAllowlistEvent {
        worker: worker.worker_cap_address(),
        oapp,
        allowed,
    }
}

#[test_only]
public fun create_set_denylist_event(worker: &Worker, oapp: address, denied: bool): SetDenylistEvent {
    SetDenylistEvent {
        worker: worker.worker_cap_address(),
        oapp,
        denied,
    }
}

#[test_only]
public fun create_set_worker_fee_lib_event(worker: &Worker, worker_fee_lib: address): SetWorkerFeeLibEvent {
    SetWorkerFeeLibEvent {
        worker: worker.worker_cap_address(),
        fee_lib: worker_fee_lib,
    }
}

#[test_only]
public fun create_set_deposit_address_event(worker: &Worker, deposit_address: address): SetDepositAddressEvent {
    SetDepositAddressEvent {
        worker: worker.worker_cap_address(),
        deposit_address,
    }
}

#[test_only]
public fun create_set_price_feed_event(worker: &Worker, price_feed: address): SetPriceFeedEvent {
    SetPriceFeedEvent {
        worker: worker.worker_cap_address(),
        price_feed,
    }
}

#[test_only]
public fun create_set_supported_option_types_event(
    worker: &Worker,
    dst_eid: u32,
    option_types: vector<u8>,
): SetSupportedOptionTypesEvent {
    SetSupportedOptionTypesEvent {
        worker: worker.worker_cap_address(),
        dst_eid,
        option_types,
    }
}

#[test_only]
public fun create_set_supported_message_lib_event(
    worker: &Worker,
    message_lib: address,
    supported: bool,
): SetSupportedMessageLibEvent {
    SetSupportedMessageLibEvent {
        worker: worker.worker_cap_address(),
        message_lib,
        supported,
    }
}

#[test_only]
public fun create_admin_cap_for_test(ctx: &mut TxContext): AdminCap {
    AdminCap { id: object::new(ctx) }
}
