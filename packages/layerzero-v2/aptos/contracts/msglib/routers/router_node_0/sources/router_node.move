/// This module provides the base branching mechanism for routing to the correct msglib implementation.
/// The design provides multiple msglib slots per router node. Each is checked against the msglib address until the
/// correct implementation is found. If no implementation is found, the request is forwarded to the next router node.
/// The final router node will always be a placeholder contract that will return an error stating that the desired
/// library was not found.
/// Any unused slot points to a upgradable placeholder contract, which makes appending new msglib implementations
/// possible while the router or any msglib contracts can remain permanently undisturbed.
module router_node_0::router_node {
    use std::any::Any;
    use std::fungible_asset::FungibleAsset;
    use std::option::Option;

    use blocked_msglib::router_calls as blocked_msglib;
    use endpoint_v2_common::bytes32::Bytes32;
    use endpoint_v2_common::contract_identity::DynamicCallRef;
    use endpoint_v2_common::packet_raw::RawPacket;
    use endpoint_v2_common::send_packet::SendPacket;
    use router_node_1::router_node as router_node_next;
    use simple_msglib::router_calls as simple_msglib;
    use uln_302::router_calls as uln_302;

    public fun quote(
        msglib: address,
        packet: SendPacket,
        options: vector<u8>,
        pay_in_zro: bool,
    ): (u64, u64) {
        if (msglib == @uln_302) {
            uln_302::quote(packet, options, pay_in_zro)
        } else if (msglib == @simple_msglib) {
            simple_msglib::quote(packet, options, pay_in_zro)
        } else if (msglib == @blocked_msglib) {
            blocked_msglib::quote(packet, options, pay_in_zro)
        } else {
            router_node_next::quote(msglib, packet, options, pay_in_zro)
        }
    }

    public fun send(
        msglib: address,
        call_ref: &DynamicCallRef,
        packet: SendPacket,
        options: vector<u8>,
        native_token: &mut FungibleAsset,
        zro_token: &mut Option<FungibleAsset>,
    ): (u64, u64, RawPacket) {
        if (msglib == @uln_302) {
            uln_302::send(call_ref, packet, options, native_token, zro_token)
        } else if (msglib == @simple_msglib) {
            simple_msglib::send(call_ref, packet, options, native_token, zro_token)
        } else if (msglib == @blocked_msglib) {
            blocked_msglib::send(call_ref, packet, options, native_token, zro_token)
        } else {
            router_node_next::send(msglib, call_ref, packet, options, native_token, zro_token)
        }
    }

    public fun commit_verification(
        msglib: address,
        call_ref: &DynamicCallRef,
        packet_header: RawPacket,
        payload_hash: Bytes32,
        extra_data: vector<u8>,
    ): (address, u32, Bytes32, u64) {
        if (msglib == @uln_302) {
            uln_302::commit_verification(call_ref, packet_header, payload_hash, extra_data)
        } else if (msglib == @simple_msglib) {
            simple_msglib::commit_verification(call_ref, packet_header, payload_hash, extra_data)
        } else if (msglib == @blocked_msglib) {
            blocked_msglib::commit_verification(call_ref, packet_header, payload_hash, extra_data)
        } else {
            router_node_next::commit_verification(msglib, call_ref, packet_header, payload_hash, extra_data)
        }
    }

    public fun dvn_verify(msglib: address, call_ref: &DynamicCallRef, params: Any) {
        if (msglib == @uln_302) {
            uln_302::dvn_verify(call_ref, params)
        } else if (msglib == @simple_msglib) {
            simple_msglib::dvn_verify(call_ref, params)
        } else if (msglib == @blocked_msglib) {
            blocked_msglib::dvn_verify(call_ref, params)
        } else {
            router_node_next::dvn_verify(msglib, call_ref, params)
        }
    }

    public fun set_config(
        msglib: address,
        call_ref: &DynamicCallRef,
        oapp: address,
        eid: u32,
        config_type: u32,
        config: vector<u8>,
    ) {
        if (msglib == @uln_302) {
            uln_302::set_config(call_ref, oapp, eid, config_type, config)
        } else if (msglib == @simple_msglib) {
            simple_msglib::set_config(call_ref, oapp, eid, config_type, config)
        } else if (msglib == @blocked_msglib) {
            blocked_msglib::set_config(call_ref, oapp, eid, config_type, config)
        } else {
            router_node_next::set_config(msglib, call_ref, oapp, eid, config_type, config)
        }
    }

    #[view]
    public fun get_config(msglib: address, oapp: address, eid: u32, config_type: u32): vector<u8> {
        if (msglib == @uln_302) {
            uln_302::get_config(oapp, eid, config_type)
        } else if (msglib == @simple_msglib) {
            simple_msglib::get_config(oapp, eid, config_type)
        } else if (msglib == @blocked_msglib) {
            blocked_msglib::get_config(oapp, eid, config_type)
        } else {
            router_node_next::get_config(msglib, oapp, eid, config_type)
        }
    }

    #[view]
    public fun version(msglib: address): (u64, u8, u8) {
        if (msglib == @uln_302) {
            uln_302::version()
        } else if (msglib == @simple_msglib) {
            simple_msglib::version()
        } else if (msglib == @blocked_msglib) {
            blocked_msglib::version()
        } else {
            router_node_next::version(msglib)
        }
    }

    #[view]
    public fun is_supported_send_eid(msglib: address, eid: u32): bool {
        if (msglib == @uln_302) {
            uln_302::is_supported_send_eid(eid)
        } else if (msglib == @simple_msglib) {
            simple_msglib::is_supported_send_eid(eid)
        } else if (msglib == @blocked_msglib) {
            blocked_msglib::is_supported_send_eid(eid)
        } else {
            router_node_next::is_supported_send_eid(msglib, eid)
        }
    }

    #[view]
    public fun is_supported_receive_eid(msglib: address, eid: u32): bool {
        if (msglib == @uln_302) {
            uln_302::is_supported_receive_eid(eid)
        } else if (msglib == @simple_msglib) {
            simple_msglib::is_supported_receive_eid(eid)
        } else if (msglib == @blocked_msglib) {
            blocked_msglib::is_supported_receive_eid(eid)
        } else {
            router_node_next::is_supported_receive_eid(msglib, eid)
        }
    }
}