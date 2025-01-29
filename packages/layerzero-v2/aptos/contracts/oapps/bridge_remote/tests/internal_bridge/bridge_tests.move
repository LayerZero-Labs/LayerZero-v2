#[test_only]
module bridge_remote::bridge_tests {
    use std::account::create_signer_for_test;
    use std::event::was_event_emitted;
    use std::fungible_asset::Metadata;
    use std::object::address_to_object;
    use std::option;
    use std::primary_fungible_store;
    use std::string::utf8;

    use bridge_remote::bridge::{
        Self, get_supported_tokens, lz_receive_impl, send_acknowledge_creation_message, supported_token_count,
        token_bridge_created_event,
    };
    use bridge_remote::bridge_codecs;
    use bridge_remote::oapp_core::set_peer;
    use bridge_remote::woft_core::woft_received_event;
    use bridge_remote::woft_store;
    use bridge_remote::wrapped_assets;
    use endpoint_v2::channels::packet_sent_event;
    use endpoint_v2::test_helpers::setup_layerzero_for_test;
    use endpoint_v2_common::bytes32::{Self, Bytes32, from_address, from_bytes32};
    use endpoint_v2_common::native_token_test_helpers::{burn_token_for_test, mint_native_token_for_test};

    const MAXU64: u64 = 0xffffffffffffffff;
    const SRC_EID: u32 = 101;
    const DST_EID: u32 = 201;

    #[test]
    fun test_supported_tokens() {
        bridge::init_module_for_test();
        assert!(supported_token_count() == 0, 1);
        assert!(get_supported_tokens(0, 100) == vector[], 1);
        bridge::add_supported_token(bytes32::from_address(@0x2000));
        assert!(supported_token_count() == 1, 1);
        assert!(get_supported_tokens(0, 100) == vector[bytes32::from_address(@0x2000)], 1);
        bridge::add_supported_token(bytes32::from_address(@0x3000));
        bridge::add_supported_token(bytes32::from_address(@0x4000));
        bridge::add_supported_token(bytes32::from_address(@0x5000));
        assert!(supported_token_count() == 4, 1);
        assert!(
            get_supported_tokens(0, 100) == vector[
                bytes32::from_address(@0x2000),
                bytes32::from_address(@0x3000),
                bytes32::from_address(@0x4000),
                bytes32::from_address(@0x5000),
            ],
            1,
        );
        assert!(
            get_supported_tokens(0, 2) == vector[
                bytes32::from_address(@0x2000),
                bytes32::from_address(@0x3000),
            ],
            1,
        );
        assert!(get_supported_tokens(2, 2) == vector[], 1);
        assert!(
            get_supported_tokens(2, 100) == vector[
                bytes32::from_address(@0x4000),
                bytes32::from_address(@0x5000),
            ],
            1,
        );
    }

    #[test]
    fun test_next_nonce_impl() {
        // Zero indicates ordered execution is disabled
        assert!(bridge::next_nonce_impl(30300, bytes32::zero_bytes32()) == 0, 1);
    }

    fun setup(local_eid: u32, remote_eid: u32) {
        let woft_admin = &create_signer_for_test(@bridge_remote_admin);
        setup_layerzero_for_test(@simple_msglib, local_eid, remote_eid);
        bridge_remote::oapp_test_helper::init_oapp();
        bridge::init_module_for_test();

        let token: Bytes32 = from_address(@0x2000);
        woft_store::init_module_for_test();
        bridge_remote::woft_impl::init_module_for_test();
        bridge_remote::woft_impl::initialize(
            woft_admin,
            token,
            utf8(b"My Test Token"),
            utf8(b"MYT"),
            6,
            6,
        );

        let remote_oapp = from_address(@4444);
        set_peer(woft_admin, DST_EID, from_bytes32(remote_oapp));
    }

    #[test]
    fun test_send_acknowledge() {
        setup(SRC_EID, DST_EID);

        let fee = mint_native_token_for_test(100000);
        send_acknowledge_creation_message(bytes32::from_address(@0x2000), DST_EID, &mut fee);

        // ACK message should be a 0 value transfer
        let expected_message = bridge_codecs::encode_tokens_transfer_message(
            bytes32::from_address(@0x2000),
            bytes32::zero_bytes32(),
            0,
            bytes32::zero_bytes32(),
            vector[],
        );

        let expected_packet = endpoint_v2_common::packet_v1_codec::new_packet_v1(
            SRC_EID,
            from_address(@bridge_remote),
            DST_EID,
            from_address(@4444),
            1,
            endpoint_v2_common::guid::compute_guid(
                1,
                SRC_EID,
                bytes32::from_address(@bridge_remote),
                DST_EID,
                bytes32::from_address(@4444),
            ),
            expected_message,
        );

        assert!(was_event_emitted(&packet_sent_event(expected_packet, x"", @simple_msglib)), 1);

        burn_token_for_test(fee);
    }

    #[test]
    fun test_lz_receive_impl() {
        setup(SRC_EID, DST_EID);

        // Test token creation message
        let message = bridge_codecs::encode_factory_add_token_message(
            bytes32::from_address(@0x2222),
            6,
            b"My Test Token",
            b"MYT",
        );

        let aba_value = mint_native_token_for_test(100000);
        lz_receive_impl(
            DST_EID,
            bytes32::from_address(@4321),
            1,
            bytes32::zero_bytes32(),
            message,
            vector[],
            option::some(aba_value),
        );

        let metadata_address = wrapped_assets::metadata_address_for_token(std::bcs::to_bytes(&@0x2222));

        assert!(was_event_emitted(&token_bridge_created_event(
            std::bcs::to_bytes(&@0x2222),
            metadata_address,
        )), 1);

        // Test token transfer message
        let message = bridge_codecs::encode_tokens_transfer_message(
            bytes32::from_address(@0x2222),
            bytes32::from_address(@0x3333),
            891,
            bytes32::from_address(@0x4444),
            vector[],
        );

        lz_receive_impl(
            DST_EID,
            bytes32::from_address(@4321),
            2,
            bytes32::zero_bytes32(),
            message,
            vector[],
            option::none(),
        );

        assert!(was_event_emitted(&woft_received_event(
            std::bcs::to_bytes(&@0x2222),
            bytes32::ZEROS_32_BYTES(),
            201,
            @0x3333,
            891,
        )), 1);

        assert!(primary_fungible_store::balance(@0x3333, address_to_object<Metadata>(metadata_address)) == 891, 1);
    }
}

