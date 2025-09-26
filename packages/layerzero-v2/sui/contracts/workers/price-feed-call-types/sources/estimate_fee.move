module price_feed_call_types::estimate_fee;

public struct EstimateFeeParam has copy, drop, store {
    dst_eid: u32,
    call_data_size: u64,
    gas: u256,
}

public struct EstimateFeeResult has copy, drop, store {
    fee: u128,
    price_ratio: u128,
    price_ratio_denominator: u128,
    native_price_usd: u128,
}

// === Creation ===

public fun create_param(dst_eid: u32, call_data_size: u64, gas: u256): EstimateFeeParam {
    EstimateFeeParam { dst_eid, call_data_size, gas }
}

public fun create_result(
    fee: u128,
    price_ratio: u128,
    price_ratio_denominator: u128,
    native_price_usd: u128,
): EstimateFeeResult {
    EstimateFeeResult { fee, price_ratio, price_ratio_denominator, native_price_usd }
}

// === Param Getters ===

public fun dst_eid(self: &EstimateFeeParam): u32 {
    self.dst_eid
}

public fun call_data_size(self: &EstimateFeeParam): u64 {
    self.call_data_size
}

public fun gas(self: &EstimateFeeParam): u256 {
    self.gas
}

// === Result Getters ===

public fun fee(self: &EstimateFeeResult): u128 {
    self.fee
}

public fun price_ratio(self: &EstimateFeeResult): u128 {
    self.price_ratio
}

public fun price_ratio_denominator(self: &EstimateFeeResult): u128 {
    self.price_ratio_denominator
}

public fun native_price_usd(self: &EstimateFeeResult): u128 {
    self.native_price_usd
}
