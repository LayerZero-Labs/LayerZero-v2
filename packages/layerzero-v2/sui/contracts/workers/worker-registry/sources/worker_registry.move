/// Worker Registry Module
///
/// This module maintains mappings between worker addresses and their associated information.
module worker_registry::worker_registry;

use call::call_cap::CallCap;
use sui::{event, table::{Self, Table}};
use utils::table_ext;

// === Errors ===

const EWorkerInfoInvalid: u64 = 1;
const EWorkerInfoNotFound: u64 = 2;

// === Structs ===

/// Central registry for worker information storage and retrieval.
/// Maintains a mapping between worker addresses and their serialized configuration data.
public struct WorkerRegistry has key {
    /// Unique identifier for this registry object
    id: UID,
    /// Table mapping worker addresses to their encoded information
    worker_infos: Table<address, vector<u8>>,
}

// === Events ===

/// Event emitted when worker information is set or updated in the registry.
public struct WorkerInfoSetEvent has copy, drop {
    /// Address of the worker whose information was updated
    worker: address,
    /// The new worker information data that was stored
    worker_info: vector<u8>,
}

// === Initialization ===

/// Initializes the worker registry as a shared object.
/// This function is automatically called during module publication.
///
/// **Parameters**:
/// - `ctx`: Transaction context for object creation
fun init(ctx: &mut TxContext) {
    let worker_registry = WorkerRegistry { id: object::new(ctx), worker_infos: table::new(ctx) };
    transfer::share_object(worker_registry);
}

// === Functions ===

/// Sets or updates worker information in the registry.
/// Only the worker itself (via its CallCap) can update its own information.
///
/// **Parameters**:
/// - `self`: Mutable reference to the worker registry
/// - `worker`: CallCap proving the caller's authority over the worker
/// - `worker_info`: Encoded worker information data to store
///
/// **Emits**: WorkerInfoSetEvent with the updated information
///
/// **Aborts**: If worker_info is empty (EWorkerInfoInvalid)
public fun set_worker_info(self: &mut WorkerRegistry, worker: &CallCap, worker_info: vector<u8>) {
    assert!(worker_info.length() > 0, EWorkerInfoInvalid);
    table_ext::upsert!(&mut self.worker_infos, worker.id(), worker_info);
    event::emit(WorkerInfoSetEvent { worker: worker.id(), worker_info });
}

// === View Functions ===

/// Retrieves worker information from the registry.
/// Returns a reference to the stored worker data without copying.
///
/// **Parameters**:
/// - `self`: Reference to the worker registry
/// - `worker`: Address of the worker to look up
///
/// **Returns**: Reference to the encoded worker information data
///
/// **Aborts**: If worker is not registered (EWorkerInfoNotFound)
public fun get_worker_info(self: &WorkerRegistry, worker: address): &vector<u8> {
    table_ext::borrow_or_abort!(&self.worker_infos, worker, EWorkerInfoNotFound)
}

// === Testing Functions ===

/// Creates a WorkerRegistry instance for testing purposes.
/// Bypasses the shared object creation used in production.
///
/// **Parameters**:
/// - `ctx`: Transaction context for object creation
///
/// **Returns**: WorkerRegistry instance for testing
#[test_only]
public fun init_for_test(ctx: &mut TxContext): WorkerRegistry {
    WorkerRegistry { id: object::new(ctx), worker_infos: table::new(ctx) }
}

/// Creates a WorkerInfoSetEvent for testing event emission.
/// Allows tests to verify correct event data without triggering actual events.
///
/// **Parameters**:
/// - `worker`: Worker address for the event
/// - `worker_info`: Worker information data for the event
///
/// **Returns**: WorkerInfoSetEvent instance for testing
#[test_only]
public(package) fun create_worker_info_set_event(worker: address, worker_info: vector<u8>): WorkerInfoSetEvent {
    WorkerInfoSetEvent { worker, worker_info }
}
