/// This is the OFT interface that provides send, quote, and view functions for the OFT.
///
/// The OFT developer should update the name of the implementation module in the configuration section of this module.
/// Other than that, this module generally does not need to be updated by the OFT developer. As much as possible,
/// customizations should be made in the OFT implementation module.
module oapp::oapp {
    use std::fungible_asset::{FungibleAsset, Metadata};
    use std::object;
    use std::option;
    use std::option::Option;
    use std::primary_fungible_store;
    use std::signer::address_of;

    use endpoint_v2_common::bytes32::Bytes32;
    use oapp::oapp_core::{combine_options, lz_quote, lz_send, refund_fees};
    use oapp::oapp_store::OAPP_ADDRESS;

    friend oapp::oapp_receive;
    friend oapp::oapp_compose;

    const STANDARD_MESSAGE_TYPE: u16 = 1;

    // todo: replicate the logic in here where sending a message must happen
    public entry fun example_message_sender(
        account: &signer,
        dst_eid: u32,
        message: vector<u8>,
        extra_options: vector<u8>,
        native_fee: u64,
    ) {
        let sender = address_of(account);

        // Withdraw the amount and fees from the account
        let native_metadata = object::address_to_object<Metadata>(@native_token_metadata_address);
        let native_fee_fa = primary_fungible_store::withdraw(move account, native_metadata, native_fee);
        let zro_fee_fa = option::none();

        lz_send(
            dst_eid,
            message,
            combine_options(dst_eid, STANDARD_MESSAGE_TYPE, extra_options),
            &mut native_fee_fa,
            &mut zro_fee_fa,
        );

        // Return unused amounts and fees to the account
        refund_fees(sender, native_fee_fa, zro_fee_fa);
    }

    #[view]
    /// Quote the network fees for a particular send
    /// @return (native_fee, zro_fee)
    // todo: replicate the logic in here where a quote is needed
    public fun example_message_quoter(
        dst_eid: u32,
        message: vector<u8>,
        extra_options: vector<u8>,
    ): (u64, u64) {
        let options = combine_options(dst_eid, STANDARD_MESSAGE_TYPE, extra_options);

        lz_quote(
            dst_eid,
            message,
            options,
            false,
        )
    }

    public(friend) fun lz_receive_impl(
        _src_eid: u32,
        _sender: Bytes32,
        _nonce: u64,
        _guid: Bytes32,
        _message: vector<u8>,
        _extra_data: vector<u8>,
        receive_value: Option<FungibleAsset>,
    ) {
        // Deposit any received value
        option::destroy(receive_value, |value| primary_fungible_store::deposit(OAPP_ADDRESS(), value));

        // todo: Perform any actions with received message here
    }

    // ==================================================== Compose ===================================================

    public(friend) fun lz_compose_impl(
        _from: address,
        _guid: Bytes32,
        _index: u16,
        _message: vector<u8>,
        _extra_data: vector<u8>,
        _value: Option<FungibleAsset>,
    ) {
        // todo: Replace this function body with any actions that need to be run if this OApp receives a compose message
        // This only needs to be implemented if the OApp needs to *receive* composed messages
        abort ECOMPOSE_NOT_IMPLEMENTED
    }

    // =============================================== Ordered Execution ==============================================

    /// Provides the next nonce if executor options request ordered execution; returning 0 for disabled ordered
    /// execution
    public(friend) fun next_nonce_impl(_src_eid: u32, _sender: Bytes32): u64 {
        0
    }

    // ================================================== Error Codes =================================================

    const ECOMPOSE_NOT_IMPLEMENTED: u64 = 1;
}
