/// OFT Send Context Module
///
/// This module provides the `OFTSendContext` struct which encapsulates the context
/// information for OFT send operations. It combines transfer receipt details with
/// sender information to maintain the connection between transfer details and the
/// originating sender address throughout the two-phase OFT transfer process (send -> confirm).
///
/// This design enables the OFT system to validate that the same entity that initiated
/// a transfer is the one confirming it, providing security against unauthorized confirmations.
module oft::oft_send_context;

use oft::oft_receipt::OFTReceipt;

// === Structs ===

/// Encapsulates the context information for an OFT send operation.
public struct OFTSendContext {
    oft_receipt: OFTReceipt,
    sender: address,
    call_id: address,
}

// === Creation ===

/// Creates a new OFTSendContext by combining transfer details with sender info.
public(package) fun create(oft_receipt: OFTReceipt, sender: address, call_id: address): OFTSendContext {
    OFTSendContext { oft_receipt, sender, call_id }
}

// === Destruction ===

/// Destroys the send context and returns its constituent parts.
public(package) fun destroy(self: OFTSendContext): (OFTReceipt, address, address) {
    let OFTSendContext { oft_receipt, sender, call_id } = self;
    (oft_receipt, sender, call_id)
}

// === Getters ===

/// Returns the sender address associated with this send context.
public fun sender(self: &OFTSendContext): address {
    self.sender
}

/// Returns a reference to the underlying OFT receipt.
public fun oft_receipt(self: &OFTSendContext): &OFTReceipt {
    &self.oft_receipt
}

/// Returns the call ID associated with this send context.
public fun call_id(self: &OFTSendContext): address {
    self.call_id
}
