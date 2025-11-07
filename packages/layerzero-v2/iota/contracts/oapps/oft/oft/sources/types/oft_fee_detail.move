module oft::oft_fee_detail;

use std::ascii::String;

// === Structs ===

/// Detailed fee information for OFT transfer operations
public struct OFTFeeDetail has copy, drop, store {
    /// Fee amount in local decimals (positive value regardless of fee/reward)
    fee_amount_ld: u64,
    /// Whether this represents a reward (true) or cost (false) to the user
    is_reward: bool,
    /// Human-readable description of this fee component
    description: String,
}

// === Creation ===

/// Creates fee detail information for OFT operations
public(package) fun create(fee_amount_ld: u64, is_reward: bool, description: String): OFTFeeDetail {
    OFTFeeDetail { fee_amount_ld, is_reward, description }
}

// === Getters ===

/// Returns the fee amount and reward flag (amount should be subtracted if reward is true)
public fun fee_amount_ld(self: &OFTFeeDetail): (u64, bool) {
    (self.fee_amount_ld, self.is_reward)
}

/// Returns the human-readable description of this fee component
public fun description(self: &OFTFeeDetail): &String {
    &self.description
}
