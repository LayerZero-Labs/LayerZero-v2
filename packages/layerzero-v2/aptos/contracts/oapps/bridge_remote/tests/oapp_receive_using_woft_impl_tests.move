#[test_only]
module bridge_remote::oapp_receive_using_woft_impl_tests {
    use std::account::create_signer_for_test;
    use std::event::was_event_emitted;
    use std::string::utf8;

    use bridge_remote::bridge_codecs;
    use bridge_remote::oapp_core;
    use bridge_remote::oapp_receive;
    use bridge_remote::oapp_store::OAPP_ADDRESS;
    use bridge_remote::woft_core;
    use bridge_remote::woft_impl;
    use bridge_remote::woft_store;
    use endpoint_v2::endpoint;
    use endpoint_v2::test_helpers::setup_layerzero_for_test;
    use endpoint_v2_common::bytes32::{Self, Bytes32, from_address, from_bytes32};
    use endpoint_v2_common::native_token_test_helpers::initialize_native_token_for_test;
    use endpoint_v2_common::packet_v1_codec::{Self, compute_payload_hash};

    const SRC_EID: u32 = 101;
    const DST_EID: u32 = 201;

    fun setup(local_eid: u32, remote_eid: u32) {
        // Test the send function
        setup_layerzero_for_test(@simple_msglib, local_eid, remote_eid);
        let oft_admin = &create_signer_for_test(@bridge_remote_admin);
        initialize_native_token_for_test();
        bridge_remote::oapp_test_helper::init_oapp();

        let token: Bytes32 = from_address(@0x2000);
        woft_store::init_module_for_test();
        woft_impl::init_module_for_test();
        woft_impl::initialize(
            &create_signer_for_test(@bridge_remote_admin),
            token,
            utf8(b"My Test Token"),
            utf8(b"MYT"),
            6,
            6,
        );
        oapp_core::set_peer(oft_admin, SRC_EID, from_bytes32(from_address(@1234)));
        oapp_core::set_peer(oft_admin, DST_EID, from_bytes32(from_address(@4321)));
    }

    #[test]
    fun test_receive() {
        setup(DST_EID, SRC_EID);

        let called_inspect = false;
        assert!(!called_inspect, 0);

        let token: Bytes32 = from_address(@0x2000);
        let nonce = 1;
        let guid = bytes32::from_address(@23498213432414324);

        let message = bridge_codecs::encode_tokens_transfer_message(
            token,
            bytes32::from_address(@0x2000),
            123,
            bytes32::from_address(@0x3000),
            b"",
        );
        let sender = bytes32::from_address(@1234);

        endpoint::verify(
            @simple_msglib,
            packet_v1_codec::new_packet_v1_header_only_bytes(
                SRC_EID,
                sender,
                DST_EID,
                bytes32::from_address(OAPP_ADDRESS()),
                nonce,
            ),
            bytes32::from_bytes32(compute_payload_hash(guid, message)),
        );


        oapp_receive::lz_receive(
            SRC_EID,
            from_bytes32(sender),
            nonce,
            from_bytes32(guid),
            message,
            b"",
        );

        assert!(was_event_emitted(&woft_core::woft_received_event(
            from_bytes32(token),
            from_bytes32(guid),
            SRC_EID,
            @0x2000,
            123,
        )), 3);
    }

    #[test]
    fun test_receive_with_compose() {
        setup(DST_EID, SRC_EID);

        let called_inspect = false;
        assert!(!called_inspect, 0);

        let token: Bytes32 = from_address(@0x2000);
        let nonce = 1;
        let guid = bytes32::from_address(@23498213432414324);

        let message = bridge_codecs::encode_tokens_transfer_message(
            token,
            bytes32::from_address(@0x2000),
            123,
            bytes32::from_address(@0x3000),
            b"Hello",
        );

        // Composer must be registered
        let to_address_account = &create_signer_for_test(@0x2000);
        endpoint::register_composer(to_address_account, utf8(b"composer"));

        let sender = bytes32::from_address(@1234);

        endpoint::verify(
            @simple_msglib,
            packet_v1_codec::new_packet_v1_header_only_bytes(
                SRC_EID,
                sender,
                DST_EID,
                bytes32::from_address(OAPP_ADDRESS()),
                nonce,
            ),
            bytes32::from_bytes32(compute_payload_hash(guid, message)),
        );


        oapp_receive::lz_receive(
            SRC_EID,
            from_bytes32(sender),
            nonce,
            from_bytes32(guid),
            message,
            b"",
        );

        assert!(was_event_emitted(&woft_core::woft_received_event(
            from_bytes32(token),
            from_bytes32(guid),
            SRC_EID,
            @0x2000,
            123,
        )), 3);

        let expected_compose_message = bridge_codecs::encode_compose(
            nonce,
            SRC_EID,
            token,
            123,
            bytes32::from_address(@0x3000),
            b"Hello",
        );

        // Compose Triggered to the same address
        assert!(was_event_emitted(&endpoint_v2::messaging_composer::compose_sent_event(
            OAPP_ADDRESS(),
            @0x2000,
            from_bytes32(guid),
            0,
            expected_compose_message,
        )), 0);
    }
}