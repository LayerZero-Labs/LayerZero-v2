/// Compose module for an OApp
/// This only needs to be included if the OApp needs to be a compose recipient
module oft::oapp_compose {
    use std::fungible_asset::FungibleAsset;
    use std::option::{Self, Option};
    use std::string::utf8;
    use std::type_info::{module_name, type_of};

    use endpoint_v2::endpoint::{Self, get_guid_and_index_from_wrapped, wrap_guid_and_index, WrappedGuidAndIndex};
    use endpoint_v2_common::bytes32::to_bytes32;
    use oft::oapp_store;
    use oft::oapp_store::is_native_token;
    use oft::oft::lz_compose_impl;

    /// LZ Compose function for self-execution
    public entry fun lz_compose(
        from: address,
        guid: vector<u8>,
        index: u16,
        message: vector<u8>,
        extra_data: vector<u8>,
    ) {
        let guid = to_bytes32(guid);
        endpoint::clear_compose(&oapp_store::call_ref(), from, wrap_guid_and_index(guid, index), message);

        lz_compose_impl(
            from,
            guid,
            index,
            message,
            extra_data,
            option::none(),
        )
    }

    /// LZ Compose function to be called by the Executor
    /// This is able to be provided a compose value in the form of a FungibleAsset
    /// For self-executing with a value, this should be called with a script
    public fun lz_compose_with_value(
        from: address,
        guid_and_index: WrappedGuidAndIndex,
        message: vector<u8>,
        extra_data: vector<u8>,
        value: Option<FungibleAsset>,
    ) {
        // Make sure that the value provided is of the native token type
        assert!(option::is_none(&value) || is_native_token(option::borrow(&value)), EINVALID_TOKEN);

        // Unwrap the guid and index from the wrapped guid and index, this wrapping
        let (guid, index) = get_guid_and_index_from_wrapped(&guid_and_index);

        endpoint::clear_compose(&oapp_store::call_ref(), from, guid_and_index, message);

        lz_compose_impl(
            from,
            guid,
            index,
            message,
            extra_data,
            value,
        );
    }

    // ================================================ Initialization ================================================

    fun init_module(account: &signer) {
        let module_name = module_name(&type_of<LzComposeModule>());
        endpoint::register_composer(account, utf8(module_name));
    }

    /// Struct to dynamically derive the module name to register on the endpoint
    struct LzComposeModule {}

    #[test_only]
    public fun init_module_for_test() {
        init_module(&std::account::create_signer_for_test(oft::oapp_store::OAPP_ADDRESS()));
    }

    // ================================================== Error Codes =================================================

    const EINVALID_TOKEN: u64 = 1;
}
