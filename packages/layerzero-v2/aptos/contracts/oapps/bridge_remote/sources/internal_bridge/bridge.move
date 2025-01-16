module bridge_remote::bridge {
    use std::event::emit;
    use std::fungible_asset::{FungibleAsset, Metadata};
    use std::math64::min;
    use std::object::{Self, ExtendRef, Object};
    use std::option::{Self, Option};
    use std::primary_fungible_store;
    use std::string::utf8;
    use std::table::{Self, Table};
    use std::vector;

    use bridge_remote::bridge_codecs;
    use bridge_remote::oapp_core::{combine_options, get_admin, lz_send};
    use bridge_remote::oapp_store::OAPP_ADDRESS;
    use bridge_remote::woft_core;
    use bridge_remote::woft_impl;
    use bridge_remote::wrapped_assets;
    use endpoint_v2_common::bytes32::{Bytes32, from_bytes32, zero_bytes32};
    use endpoint_v2_common::serde;

    friend bridge_remote::oapp_receive;

    #[test_only]
    friend bridge_remote::bridge_tests;

    const SEND: u16 = 1;
    const SEND_AND_CALL: u16 = 2;

    struct BridgeStore has key {
        supported_tokens: Table<u64, Bytes32>,
        supported_token_count: u64,
        factory_extend_ref: ExtendRef,
    }

    public(friend) fun lz_receive_impl(
        src_eid: u32,
        sender: Bytes32,
        nonce: u64,
        guid: Bytes32,
        message: vector<u8>,
        extra_data: vector<u8>,
        receive_value: Option<FungibleAsset>,
    ) acquires BridgeStore {
        let token = serde::extract_bytes32(&message, &mut 0);

        if (!woft_core::has_token(token)) {
            // If the token is not in the store, it's a token creation message
            let (token, shared_decimals, token_name, symbol) = bridge_codecs::decode_factory_add_token_message(
                &message
            );

            // Create the token bridge
            // Use local_decimals = shared_decimals
            let factory_signer = &object::generate_signer_for_extending(&store().factory_extend_ref);
            woft_impl::initialize(
                factory_signer,
                token,
                utf8(token_name),
                utf8(symbol),
                shared_decimals,
                shared_decimals
            );

            // Add the token to the supported tokens list
            add_supported_token(token);

            // Acknowledge token bridge creation with a 0 value transfer
            assert!(option::is_some(&receive_value), ERECEIVE_VALUE_REQUIRED);
            send_acknowledge_creation_message(token, src_eid, option::borrow_mut(&mut receive_value));

            // Emit an event for the token bridge creation
            emit(TokenBridgeCreated {
                token: from_bytes32(token),
                metadata_address: woft_core::get_metadata_address_from_token(token),
            });

            // Transmit unused receive value to WAB Admin
            option::destroy(receive_value, |value| primary_fungible_store::deposit(get_admin(), value));
        } else {
            // If it's not a token creation message, it's a token transfer message
            // Forward to WOFT to handle the transfer
            wrapped_assets::lz_receive_impl(
                src_eid,
                sender,
                nonce,
                guid,
                message,
                extra_data,
                receive_value,
            )
        };
    }

    /// Send a 0 value transfer to acknowledge the creation of a token bridge
    public(friend) fun send_acknowledge_creation_message(token: Bytes32, dst_eid: u32, fee: &mut FungibleAsset) {
        let message = bridge_codecs::encode_tokens_transfer_message(
            token,
            zero_bytes32(),
            0,
            zero_bytes32(),
            vector[],
        );

        let zro_fee = option::none();
        lz_send(
            dst_eid,
            message,
            combine_options(dst_eid, SEND, vector[]),
            fee,
            &mut zro_fee,
        );
        option::destroy_none(zro_fee);
    }

    /// Provides the next nonce if executor options request ordered execution; returns 0 to indicate ordered execution
    /// is disabled
    public(friend) fun next_nonce_impl(_src_eid: u32, _sender: Bytes32): u64 {
        0
    }

    /// Add a token to the supported tokens list (list of all tokens that have been created)
    public(friend) fun add_supported_token(token: Bytes32) acquires BridgeStore {
        let token_id = store().supported_token_count;
        table::add(&mut store_mut().supported_tokens, token_id, token);
        store_mut().supported_token_count = store().supported_token_count + 1;
    }

    // ================================================ View Functions ================================================

    #[view]
    /// Get the supported tokens in a range
    /// @param start The start index of the range
    /// @param end The end index (exclusive) of the range
    public fun get_supported_tokens(start: u64, end: u64): vector<Bytes32> acquires BridgeStore {
        // Ensure the range is within the supported token count
        let start = min(start, store().supported_token_count);
        let end = min(end, store().supported_token_count);

        // Get the tokens in the range
        let tokens = vector[];
        for (i in start..end) {
            vector::push_back(&mut tokens, *table::borrow(&store().supported_tokens, i));
        };
        tokens
    }

    #[view]
    /// Get the number of supported tokens
    public fun supported_token_count(): u64 acquires BridgeStore {
        store().supported_token_count
    }

    // ==================================================== Helpers ===================================================

    inline fun store(): &BridgeStore {
        borrow_global(OAPP_ADDRESS())
    }

    inline fun store_mut(): &mut BridgeStore {
        borrow_global_mut(OAPP_ADDRESS())
    }

    inline fun native_metadata(): Object<Metadata> {
        object::address_to_object(@native_token_metadata_address)
    }

    // ==================================================== Events ====================================================

    #[event]
    struct TokenBridgeCreated has drop, store {
        token: vector<u8>,
        metadata_address: address,
    }

    #[test_only]
    public fun token_bridge_created_event(token: vector<u8>, metadata_address: address): TokenBridgeCreated {
        TokenBridgeCreated { token, metadata_address }
    }

    // ================================================ Initialization ================================================

    fun init_module(account: &signer) {
        // Create an object strictly for the purpose of creating new FA Metadata Objects
        let constructor_ref = &object::create_named_object(account, b"factory");
        let factory_extend_ref = object::generate_extend_ref(constructor_ref);
        object::disable_ungated_transfer(&object::generate_transfer_ref(constructor_ref));

        move_to(account, BridgeStore {
            factory_extend_ref,
            supported_tokens: table::new(),
            supported_token_count: 0,
        });
    }

    #[test_only]
    public fun init_module_for_test() {
        init_module(&std::account::create_signer_for_test(OAPP_ADDRESS()));
    }

    // ================================================== Error Codes =================================================

    const ERECEIVE_VALUE_REQUIRED: u64 = 1;
}
