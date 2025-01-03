module blocked_msglib::router_calls {
    use std::any::Any;
    use std::fungible_asset::FungibleAsset;
    use std::option::Option;

    use endpoint_v2_common::bytes32::Bytes32;
    use endpoint_v2_common::contract_identity::DynamicCallRef;
    use endpoint_v2_common::packet_raw::RawPacket;
    use endpoint_v2_common::send_packet::SendPacket;

    const ENOT_IMPLEMENTED: u64 = 1;

    public fun quote(
        _packet: SendPacket,
        _options: vector<u8>,
        _pay_in_zro: bool,
    ): (u64, u64) {
        abort ENOT_IMPLEMENTED
    }

    public fun send(
        _call_ref: &DynamicCallRef,
        _packet: SendPacket,
        _options: vector<u8>,
        _native_token: &mut FungibleAsset,
        _zro_token: &mut Option<FungibleAsset>,
    ): (u64, u64, RawPacket) {
        abort ENOT_IMPLEMENTED
    }

    public fun commit_verification(
        _call_ref: &DynamicCallRef,
        _packet_header: RawPacket,
        _payload_hash: Bytes32,
    ): (address, u32, Bytes32, u64) {
        abort ENOT_IMPLEMENTED
    }

    public fun dvn_verify(_call_ref: &DynamicCallRef, _params: Any) {
        abort ENOT_IMPLEMENTED
    }

    public fun set_config(_call_ref: &DynamicCallRef, _oapp: address, _config_type: u32, _config: vector<u8>) {
        abort ENOT_IMPLEMENTED
    }

    #[view]
    public fun get_config(_oapp: address, _eid: u32, _config_type: u32): vector<u8> {
        abort ENOT_IMPLEMENTED
    }

    #[view]
    public fun version(): (u64 /*major*/, u8 /*minor*/, u8 /*endpoint_version*/) {
        (0xffffffffffffffff, 0xff, 2)
    }

    #[view]
    public fun is_supported_send_eid(_eid: u32): bool {
        true
    }

    #[view]
    public fun is_supported_receive_eid(_eid: u32): bool {
        true
    }
}
