/// Entrypoint for all calls that come from the Message Library Router
module uln_302::router_calls {
    use std::any::Any;
    use std::fungible_asset::FungibleAsset;
    use std::option::Option;

    use endpoint_v2_common::bytes32::Bytes32;
    use endpoint_v2_common::contract_identity::{
        DynamicCallRef,
        get_dynamic_call_ref_caller,
    };
    use endpoint_v2_common::packet_raw::RawPacket;
    use endpoint_v2_common::send_packet::SendPacket;
    use msglib_types::dvn_verify_params;
    use uln_302::configuration;
    use uln_302::sending;
    use uln_302::verification;

    // ==================================================== Sending ===================================================

    /// Provides a quote for sending a packet
    public fun quote(
        packet: SendPacket,
        options: vector<u8>,
        pay_in_zro: bool,
    ): (u64, u64) {
        sending::quote(packet, options, pay_in_zro)
    }

    /// Takes payment for sending a packet and triggers offchain entities to verify and deliver the packet
    public fun send(
        call_ref: &DynamicCallRef,
        packet: SendPacket,
        options: vector<u8>,
        native_token: &mut FungibleAsset,
        zro_token: &mut Option<FungibleAsset>,
    ): (u64, u64, RawPacket) {
        assert_caller_is_endpoint_v2(call_ref, b"send");
        sending::send(
            packet,
            options,
            native_token,
            zro_token,
        )
    }

    // =================================================== Receiving ==================================================

    /// Commits a verification for a packet and clears the memory of that packet
    ///
    /// Once a packet is committed, it cannot be recommitted without receiving all verifications again. This will abort
    /// if the packet has not been verified by all required parties. This is to be called in conjunction with the
    /// endpoint's `verify()`, which identifies the message as ready to be delivered by storing the message hash.
    public fun commit_verification(
        call_ref: &DynamicCallRef,
        packet_header: RawPacket,
        payload_hash: Bytes32,
    ): (address, u32, Bytes32, u64) {
        assert_caller_is_endpoint_v2(call_ref, b"commit_verification");
        verification::commit_verification(packet_header, payload_hash)
    }

    // ===================================================== DVNs =====================================================

    /// This is called by the DVN to verify a packet
    ///
    /// This expects an Any of type DvnVerifyParams, which contains the packet header, payload hash, and the number of
    /// confirmations. This is stored and the verifications are checked as a group when `commit_verification` is called.
    public fun dvn_verify(contract_id: &DynamicCallRef, params: Any) {
        let worker = get_dynamic_call_ref_caller(contract_id, @uln_302, b"dvn_verify");
        let (packet_header, payload_hash, confirmations) = dvn_verify_params::unpack_dvn_verify_params(params);
        verification::verify(worker, packet_header, payload_hash, confirmations)
    }

    // ================================================= Configuration ================================================

    /// Sets the ULN and Executor configurations for an OApp
    public fun set_config(call_ref: &DynamicCallRef, oapp: address, config_type: u32, config: vector<u8>) {
        assert_caller_is_endpoint_v2(call_ref, b"set_config");
        configuration::set_config(oapp, config_type, config)
    }

    #[view]
    /// Gets the ULN or Executor configuration for an eid on an OApp
    public fun get_config(oapp: address, eid: u32, config_type: u32): vector<u8> {
        configuration::get_config(oapp, eid, config_type)
    }

    // ==================================================== Helper ====================================================

    fun assert_caller_is_endpoint_v2(call_ref: &DynamicCallRef, authorization: vector<u8>) {
        let caller = get_dynamic_call_ref_caller(call_ref, @uln_302, authorization);
        assert!(caller == @endpoint_v2, EINVALID_CALLER);
    }

    // ================================================ View Functions ================================================

    #[view]
    public fun version(): (u64 /*major*/, u8 /*minor*/, u8 /*endpoint_version*/) {
        (3, 0, 2)
    }

    #[view]
    public fun is_supported_send_eid(eid: u32): bool {
        configuration::supports_send_eid(eid)
    }

    #[view]
    public fun is_supported_receive_eid(eid: u32): bool {
        configuration::supports_receive_eid(eid)
    }

    // ================================================== Error Codes =================================================

    const EINVALID_CALLER: u64 = 1;
}
