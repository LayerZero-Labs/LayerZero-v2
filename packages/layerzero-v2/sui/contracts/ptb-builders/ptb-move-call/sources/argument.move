/// Module for representing and manipulating arguments used in Programmable Transaction Block (PTB) move calls.
/// This module provides an abstraction for different types of arguments that can be passed to functions
/// in a transaction block, including object references, pure values, and results from previous calls.
module ptb_move_call::argument;

use utils::bytes32::Bytes32;

// === Errors ===

const EInvalidArgument: u64 = 1;

// === Structs ===

/// Represents different types of arguments that can be used in PTB move calls.
/// Each variant corresponds to a different way of providing data to a function call.
public enum Argument has copy, drop, store {
    // A global ID reference to any result from a previous transaction or call.
    // Used to reference any value by its unique identifier.
    ID(Bytes32),
    // A direct object address reference.
    // Used when you have the address of an object and want to pass it as an argument.
    Object(address),
    // Pure data encoded as BCS (Binary Canonical Serialization) bytes.
    // Used for passing primitive values, structs, or any serializable data.
    Pure(vector<u8>),
    // A reference to the result of a previous call within the same transaction block.
    // The first u16 is the call index, the second u16 is the result index from that call.
    NestedResult(u16, u16),
}

// === Argument Creators ===

/// Creates an ID argument from a Bytes32 object identifier.
public fun create_id(id: Bytes32): Argument {
    Argument::ID(id)
}

/// Creates an Object argument from an address.
public fun create_object(object: address): Argument {
    Argument::Object(object)
}

/// Creates a Pure argument from BCS-encoded bytes.
public fun create_pure(value: vector<u8>): Argument {
    Argument::Pure(value)
}

/// Creates a NestedResult argument referencing the result of a previous call.
public fun create_nested_result(call_index: u16, result_index: u16): Argument {
    Argument::NestedResult(call_index, result_index)
}

// === Argument View Functions ===

/// Extracts the Bytes32 ID from an ID argument.
/// Aborts with `EInvalidArgument` if the argument is not an ID variant.
public fun id(self: &Argument): Bytes32 {
    match (self) {
        Argument::ID(id) => *id,
        _ => abort EInvalidArgument,
    }
}

/// Extracts the address from an Object argument.
/// Aborts with `EInvalidArgument` if the argument is not an Object variant.
public fun object(self: &Argument): address {
    match (self) {
        Argument::Object(object) => *object,
        _ => abort EInvalidArgument,
    }
}

/// Extracts the BCS bytes from a Pure argument.
/// Aborts with `EInvalidArgument` if the argument is not a Pure variant.
public fun pure(self: &Argument): &vector<u8> {
    match (self) {
        Argument::Pure(pure) => pure,
        _ => abort EInvalidArgument,
    }
}

/// Extracts the call and result indices from a NestedResult argument.
/// Aborts with `EInvalidArgument` if the argument is not a NestedResult variant.
public fun nested_result(self: &Argument): (u16, u16) {
    match (self) {
        Argument::NestedResult(call_index, result_index) => (*call_index, *result_index),
        _ => abort EInvalidArgument,
    }
}

// === Argument Type Checkers ===

/// Checks if the argument is an ID variant.
public fun is_id(self: &Argument): bool {
    match (self) {
        Argument::ID(_) => true,
        _ => false,
    }
}

/// Checks if the argument is an Object variant.
public fun is_object(self: &Argument): bool {
    match (self) {
        Argument::Object(_) => true,
        _ => false,
    }
}

/// Checks if the argument is a Pure variant.
public fun is_pure(self: &Argument): bool {
    match (self) {
        Argument::Pure(_) => true,
        _ => false,
    }
}

/// Checks if the argument is a NestedResult variant.
public fun is_nested_result(self: &Argument): bool {
    match (self) {
        Argument::NestedResult(_, _) => true,
        _ => false,
    }
}
