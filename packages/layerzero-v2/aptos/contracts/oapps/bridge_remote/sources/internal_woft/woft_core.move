/// This provides core WOFT functionality.
module bridge_remote::woft_core {
    use std::event::emit;
    use std::fungible_asset::Metadata;
    use std::math64::pow;
    use std::object::{Self, Object};
    use std::vector;

    use bridge_remote::bridge_codecs;
    use bridge_remote::woft_store::{Self, has_metadata};
    use endpoint_v2::messaging_receipt::{get_guid, MessagingReceipt};
    use endpoint_v2_common::bytes32::{Self, Bytes32, from_bytes32, to_bytes32};

    friend bridge_remote::wrapped_assets;
    friend bridge_remote::oapp_receive;
    friend bridge_remote::bridge;
    #[test_only]
    friend bridge_remote::woft_core_tests;

    friend bridge_remote::woft_impl;
    #[test_only]
    friend bridge_remote::woft_impl_tests;
    #[test_only]
    friend bridge_remote::oapp_receive_using_woft_impl_tests;

    // ==================================================== WOFT Core =================================================

    /// Send a message to a destination endpoint using the provided send implementation and debit behavior.
    ///
    /// @param user_sender: The address of the user sending the message
    /// @param dst_eid: The destination endpoint ID
    /// @param to: The destination wallet address
    /// @param compose_message: The compose message to be sent
    /// @param send_impl: A function to send the message
    ///        |message, options| MessagingReceipt
    /// @param debit: A function to debit the user account (unused field included to prevent IDE error)
    ///        |_unused_field| (sent_amount_ld, received_amount_ld)
    /// @param build_options: A function to build the options for the message
    ///        |received_amount_ld, msg_type| options
    /// @param inspect: A function to inspect the message and options before sending
    ///        |message, options| ()
    /// @return (messaging_receipt, amount_sent_ld, amount_received_ld)
    public(friend) inline fun send(
        token: Bytes32,
        user_sender: address,
        dst_eid: u32,
        to: Bytes32,
        compose_payload: vector<u8>,
        send_impl: |vector<u8>, vector<u8>| MessagingReceipt,
        debit: |bool /*unused*/| (u64, u64),
        build_options: |u64, u16| vector<u8>,
        inspect: |&vector<u8>, &vector<u8>|,
    ): (MessagingReceipt, u64, u64) {
        let (amount_sent_ld, amount_received_ld) = debit(true /*unused*/);

        let msg_type = if (vector::length(&compose_payload) > 0) { SEND_AND_CALL() } else { SEND() };
        let options = build_options(amount_received_ld, msg_type);

        // Construct message and options
        let amount_received_sd = to_sd(token, amount_received_ld);
        let message = bridge_codecs::encode_tokens_transfer_message(
            token,
            to,
            amount_received_sd,
            bytes32::from_address(user_sender),
            compose_payload,
        );

        // Hook to inspect the message and options before sending
        inspect(&message, &options);

        // Send by endpoint
        let messaging_receipt = send_impl(message, options);

        emit_woft_sent(
            from_bytes32(token),
            from_bytes32(get_guid(&messaging_receipt)),
            dst_eid,
            user_sender,
            amount_sent_ld,
            amount_received_ld,
        );

        (messaging_receipt, amount_sent_ld, amount_received_ld)
    }

    /// Handle a received packet
    /// @param src_eid: The source endpoint ID
    /// @param nonce: The nonce of the message
    /// @param guid: The GUID of the message
    /// @param message: The message received
    /// @param send_compose: A function to send the compose message
    ///        |to_address, index, message| ()
    /// @param credit: A function to credit the user account
    ///        |to_address, amount_received_ld| credited_amount_ld
    public(friend) inline fun receive(
        src_eid: u32,
        nonce: u64,
        guid: Bytes32,
        message: vector<u8>,
        send_compose: |address, u16, vector<u8>| (),
        credit: |Bytes32, address, u64| u64,
    ) {
        let (token, to, amount_sd, has_compose, sender, compose_payload) = bridge_codecs::decode_tokens_transfer_message(
            &message
        );
        let to_address = bytes32::to_address(to);
        let message_amount_ld = to_ld(token, amount_sd);

        let amount_received_ld = credit(token, to_address, message_amount_ld);

        // Send compose payload if present
        if (has_compose) {
            let compose_message = bridge_codecs::encode_compose(
                nonce,
                src_eid,
                token,
                amount_received_ld,
                sender,
                compose_payload,
            );
            // In the default implementation the compose index is always 0; send_compose accepts the index parameter
            // for extensibility
            send_compose(to_address, 0, compose_message);
        };

        emit_woft_received(
            from_bytes32(token),
            from_bytes32(guid),
            src_eid,
            to_address,
            amount_received_ld,
        );
    }

    /// Get a quote for the network fee for sending a message to a destination endpoint
    /// @param user_sender: The address of the user sending the message
    /// @param to: The destination wallet address
    /// @param compose_message: The compose message to be included
    /// @param quote_impl: A function to get a quote from the LayerZero endpoint
    /// @param debit_view: A function that provides the debit amounts (unused param only included to prevent Move IDE error)
    ///       |_unused_field| (sent_amount_ld, received_amount_ld)
    /// @param build_options: A function to build the options for the message
    ///       |received_amount_ld, msg_type| options
    /// @param inspect: A function to inspect the message and options before quoting
    ///       |message, options| ()
    /// @return (native_fee, lz_fee)
    public(friend) inline fun quote_send(
        token: Bytes32,
        user_sender: address,
        to: vector<u8>,
        compose_message: vector<u8>,
        quote_impl: |vector<u8>, vector<u8>| (u64, u64),
        debit_view: |bool /*unused*/| (u64, u64),
        build_options: |u64, u16| vector<u8>,
        inspect: |&vector<u8>, &vector<u8>|,
    ): (u64, u64) {
        let (_, amount_received_ld) = debit_view(true /*unused*/);
        let (message, msg_type) = encode_woft_msg(
            token,
            user_sender,
            amount_received_ld,
            to_bytes32(to),
            compose_message
        );
        let options = build_options(amount_received_ld, msg_type);

        // Hook to inspect the message and options before sending
        inspect(&message, &options);

        quote_impl(message, options)
    }


    // ===================================================== Utils ====================================================

    /// This is a debit view implementation that can be used by the WOFT to compute the amount to be sent and received
    /// with no fees
    public(friend) fun no_fee_debit_view(token: Bytes32, amount_ld: u64, min_amount_ld: u64): (u64, u64) {
        let amount_sent_ld = remove_dust(token, amount_ld);
        let amount_received_ld = amount_sent_ld;
        assert!(amount_received_ld >= min_amount_ld, ESLIPPAGE_EXCEEDED);
        (amount_sent_ld, amount_received_ld)
    }

    /// Encode an WOFT message
    public(friend) fun encode_woft_msg(
        token: Bytes32,
        sender: address,
        amount_ld: u64,
        to: Bytes32,
        compose_payload: vector<u8>,
    ): (vector<u8>, u16) {
        let encoded_msg = bridge_codecs::encode_tokens_transfer_message(
            token,
            to,
            to_sd(token, amount_ld),
            bytes32::from_address(sender),
            compose_payload,
        );
        let msg_type = if (!vector::is_empty(&compose_payload)) { SEND_AND_CALL() } else { SEND() };

        (encoded_msg, msg_type)
    }

    // =================================================== Viewable ===================================================

    /// Convert an amount from shared decimals to local decimals
    public(friend) fun to_ld(token: Bytes32, amount_sd: u64): u64 {
        amount_sd * woft_store::decimal_conversion_rate(token)
    }

    /// Convert an amount from local decimals to shared decimals
    public(friend) fun to_sd(token: Bytes32, amount_ld: u64): u64 {
        amount_ld / woft_store::decimal_conversion_rate(token)
    }

    /// Calculate an amount in local decimals minus the dust
    public(friend) fun remove_dust(token: Bytes32, amount_ld: u64): u64 {
        let decimal_conversion_rate = woft_store::decimal_conversion_rate(token);
        (amount_ld / decimal_conversion_rate) * decimal_conversion_rate
    }

    /// Get the shared decimals for the WOFT
    public(friend) fun shared_decimals(token: Bytes32): u8 { woft_store::shared_decimals(token) }

    /// Get the decimal conversion rate
    /// This is the multiplier to convert a shared decimals to a local decimals representation
    public(friend) fun decimal_conversion_rate(token: Bytes32): u64 { woft_store::decimal_conversion_rate(token) }

    /// Get the peer "token" address that corresponds to the fungible asset metadata
    public(friend) fun get_token_from_metadata(metadata: Object<Metadata>): Bytes32 {
        woft_store::get_token_from_metadata(metadata)
    }

    /// Get the fungible asset metadata that corresponds to the peer "token" address
    public(friend) fun get_metadata_from_token(token: Bytes32): Object<Metadata> {
        woft_store::get_metadata_from_token(token)
    }

    /// Get the fungible asset metadata that corresponds to the peer "token" address
    public(friend) fun get_metadata_address_from_token(token: Bytes32): address {
        object::object_address(&woft_store::get_metadata_from_token(token))
    }

    /// Check if a token is registered in the WOFT store
    public(friend) fun has_token(token: Bytes32): bool {
        woft_store::has_token(token)
    }

    /// Assert that a token is supported
    public(friend) fun assert_token_supported(token: Bytes32) {
        assert!(has_token(token), ETOKEN_NOT_SUPPORTED);
    }

    /// Assert that a metadata is supported
    public(friend) fun assert_metadata_supported(metadata: Object<Metadata>) {
        assert!(has_metadata(metadata), EMETADATA_NOT_SUPPORTED);
    }

    // ===================================================== Store ====================================================

    public(friend) fun initialize(token: Bytes32, metadata: Object<Metadata>, local_decimals: u8, shared_decimals: u8) {
        assert!(shared_decimals <= local_decimals, EINVALID_LOCAL_DECIMALS);
        let decimal_conversion_rate = pow(10, ((local_decimals - shared_decimals) as u64));
        woft_store::initialize(token, metadata, shared_decimals, decimal_conversion_rate);
    }

    // ==================================================== Events ====================================================

    #[event]
    struct WoftReceived has store, drop {
        token: vector<u8>,
        guid: vector<u8>,
        src_eid: u32,
        to_address: address,
        amount_received_ld: u64,
    }

    #[event]
    struct WoftSent has store, drop {
        token: vector<u8>,
        // GUID of the WOFT message
        guid: vector<u8>,
        // Destination Endpoint ID
        dst_eid: u32,
        // Address of the sender on the src chain
        from_address: address,
        // Amount of tokens sent in local decimals
        amount_sent_ld: u64,
        // Amount of tokens received in local decimals
        amount_received_ld: u64
    }

    public(friend) fun emit_woft_received(
        token: vector<u8>,
        guid: vector<u8>,
        src_eid: u32,
        to_address: address,
        amount_received_ld: u64,
    ) {
        emit(WoftReceived { token, guid, src_eid, to_address, amount_received_ld });
    }

    public(friend) fun emit_woft_sent(
        token: vector<u8>,
        guid: vector<u8>,
        dst_eid: u32,
        from_address: address,
        amount_sent_ld: u64,
        amount_received_ld: u64,
    ) {
        emit(
            WoftSent { token, guid, dst_eid, from_address, amount_sent_ld, amount_received_ld }
        );
    }

    #[test_only]
    public fun woft_received_event(
        token: vector<u8>,
        guid: vector<u8>,
        src_eid: u32,
        to_address: address,
        amount_received_ld: u64,
    ): WoftReceived {
        WoftReceived { token, guid, src_eid, to_address, amount_received_ld }
    }

    #[test_only]
    public fun woft_sent_event(
        token: vector<u8>,
        guid: vector<u8>,
        dst_eid: u32,
        from_address: address,
        amount_sent_ld: u64,
        amount_received_ld: u64,
    ): WoftSent {
        WoftSent { token, guid, dst_eid, from_address, amount_sent_ld, amount_received_ld }
    }

    // =============================================== Shared Constants ===============================================

    // Message type for a message that does not contain a compose message
    public inline fun SEND(): u16 { 1 }

    // Message type for a message that contains a compose message
    public inline fun SEND_AND_CALL(): u16 { 2 }

    // ================================================== Error Codes =================================================

    const EINVALID_LOCAL_DECIMALS: u64 = 1;
    const EMETADATA_NOT_SUPPORTED: u64 = 2;
    const ESLIPPAGE_EXCEEDED: u64 = 3;
    const ETOKEN_NOT_SUPPORTED: u64 = 4;
    const EUNAUTHORIZED: u64 = 5;
}
