/// Fee Recipient Module
///
/// This module defines a `FeeRecipient` struct that pairs a fee amount with a recipient address.
/// It's commonly used in message libraries to specify where fees should be sent and how much
/// should be charged for various operations.
module message_lib_common::fee_recipient;

/// Represents a fee amount and the address that should receive it.
/// This struct is used to bundle fee information for message library operations.
public struct FeeRecipient has copy, drop, store {
    // The fee amount of the token to be paid
    fee: u64,
    // The address that should receive the fee
    recipient: address,
}

/// Creates a new FeeRecipient instance with the specified fee and recipient address.
public fun create(fee: u64, recipient: address): FeeRecipient {
    FeeRecipient { fee, recipient }
}

// === Getters ===

/// Returns the fee amount from a FeeRecipient.
public fun fee(self: &FeeRecipient): u64 {
    self.fee
}

/// Returns the recipient address from a FeeRecipient.
public fun recipient(self: &FeeRecipient): address {
    self.recipient
}
