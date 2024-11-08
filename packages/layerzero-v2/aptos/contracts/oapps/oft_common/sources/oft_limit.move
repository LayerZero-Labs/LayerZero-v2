/// This provides a struct that represents an OFT limit (min and max amount transferrable in local decimals)
module oft_common::oft_limit {

    const MAX_U64: u64 = 0xffffffffffffffff;

    struct OftLimit has store, copy, drop {
        min_amount_ld: u64,
        max_amount_ld: u64,
    }

    /// Create a new OftLimit
    public fun new_oft_limit(min_amount_ld: u64, max_amount_ld: u64): OftLimit {
        OftLimit { min_amount_ld, max_amount_ld }
    }

    /// Create a new unbounded OFT Limit
    public fun new_unbounded_oft_limit(): OftLimit {
        OftLimit { min_amount_ld: 0, max_amount_ld: MAX_U64 }
    }

    /// Get the minimum amount in local decimals
    public fun min_amount_ld(oft_limit: &OftLimit): u64 { oft_limit.min_amount_ld }

    /// Get the maximum amount in local decimals
    public fun max_amount_ld(oft_limit: &OftLimit): u64 { oft_limit.max_amount_ld }

    /// Get all the fields of the OftLimit
    /// @return (min_amount_ld, max_amount_ld)
    public fun unpack_oft_limit(oft_limit: OftLimit): (u64, u64) {
        let OftLimit { min_amount_ld, max_amount_ld } = oft_limit;
        (min_amount_ld, max_amount_ld)
    }
}
