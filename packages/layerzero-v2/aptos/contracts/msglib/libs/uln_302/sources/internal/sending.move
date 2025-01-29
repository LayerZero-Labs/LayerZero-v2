module uln_302::sending {
    use std::event;
    use std::fungible_asset::{Self, FungibleAsset};
    use std::option::{Self, Option};
    use std::primary_fungible_store;
    use std::vector;

    use dvn_fee_lib_router_0::dvn_fee_lib_router::get_dvn_fee as fee_lib_router_get_dvn_fee;
    use endpoint_v2_common::bytes32::{Self, Bytes32};
    use endpoint_v2_common::packet_raw::{Self, RawPacket};
    use endpoint_v2_common::packet_v1_codec;
    use endpoint_v2_common::send_packet::{Self, SendPacket, unpack_send_packet};
    use executor_fee_lib_router_0::executor_fee_lib_router::get_executor_fee as fee_lib_router_get_executor_fee;
    use msglib_types::configs_executor;
    use msglib_types::configs_uln::{Self, unpack_uln_config};
    use msglib_types::worker_options::get_matching_options;
    use treasury::treasury;
    use uln_302::configuration;
    use uln_302::for_each_dvn::for_each_dvn;
    use uln_302::msglib::worker_config_for_fee_lib_routing_opt_in;
    use worker_common::worker_config;

    friend uln_302::router_calls;

    #[test_only]
    friend uln_302::sending_tests;

    // ==================================================== Sending ===================================================

    /// Makes payment to workers and triggers the packet send
    public(friend) fun send(
        packet: SendPacket,
        options: vector<u8>,
        native_token: &mut FungibleAsset,
        zro_token: &mut Option<FungibleAsset>,
    ): (u64, u64, RawPacket) {
        let dst_eid = send_packet::get_dst_eid(&packet);
        let sender = bytes32::to_address(send_packet::get_sender(&packet));
        let message_length = send_packet::get_message_length(&packet);
        send_internal(
            packet,
            options,
            native_token,
            zro_token,
            // Get Executor Fee
            |executor_address, executor_options| fee_lib_router_get_executor_fee(
                @uln_302,
                get_worker_fee_lib(executor_address),
                executor_address,
                dst_eid,
                sender,
                message_length,
                executor_options,
            ),
            // Get DVN Fee
            |dvn, confirmations, dvn_options, packet_header, payload_hash| fee_lib_router_get_dvn_fee(
                @uln_302,
                get_worker_fee_lib(dvn),
                dvn,
                dst_eid,
                sender,
                packet_raw::get_packet_bytes(packet_header),
                bytes32::from_bytes32(payload_hash),
                confirmations,
                dvn_options,
            )
        )
    }

    /// Internal function to send a packet. The fee library function calls are injected as parameters so that this
    /// behavior can be mocked in tests
    ///
    /// @param packet: the packet details that will be sent
    /// @param options: combined executor and DVN options for the packet
    /// @param native_token: the native token fungible asset mutable ref to pay the workers
    /// @param zro_token: optional ZRO token fungible asset mutable ref to pay the workers
    /// @param get_executor_fee: function that gets the fee for the executor
    ///        |executor, executor_options| (fee, deposit_address)
    /// @param get_dvn_fee: function that gets the fee for one DVN
    ///        |dvn, confirmations, dvn_option, packet_header, payload_hash| (fee, deposit_address)
    public(friend) inline fun send_internal(
        packet: SendPacket,
        options: vector<u8>,
        native_token: &mut FungibleAsset,
        zro_token: &mut Option<FungibleAsset>,
        get_executor_fee: |address, vector<u8>| (u64, address),
        get_dvn_fee: |address, u64, vector<u8>, RawPacket, Bytes32| (u64, address),
    ): (u64 /*native*/, u64 /*zro*/, RawPacket /*encoded_packet*/) {
        // Convert the Send Packet in the a Packet of the Codec V1 format
        let (nonce, src_eid, sender, dst_eid, receiver, guid, message) = unpack_send_packet(packet);
        let sender_address = bytes32::to_address(sender);
        let raw_packet = packet_v1_codec::new_packet_v1(
            src_eid,
            sender,
            dst_eid,
            receiver,
            nonce,
            guid,
            message,
        );

        // Calculate and Pay Worker Fees (DVNs and Executor)
        let packet_header = packet_v1_codec::extract_header(&raw_packet);
        let payload_hash = packet_v1_codec::get_payload_hash(&raw_packet);
        let message_length = vector::length(&message);
        let worker_native_fee = pay_workers(
            sender_address,
            dst_eid,
            message_length,
            options,
            native_token,
            // Get Executor Fee
            |executor, executor_options| get_executor_fee(executor, executor_options),
            // Get DVN Fee - Partially apply the parameters that are known in this scope
            |dvn, confirmations, dvn_options| get_dvn_fee(
                dvn,
                confirmations,
                dvn_options,
                packet_header,
                payload_hash,
            ),
        );

        // Calculate and Pay Treasury Fee
        let treasury_zro_fee = 0;
        let treasury_native_fee = 0;
        if (option::is_some(zro_token)) {
            treasury_zro_fee = treasury::pay_fee(worker_native_fee, option::borrow_mut(zro_token));
        } else {
            treasury_native_fee = treasury::pay_fee(worker_native_fee, native_token);
        };

        // Return the total Native and ZRO paid
        let total_native_fee = worker_native_fee + treasury_native_fee;
        (total_native_fee, treasury_zro_fee, raw_packet)
    }

    // ==================================================== Quoting ===================================================

    // Quote the price of a send in native and ZRO tokens (if `pay_in_zro` is true)
    public(friend) fun quote(packet: SendPacket, options: vector<u8>, pay_in_zro: bool): (u64, u64) {
        let dst_eid = send_packet::get_dst_eid(&packet);
        let sender = bytes32::to_address(send_packet::get_sender(&packet));
        let message_length = send_packet::get_message_length(&packet);

        quote_internal(
            packet,
            options,
            pay_in_zro,
            // Get Executor Fee
            |executor_address, executor_options| fee_lib_router_get_executor_fee(
                @uln_302,
                get_worker_fee_lib(executor_address),
                executor_address,
                dst_eid,
                sender,
                message_length,
                executor_options,
            ),
            // Get DVN Fee
            |dvn, confirmations, dvn_options, packet_header, payload_hash| fee_lib_router_get_dvn_fee(
                @uln_302,
                get_worker_fee_lib(dvn),
                dvn,
                dst_eid,
                sender,
                packet_raw::get_packet_bytes(packet_header),
                bytes32::from_bytes32(payload_hash),
                confirmations,
                dvn_options,
            )
        )
    }

    /// Provides a quote for sending a packet
    ///
    /// @param packet: the packet to be sent
    /// @param options: combined executor and DVN options for the packet
    /// @param pay_in_zro: whether the fees should be paid in ZRO or native token
    /// @param get_executor_fee: function that gets the fee for the executor
    ///        |executor, executor_option| (fee, deposit_address)
    /// @param get_dvn_fee function: that gets the fee for one DVN
    ///        |dvn, confirmations, dvn_option, packet_header, payload_hash| (fee, deposit_address)
    public(friend) inline fun quote_internal(
        packet: SendPacket,
        options: vector<u8>,
        pay_in_zro: bool,
        get_executor_fee: |address, vector<u8>| (u64, address),
        get_dvn_fee: |address, u64, vector<u8>, RawPacket, Bytes32| (u64, address),
    ): (u64, u64) {
        let (nonce, src_eid, sender, dst_eid, receiver, guid, message) = unpack_send_packet(packet);
        let sender_address = bytes32::to_address(sender);

        // Extract the packet header and payload hash
        let packet_header = packet_v1_codec::new_packet_v1_header_only(
            src_eid,
            sender,
            dst_eid,
            receiver,
            nonce,
        );

        // Get the Executor Configuration
        let executor_config = uln_302::configuration::get_executor_config(sender_address, dst_eid);
        let executor_address = configs_executor::get_executor_address(&executor_config);
        let max_msg_size = configs_executor::get_max_message_size(&executor_config);

        // Split provided options into executor and DVN options
        let (executor_options, all_dvn_options) = msglib_types::worker_options::extract_and_split_options(&options);

        // Assert message size is less than what is configured for the OApp
        assert!(vector::length(&message) <= (max_msg_size as u64), err_EMESSAGE_SIZE_EXCEEDS_MAX());

        // Get Executor Fee
        let (executor_fee, _deposit_address) = get_executor_fee(executor_address, executor_options);

        // Get Fee for all DVNs
        let payload_hash = packet_v1_codec::compute_payload_hash(guid, message);
        let config = configuration::get_send_uln_config(sender_address, dst_eid);
        let (confirmations, _, required_dvns, optional_dvns, _, _, _) = unpack_uln_config(config);
        let (dvn_fee, _dvn_fees, _dvn_deposit_addresses) = get_all_dvn_fees(
            &required_dvns,
            &optional_dvns,
            all_dvn_options,
            // Get DVN Fee - Partially apply the parameters that are known in this scope
            |dvn, dvn_options| get_dvn_fee(
                dvn,
                confirmations,
                dvn_options,
                packet_header,
                payload_hash,
            ),
        );

        let worker_native_fee = executor_fee + dvn_fee;

        // Calculate Treasury Fee
        let treasury_fee = treasury::get_fee(worker_native_fee, pay_in_zro);
        let treasury_zro_fee = if (pay_in_zro) { treasury_fee } else { 0 };
        let treasury_native_fee = if (!pay_in_zro) { treasury_fee } else { 0 };

        // Return Native and ZRO Fees
        let total_native_fee = worker_native_fee + treasury_native_fee;
        (total_native_fee, treasury_zro_fee)
    }

    // ==================================================== DVN Fees ==================================================

    /// Calculates the fees for all the DVNs
    ///
    /// @param required_dvns: list of required DVNs
    /// @param optional_dvns: list of optional DVNs
    /// @param validation_options: concatinated options for all DVNs
    /// @param get_dvn_fee: function that gets the fee for one DVN
    ///        |dvn, dvn_option| (u64, address)
    /// @return (total_fee, dvn_fees, dvn_deposit_addresses)
    public(friend) inline fun get_all_dvn_fees(
        required_dvns: &vector<address>,
        optional_dvns: &vector<address>,
        validation_options: vector<u8>, // options for all dvns,
        get_dvn_fee: |address, vector<u8>| (u64, address),
    ): (u64, vector<u64>, vector<address>) {
        let index_option_pairs = msglib_types::worker_options::group_dvn_options_by_index(&validation_options);

        // Calculate the fee for each DVN and accumulate total DVN fee
        let total_dvn_fee = 0;
        let dvn_fees = vector<u64>[];
        let dvn_deposit_addresses = vector<address>[];

        for_each_dvn(required_dvns, optional_dvns, |dvn, i| {
            let options = get_matching_options(&index_option_pairs, (i as u8));
            let (fee, deposit_address) = get_dvn_fee(dvn, options);
            vector::push_back(&mut dvn_fees, fee);
            vector::push_back(&mut dvn_deposit_addresses, deposit_address);
            total_dvn_fee = total_dvn_fee + fee;
        });

        (total_dvn_fee, dvn_fees, dvn_deposit_addresses)
    }

    // ==================================================== Payment ===================================================

    /// Pay the workers for the message
    ///
    /// @param sender the address of the sender
    /// @param dst_eid the destination endpoint id
    /// @param message_length the length of the message
    /// @param options the options for the workers
    /// @param native_token the native token fungible asset to pay the workers
    /// @param get_executor_fee function that gets the fee for the Executor
    ///        |executor, executor_option| (fee, deposit_address)
    /// @param get_dvn_fee function that gets the fee for one DVN
    ///        |dvn, confirmations, dvn_options| (fee, deposit_address)
    public(friend) inline fun pay_workers(
        sender: address,
        dst_eid: u32,
        message_length: u64,
        options: vector<u8>,
        native_token: &mut FungibleAsset,
        get_executor_fee: |address, vector<u8>| (u64, address),
        get_dvn_fee: |address, u64, vector<u8>| (u64, address),
    ): u64 /*native fee*/ {
        // Split serialized options into separately concatenated executor options and dvn options
        let (executor_options, dvn_options) = msglib_types::worker_options::extract_and_split_options(&options);

        // Pay Executor
        let executor_native_fee = pay_executor_and_assert_size(
            sender,
            native_token,
            dst_eid,
            message_length,
            executor_options,
            // Get Executor Fee
            |executor, options| get_executor_fee(executor, options),
        );

        // Pay Verifier
        let verifier_native_fee = pay_verifier(
            sender,
            dst_eid,
            native_token,
            dvn_options,
            // Get DVN Fee
            |dvn, confirmations, options| get_dvn_fee(dvn, confirmations, options)
        );

        let total_native_fee = executor_native_fee + verifier_native_fee;
        total_native_fee
    }

    /// Pay the executor for the message and check the size against the configured maximum
    ///
    /// @param sender: the address of the sender
    /// @param native_token: the native token fungible asset to pay the executor
    /// @param dst_eid: the destination endpoint id
    /// @param message_length: the length of the message
    /// @param executor_options: the options for the executor
    /// @param get_executor_fee: function that gets the fee for the Executor
    ///        |executor, executor_option| (fee, deposit_address)
    /// @return the fee paid to the executor
    inline fun pay_executor_and_assert_size(
        sender: address,
        native_token: &mut FungibleAsset,
        dst_eid: u32,
        message_length: u64,
        executor_options: vector<u8>,
        get_executor_fee: |address, vector<u8>| (u64, address),
    ): u64 {
        // Load config
        let executor_config = configuration::get_executor_config(sender, dst_eid);
        let max_msg_size = configs_executor::get_max_message_size(&executor_config);
        let executor_address = configs_executor::get_executor_address(&executor_config);

        // Assert message size is less than what is configured for the OApp
        assert!(message_length <= (max_msg_size as u64), err_EMESSAGE_SIZE_EXCEEDS_MAX());

        // Extract and Deposit the Executor Fee
        let (fee, deposit_address) = get_executor_fee(executor_address, executor_options);
        let fee_fa = fungible_asset::extract(native_token, fee);
        primary_fungible_store::deposit(deposit_address, fee_fa);

        // Emit a record of the fee paid to the executor
        emit_executor_fee_paid(executor_address, deposit_address, fee);

        fee
    }

    /// Pay the DVNs for verification
    /// Emits a DvnFeePaidEvent to notify the DVNs that they have been paid
    ///
    /// @param sender: the address of the sender
    /// @param dst_eid: the destination endpoint id
    /// @param native_token: the native token fungible asset to pay the DVNs
    /// @param dvn_options: the options for the DVNs
    /// @param get_dvn_fee: function that gets the dvn fee for one DVN
    ///        |dvn, confirmations, dvn_option| (fee, deposit_address)
    /// @return the total fee paid to all DVNs
    inline fun pay_verifier(
        sender: address,
        dst_eid: u32,
        native_token: &mut FungibleAsset,
        dvn_options: vector<u8>,
        get_dvn_fee: |address, u64, vector<u8>| (u64, address),
    ): u64 /*native_fee*/ {
        let config = configuration::get_send_uln_config(sender, dst_eid);
        let required_dvns = configs_uln::get_required_dvns(&config);
        let optional_dvns = configs_uln::get_optional_dvns(&config);
        let confirmations = configs_uln::get_confirmations(&config);

        let (total_fee, dvn_fees, dvn_deposit_addresses) = get_all_dvn_fees(
            &required_dvns,
            &optional_dvns,
            dvn_options,
            // Get DVN Fee - Partially apply the parameters that are known in this scope
            |dvn, options| get_dvn_fee(
                dvn,
                confirmations,
                options,
            ),
        );

        // Deposit the appropriate fee into each of the DVN deposit addresses
        for_each_dvn(&required_dvns, &optional_dvns, |_dvn, i| {
            let fee = vector::borrow(&dvn_fees, i);
            let deposit_address = *vector::borrow(&dvn_deposit_addresses, i);
            let fee_fa = fungible_asset::extract(native_token, *fee);
            primary_fungible_store::deposit(deposit_address, fee_fa);
        });

        // Emit a record of the fees paid to the DVNs
        emit_dvn_fee_paid(required_dvns, optional_dvns, dvn_fees, dvn_deposit_addresses);

        total_fee
    }

    // ==================================================== Routing ===================================================

    /// Provides the feelib address for a worker
    /// Defer to worker_common::worker_config if opting in to worker config. Otherwise, use the worker itself.
    fun get_worker_fee_lib(worker: address): address {
        if (worker_config_for_fee_lib_routing_opt_in(worker)) {
            worker_config::get_worker_fee_lib(worker)
        } else {
            worker
        }
    }

    // ==================================================== Events ====================================================

    #[event]
    struct DvnFeePaid has store, copy, drop {
        required_dvns: vector<address>,
        optional_dvns: vector<address>,
        dvn_deposit_addresses: vector<address>,
        dvn_fees: vector<u64>,
    }

    #[event]
    struct ExecutorFeePaid has store, copy, drop {
        executor_address: address,
        executor_deposit_address: address,
        executor_fee: u64,
    }

    public(friend) fun emit_executor_fee_paid(
        executor_address: address,
        executor_deposit_address: address,
        executor_fee: u64,
    ) {
        event::emit(ExecutorFeePaid {
            executor_address,
            executor_deposit_address,
            executor_fee,
        });
    }

    public(friend) fun emit_dvn_fee_paid(
        required_dvns: vector<address>,
        optional_dvns: vector<address>,
        dvn_fees: vector<u64>,
        dvn_deposit_addresses: vector<address>,
    ) {
        event::emit(DvnFeePaid {
            required_dvns,
            optional_dvns,
            dvn_fees,
            dvn_deposit_addresses,
        });
    }

    #[test_only]
    public fun dvn_fee_paid_event(
        required_dvns: vector<address>,
        optional_dvns: vector<address>,
        dvn_fees: vector<u64>,
        dvn_deposit_addresses: vector<address>,
    ): DvnFeePaid {
        DvnFeePaid {
            required_dvns,
            optional_dvns,
            dvn_fees,
            dvn_deposit_addresses,
        }
    }

    #[test_only]
    public fun executor_fee_paid_event(
        executor_address: address,
        executor_deposit_address: address,
        executor_fee: u64,
    ): ExecutorFeePaid {
        ExecutorFeePaid {
            executor_address,
            executor_deposit_address,
            executor_fee,
        }
    }

    // ================================================== Error Codes =================================================

    const EMESSAGE_SIZE_EXCEEDS_MAX: u64 = 1;

    public(friend) fun err_EMESSAGE_SIZE_EXCEEDS_MAX(): u64 {
        EMESSAGE_SIZE_EXCEEDS_MAX
    }
}