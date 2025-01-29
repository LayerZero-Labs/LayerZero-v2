/// This is the OFT interface that provides send, quote, and view functions for the OFT.
///
/// The OFT developer should update the name of the implementation module in the configuration section of this module.
/// Other than that, this module generally does not need to be updated by the OFT developer. As much as possible,
/// customizations should be made in the OFT implementation module.
module oft::oft {
    use std::coin::Coin;
    use std::fungible_asset::{FungibleAsset, Metadata, metadata_from_asset};
    use std::object::{Object, object_address};
    use std::option::Option;
    use std::primary_fungible_store;
    use std::signer::address_of;

    use endpoint_v2::messaging_receipt::MessagingReceipt;
    use endpoint_v2_common::bytes32::{Bytes32, to_bytes32};
    use endpoint_v2_common::contract_identity::{DynamicCallRef, get_dynamic_call_ref_caller};
    use oft::oapp_core::{Self, lz_quote, lz_send, lz_send_compose, refund_fees, withdraw_lz_fees};
    use oft::oapp_store::OAPP_ADDRESS;
    use oft::oft_adapter_coin::{
        balance as balance_internal,
        build_options,
        credit,
        debit_coin,
        debit_fungible_asset,
        debit_view as debit_view_internal,
        deposit_coin,
        inspect_message,
        metadata as metadata_internal,
        oft_limit_and_fees,
        send_standards_supported as send_standards_supported_internal,
        withdraw_coin,
    };
    use oft::oft_core;
    use oft::placeholder_coin::PlaceholderCoin;
    use oft_common::oft_fee_detail::OftFeeDetail;
    use oft_common::oft_limit::OftLimit;

    // ************************************************* CONFIGURATION *************************************************

    // **Important** Replace `oft_fa` with implementation module used
    // *********************************************** END CONFIGURATION ***********************************************

    friend oft::oapp_receive;

    // ======================================== For FungibleAsset Enabled OFTs ========================================

    /// This is called to send an amount in FungibleAsset to a recipient on another EID
    public fun send(
        call_ref: &DynamicCallRef,
        dst_eid: u32,
        to: Bytes32,
        send_value: &mut FungibleAsset,
        min_amount_ld: u64,
        extra_options: vector<u8>,
        compose_message: vector<u8>,
        oft_cmd: vector<u8>,
        native_fee: &mut FungibleAsset,
        zro_fee: &mut Option<FungibleAsset>,
    ): (MessagingReceipt, OftReceipt) {
        let sender = get_dynamic_call_ref_caller(call_ref, OAPP_ADDRESS(), b"send");
        send_internal(
            sender, dst_eid, to, send_value, min_amount_ld, extra_options, compose_message, oft_cmd, native_fee,
            zro_fee,
        )
    }

    /// Send from an account to a recipient on another EID, deducting the fees and the amount to send from the sender's
    /// account
    public entry fun send_withdraw(
        account: &signer,
        dst_eid: u32,
        to: vector<u8>,
        amount_ld: u64,
        min_amount_ld: u64,
        extra_options: vector<u8>,
        compose_message: vector<u8>,
        oft_cmd: vector<u8>,
        native_fee: u64,
        zro_fee: u64,
    ) {
        // Withdraw the amount and fees from the account
        assert!(
            primary_fungible_store::balance(address_of(account), metadata()) >= amount_ld,
            EINSUFFICIENT_BALANCE,
        );
        let send_value = primary_fungible_store::withdraw(account, metadata(), amount_ld);
        let (native_fee_fa, zro_fee_fa) = withdraw_lz_fees(account, native_fee, zro_fee);
        let sender = address_of(move account);

        send_internal(
            sender, dst_eid, to_bytes32(to), &mut send_value, min_amount_ld, extra_options, compose_message, oft_cmd,
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
        oft_cmd: vector<u8>,
        native_fee: &mut FungibleAsset,
        zro_fee: &mut Option<FungibleAsset>,
    ): (MessagingReceipt, OftReceipt) {
        assert!(metadata_from_asset(send_value) == metadata(), EINVALID_METADATA);
        let (messaging_receipt, amount_sent_ld, amount_received_ld) = oft_core::send(
            sender,
            dst_eid,
            to,
            compose_message,
            |message, options| {
                lz_send(dst_eid, message, options, native_fee, zro_fee)
            },
            |_nothing| debit_fungible_asset(sender, send_value, min_amount_ld, dst_eid),
            |amount_received_ld, message_type| build_options(
                message_type,
                dst_eid,
                extra_options,
                sender,
                amount_received_ld,
                to,
                compose_message,
                oft_cmd,
            ),
            |message, options| inspect_message(message, options, true),
        );
        (messaging_receipt, OftReceipt { amount_sent_ld, amount_received_ld })
    }

    // ============================================= For Coin-enabled OFTs ============================================

    /// This is called to send an amount in Coin to a recipient on another EID
    public fun send_coin(
        call_ref: &DynamicCallRef,
        dst_eid: u32,
        to: Bytes32,
        send_value: &mut Coin<PlaceholderCoin>,
        min_amount_ld: u64,
        extra_options: vector<u8>,
        compose_message: vector<u8>,
        oft_cmd: vector<u8>,
        native_fee: &mut FungibleAsset,
        zro_fee: &mut Option<FungibleAsset>,
    ): (MessagingReceipt, OftReceipt) {
        let sender = get_dynamic_call_ref_caller(call_ref, OAPP_ADDRESS(), b"send_coin");
        send_coin_internal(
            sender, dst_eid, to, send_value, min_amount_ld, extra_options, compose_message, oft_cmd, native_fee,
            zro_fee,
        )
    }

    /// Send from an amount to a recipient on another EID, deducting the fees and the amount from the sender's account
    public entry fun send_withdraw_coin(
        account: &signer,
        dst_eid: u32,
        to: vector<u8>,
        amount_ld: u64,
        min_amount_ld: u64,
        extra_options: vector<u8>,
        compose_message: vector<u8>,
        oft_cmd: vector<u8>,
        native_fee: u64,
        zro_fee: u64,
    ) {
        // Withdraw the amount and fees from the account
        let send_value = withdraw_coin(account, amount_ld);
        let (native_fee_fa, zro_fee_fa) = withdraw_lz_fees(account, native_fee, zro_fee);

        let sender = address_of(move account);

        send_coin_internal(
            sender, dst_eid, to_bytes32(to), &mut send_value, min_amount_ld, extra_options, compose_message, oft_cmd,
            &mut native_fee_fa, &mut zro_fee_fa,
        );

        // Return unused amounts and fees back to the account
        refund_fees(sender, native_fee_fa, zro_fee_fa);
        deposit_coin(sender, send_value);
    }

    /// This is called to send an amount in Coin to a recipient on another EID
    fun send_coin_internal(
        sender: address,
        dst_eid: u32,
        to: Bytes32,
        send_value: &mut Coin<PlaceholderCoin>,
        min_amount_ld: u64,
        extra_options: vector<u8>,
        compose_message: vector<u8>,
        oft_cmd: vector<u8>,
        native_fee: &mut FungibleAsset,
        zro_fee: &mut Option<FungibleAsset>,
    ): (MessagingReceipt, OftReceipt) {
        let (messaging_receipt, amount_sent_ld, amount_received_ld) = oft_core::send(
            sender,
            dst_eid,
            to,
            compose_message,
            |message, options| {
                lz_send(dst_eid, message, options, native_fee, zro_fee)
            },
            |_nothing| debit_coin(sender, send_value, min_amount_ld, dst_eid),
            |amount_received_ld, message_type| build_options(
                message_type,
                dst_eid,
                extra_options,
                sender,
                amount_received_ld,
                to,
                compose_message,
                oft_cmd,
            ),
            |message, options| inspect_message(message, options, true),
        );
        (messaging_receipt, OftReceipt { amount_sent_ld, amount_received_ld })
    }


    // ===================================================== Quote ====================================================

    #[view]
    /// Quote the OFT for a particular send without sending
    /// @return (
    ///   oft_limit: The minimum and maximum limits that can be sent to the recipient
    ///   fees: The fees that will be applied to the amount sent
    ///   amount_sent_ld: The amount that would be debited from the sender in local decimals
    ///   amount_received_ld: The amount that would be received by the recipient in local decimals
    /// )
    public fun quote_oft(
        dst_eid: u32,
        to: vector<u8>,
        amount_ld: u64,
        min_amount_ld: u64,
        extra_options: vector<u8>,
        compose_msg: vector<u8>,
        oft_cmd: vector<u8>,
    ): (OftLimit, vector<OftFeeDetail>, u64, u64) {
        let (amount_sent_ld, amount_received_ld) = debit_view_internal(amount_ld, min_amount_ld, dst_eid);

        let (limit, fees) = oft_limit_and_fees(
            dst_eid,
            to,
            amount_ld,
            min_amount_ld,
            extra_options,
            compose_msg,
            oft_cmd,
        );
        (limit, fees, amount_sent_ld, amount_received_ld)
    }

    #[view]
    /// Quote the network fees for a particular send
    /// @return (native_fee, zro_fee)
    public fun quote_send(
        user_sender: address,
        dst_eid: u32,
        to: vector<u8>,
        amount_ld: u64,
        min_amount_ld: u64,
        extra_options: vector<u8>,
        compose_message: vector<u8>,
        oft_cmd: vector<u8>,
        pay_in_zro: bool,
    ): (u64, u64) {
        oft_core::quote_send(
            user_sender,
            to,
            compose_message,
            |message, options| lz_quote(dst_eid, message, options, pay_in_zro),
            |_nothing| debit_view_internal(amount_ld, min_amount_ld, dst_eid),
            |amount_received_ld, message_type| build_options(
                message_type,
                dst_eid,
                extra_options,
                user_sender,
                amount_received_ld,
                to_bytes32(to),
                compose_message,
                oft_cmd,
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
        oft_core::receive(
            src_eid,
            nonce,
            guid,
            message,
            |to, index, message| lz_send_compose(to, index, guid, message),
            |to, amount_ld| credit(to, amount_ld, src_eid, receive_value),
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

    // =============================================== Ordered Execution ==============================================

    /// Provides the next nonce if executor options request ordered execution; returns 0 to indicate ordered execution
    /// is disabled
    public(friend) fun next_nonce_impl(_src_eid: u32, _sender: Bytes32): u64 {
        0
    }

    // ================================================== OFT Receipt =================================================

    struct OftReceipt has drop, store {
        amount_sent_ld: u64,
        amount_received_ld: u64,
    }

    public fun get_amount_sent_ld(receipt: &OftReceipt): u64 { receipt.amount_sent_ld }

    public fun get_amount_received_ld(receipt: &OftReceipt): u64 { receipt.amount_received_ld }

    public fun unpack_oft_receipt(receipt: &OftReceipt): (u64, u64) {
        (receipt.amount_sent_ld, receipt.amount_received_ld)
    }

    // ===================================================== View =====================================================

    #[view]
    public fun balance(account: address): u64 {
        balance_internal(account)
    }

    #[view]
    /// The version of the OFT
    /// @return (interface_id, protocol_version)
    public fun oft_version(): (u64, u64) {
        (1, 1)
    }

    #[view]
    public fun send_standards_supported(): vector<vector<u8>> {
        send_standards_supported_internal()
    }

    #[view]
    /// The address of the OFT token
    public fun token(): address {
        object_address(&metadata_internal())
    }

    #[view]
    /// The metadata object of the OFT
    public fun metadata(): Object<Metadata> {
        metadata_internal()
    }

    #[view]
    public fun debit_view(amount_ld: u64, min_amount_ld: u64, _dst_eid: u32): (u64, u64) {
        debit_view_internal(amount_ld, min_amount_ld, _dst_eid)
    }

    #[view]
    public fun to_ld(amount_sd: u64): u64 { oft_core::to_ld(amount_sd) }

    #[view]
    public fun to_sd(amount_ld: u64): u64 { oft_core::to_sd(amount_ld) }

    #[view]
    public fun remove_dust(amount_ld: u64): u64 { oft_core::remove_dust(amount_ld) }

    #[view]
    public fun shared_decimals(): u8 { oft_core::shared_decimals() }

    #[view]
    public fun decimal_conversion_rate(): u64 { oft_core::decimal_conversion_rate() }

    #[view]
    /// Encode an OFT message
    /// @return (message, message_type)
    public fun encode_oft_msg(
        sender: address,
        amount_ld: u64,
        to: vector<u8>,
        compose_msg: vector<u8>,
    ): (vector<u8>, u16) {
        oft_core::encode_oft_msg(sender, amount_ld, to_bytes32(to), compose_msg)
    }

    #[view]
    public fun get_peer(eid: u32): vector<u8> {
        oapp_core::get_peer(eid)
    }

    // ================================================== Error Codes =================================================

    const ECOMPOSE_NOT_IMPLEMENTED: u64 = 1;
    const EINSUFFICIENT_BALANCE: u64 = 2;
    const EINVALID_METADATA: u64 = 3;
}
