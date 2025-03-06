module dvn_fee_lib_router_1::dvn_fee_lib_router {
    const ENOT_IMPLEMENTED: u64 = 1;

    public fun get_dvn_fee(
        _msglib: address,
        _fee_lib: address,
        _worker: address,
        _dst_eid: u32,
        _sender: address,
        _packet_header: vector<u8>,
        _payload_hash: vector<u8>,
        _confirmations: u64,
        _options: vector<u8>,
    ): (u64, address) {
        abort ENOT_IMPLEMENTED
    }
}