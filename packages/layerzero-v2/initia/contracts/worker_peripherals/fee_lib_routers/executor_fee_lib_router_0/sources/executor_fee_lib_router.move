module executor_fee_lib_router_0::executor_fee_lib_router {
    use executor_fee_lib_router_1::executor_fee_lib_router as executor_fee_lib_router_next;

    public fun get_executor_fee(
        msglib: address,
        executor_fee_lib: address,
        worker: address,
        dst_eid: u32,
        sender: address,
        message_size: u64,
        options: vector<u8>,
    ): (u64, address) {
        if (executor_fee_lib == @executor_fee_lib_0) {
            executor_fee_lib_0::executor_fee_lib::get_executor_fee(
                msglib,
                worker,
                dst_eid,
                sender,
                message_size,
                options,
            )
        } else {
            executor_fee_lib_router_next::get_executor_fee(
                msglib,
                executor_fee_lib,
                worker,
                dst_eid,
                sender,
                message_size,
                options,
            )
        }
    }
}
