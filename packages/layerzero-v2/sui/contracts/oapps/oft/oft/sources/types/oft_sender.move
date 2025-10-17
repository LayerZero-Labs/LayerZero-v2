/// OFT Sender Module
///
/// This module defines the `OFTSender` enum which represents different types of senders
/// that can initiate OFT (Omnichain Fungible Token) transfers. It provides a unified
/// interface for handling both transaction-based senders and capability-based senders.
module oft::oft_sender;

use call::call_cap::CallCap;

// === Structs ===

/// Represents the different types of senders that can initiate OFT transfers.
public enum OFTSender has drop {
    /// Transaction-based sender - represents a direct transaction sender
    Tx(address),
    /// Capability-based sender - represents authorization through a CallCap
    CallCap(address),
}

// === Creation ===

/// Creates an OFTSender for a transaction-based sender.
public fun tx_sender(ctx: &TxContext): OFTSender {
    OFTSender::Tx(ctx.sender())
}

/// Creates an OFTSender for a capability-based authorization.
public fun call_cap_sender(call_cap: &CallCap): OFTSender {
    OFTSender::CallCap(call_cap.id())
}

// === View Functions ===

/// Extracts the address from a OFTSender variant.
public fun get_address(self: &OFTSender): address {
    match (self) {
        OFTSender::Tx(sender) => *sender,
        OFTSender::CallCap(sender) => *sender,
    }
}

/// Checks if the sender is a transaction-based sender.
public fun is_tx_sender(self: &OFTSender): bool {
    match (self) {
        OFTSender::Tx(_) => true,
        OFTSender::CallCap(_) => false,
    }
}
