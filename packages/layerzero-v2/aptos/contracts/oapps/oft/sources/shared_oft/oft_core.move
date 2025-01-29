/// This provides core OFT functionality.
///
/// This module should generally not be modified by the OFT developer except to correct the friend declarations to
/// match the modules that are actually used.
module oft::oft_core {
    use std::event::emit;
    use std::math64::pow;
    use std::vector;

    use endpoint_v2::messaging_receipt::{get_guid, MessagingReceipt};
    use endpoint_v2_common::bytes32::{Self, Bytes32, from_bytes32, to_bytes32};
    use oft::oft_store;
    use oft_common::oft_compose_msg_codec;
    use oft_common::oft_msg_codec;

    friend oft::oft;
    friend oft::oft_impl_config;
    friend oft::oapp_receive;
    #[test_only]
    friend oft::oft_core_tests;
    #[test_only]
    friend oft::oft_impl_config_tests;

    // **Important** Please delete any friend declarations to unused / deleted modules
    friend oft::oft_fa;
    friend oft::oft_adapter_fa;
    friend oft::oft_coin;
    friend oft::oft_adapter_coin;
    #[test_only]
    friend oft::oft_fa_tests;
    #[test_only]
    friend oft::oft_adapter_fa_tests;
    #[test_only]
    friend oft::oapp_receive_using_oft_fa_tests;

    // ===================================================== OFT Core =================================================

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
        let (message, _) = encode_oft_msg(user_sender, amount_received_ld, to, compose_payload);

        // Hook to inspect the message and options before sending
        inspect(&message, &options);

        // Send by endpoint
        let messaging_receipt = send_impl(message, options);

        emit_oft_sent(
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
        credit: |address, u64| u64,
    ) {
        // Decode the message using the OFT v2 codec
        let to_address = bytes32::to_address(oft_msg_codec::send_to(&message));
        let message_amount_ld = to_ld(oft_msg_codec::amount_sd(&message));
        let has_compose = oft_msg_codec::has_compose(&message);

        // Credit the user account
        let amount_received_ld = credit(to_address, message_amount_ld);

        // Send compose payload if present
        if (has_compose) {
            let compose_payload = oft_msg_codec::compose_payload(&message);
            let compose_message = oft_compose_msg_codec::encode(
                nonce,
                src_eid,
                amount_received_ld,
                compose_payload,
            );
            // In the default implementation the compose index is always 0; send_compose accepts the index parameter
            // for extensibility
            send_compose(to_address, 0, compose_message);
        };
        emit_oft_received(from_bytes32(guid), src_eid, to_address, amount_received_ld);
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
        user_sender: address,
        to: vector<u8>,
        compose_message: vector<u8>,
        quote_impl: |vector<u8>, vector<u8>| (u64, u64),
        debit_view: |bool /*unused*/| (u64, u64),
        build_options: |u64, u16| vector<u8>,
        inspect: |&vector<u8>, &vector<u8>|,
    ): (u64, u64) {
        let (_, amount_received_ld) = debit_view(true /*unused*/);
        let (message, msg_type) = encode_oft_msg(user_sender, amount_received_ld, to_bytes32(to), compose_message);
        let options = build_options(amount_received_ld, msg_type);

        // Hook to inspect the message and options before sending
        inspect(&message, &options);

        quote_impl(message, options)
    }


    // ===================================================== Utils ====================================================

    /// This is a debit view implementation that can be used by the OFT to compute the amount to be sent and received
    /// with no fees
    public(friend) fun no_fee_debit_view(amount_ld: u64, min_amount_ld: u64): (u64, u64) {
        let amount_sent_ld = remove_dust(amount_ld);
        let amount_received_ld = amount_sent_ld;
        assert!(amount_received_ld >= min_amount_ld, ESLIPPAGE_EXCEEDED);
        (amount_sent_ld, amount_received_ld)
    }

    /// Encode an OFT message
    public(friend) fun encode_oft_msg(
        sender: address,
        amount_ld: u64,
        to: Bytes32,
        compose_payload: vector<u8>,
    ): (vector<u8>, u16) {
        let encoded_msg = oft_msg_codec::encode(
            to,
            to_sd(amount_ld),
            bytes32::from_address(sender),
            compose_payload,
        );
        let msg_type = if (!vector::is_empty(&compose_payload)) { SEND_AND_CALL() } else { SEND() };

        (encoded_msg, msg_type)
    }

    // =================================================== Viewable ===================================================

    /// Convert an amount from shared decimals to local decimals
    public(friend) fun to_ld(amount_sd: u64): u64 {
        amount_sd * oft_store::decimal_conversion_rate()
    }

    /// Convert an amount from local decimals to shared decimals
    public(friend) fun to_sd(amount_ld: u64): u64 {
        amount_ld / oft_store::decimal_conversion_rate()
    }

    /// Calculate an amount in local decimals minus the dust
    public(friend) fun remove_dust(amount_ld: u64): u64 {
        let decimal_conversion_rate = oft_store::decimal_conversion_rate();
        (amount_ld / decimal_conversion_rate) * decimal_conversion_rate
    }

    /// Get the shared decimals for the OFT
    public(friend) fun shared_decimals(): u8 { oft_store::shared_decimals() }

    /// Get the decimal conversion rate
    /// This is the multiplier to convert a shared decimals to a local decimals representation
    public(friend) fun decimal_conversion_rate(): u64 { oft_store::decimal_conversion_rate() }

    // ===================================================== Store ====================================================

    public(friend) fun initialize(local_decimals: u8, shared_decimals: u8) {
        assert!(shared_decimals <= local_decimals, EINVALID_LOCAL_DECIMALS);
        let decimal_conversion_rate = pow(10, ((local_decimals - shared_decimals) as u64));
        oft_store::initialize(shared_decimals, decimal_conversion_rate);
    }

    // ==================================================== Events ====================================================

    #[event]
    struct OftReceived has store, drop {
        guid: vector<u8>,
        src_eid: u32,
        to_address: address,
        amount_received_ld: u64,
    }

    #[event]
    struct OftSent has store, drop {
        // GUID of the OFT message
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

    public(friend) fun emit_oft_received(
        guid: vector<u8>,
        src_eid: u32,
        to_address: address,
        amount_received_ld: u64,
    ) {
        emit(OftReceived { guid, src_eid, to_address, amount_received_ld });
    }

    public(friend) fun emit_oft_sent(
        guid: vector<u8>,
        dst_eid: u32,
        from_address: address,
        amount_sent_ld: u64,
        amount_received_ld: u64,
    ) {
        emit(OftSent { guid, dst_eid, from_address, amount_sent_ld, amount_received_ld });
    }

    #[test_only]
    public fun oft_received_event(
        guid: vector<u8>,
        src_eid: u32,
        to_address: address,
        amount_received_ld: u64,
    ): OftReceived {
        OftReceived { guid, src_eid, to_address, amount_received_ld }
    }

    #[test_only]
    public fun oft_sent_event(
        guid: vector<u8>,
        dst_eid: u32,
        from_address: address,
        amount_sent_ld: u64,
        amount_received_ld: u64,
    ): OftSent {
        OftSent { guid, dst_eid, from_address, amount_sent_ld, amount_received_ld }
    }

    // =============================================== Shared Constants ===============================================

    // Message type for a message that does not contain a compose message
    public inline fun SEND(): u16 { 1 }

    // Message type for a message that contains a compose message
    public inline fun SEND_AND_CALL(): u16 { 2 }

    // ================================================== Error Codes =================================================

    const EINVALID_LOCAL_DECIMALS: u64 = 1;
    const ESLIPPAGE_EXCEEDED: u64 = 2;
}
