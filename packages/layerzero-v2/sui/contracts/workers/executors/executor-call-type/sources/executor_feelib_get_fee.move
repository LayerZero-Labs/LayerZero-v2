module executor_call_type::executor_feelib_get_fee;

// === Structs ===

public struct FeelibGetFeeParam has copy, drop, store {
    // message params
    sender: address,
    dst_eid: u32,
    call_data_size: u64,
    options: vector<u8>,
    // common configed params
    price_feed: address,
    default_multiplier_bps: u16,
    // by dst_eid configed params
    lz_receive_base_gas: u64,
    lz_compose_base_gas: u64,
    floor_margin_usd: u128,
    native_cap: u128,
    multiplier_bps: u16,
}

// result is u64

// === Creation ===

public fun create_param(
    // message params
    sender: address,
    dst_eid: u32,
    call_data_size: u64,
    options: vector<u8>,
    // common configed params
    price_feed: address,
    default_multiplier_bps: u16,
    // by dst_eid configed params
    lz_receive_base_gas: u64,
    lz_compose_base_gas: u64,
    floor_margin_usd: u128,
    native_cap: u128,
    multiplier_bps: u16,
): FeelibGetFeeParam {
    FeelibGetFeeParam {
        sender,
        dst_eid,
        call_data_size,
        options,
        price_feed,
        default_multiplier_bps,
        lz_receive_base_gas,
        lz_compose_base_gas,
        floor_margin_usd,
        native_cap,
        multiplier_bps,
    }
}

// === Getters ===

public fun sender(self: &FeelibGetFeeParam): address {
    self.sender
}

public fun dst_eid(self: &FeelibGetFeeParam): u32 {
    self.dst_eid
}

public fun call_data_size(self: &FeelibGetFeeParam): u64 {
    self.call_data_size
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

public fun lz_receive_base_gas(self: &FeelibGetFeeParam): u64 {
    self.lz_receive_base_gas
}

public fun lz_compose_base_gas(self: &FeelibGetFeeParam): u64 {
    self.lz_compose_base_gas
}

public fun floor_margin_usd(self: &FeelibGetFeeParam): u128 {
    self.floor_margin_usd
}

public fun native_cap(self: &FeelibGetFeeParam): u128 {
    self.native_cap
}

public fun multiplier_bps(self: &FeelibGetFeeParam): u16 {
    self.multiplier_bps
}
