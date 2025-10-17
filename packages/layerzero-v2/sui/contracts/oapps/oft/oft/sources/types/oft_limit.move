module oft::oft_limit;

use std::u64;

// === Structs ===

/// Transfer amount bounds for OFT quote operations
public struct OFTLimit has copy, drop, store {
    /// Minimum amount for transfer quotes in local decimals
    min_amount_ld: u64,
    /// Maximum amount for transfer quotes in local decimals
    max_amount_ld: u64,
}

// === Creation ===

/// Creates transfer bounds with specified minimum and maximum quote amounts
public(package) fun create(min_amount_ld: u64, max_amount_ld: u64): OFTLimit {
    OFTLimit { min_amount_ld, max_amount_ld }
}

/// Creates unbounded transfer bounds (no minimum, maximum possible amount for quotes)
public(package) fun new_unbounded_oft_limit(): OFTLimit {
    OFTLimit { min_amount_ld: 0, max_amount_ld: u64::max_value!() }
}

// === Getters ===

/// Returns the minimum amount for transfer quotes in local decimals
public fun min_amount_ld(self: &OFTLimit): u64 {
    self.min_amount_ld
}

/// Returns the maximum amount for transfer quotes in local decimals
public fun max_amount_ld(self: &OFTLimit): u64 {
    self.max_amount_ld
}
