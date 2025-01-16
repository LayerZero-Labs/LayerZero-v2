/// This is the WOFT interface that provides send, quote, and view functions for the WOFT.
///
/// The WOFT developer should update the name of the implementation module in the configuration section of this module.
/// Other than that, this module generally does not need to be updated by the WOFT developer. As much as possible,
/// customizations should be made in the WOFT implementation module.
module bridge_remote::wrapped_assets {
    use std::fungible_asset::{Self, BurnRef, FungibleAsset, Metadata, metadata_from_asset, MintRef, MutateMetadataRef};
    use std::object::{Self, ExtendRef, Object, object_address};
    use std::option::Option;
    use std::primary_fungible_store;
    use std::signer::address_of;
    use std::string::String;

    use bridge_remote::oapp_core::{
        assert_admin,
        lz_quote,
        lz_send,
        lz_send_compose,
        refund_fees,
        withdraw_lz_fees
    };
    use bridge_remote::oapp_store::OAPP_ADDRESS;
    use bridge_remote::woft_core::{Self, assert_metadata_supported, assert_token_supported, get_token_from_metadata};
    use bridge_remote::woft_impl::{
        Self,
        balance as balance_internal,
        build_options,
        credit,
        debit_fungible_asset,
        debit_view as debit_view_internal,
        inspect_message,
        metadata as metadata_internal, woft_limit_and_fees,
    };
    use endpoint_v2::messaging_receipt::MessagingReceipt;
    use endpoint_v2_common::bytes32::{Bytes32, to_bytes32};
    use endpoint_v2_common::contract_identity::{DynamicCallRef, get_dynamic_call_ref_caller};
    use oft_common::oft_fee_detail::OftFeeDetail;
    use oft_common::oft_limit::OftLimit;

    friend bridge_remote::oapp_receive;
    friend bridge_remote::oapp_compose;
    friend bridge_remote::bridge;

    // ======================================== For FungibleAsset Enabled WOFTs =======================================

    /// Send an amount in FungibleAsset to a recipient on another EID
    public fun send(
        call_ref: &DynamicCallRef,
        dst_eid: u32,
        to: Bytes32,
        send_value: &mut FungibleAsset,
        min_amount_ld: u64,
        extra_options: vector<u8>,
        compose_message: vector<u8>,
        native_fee: &mut FungibleAsset,
        zro_fee: &mut Option<FungibleAsset>,
    ): (MessagingReceipt, WoftReceipt) {
        assert_metadata_supported(fungible_asset::metadata_from_asset(send_value));

        let sender = get_dynamic_call_ref_caller(call_ref, OAPP_ADDRESS(), b"send");
        send_internal(
            sender, dst_eid, to, send_value, min_amount_ld, extra_options, compose_message, native_fee, zro_fee,
        )
    }

    /// Send from an account to a recipient on another EID, deducting the fees and the amount to send from the sender's
    /// account
    public entry fun send_withdraw(
        account: &signer,
        token: vector<u8>,
        dst_eid: u32,
        to: vector<u8>,
        amount_ld: u64,
        min_amount_ld: u64,
        extra_options: vector<u8>,
        compose_message: vector<u8>,
        native_fee: u64,
        zro_fee: u64,
    ) {
        assert_token_supported(to_bytes32(token));

        // Withdraw the amount and fees from the account
        let metadata = metadata_internal(to_bytes32(token));
        let send_value = primary_fungible_store::withdraw(account, metadata, amount_ld);
        let (native_fee_fa, zro_fee_fa) = withdraw_lz_fees(account, native_fee, zro_fee);
        let sender = address_of(move account);

        send_internal(
            sender, dst_eid, to_bytes32(to), &mut send_value, min_amount_ld, extra_options, compose_message,
            &mut native_fee_fa, &mut zro_fee_fa,
        );

        // Return unused amounts and fees to the account
        refund_fees(sender, native_fee_fa, zro_fee_fa);
        primary_fungible_store::deposit(sender, send_value);
    }

    fun send_internal(
        sender: address,
        dst_eid: u32,
        to: Bytes32,
        send_value: &mut FungibleAsset,
        min_amount_ld: u64,
        extra_options: vector<u8>,
        compose_message: vector<u8>,
        native_fee: &mut FungibleAsset,
        zro_fee: &mut Option<FungibleAsset>,
    ): (MessagingReceipt, WoftReceipt) {
        let token = get_token_from_metadata(metadata_from_asset(send_value));

        let (messaging_receipt, amount_sent_ld, amount_received_ld) = woft_core::send(
            token,
            sender,
            dst_eid,
            to,
            compose_message,
            |message, options| {
                lz_send(dst_eid, message, options, native_fee, zro_fee)
            },
            |_nothing| debit_fungible_asset(token, sender, send_value, min_amount_ld, dst_eid),
            |amount_received_ld, message_type| build_options(
                message_type,
                dst_eid,
                extra_options,
                sender,
                amount_received_ld,
                to,
                compose_message,
            ),
            |message, options| inspect_message(message, options, true),
        );
        (messaging_receipt, WoftReceipt { token, amount_sent_ld, amount_received_ld })
    }

    // ===================================================== Quote ====================================================

    #[view]
    /// Quote the WOFT for a particular send without sending
    /// @return (
    ///   woft_limit: The minimum and maximum limits that can be sent to the recipient
    ///   fees: The fees that will be applied to the amount sent
    ///   amount_sent_ld: The amount that would be debited from the sender in local decimals
    ///   amount_received_ld: The amount that would be received by the recipient in local decimals
    /// )
    public fun quote_oft(
        token: vector<u8>,
        dst_eid: u32,
        to: vector<u8>,
        amount_ld: u64,
        min_amount_ld: u64,
        extra_options: vector<u8>,
        compose_msg: vector<u8>,
    ): (OftLimit, vector<OftFeeDetail>, u64, u64) {
        let token = to_bytes32(token);
        assert_token_supported(token);

        let (amount_sent_ld, amount_received_ld) = debit_view_internal(token, amount_ld, min_amount_ld, dst_eid);

        let (limit, fees) = woft_limit_and_fees(
            token,
            dst_eid,
            to,
            amount_ld,
            min_amount_ld,
            extra_options,
            compose_msg,
        );

        (limit, fees, amount_sent_ld, amount_received_ld)
    }

    #[view]
    /// Quote the network fees for a particular send
    /// @return (native_fee, zro_fee)
    public fun quote_send(
        token: vector<u8>,
        user_sender: address,
        dst_eid: u32,
        to: vector<u8>,
        amount_ld: u64,
        min_amount_ld: u64,
        extra_options: vector<u8>,
        compose_message: vector<u8>,
        pay_in_zro: bool,
    ): (u64, u64) {
        let token = to_bytes32(token);
        assert_token_supported(token);

        woft_core::quote_send(
            token,
            user_sender,
            to,
            compose_message,
            |message, options| lz_quote(dst_eid, message, options, pay_in_zro),
            |_nothing| debit_view_internal(token, amount_ld, min_amount_ld, dst_eid),
            |amount_received_ld, message_type| build_options(
                message_type,
                dst_eid,
                extra_options,
                user_sender,
                amount_received_ld,
                to_bytes32(to),
                compose_message,
            ),
            |message, options| inspect_message(message, options, false),
        )
    }

    // ==================================================== Receive ===================================================

    public(friend) fun lz_receive_impl(
        src_eid: u32,
        _sender: Bytes32,
        nonce: u64,
        guid: Bytes32,
        message: vector<u8>,
        _extra_data: vector<u8>,
        receive_value: Option<FungibleAsset>,
    ) {
        woft_core::receive(
            src_eid,
            nonce,
            guid,
            message,
            |to, index, message| lz_send_compose(to, index, guid, message),
            |token, to, amount_ld| credit(token, to, amount_ld, src_eid, receive_value),
        );
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
        abort ECOMPOSE_NOT_IMPLEMENTED
    }

    // ================================================= WOFT Receipt =================================================

    struct WoftReceipt has drop, store {
        token: Bytes32,
        amount_sent_ld: u64,
        amount_received_ld: u64,
    }

    public fun get_token(receipt: &WoftReceipt): Bytes32 { receipt.token }

    public fun get_amount_sent_ld(receipt: &WoftReceipt): u64 { receipt.amount_sent_ld }

    public fun get_amount_received_ld(receipt: &WoftReceipt): u64 { receipt.amount_received_ld }

    public fun unpack_oft_receipt(receipt: &WoftReceipt): (u64, u64) {
        (receipt.amount_sent_ld, receipt.amount_received_ld)
    }

    // ===================================================== Admin ====================================================

    /// Admin function to set the fee deposit address; this is initially the admin address
    public entry fun set_fee_deposit_address(admin: &signer, fee_deposit_address: address) {
        assert_admin(address_of(admin));
        woft_impl::set_fee_deposit_address(fee_deposit_address)
    }

    /// Admin function to set the default fee in basis points
    public entry fun set_default_fee_bps(admin: &signer, default_fee_bps: u64) {
        assert_admin(address_of(admin));
        woft_impl::set_default_fee_bps(default_fee_bps)
    }

    /// Admin function to set the fee in basis points for a specific token
    public entry fun set_fee_bps(admin: &signer, token: vector<u8>, default_fee_min: u64) {
        assert_admin(address_of(admin));
        woft_impl::set_fee_bps(to_bytes32(token), default_fee_min)
    }

    /// Admin function to unset the fee in basis points for a specific token
    /// After this is called, the default fee will be used
    public entry fun unset_fee_bps(admin: &signer, token: vector<u8>) {
        assert_admin(address_of(admin));
        woft_impl::unset_fee_bps(to_bytes32(token))
    }

    /// Admin function to set the icon URI for the Fungible Asset that this WAB is managing
    public entry fun set_icon_uri(admin: &signer, token: vector<u8>, icon_uri: String) {
        assert_admin(address_of(admin));
        woft_impl::set_icon_uri(to_bytes32(token), icon_uri)
    }

    /// Admin function to set the project URI for the Fungible Asset that this WAB is managing
    public entry fun set_project_uri(admin: &signer, token: vector<u8>, project_uri: String) {
        assert_admin(address_of(admin));
        woft_impl::set_project_uri(to_bytes32(token), project_uri)
    }

    /// One time admin-only function to release the refs related to the Fungible Asset that this WAB is managing
    public fun release_refs(admin: &signer, token: vector<u8>): (
        ExtendRef,
        object::TransferRef,
        MutateMetadataRef,
        fungible_asset::TransferRef,
        MintRef,
        BurnRef,
    ) {
        assert_admin(address_of(admin));
        woft_impl::release_refs(to_bytes32(token))
    }

    // ===================================================== View =====================================================

    #[view]
    /// Get the default fee in basis points
    public fun get_default_fee_bps(): u64 {
        woft_impl::get_default_fee_bps()
    }

    #[view]
    /// Get the fee in basis points for a specific token
    /// The is_default flag will be true if no fee is set for the token
    /// @return (fee_bps, is_default)
    public fun get_fee_bps_for_token(token: vector<u8>): (u64, bool) {
        let token = to_bytes32(token);
        assert_token_supported(token);
        woft_impl::get_fee_bps(token)
    }

    #[view]
    /// Get the balance of the account for the given token
    public fun balance(account: address, token: vector<u8>): u64 {
        let token = to_bytes32(token);
        assert_token_supported(token);
        balance_internal(token, account)
    }

    #[view]
    /// The address of the WOFT token
    public fun metadata_address_for_token(token: vector<u8>): address {
        object_address(&metadata_for_token(token))
    }

    #[view]
    /// The metadata object given the token address on the peer Wrapped Asset Bridge
    public fun metadata_for_token(token: vector<u8>): Object<Metadata> {
        let token = to_bytes32(token);
        assert_token_supported(token);
        metadata_internal(token)
    }

    #[view]
    /// Get the sent and received amounts for the WOFT
    /// @return (sent_amount_ld, received_amount_ld)
    public fun debit_view(token: vector<u8>, amount_ld: u64, min_amount_ld: u64, _dst_eid: u32): (u64, u64) {
        let token = to_bytes32(token);
        assert_token_supported(token);
        debit_view_internal(token, amount_ld, min_amount_ld, _dst_eid)
    }

    #[view]
    /// Converts an amount from shared decimals to local decimals
    public fun to_ld(token: vector<u8>, amount_sd: u64): u64 {
        let token = to_bytes32(token);
        assert_token_supported(token);
        woft_core::to_ld(token, amount_sd)
    }

    #[view]
    /// Converts an amount from local decimals to shared decimals
    public fun to_sd(token: vector<u8>, amount_ld: u64): u64 {
        let token = to_bytes32(token);
        assert_token_supported(token);
        woft_core::to_sd(token, amount_ld)
    }

    #[view]
    /// Get an amount with dust removed
    public fun remove_dust(token: vector<u8>, amount_ld: u64): u64 {
        let token = to_bytes32(token);
        assert_token_supported(token);
        woft_core::remove_dust(token, amount_ld)
    }

    #[view]
    /// Get the shared decimals of the WOFT
    public fun shared_decimals(token: vector<u8>): u8 {
        let token = to_bytes32(token);
        assert_token_supported(token);
        woft_core::shared_decimals(token)
    }

    #[view]
    /// Get the decimal conversion rate of the WOFT
    public fun decimal_conversion_rate(token: vector<u8>): u64 {
        let token = to_bytes32(token);
        assert_token_supported(token);
        woft_core::decimal_conversion_rate(token)
    }

    #[view]
    /// Encode an WOFT message
    /// @return (message, message_type)
    public fun encode_oft_msg(
        token: vector<u8>,
        sender: address,
        amount_ld: u64,
        to: vector<u8>,
        compose_msg: vector<u8>,
    ): (vector<u8>, u16) {
        let token = to_bytes32(token);
        assert_token_supported(token);
        woft_core::encode_woft_msg(token, sender, amount_ld, to_bytes32(to), compose_msg)
    }

    // ================================================== Error Codes =================================================

    const ECOMPOSE_NOT_IMPLEMENTED: u64 = 1;
    const EINVALID_METADATA: u64 = 2;
}
