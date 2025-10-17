module oft::oft_receipt;

// === Structs ===

/// Receipt providing transaction details for cross-chain OFT transfers
public struct OFTReceipt has copy, drop, store {
    /// Amount actually debited from sender in local decimals (after fees)
    amount_sent_ld: u64,
    /// Amount that will be received on destination chain in local decimals
    amount_received_ld: u64,
}

// === Creation ===

/// Creates a receipt documenting the amounts involved in an OFT transfer
public(package) fun create(amount_sent_ld: u64, amount_received_ld: u64): OFTReceipt {
    OFTReceipt { amount_sent_ld, amount_received_ld }
}

// === Getters ===

/// Returns the actual amount debited from sender (includes fees and protocol costs)
public fun amount_sent_ld(self: &OFTReceipt): u64 {
    self.amount_sent_ld
}

/// Returns the amount that will be received on the destination chain
public fun amount_received_ld(self: &OFTReceipt): u64 {
    self.amount_received_ld
}
