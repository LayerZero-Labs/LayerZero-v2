module dvn_fee_lib_router_0::dvn_fee_lib_router {
    use dvn_fee_lib_router_1::dvn_fee_lib_router as dvn_fee_lib_router_next;

    public fun get_dvn_fee(
        msglib: address,
        dvn_fee_lib: address,
        worker: address,
        dst_eid: u32,
        sender: address,
        packet_header: vector<u8>,
        payload_hash: vector<u8>,
        confirmations: u64,
        options: vector<u8>,
    ): (u64, address) {
        if (dvn_fee_lib == @dvn_fee_lib_0) {
            dvn_fee_lib_0::dvn_fee_lib::get_dvn_fee(
                msglib,
                worker,
                dst_eid,
                sender,
                packet_header,
                payload_hash,
                confirmations,
                options,
            )
        } else {
            dvn_fee_lib_router_next::get_dvn_fee(
                msglib,
                dvn_fee_lib,
                worker,
                dst_eid,
                sender,
                packet_header,
                payload_hash,
                confirmations,
                options,
            )
        }
    }
}
