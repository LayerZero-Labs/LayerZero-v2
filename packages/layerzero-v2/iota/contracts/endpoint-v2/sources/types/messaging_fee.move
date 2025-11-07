/// Messaging fee structure for endpoint v2.
/// Defines the fee structure for cross-chain messaging operations, supporting both native and ZRO token fees.
module endpoint_v2::messaging_fee;

/// Fee structure for messaging operations containing native and ZRO token fees.
/// Used to specify the cost of sending messages across different chains.
public struct MessagingFee has copy, drop, store {
    // Fee amount in native tokens
    native_fee: u64,
    // Fee amount in ZRO tokens
    zro_fee: u64,
}

/// Creates a new MessagingFee with the specified native and ZRO fee amounts.
public fun create(native_fee: u64, zro_fee: u64): MessagingFee {
    MessagingFee { native_fee, zro_fee }
}

// === Public View Functions ===

/// Returns the native fee amount.
public fun native_fee(self: &MessagingFee): u64 {
    self.native_fee
}

/// Returns the ZRO fee amount.
public fun zro_fee(self: &MessagingFee): u64 {
    self.zro_fee
}
