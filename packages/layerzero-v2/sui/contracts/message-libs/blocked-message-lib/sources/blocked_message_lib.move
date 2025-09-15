/// Blocked Message Library
///
/// This module implements a non-operational message library that intentionally
/// aborts all core operations. It is useful as a sentinel to explicitly
/// disable messaging flows.
module blocked_message_lib::blocked_message_lib;

use call::{call::{Call, Void}, call_cap::{Self, CallCap}};
use endpoint_v2::{
    message_lib_quote::QuoteParam,
    message_lib_send::{SendParam, SendResult},
    message_lib_set_config::SetConfigParam,
    messaging_fee::MessagingFee
};
use std::{u64, u8};

// === Error Codes ===

const ENotImplemented: u64 = 1;

// === Structs ===

/// One-time witness for the blocked message library.
public struct BLOCKED_MESSAGE_LIB has drop {}

/// A shared object that contains a CallCap that can be referenced but never used for actual operations.
public struct BlockedMessageLib has key {
    id: UID,
    call_cap: CallCap,
}

/// Initializes and shares a new BlockedMessageLib object.
fun init(otw: BLOCKED_MESSAGE_LIB, ctx: &mut TxContext) {
    transfer::share_object(BlockedMessageLib {
        id: object::new(ctx),
        call_cap: call_cap::new_package_cap(&otw, ctx),
    });
}

// === Core Message Lib Functions ===

/// Always aborts with ENotImplemented to block quote operations.
public fun quote(_self: &BlockedMessageLib, _call: Call<QuoteParam, MessagingFee>) {
    abort ENotImplemented
}

/// Always aborts with ENotImplemented to block send operations.
public fun send(_self: &BlockedMessageLib, _call: Call<SendParam, SendResult>) {
    abort ENotImplemented
}

/// Always aborts with ENotImplemented to block config operations.
public fun set_config(_self: &BlockedMessageLib, _call: Call<SetConfigParam, Void>) {
    abort ENotImplemented
}

// === Getters ===

/// Returns the message library version tuple.
public fun version(): (u64, u8, u8) {
    (u64::max_value!(), u8::max_value!(), 2)
}
