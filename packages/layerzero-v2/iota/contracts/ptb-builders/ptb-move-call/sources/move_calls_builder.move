/// Module for building and managing sequences of Move calls in Programmable Transaction Blocks.
/// Provides utilities to construct, combine, and manage multiple Move calls with proper
/// argument reference handling and result tracking.
module ptb_move_call::move_calls_builder;

use ptb_move_call::{argument::{Self, Argument}, move_call::MoveCall};
use utils::bytes32::Bytes32;

// === Errors ===

const EInvalidMoveCallResult: u64 = 1;
const EResultIDNotFound: u64 = 2;

// === Structs ===

/// Builder for constructing sequences of Move calls.
/// Manages a collection of Move calls and handles argument references between calls.
public struct MoveCallsBuilder has copy {
    // Vector of Move calls in execution order
    move_calls: vector<MoveCall>,
}

/// Represents the result of adding a Move call to the builder.
/// Tracks how to reference the results of the added call.
public enum MoveCallResult has copy, drop, store {
    // Index of a direct move call in the builder
    Direct(u16),
    // Global IDs of the results from a builder call
    Builder(vector<Bytes32>),
}

// === Creators ===

/// Creates a new empty MoveCallsBuilder.
public fun new(): MoveCallsBuilder {
    MoveCallsBuilder { move_calls: vector[] }
}

/// Creates a MoveCallsBuilder from an existing vector of Move calls.
public fun create(move_calls: vector<MoveCall>): MoveCallsBuilder {
    MoveCallsBuilder { move_calls }
}

// === Builder Functions ===

/// Adds a Move call to the builder and returns a result reference.
/// Returns different result types based on whether the call is a builder call or direct call.
public fun add(self: &mut MoveCallsBuilder, move_call: MoveCall): MoveCallResult {
    let result = if (move_call.is_builder_call()) {
        // check if the result_ids are all non-zero
        assert!(move_call.result_ids().all!(|id| !id.is_zero()), EInvalidMoveCallResult);
        MoveCallResult::Builder(*move_call.result_ids())
    } else {
        MoveCallResult::Direct(self.move_calls.length() as u16)
    };
    self.move_calls.push_back(move_call);
    result
}

/// Appends multiple Move calls to the builder, adjusting nested result indices.
/// Updates all nested result argument indices to account for the current builder state.
public fun append(self: &mut MoveCallsBuilder, move_calls: vector<MoveCall>) {
    let offset = self.move_calls.length() as u16;
    move_calls.do!(|mut call| {
        call.arguments_mut().do_mut!(|arg| {
            if (arg.is_nested_result()) {
                let (call_index, result_index) = arg.nested_result();
                *arg = argument::create_nested_result(call_index + offset, result_index);
            };
        });
        self.move_calls.push_back(call);
    });
}

/// Consumes the builder and returns the vector of Move calls.
public fun build(self: MoveCallsBuilder): vector<MoveCall> {
    let MoveCallsBuilder { move_calls } = self;
    move_calls
}

// === MoveCallResult View Functions ===

/// Converts a Direct MoveCallResult to a nested result argument.
/// Aborts with `EInvalidMoveCallResult` if the result is not a Direct variant.
public fun to_nested_result_arg(self: &MoveCallResult, result_index: u16): Argument {
    match (self) {
        MoveCallResult::Direct(call_index) => argument::create_nested_result(*call_index, result_index),
        _ => abort EInvalidMoveCallResult,
    }
}

/// Converts a Builder MoveCallResult to an ID argument for a specific expected ID.
/// Aborts with `EInvalidMoveCallResult` if not a Builder variant or `EResultIDNotFound` if ID not found.
public fun to_id_arg(self: &MoveCallResult, expected_id: Bytes32): Argument {
    match (self) {
        MoveCallResult::Builder(ids) => {
            assert!(ids.contains(&expected_id), EResultIDNotFound);
            argument::create_id(expected_id)
        },
        _ => abort EInvalidMoveCallResult,
    }
}

/// Checks if the MoveCallResult is the result of a builder call.
public fun is_builder_call(self: &MoveCallResult): bool {
    match (self) {
        MoveCallResult::Builder(_) => true,
        _ => false,
    }
}
