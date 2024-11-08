// This module provides functions to encode and decode OFT fee detail struct
module oft_common::oft_fee_detail {
    use std::string::String;

    struct OftFeeDetail has store, copy, drop {
        // Amount of the fee in local decimals
        fee_amount_ld: u64,
        // If true, the fee is a reward; this means the fee should be taken as negative
        is_reward: bool,
        // Description of the fee
        description: String,
    }

    /// Create a new OftFeeDetail
    public fun new_oft_fee_detail(fee_amount_ld: u64, is_reward: bool, description: String): OftFeeDetail {
        OftFeeDetail { fee_amount_ld, is_reward, description }
    }

    /// Get the amount of the fee in local decimals (if is_reward is true, the fee should be taken as negative)
    public fun fee_amount_ld(fd: &OftFeeDetail): (u64, bool) { (fd.fee_amount_ld, fd.is_reward) }

    /// Get the description of the fee
    public fun description(fd: &OftFeeDetail): String { fd.description }

    /// Get all the fields of the OftFeeDetail
    /// @return (fee_amount_ld, is_reward, description)
    public fun unpack_oft_fee_detail(fd: OftFeeDetail): (u64, bool, String) {
        let OftFeeDetail { fee_amount_ld, is_reward, description } = fd;
        (fee_amount_ld, is_reward, description)
    }
}
