/// Messaging receipt structure for endpoint v2.
/// Provides a receipt for successful message sending operations with unique identifiers and fee information.
module endpoint_v2::messaging_receipt;

use endpoint_v2::messaging_fee::MessagingFee;
use utils::bytes32::Bytes32;

/// Receipt structure returned after successfully sending a message.
/// Contains unique identifiers and fee information for tracking and verification purposes.
public struct MessagingReceipt has copy, drop, store {
    // Globally unique identifier for the message
    guid: Bytes32,
    // Sequential number for message ordering
    nonce: u64,
    // Fee information for the messaging operation
    messaging_fee: MessagingFee,
}

/// Creates a new MessagingReceipt with the specified guid, nonce, and messaging fee.
public(package) fun create(guid: Bytes32, nonce: u64, messaging_fee: MessagingFee): MessagingReceipt {
    MessagingReceipt { guid, nonce, messaging_fee }
}

// === Getters ===

/// Returns the globally unique identifier of the message.
public fun guid(self: &MessagingReceipt): Bytes32 {
    self.guid
}

/// Returns the nonce (sequential number) of the message.
public fun nonce(self: &MessagingReceipt): u64 {
    self.nonce
}

/// Returns a reference to the messaging fee information.
public fun messaging_fee(self: &MessagingReceipt): &MessagingFee {
    &self.messaging_fee
}
