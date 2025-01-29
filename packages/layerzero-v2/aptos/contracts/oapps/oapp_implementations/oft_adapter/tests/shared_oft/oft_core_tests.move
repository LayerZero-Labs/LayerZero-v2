#[test_only]
module oft::oft_core_tests {
    use std::account::create_signer_for_test;
    use std::event::was_event_emitted;
    use std::fungible_asset;
    use std::fungible_asset::FungibleAsset;
    use std::option;
    use std::string::utf8;
    use std::vector;

    use endpoint_v2::endpoint;
    use endpoint_v2::messaging_receipt;
    use endpoint_v2::messaging_receipt::new_messaging_receipt_for_test;
    use endpoint_v2::test_helpers::setup_layerzero_for_test;
    use endpoint_v2_common::bytes32;
    use endpoint_v2_common::bytes32::{from_address, from_bytes32};
    use endpoint_v2_common::native_token_test_helpers::{burn_token_for_test, initialize_native_token_for_test,
        mint_native_token_for_test
    };
    use endpoint_v2_common::packet_v1_codec;
    use endpoint_v2_common::packet_v1_codec::compute_payload_hash;
    use endpoint_v2_common::zro_test_helpers::create_fa;
    use oft::oapp_core;
    use oft::oapp_store::OAPP_ADDRESS;
    use oft::oft_core::{Self, SEND, SEND_AND_CALL};
    use oft::oft_store;
    use oft_common::oft_compose_msg_codec;
    use oft_common::oft_msg_codec;

    const SRC_EID: u32 = 101;
    const DST_EID: u32 = 201;

    fun setup(local_eid: u32, remote_eid: u32) {
        // Test the send function
        setup_layerzero_for_test(@simple_msglib, local_eid, remote_eid);
        let oft_admin = &create_signer_for_test(@oft_admin);
        initialize_native_token_for_test();
        let (_, metadata, _) = create_fa(b"ZRO");
        let local_decimals = fungible_asset::decimals(metadata);
        oft::oapp_test_helper::init_oapp();

        oft_store::init_module_for_test();
        oft_core::initialize(local_decimals, 6);
        oapp_core::set_peer(oft_admin, SRC_EID, from_bytes32(from_address(@1234)));
        oapp_core::set_peer(oft_admin, DST_EID, from_bytes32(from_address(@4321)));
    }

    #[test]
    fun test_send() {
        setup(SRC_EID, DST_EID);

        let user_sender = @99;
        let to = bytes32::from_address(@2001);
        let native_fee = mint_native_token_for_test(100000);
        let zro_fee = option::none<FungibleAsset>();
        let compose_message = b"Hello";

        let called_send = false;
        let called_inspect = false;
        assert!(!called_inspect && !called_send, 0);

        let (messaging_receipt, amount_sent_ld, amount_received_ld) = oft_core::send(
            user_sender,
            DST_EID,
            to,
            compose_message,
            |message, options| {
                called_send = true;
                assert!(oft_msg_codec::has_compose(&message), 0);
                assert!(oft_msg_codec::sender(&message) == from_address(user_sender), 1);
                assert!(oft_msg_codec::send_to(&message) == to, 0);
                assert!(oft_msg_codec::amount_sd(&message) == 40, 1);
                assert!(options == b"options", 2);

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

        let called_inspect = false;
        assert!(!called_inspect, 0);

        let nonce = 1;
        let guid = bytes32::from_address(@23498213432414324);

        let called_credit = false;
        assert!(!called_credit, 1);

        let message = oft_msg_codec::encode(
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
            b""
        );

        oft_core::receive(
            SRC_EID,
            nonce,
            guid,
            message,
            |_to, _index, _message| {
                // should not be called
                assert!(false, 0);
            },
            |to_address, message_amount| {
                called_credit = true;

                assert!(to_address == @0x2000, 0);
                // Add 2 0s for (8 local decimals - 6 shared decimals)
                assert!(message_amount == 12300, 1);

                5000
            },
        );

        assert!(called_credit, 2);

        assert!(was_event_emitted(&oft_core::oft_received_event(
            from_bytes32(guid),
            SRC_EID,
            @0x2000,
            5000,
        )), 3);
    }

    #[test]
    fun test_receive_with_compose() {
        setup(DST_EID, SRC_EID);

        let called_inspect = false;
        assert!(!called_inspect, 0);

        let nonce = 1;
        let guid = bytes32::from_address(@23498213432414324);

        let called_credit = 0;
        assert!(called_credit == 0, 1);


        let message = oft_msg_codec::encode(
            bytes32::from_address(@0x2000),
            123,
            bytes32::from_address(@0x3000),
            b"Hello",
        );

        // Composer must be registered
        let to_address_account = &create_signer_for_test(@0x2000);
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
            b""
        );

        let called_compose = 0;
        assert!(called_compose == 0, 0);

        oft_core::receive(
            SRC_EID,
            nonce,
            guid,
            message,
            |to, index, message| {
                called_compose = called_compose + 1;
                assert!(to == @0x2000, 0);
                assert!(index == 0, 1);
                assert!(oft_compose_msg_codec::compose_payload_message(&message) == b"Hello", 2);
            },
            |to_address, message_amount| {
                called_credit = called_credit + 1;

                assert!(to_address == @0x2000, 0);
                // Add 2 0s for (8 local decimals - 6 shared decimals)
                assert!(message_amount == 12300, 1);
                12300 // message_amount
            },
        );

        assert!(called_compose == 1, 0);
        assert!(called_credit == 1, 2);

        assert!(was_event_emitted(&oft_core::oft_received_event(
            from_bytes32(guid),
            SRC_EID,
            @0x2000,
            12300,
        )), 3);
    }


    #[test]
    fun test_no_fee_debit_view() {
        setup(SRC_EID, DST_EID);

        let (sent, received) = oft_core::no_fee_debit_view(123456789, 200);
        assert!(sent == received, 0);
        // dust removed (last 2 digits cleared)
        assert!(sent == 123456700, 1);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_core::ESLIPPAGE_EXCEEDED)]
    fun test_no_fee_debit_view_fails_if_post_dust_remove_less_than_min() {
        setup(SRC_EID, DST_EID);

        oft_core::no_fee_debit_view(99, 20);
    }

    #[test]
    fun test_encode_oft_msg() {
        setup(SRC_EID, DST_EID);

        let (encoded, message_type) = oft_core::encode_oft_msg(
            @0x12345678,
            123,
            bytes32::from_address(@0x2000),
            b"Hello",
        );

        assert!(message_type == SEND_AND_CALL(), 0);

        let expected_encoded = oft_msg_codec::encode(
            bytes32::from_address(@0x2000),
            // dust removed and SD
            1,
            bytes32::from_address(@0x12345678),
            b"Hello",
        );

        assert!(encoded == expected_encoded, 1);

        // without compose
        let (encoded, message_type) = oft_core::encode_oft_msg(
            @0x12345678,
            123,
            bytes32::from_address(@0x2000),
            b"",
        );

        assert!(message_type == SEND(), 2);

        let expected_encoded = oft_msg_codec::encode(
            bytes32::from_address(@0x2000),
            // dust removed and SD
            1,
            bytes32::from_address(@0x12345678),
            b"",
        );

        assert!(encoded == expected_encoded, 1);
    }
}