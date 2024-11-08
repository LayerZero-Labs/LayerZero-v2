module simple_msglib::router_calls {
    use std::any::Any;
    use std::fungible_asset::FungibleAsset;
    use std::option::{Self, Option};

    use endpoint_v2_common::bytes32::{Self, Bytes32};
    use endpoint_v2_common::contract_identity::{DynamicCallRef, get_dynamic_call_ref_caller};
    use endpoint_v2_common::packet_raw::RawPacket;
    use endpoint_v2_common::packet_v1_codec;
    use endpoint_v2_common::send_packet::{Self, SendPacket};
    use endpoint_v2_common::universal_config;
    use simple_msglib::msglib;

    public fun quote(_packet: SendPacket, _options: vector<u8>, pay_in_zro: bool): (u64, u64) {
        let (native_fee, zro_fee) = msglib::get_messaging_fee();
        if (pay_in_zro) (0, zro_fee) else (native_fee, 0)
    }

    public fun send(
        call_ref: &DynamicCallRef,
        packet: SendPacket,
        _options: vector<u8>,
        _native_token: &mut FungibleAsset,
        zro_token: &mut Option<FungibleAsset>,
    ): (u64, u64, RawPacket) {
        assert!(get_dynamic_call_ref_caller(call_ref, @simple_msglib, b"send") == @endpoint_v2, EINVALID_CALLER);

        let (
            nonce,
            src_eid,
            sender,
            dst_eid,
            receiver,
            guid,
            message,
        ) = send_packet::unpack_send_packet(packet);

        let (native_fee, zro_fee) = msglib::get_messaging_fee();
        let packet = packet_v1_codec::new_packet_v1(
            src_eid,
            sender,
            dst_eid,
            receiver,
            nonce,
            guid,
            message,
        );
        if (option::is_some(zro_token)) (0, zro_fee, packet) else (native_fee, 0, packet)
    }

    public fun commit_verification(
        call_ref: &DynamicCallRef,
        packet_header: RawPacket,
        _payload_hash: Bytes32,
    ): (address, u32, Bytes32, u64) {
        assert!(
            get_dynamic_call_ref_caller(call_ref, @simple_msglib, b"commit_verification") == @endpoint_v2,
            EINVALID_CALLER,
        );

        // Assert header
        packet_v1_codec::assert_receive_header(&packet_header, universal_config::eid());

        // No check for verifiable in simple message lib

        // Decode the header
        let receiver = bytes32::to_address(packet_v1_codec::get_receiver(&packet_header));
        let src_eid = packet_v1_codec::get_src_eid(&packet_header);
        let sender = packet_v1_codec::get_sender(&packet_header);
        let nonce = packet_v1_codec::get_nonce(&packet_header);
        (receiver, src_eid, sender, nonce)
    }

    public fun dvn_verify(_call_ref: &DynamicCallRef, _params: Any) {
        abort ENOT_IMPLEMENTED
    }

    public fun set_config(_call_ref: &DynamicCallRef, __oapp: address, _config_type: u32, _config: vector<u8>) {
        abort ENOT_IMPLEMENTED
    }

    #[view]
    public fun get_config(_oapp: address, _eid: u32, _config_type: u32): vector<u8> {
        abort ENOT_IMPLEMENTED
    }

    #[view]
    public fun version(): (u64 /*major*/, u8 /*minor*/, u8 /*endpoint_version*/) {
        (0, 0, 2)
    }

    #[view]
    public fun is_supported_send_eid(_eid: u32): bool {
        true
    }

    #[view]
    public fun is_supported_receive_eid(_eid: u32): bool {
        true
    }

    // ================================================== Error Codes =================================================

    const EINVALID_CALLER: u64 = 1;
    const ENOT_IMPLEMENTED: u64 = 2;
}
