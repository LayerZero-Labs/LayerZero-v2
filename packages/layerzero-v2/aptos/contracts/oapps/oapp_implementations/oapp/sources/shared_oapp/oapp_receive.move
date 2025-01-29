/// This is an internal module that receives the lz_receive call from the Executor. This in turn calls the handler in
/// `oapp_receive_handler::lz_receive_impl` which is implemented by the OApp developer.
///
/// This module should generally not be modified by the OApp developer.
module oapp::oapp_receive {
    use std::fungible_asset::FungibleAsset;
    use std::option::{Self, Option};
    use std::string::utf8;
    use std::type_info::{module_name, type_of};

    use endpoint_v2::endpoint::{Self, get_guid_from_wrapped, wrap_guid, WrappedGuid};
    use endpoint_v2_common::bytes32::to_bytes32;
    use oapp::oapp::{lz_receive_impl, next_nonce_impl};
    use oapp::oapp_core::get_peer_bytes32;
    use oapp::oapp_store;
    use oapp::oapp_store::is_native_token;

    /// LZ Receive function for self-execution
    public entry fun lz_receive(
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        guid: vector<u8>,
        message: vector<u8>,
        extra_data: vector<u8>,
    ) {
        lz_receive_with_value(
            src_eid,
            sender,
            nonce,
            wrap_guid(to_bytes32(guid)),
            message,
            extra_data,
            option::none(),
        )
    }

    /// LZ Receive function to be called by the Executor
    /// This is able to be provided a receive value in the form of a FungibleAsset
    /// For self-executing with a value, this should be called with a script
    /// The WrappedGuid is used by the caller script to enforce that the LayerZero endpoint is called by the OApp
    public fun lz_receive_with_value(
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        wrapped_guid: WrappedGuid,
        message: vector<u8>,
        extra_data: vector<u8>,
        value: Option<FungibleAsset>,
    ) {
        assert!(option::is_none(&value) || is_native_token(option::borrow(&value)), EINVALID_TOKEN);
        let sender = to_bytes32(sender);
        assert!(get_peer_bytes32(src_eid) == sender, ENOT_PEER);

        let guid = get_guid_from_wrapped(&wrapped_guid);
        endpoint::clear(&oapp_store::call_ref(), src_eid, sender, nonce, wrapped_guid, message);

        lz_receive_impl(
            src_eid,
            sender,
            nonce,
            guid,
            message,
            extra_data,
            value,
        );
    }

    #[view]
    /// Get the next nonce for the given pathway
    public fun next_nonce(src_eid: u32, sender: vector<u8>): u64 {
        next_nonce_impl(src_eid, to_bytes32(sender))
    }

    // ================================================ Initialization ================================================

    fun init_module(account: &signer) {
        let module_name = module_name(&type_of<LzReceiveModule>());
        endpoint::register_oapp(account, utf8(module_name));
    }

    struct LzReceiveModule {}

    #[test_only]
    public fun init_module_for_test() {
        init_module(&std::account::create_signer_for_test(oapp::oapp_store::OAPP_ADDRESS()));
    }

    // ================================================== Error Codes =================================================

    const EINVALID_TOKEN: u64 = 1;
    const ENOT_PEER: u64 = 2;
}
