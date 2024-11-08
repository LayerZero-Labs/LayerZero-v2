module executor_fee_lib_router_1::executor_fee_lib_router {
    const ENOT_IMPLEMENTED: u64 = 1;

    public fun get_executor_fee(
        _msglib: address,
        _fee_lib: address,
        _worker: address,
        _dst_eid: u32,
        _sender: address,
        _message_size: u64,
        _options: vector<u8>,
    ): (u64, address) {
        abort ENOT_IMPLEMENTED
    }
}
