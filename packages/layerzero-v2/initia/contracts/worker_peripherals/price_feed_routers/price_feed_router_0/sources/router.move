module price_feed_router_0::router {
    public fun estimate_fee_on_send(
        price_feed: address,
        feed_address: address,
        dst_eid: u32,
        call_data_size: u64,
        gas: u128,
    ): (u128, u128, u128, u128) {
        if (price_feed == @price_feed_module_0) {
            price_feed_module_0::feeds::estimate_fee_on_send(feed_address, dst_eid, call_data_size, gas)
        } else {
            price_feed_router_1::router::estimate_fee_on_send(
                price_feed,
                feed_address,
                dst_eid,
                call_data_size,
                gas,
            )
        }
    }
}