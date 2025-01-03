module price_feed_router_1::router {
    public fun estimate_fee_on_send(
        _price_feed: address,
        _feed_address: address,
        _dst_eid: u32,
        _call_data_size: u64,
        _gas: u128,
    ): (u128, u128, u128, u128) {
        abort EUNKNOWN_PRICE_FEED
    }

    // ================================================== Error Codes =================================================

    const EUNKNOWN_PRICE_FEED: u64 = 1;
}