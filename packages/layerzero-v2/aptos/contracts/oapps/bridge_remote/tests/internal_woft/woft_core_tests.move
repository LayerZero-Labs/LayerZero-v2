#[test_only]
module bridge_remote::woft_core_tests {
    use std::account::create_signer_for_test;
    use std::event::was_event_emitted;
    use std::fungible_asset::{FungibleAsset, Metadata};
    use std::object::{Self, address_from_constructor_ref, address_to_object};
    use std::option;
    use std::primary_fungible_store;
    use std::string::utf8;
    use std::vector;

    use bridge_remote::bridge_codecs;
    use bridge_remote::oapp_core;
    use bridge_remote::oapp_store::OAPP_ADDRESS;
    use bridge_remote::woft_core::{Self, SEND, SEND_AND_CALL};
    use bridge_remote::woft_store;
    use endpoint_v2::endpoint;
    use endpoint_v2::messaging_receipt::{Self, new_messaging_receipt_for_test};
    use endpoint_v2::test_helpers::setup_layerzero_for_test;
    use endpoint_v2_common::bytes32::{Self, Bytes32, from_address, from_bytes32};
    use endpoint_v2_common::native_token_test_helpers::{burn_token_for_test, initialize_native_token_for_test,
        mint_native_token_for_test
    };
    use endpoint_v2_common::packet_v1_codec::{Self, compute_payload_hash};

    const SRC_EID: u32 = 101;
    const DST_EID: u32 = 201;

    fun setup(local_eid: u32, remote_eid: u32) {
        // Test the send function
        setup_layerzero_for_test(@simple_msglib, local_eid, remote_eid);
        let woft_admin = &create_signer_for_test(@bridge_remote_admin);
        initialize_native_token_for_test();
        bridge_remote::oapp_test_helper::init_oapp();

        woft_store::init_module_for_test();

        let token: Bytes32 = from_address(@0x2000);
        let factory = &create_signer_for_test(@1111111);

        // Create the Fungible Asset, using an object seeded by the unique peer token address
        let constructor_ref = &object::create_named_object(factory, b"token");
        object::disable_ungated_transfer(&object::generate_transfer_ref(constructor_ref));
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            utf8(b"ZRO"),
            utf8(b"symbol"),
            6,
            utf8(b""),
            utf8(b""),
        );

        // Initialize the general WOFT configuration
        let metadata = address_to_object<Metadata>(address_from_constructor_ref(constructor_ref));

        woft_core::initialize(token, metadata, 6, 6);
        oapp_core::set_peer(woft_admin, SRC_EID, from_bytes32(from_address(@1234)));
        oapp_core::set_peer(woft_admin, DST_EID, from_bytes32(from_address(@4321)));
    }

    #[test]
    fun test_send() {
        setup(SRC_EID, DST_EID);

        let token: Bytes32 = from_address(@0x2000);
        let user_sender = @99;
        let to = bytes32::from_address(@2001);
        let native_fee = mint_native_token_for_test(100000);
        let zro_fee = option::none<FungibleAsset>();
        let compose_message = b"Hello";

        let called_send = false;
        let called_inspect = false;
        assert!(!called_inspect && !called_send, 0);


        let (messaging_receipt, amount_sent_ld, amount_received_ld) = woft_core::send(
            token,
            user_sender,
            DST_EID,
            to,
            compose_message,
            |message, options| {
                called_send = true;
                let (
                    token_from_message,
                    send_to,
                    amount_sd,
                    has_compose,
                    sender,
                    compose_payload,
                ) = bridge_codecs::decode_tokens_transfer_message(&message);

                assert!(token_from_message == token, 0);
                assert!(send_to == to, 0);
                assert!(amount_sd == 4000, 1);
                assert!(options == b"options", 2);
                assert!(sender == from_address(user_sender), 1);
                assert!(compose_payload == b"Hello", 3);
                assert!(has_compose, 0);

                new_messaging_receipt_for_test(
                    from_address(@333),
                    4,
                    1111,
                    2222,
                )
            },
            |_unused| (5000, 4000),
            |_amount_received_ld, _msg_type| b"options",
            |message, options| {
                called_inspect = true;
                assert!(vector::length(message) > 0, 0);
                assert!(*options == b"options", 0);
            },
        );

        assert!(called_send, 0);
        assert!(called_inspect, 0);

        let (guid, nonce, native_fee_amount, zro_fee_amount) = messaging_receipt::unpack_messaging_receipt(
            messaging_receipt,
        );
        assert!(guid == from_address(@333), 0);
        assert!(nonce == 4, 0);
        assert!(native_fee_amount == 1111, 1);
        assert!(zro_fee_amount == 2222, 2);

        assert!(amount_sent_ld == 5000, 3);
        assert!(amount_received_ld == 4000, 4);

        burn_token_for_test(native_fee);
        option::destroy_none(zro_fee);
    }

    #[test]
    fun test_receive() {
        setup(DST_EID, SRC_EID);

        let token: Bytes32 = from_address(@0x2000);
        let called_inspect = false;
        assert!(!called_inspect, 0);

        let nonce = 1;
        let guid = bytes32::from_address(@23498213432414324);

        let called_credit = false;
        assert!(!called_credit, 1);

        let message = bridge_codecs::encode_tokens_transfer_message(
            bytes32::from_address(@0x2000),
            bytes32::from_address(@0x3000),
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

        woft_core::receive(
            SRC_EID,
            nonce,
            guid,
            message,
            |_to, _index, _message| {
                // should not be called
                assert!(false, 0);
            },
            |token, to_address, message_amount| {
                called_credit = true;

                assert!(token == token, 0);
                assert!(to_address == @0x3000, 0);
                // Add 2 0s for (8 local decimals - 6 shared decimals)
                assert!(message_amount == 123, 1);

                5000
            },
        );

        assert!(called_credit, 2);

        assert!(was_event_emitted(&woft_core::woft_received_event(
            from_bytes32(token),
            from_bytes32(guid),
            SRC_EID,
            @0x3000,
            5000,
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

        let called_credit = 0;
        assert!(called_credit == 0, 1);


        let message = bridge_codecs::encode_tokens_transfer_message(
            token,
            bytes32::from_address(@0x1111),
            123,
            bytes32::from_address(@0x3000),
            b"Hello",
        );

        // Composer must be registered
        let to_address_account = &create_signer_for_test(@0x1111);
        endpoint::register_composer(to_address_account, utf8(b"oft"));

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

        let called_compose = 0;
        assert!(called_compose == 0, 0);

        woft_core::receive(
            SRC_EID,
            nonce,
            guid,
            message,
            |to, index, message| {
                called_compose = called_compose + 1;
                assert!(to == @0x1111, 0);
                assert!(index == 0, 1);
                let (_nonce, _src_eid, _token, _amount_ld, _sender, compose_payload) =
                    bridge_codecs::decode_compose(&message);
                assert!(compose_payload == b"Hello", 2);
            },
            |token, to_address, message_amount| {
                called_credit = called_credit + 1;

                assert!(token == token, 0);
                assert!(to_address == @0x1111, 0);
                assert!(message_amount == 123, 1);
                123 // message_amount
            },
        );

        assert!(called_compose == 1, 0);
        assert!(called_credit == 1, 2);

        assert!(was_event_emitted(&woft_core::woft_received_event(
            from_bytes32(token),
            from_bytes32(guid),
            SRC_EID,
            @0x1111,
            123,
        )), 3);
    }

    #[test]
    fun test_no_fee_debit_view() {
        setup(SRC_EID, DST_EID);

        let token: Bytes32 = from_address(@0x2000);
        let (sent, received) = woft_core::no_fee_debit_view(token, 123456789, 200);
        assert!(sent == received, 0);
        // dust removed (last 2 digits cleared)
        assert!(sent == 123456789, 1);
    }

    #[test]
    fun test_encode_oft_msg() {
        setup(SRC_EID, DST_EID);

        let token: Bytes32 = from_address(@0x2000);
        let (encoded, message_type) = woft_core::encode_woft_msg(
            token,
            @0x12345678,
            123,
            bytes32::from_address(@0x1111),
            b"Hello",
        );

        assert!(message_type == SEND_AND_CALL(), 0);

        let expected_encoded = bridge_codecs::encode_tokens_transfer_message(
            token,
            bytes32::from_address(@0x1111),
            // dust removed and SD
            123,
            bytes32::from_address(@0x12345678),
            b"Hello",
        );

        assert!(encoded == expected_encoded, 1);

        // without compose
        let (encoded, message_type) = woft_core::encode_woft_msg(
            token,
            @0x12345678,
            123,
            bytes32::from_address(@0x1111),
            b"",
        );

        assert!(message_type == SEND(), 2);

        let expected_encoded = bridge_codecs::encode_tokens_transfer_message(
            token,
            bytes32::from_address(@0x1111),
            // dust removed and SD
            123,
            bytes32::from_address(@0x12345678),
            b"",
        );

        assert!(encoded == expected_encoded, 1);
    }
}