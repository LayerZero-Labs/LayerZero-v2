/// Sequential multi-call utility module for ordered batch operations
///
/// This module provides a specialized wrapper for managing multiple calls as a coordinated batch
/// with sequential processing requirements.
///
/// 1. Sequential access to calls in a specific order
/// 2. Flexible index management
/// 3. Support for duplicate callees in the sequence
module multi_call::multi_call;

use call::{call::Call, call_cap::CallCap};

// === Errors ===

const ENoMoreCalls: u64 = 1;
const EUnauthorized: u64 = 2;

// === Structs ===

/// Container for managing multiple calls as a sequential batch
public struct MultiCall<Param, Result> {
    // Address of the caller that created this multi-call
    caller: address,
    // Vector of calls managed by this multi-call (supports duplicate callees)
    calls: vector<Call<Param, Result>>,
    // The index of the next call to be processed
    next_index: u64,
}

// === Caller Functions ===

/// Create a new multi-call batch wrapper
///
/// Creates a container for managing multiple calls with the same types.
/// The caller is authorized to destroy the multi-call and extract all calls.
/// The calls should be in the same order as the caller expects them to be processed.
public fun create<Param, Result>(caller: &CallCap, calls: vector<Call<Param, Result>>): MultiCall<Param, Result> {
    MultiCall { caller: caller.id(), calls, next_index: 0 }
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

/// Borrow the next call for sequential processing by a specific callee
///
/// This function provides controlled access to the next call in the batch by validating
/// that the requesting callee (via CallCap) is authorized to process the current call.
/// The function ensures sequential processing while allowing flexibility for callees that
/// need to access the same call multiple times before completion.
///
/// If increment_index is true, the index will be incremented to the next call.
public fun borrow_next<Param, Result>(
    self: &mut MultiCall<Param, Result>,
    callee: &CallCap,
    increment_index: bool,
): &mut Call<Param, Result> {
    // Only borrow the call if the callee matches the expected callee
    let next_index = self.next_index;
    assert!(next_index < self.calls.length(), ENoMoreCalls);
    assert!(self.calls[next_index].callee() == callee.id(), EUnauthorized);

    // Increment the index if requested
    if (increment_index) self.next_index = next_index + 1;

    // Return the call
    &mut self.calls[next_index]
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

/// Get the next index of the multi-call
public fun next_index<Param, Result>(self: &MultiCall<Param, Result>): u64 {
    self.next_index
}

/// Check if the multi-call has a next call
public fun has_next<Param, Result>(self: &MultiCall<Param, Result>): bool {
    self.next_index < self.calls.length()
}
