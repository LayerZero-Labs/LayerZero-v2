/// Multi-call utility module for batch call operations
///
/// This module provides a convenient wrapper for managing multiple calls as a batch.
/// The MultiCall wrapper makes call object processing more convenient by allowing
/// the container to be passed around to different callees instead of using a vector
/// directly.
///
/// Security Notes:
/// - This wrapper does not add extra security beyond the underlying Call objects
/// - Only the specific callee can borrow their call from the MultiCall
/// - Multiple calls with the same callee are not supported by design
module call::multi_call;

use call::{call::Call, call_cap::CallCap};

// === Errors ===

const ECalleeNotFound: u64 = 1;
const EUnauthorized: u64 = 2;

// === Structs ===

/// Container for managing multiple calls as a batch
///
/// A wrapper that holds a collection of calls with the same parameter and result types.
/// This container can be passed around to different callees for processing without
/// manual vector management. Each call should have a unique callee address.
public struct MultiCall<Param, Result> {
    // Address of the caller that created this multi-call
    caller: address,
    // Vector of calls managed by this multi-call (should have unique callees)
    calls: vector<Call<Param, Result>>,
}

// === Caller Functions ===

/// Create a new multi-call batch wrapper
///
/// Creates a container for managing multiple calls with the same types.
/// The caller is authorized to destroy the multi-call and extract all calls.
/// Each call should have a unique callee address for proper operation.
public fun create<Param, Result>(caller: &CallCap, calls: vector<Call<Param, Result>>): MultiCall<Param, Result> {
    MultiCall { caller: caller.id(), calls }
}

/// Destroy the multi-call wrapper and extract all calls
///
/// Consumes the multi-call container and returns all contained calls.
/// Only the caller who created the multi-call can perform this operation.
public fun destroy<Param, Result>(self: MultiCall<Param, Result>, caller: &CallCap): vector<Call<Param, Result>> {
    assert!(caller.id() == self.caller, EUnauthorized);
    let MultiCall { calls, .. } = self;
    calls
}

// === Callee Functions ===

/// Borrow a call by callee address
///
/// Returns an immutable reference to the call that has the specified callee address.
/// This allows callees to access their specific call without manual vector management.
/// Aborts if no call with the given callee is found.
public fun borrow<Param, Result>(self: &MultiCall<Param, Result>, callee: &CallCap): &Call<Param, Result> {
    let index = self.calls.find_index!(|call| call.callee() == callee.id());
    &self.calls[index.destroy_or!(abort ECalleeNotFound)]
}

/// Borrow a mutable call by callee address
///
/// Returns a mutable reference to the call that has the specified callee address.
/// This allows callees to process and modify their specific call in place.
/// Aborts if no call with the given callee is found.
public fun borrow_mut<Param, Result>(self: &mut MultiCall<Param, Result>, callee: &CallCap): &mut Call<Param, Result> {
    let index = self.calls.find_index!(|call| call.callee() == callee.id());
    &mut self.calls[index.destroy_or!(abort ECalleeNotFound)]
}

// === Getters ===

/// Get the caller address of the multi-call
public fun caller<Param, Result>(self: &MultiCall<Param, Result>): address {
    self.caller
}

/// Get the number of calls in the multi-call
public fun length<Param, Result>(self: &MultiCall<Param, Result>): u64 {
    self.calls.length()
}

/// Check if the multi-call contains a call for the given callee
public fun contains<Param, Result>(self: &MultiCall<Param, Result>, callee: address): bool {
    self.calls.find_index!(|call| call.callee() == callee).is_some()
}
