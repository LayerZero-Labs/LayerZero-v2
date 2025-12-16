module dvn_call_type::dvn_feelib_get_fee;

public struct FeelibGetFeeParam has copy, drop, store {
    // message params
    sender: address,
    dst_eid: u32,
    confirmations: u64,
    options: vector<u8>,
    // common configed params
    quorum: u64,
    price_feed: address,
    default_multiplier_bps: u16,
    // by dst_eid configed params
    gas: u256,
    multiplier_bps: u16,
    floor_margin_usd: u128,
}

// result is u64

// === Creation ===

public fun create_param(
    sender: address,
    dst_eid: u32,
    confirmations: u64,
    options: vector<u8>,
    quorum: u64,
    price_feed: address,
    default_multiplier_bps: u16,
    gas: u256,
    multiplier_bps: u16,
    floor_margin_usd: u128,
): FeelibGetFeeParam {
    FeelibGetFeeParam {
        sender,
        dst_eid,
        confirmations,
        quorum,
        options,
        price_feed,
        default_multiplier_bps,
        gas,
        multiplier_bps,
        floor_margin_usd,
    }
}

// === Getters ===

public fun sender(self: &FeelibGetFeeParam): address {
    self.sender
}

public fun dst_eid(self: &FeelibGetFeeParam): u32 {
    self.dst_eid
}

public fun confirmations(self: &FeelibGetFeeParam): u64 {
    self.confirmations
}

public fun quorum(self: &FeelibGetFeeParam): u64 {
    self.quorum
}

public fun options(self: &FeelibGetFeeParam): &vector<u8> {
    &self.options
}

public fun price_feed(self: &FeelibGetFeeParam): address {
    self.price_feed
}

public fun default_multiplier_bps(self: &FeelibGetFeeParam): u16 {
    self.default_multiplier_bps
}

public fun gas(self: &FeelibGetFeeParam): u256 {
    self.gas
}

public fun multiplier_bps(self: &FeelibGetFeeParam): u16 {
    self.multiplier_bps
}

public fun floor_margin_usd(self: &FeelibGetFeeParam): u128 {
    self.floor_margin_usd
}
