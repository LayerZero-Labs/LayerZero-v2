module router_node_1::router_node {
    use std::any::Any;
    use std::fungible_asset::FungibleAsset;
    use std::option::Option;

    use endpoint_v2_common::bytes32::Bytes32;
    use endpoint_v2_common::contract_identity::DynamicCallRef;
    use endpoint_v2_common::packet_raw::RawPacket;
    use endpoint_v2_common::send_packet::SendPacket;

    const ENOT_IMPLEMENTED: u64 = 1;

    public fun endpoint_request(
        _msglib: address,
        _call_ref: &DynamicCallRef,
        _request: Any,
    ): Any {
        abort ENOT_IMPLEMENTED
    }

    public fun quote(
        _msglib: address,
        _packet: SendPacket,
        _options: vector<u8>,
        _pay_in_zro: bool,
    ): (u64, u64) {
        abort ENOT_IMPLEMENTED
    }

    public fun send(
        _msglib: address,
        _call_ref: &DynamicCallRef,
        _packet: SendPacket,
        _options: vector<u8>,
        _native_token: &mut FungibleAsset,
        _zro_token: &mut Option<FungibleAsset>,
    ): (u64, u64, RawPacket) {
        abort ENOT_IMPLEMENTED
    }

    public fun commit_verification(
        _msglib: address,
        _call_ref: &DynamicCallRef,
        _packet_header: RawPacket,
        _payload_hash: Bytes32,
    ): (address, u32, Bytes32, u64) {
        abort ENOT_IMPLEMENTED
    }

    public fun dvn_verify(
        _msglib: address,
        _call_ref: &DynamicCallRef,
        _params: Any,
    ) {
        abort ENOT_IMPLEMENTED
    }

    public fun set_config(
        _msglib: address,
        _call_ref: &DynamicCallRef,
        _oapp: address,
        _config_type: u32,
        _config: vector<u8>,
    ) {
        abort ENOT_IMPLEMENTED
    }

    public fun get_config(_msglib: address, _oapp: address, _eid: u32, _config_type: u32): vector<u8> {
        abort ENOT_IMPLEMENTED
    }

    #[view]
    public fun version(_msglib: address): (u64, u8, u8) {
        abort ENOT_IMPLEMENTED
    }

    #[view]
    public fun is_supported_send_eid(_msglib: address, _eid: u32): bool {
        abort ENOT_IMPLEMENTED
    }

    #[view]
    public fun is_supported_receive_eid(_msglib: address, _eid: u32): bool {
        abort ENOT_IMPLEMENTED
    }
}
