#[test_only]
module oft::oapp_receive_using_oft_adapter_fa_tests {
    use std::account::create_signer_for_test;
    use std::event::was_event_emitted;
    use std::fungible_asset::{Self, MintRef};
    use std::primary_fungible_store;
    use std::string::utf8;

    use endpoint_v2::endpoint;
    use endpoint_v2::test_helpers::setup_layerzero_for_test;
    use endpoint_v2_common::bytes32::{Self, from_address, from_bytes32};
    use endpoint_v2_common::native_token_test_helpers::initialize_native_token_for_test;
    use endpoint_v2_common::packet_v1_codec::{Self, compute_payload_hash};
    use endpoint_v2_common::zro_test_helpers::create_fa;
    use oft::oapp_core;
    use oft::oapp_receive;
    use oft::oapp_store::OAPP_ADDRESS;
    use oft::oft_adapter_fa;
    use oft::oft_core;
    use oft::oft_impl_config;
    use oft::oft_store;
    use oft_common::oft_compose_msg_codec;
    use oft_common::oft_msg_codec;

    const SRC_EID: u32 = 101;
    const DST_EID: u32 = 201;

    fun setup(local_eid: u32, remote_eid: u32): MintRef {
        // Test the send function
        setup_layerzero_for_test(@simple_msglib, local_eid, remote_eid);
        let oft_admin = &create_signer_for_test(@oft_admin);
        initialize_native_token_for_test();
        oft::oapp_test_helper::init_oapp();

        oft_store::init_module_for_test();
        oft_impl_config::init_module_for_test();
        oft_adapter_fa::init_module_for_test();

        // Generates a fungible asset with 8 decimals
        let (fa, _, mint_ref) = create_fa(b"My Test Token");
        oft_adapter_fa::initialize(oft_admin, fa, 6);

        oapp_core::set_peer(oft_admin, SRC_EID, from_bytes32(from_address(@1234)));
        oapp_core::set_peer(oft_admin, DST_EID, from_bytes32(from_address(@4321)));

        mint_ref
    }

    #[test]
    fun test_receive() {
        let mint_ref = setup(DST_EID, SRC_EID);

        let called_inspect = false;
        assert!(!called_inspect, 0);

        let nonce = 1;
        let guid = bytes32::from_address(@23498213432414324);

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

        let escrow = oft_adapter_fa::escrow_address();
        primary_fungible_store::deposit(escrow, fungible_asset::mint(&mint_ref, 20000));

        oapp_receive::lz_receive(
            SRC_EID,
            from_bytes32(sender),
            nonce,
            from_bytes32(guid),
            message,
            b"",
        );

        assert!(was_event_emitted(&oft_core::oft_received_event(
            from_bytes32(guid),
            SRC_EID,
            @0x2000,
            12300,
        )), 3);
    }

    #[test]
    fun test_receive_with_compose() {
        let mint_ref = setup(DST_EID, SRC_EID);

        let called_inspect = false;
        assert!(!called_inspect, 0);

        let nonce = 1;
        let guid = bytes32::from_address(@23498213432414324);

        let message = oft_msg_codec::encode(
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
            b""
        );

        let escrow = oft_adapter_fa::escrow_address();
        primary_fungible_store::deposit(escrow, fungible_asset::mint(&mint_ref, 20000));

        oapp_receive::lz_receive(
            SRC_EID,
            from_bytes32(sender),
            nonce,
            from_bytes32(guid),
            message,
            b"",
        );

        assert!(was_event_emitted(&oft_core::oft_received_event(
            from_bytes32(guid),
            SRC_EID,
            @0x2000,
            12300,
        )), 3);

        let compose_message_part = oft_msg_codec::compose_payload(&message);
        let expected_compose_message = oft_compose_msg_codec::encode(
            nonce,
            SRC_EID,
            12300,
            compose_message_part,
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