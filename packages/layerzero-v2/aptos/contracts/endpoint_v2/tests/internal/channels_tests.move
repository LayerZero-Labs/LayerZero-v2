#[test_only]
module endpoint_v2::channels_tests {
    use std::account::create_signer_for_test;
    use std::event::{emitted_events, was_event_emitted};
    use std::fungible_asset::FungibleAsset;
    use std::option::{Self, destroy_none};
    use std::string;
    use std::vector;

    use endpoint_v2::channels;
    use endpoint_v2::channels::{
        burn,
        clear_payload,
        get_payload_hash,
        has_payload_hash,
        inbound,
        inbound_nonce,
        inbound_nonce_skipped_event,
        nilify,
        packet_burnt_event,
        packet_nilified_event,
        packet_verified_event,
        PacketVerified,
        send_internal,
        skip,
        verify,
        verify_internal,
    };
    use endpoint_v2::endpoint::register_oapp;
    use endpoint_v2::messaging_receipt;
    use endpoint_v2::msglib_manager;
    use endpoint_v2::registration;
    use endpoint_v2::store;
    use endpoint_v2_common::bytes32;
    use endpoint_v2_common::bytes32::{from_bytes32, to_bytes32};
    use endpoint_v2_common::guid;
    use endpoint_v2_common::guid::compute_guid;
    use endpoint_v2_common::native_token_test_helpers::{burn_token_for_test, mint_native_token_for_test};
    use endpoint_v2_common::packet_raw;
    use endpoint_v2_common::packet_v1_codec;
    use endpoint_v2_common::send_packet::unpack_send_packet;
    use endpoint_v2_common::universal_config;

    #[test]
    fun test_send_internal() {
        let dst_eid = 102;
        let oapp = @123;
        universal_config::init_module_for_test(104);
        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));

        // register the default send library
        store::set_default_send_library(dst_eid, @11114444);

        let packet = packet_raw::bytes_to_raw_packet(b"123456");
        let native_token = mint_native_token_for_test(100);
        let zro_token = option::none<FungibleAsset>();

        let called = false;
        assert!(!called, 0);  // needed to avoid unused variable warning

        let receiver = bytes32::from_address(@0x1234);
        let expected_guid = guid::compute_guid(
            1,
            104,
            bytes32::from_address(oapp),
            102,
            receiver,
        );

        let receipt = send_internal(
            oapp,
            dst_eid,
            receiver,
            b"payload",
            b"options",
            &mut native_token,
            &mut zro_token,
            |msglib, send_packet| {
                called = true;

                // called correct message library
                assert!(msglib == @11114444, 1);

                // called with correct packet
                let (nonce, src_eid, sender, dst_eid, receiver, guid, message) = unpack_send_packet(send_packet);
                assert!(nonce == 1, 2);
                assert!(src_eid == 104, 3);
                assert!(sender == bytes32::from_address(oapp), 4);
                assert!(dst_eid == 102, 5);
                assert!(receiver == receiver, 6);
                assert!(guid == expected_guid, 7);
                assert!(message == b"payload", 8);

                (200, 300, packet)
            }
        );

        let (guid, nonce, native_fee, zro_fee) = messaging_receipt::unpack_messaging_receipt(receipt);
        assert!(guid == expected_guid, 9);
        assert!(nonce == 1, 10);
        assert!(native_fee == 200, 11);
        assert!(zro_fee == 300, 12);

        assert!(called, 1);
        called = false;
        assert!(!called, 1);

        // Try again (nonce = 2) with a OApp configured send library (instead of the default)
        store::set_send_library(oapp, dst_eid, @22223333);
        let receipt = send_internal(
            oapp,
            dst_eid,
            receiver,
            b"payload",
            b"options",
            &mut native_token,
            &mut zro_token,
            |msglib, _send_packet| {
                called = true;
                // called the msglib matches what is configured for the oapp
                assert!(msglib == @22223333, 1);
                (2000, 3000, packet)
            }
        );
        assert!(called, 1);

        let (guid, nonce, native_fee, zro_fee) = messaging_receipt::unpack_messaging_receipt(receipt);

        // nonce should increase to 2
        assert!(nonce == 2, 10);
        assert!(native_fee == 2000, 11);
        assert!(zro_fee == 3000, 12);

        let expected_guid = guid::compute_guid(
            2,
            104,
            bytes32::from_address(oapp),
            102,
            receiver,
        );
        assert!(guid == expected_guid, 13);

        burn_token_for_test(native_token);
        destroy_none(zro_token);
    }

    #[test]
    fun test_quote_internal() {
        let dst_eid = 102;
        let oapp = @123;

        universal_config::init_module_for_test(104);
        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);

        register_oapp(oapp_signer, string::utf8(b"receiver"));

        // register the default send library
        store::set_default_send_library(dst_eid, @11114444);

        let called = false;
        assert!(!called, 0); // needed to avoid unused variable warning

        let (native_fee, zro_fee) = channels::quote_internal(
            oapp,
            dst_eid,
            bytes32::from_address(@0x1234),
            b"payload",
            |msglib, send_packet| {
                called = true;
                assert!(msglib == @11114444, 1);
                let (nonce, src_eid, sender, dst_eid, receiver, guid, message) = unpack_send_packet(send_packet);
                assert!(nonce == 1, 2);
                assert!(src_eid == 104, 3);
                assert!(sender == bytes32::from_address(@123), 4);
                assert!(dst_eid == 102, 5);
                assert!(receiver == bytes32::from_address(@0x1234), 6);
                assert!(message == b"payload", 7);

                let expected_guid = compute_guid(
                    1,
                    104,
                    bytes32::from_address(oapp),
                    dst_eid,
                    bytes32::from_address(@0x1234),
                );

                assert!(guid == expected_guid, 8);
                (200, 300)
            }
        );
        assert!(called, 1);
        assert!(native_fee == 200, 2);
        assert!(zro_fee == 300, 3);

        // call send() to increment nonce
        let native_token = mint_native_token_for_test(100);
        let zro_token = option::none<FungibleAsset>();
        send_internal(
            oapp,
            dst_eid,
            bytes32::from_address(@0x1234),
            b"payload",
            b"options",
            &mut native_token,
            &mut zro_token,
            |msglib, _send_packet| {
                called = true;
                // called the msglib matches what is configured for the oapp
                assert!(msglib == @11114444, 1);
                let packet = packet_raw::bytes_to_raw_packet(b"123456");
                (2000, 3000, packet)
            }
        );

        burn_token_for_test(native_token);
        destroy_none(zro_token);

        assert!(called, 0);
        called = false;
        assert!(!called, 0);

        // call again with higher nonce state and a OApp configured send library
        store::set_send_library(oapp, dst_eid, @22223333);
        let (native_fee, zro_fee) = channels::quote_internal(
            oapp,
            dst_eid,
            bytes32::from_address(@0x1234),
            b"payload",
            |msglib, send_packet| {
                called = true;
                assert!(msglib == @22223333, 1);
                let (nonce, src_eid, sender, dst_eid, receiver, guid, message) = unpack_send_packet(send_packet);
                assert!(nonce == 2, 2);
                assert!(src_eid == 104, 3);
                assert!(sender == bytes32::from_address(@123), 4);
                assert!(dst_eid == 102, 5);
                assert!(receiver == bytes32::from_address(@0x1234), 6);
                assert!(message == b"payload", 7);

                let expected_guid = compute_guid(
                    2,
                    104,
                    bytes32::from_address(oapp),
                    dst_eid,
                    bytes32::from_address(@0x1234),
                );

                assert!(guid == expected_guid, 8);
                (2000, 3000)
            }
        );

        assert!(called, 0);
        assert!(native_fee == 2000, 2);
        assert!(zro_fee == 3000, 3);
    }

    #[test]
    fun test_register_receive_pathway() {
        let oapp = @123;
        let src_eid = 0x2;
        let sender = bytes32::from_address(@0x1234);
        store::init_module_for_test();

        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));
        channels::register_receive_pathway(oapp, src_eid, sender);
        assert!(was_event_emitted(&channels::receive_pathway_registered_event(oapp, src_eid, from_bytes32(sender))), 0);
        assert!(channels::receive_pathway_registered(oapp, src_eid, sender), 0);
    }

    #[test]
    fun test_inbound() {
        let oapp = @123;
        let src_eid = 0x2;
        let sender = bytes32::from_address(@0x1234);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));
        channels::register_receive_pathway(oapp, src_eid, sender);
        assert!(store::lazy_inbound_nonce(oapp, src_eid, sender) == 0, 0);

        // Inbound #1
        inbound(oapp, src_eid, sender, 1, payload_hash);
        assert!(has_payload_hash(oapp, src_eid, sender, 1), 1);
        assert!(get_payload_hash(oapp, src_eid, sender, 1) == payload_hash, 2);

        // Inbound #2
        inbound(oapp, src_eid, sender, 2, payload_hash);
        assert!(has_payload_hash(oapp, src_eid, sender, 2), 3);
        assert!(get_payload_hash(oapp, src_eid, sender, 2) == payload_hash, 4);

        // Inbound nonce should increment, but not lazy without clearing
        assert!(
            store::lazy_inbound_nonce(oapp, src_eid, sender) == 0,
            5,
        );  // inbound does not increment lazy inbound
        assert!(inbound_nonce(oapp, src_eid, sender) == 2, 6); // inbound_nonce is incremented

        // Only if cleared does the lazy increment to the inbound
        clear_payload(oapp, src_eid, sender, 2, payload);
        assert!(
            store::lazy_inbound_nonce(oapp, src_eid, sender) == 2,
            5,
        );  // inbound does not increment lazy inbound
        assert!(inbound_nonce(oapp, src_eid, sender) == 2, 6); // inbound_nonce is incremented
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::channels::EEMPTY_PAYLOAD_HASH)]
    fun test_inbound_should_not_accept_empty_payload_hash() {
        let oapp = @123;
        let src_eid = 0x2;
        let sender = bytes32::from_address(@0x1234);
        let nonce = 0x1;
        let payload_hash = bytes32::zero_bytes32();
        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));
        channels::register_receive_pathway(oapp, src_eid, sender);
        inbound(oapp, src_eid, sender, nonce, payload_hash);
    }

    #[test]
    fun test_inbound_nonce() {
        let oapp = @123;
        let src_eid = 0x2;
        let sender = bytes32::from_address(@0x1234);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);

        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));
        channels::register_receive_pathway(oapp, src_eid, sender);
        assert!(inbound_nonce(oapp, src_eid, sender) == 0, 0);
        inbound(oapp, src_eid, sender, 1, payload_hash);
        assert!(inbound_nonce(oapp, src_eid, sender) == 1, 1);
        inbound(oapp, src_eid, sender, 2, payload_hash);
        assert!(inbound_nonce(oapp, src_eid, sender) == 2, 2);
    }

    #[test]
    fun test_skip() {
        let oapp = @123;
        let src_eid = 0x2;
        let sender = bytes32::from_address(@0x1234);
        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));
        channels::register_receive_pathway(oapp, src_eid, sender);
        assert!(inbound_nonce(oapp, src_eid, sender) == 0, 0);
        skip(oapp, src_eid, sender, 1);
        assert!(inbound_nonce(oapp, src_eid, sender) == 1, 1);
        assert!(was_event_emitted(&inbound_nonce_skipped_event(src_eid, from_bytes32(sender), oapp, 1)), 2);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::channels::EINVALID_NONCE)]
    fun test_skip_invalid_nonce() {
        let oapp = @123;
        let src_eid = 0x2;
        let sender = bytes32::from_address(@0x1234);
        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));
        channels::register_receive_pathway(oapp, src_eid, sender);
        assert!(inbound_nonce(oapp, src_eid, sender) == 0, 0);
        skip(oapp, src_eid, sender, 2);  // skip_to_nonce must be 1 to succeed
    }

    #[test]
    fun test_nilify() {
        let oapp = @123;
        let src_eid = 0x2;
        let sender = bytes32::from_address(@0x1234);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));
        channels::register_receive_pathway(oapp, src_eid, sender);

        // Inbound #1
        inbound(oapp, src_eid, sender, 1, payload_hash);
        assert!(has_payload_hash(oapp, src_eid, sender, 1), 0);
        assert!(get_payload_hash(oapp, src_eid, sender, 1) == payload_hash, 1);

        // Inbound #2
        inbound(oapp, src_eid, sender, 2, payload_hash);
        assert!(has_payload_hash(oapp, src_eid, sender, 2), 2);
        assert!(get_payload_hash(oapp, src_eid, sender, 2) == payload_hash, 3);

        assert!(inbound_nonce(oapp, src_eid, sender) == 2, 3);

        // Nilify
        nilify(oapp, src_eid, sender, 1, payload_hash);
        assert!(was_event_emitted(
            &packet_nilified_event(src_eid, from_bytes32(sender), oapp, 1, from_bytes32(payload_hash))
        ), 4);

        assert!(inbound_nonce(oapp, src_eid, sender) == 2, 3);
        assert!(
            get_payload_hash(oapp, src_eid, sender, 1) == bytes32::to_bytes32(
                x"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
            ),
            3,
        );  // 1 is nilified
        assert!(has_payload_hash(oapp, src_eid, sender, 2), 2);  // 2 is not nilified
    }

    #[test]
    fun test_nilify_for_non_verified() {
        let oapp = @123;
        let src_eid = 0x2;
        let sender = bytes32::from_address(@0x1234);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));
        channels::register_receive_pathway(oapp, src_eid, sender);

        // Inbound #1
        inbound(oapp, src_eid, sender, 1, payload_hash);
        assert!(has_payload_hash(oapp, src_eid, sender, 1), 0);
        assert!(get_payload_hash(oapp, src_eid, sender, 1) == payload_hash, 1);

        // Inbound #2
        inbound(oapp, src_eid, sender, 2, payload_hash);
        assert!(has_payload_hash(oapp, src_eid, sender, 2), 2);
        assert!(get_payload_hash(oapp, src_eid, sender, 2) == payload_hash, 3);

        assert!(inbound_nonce(oapp, src_eid, sender) == 2, 3);

        let empty_payload_hash = x"0000000000000000000000000000000000000000000000000000000000000000";
        // Nilify
        nilify(
            oapp,
            src_eid,
            sender,
            3,
            to_bytes32(empty_payload_hash),
        );
        assert!(was_event_emitted(
            &packet_nilified_event(src_eid, from_bytes32(sender), oapp, 3, empty_payload_hash)
        ), 4);

        // inbound nonce increments to be beyond the nilified nonce
        assert!(inbound_nonce(oapp, src_eid, sender) == 3, 3);
        assert!(
            get_payload_hash(oapp, src_eid, sender, 3) == bytes32::to_bytes32(
                x"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
            ),
            3,
        );  // 3 is nilified
    }

    #[test]
    fun test_nilify_for_non_verified_2() {
        let oapp = @123;
        let src_eid = 0x2;
        let sender = bytes32::from_address(@0x1234);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));
        channels::register_receive_pathway(oapp, src_eid, sender);

        // Inbound #1 (don't do second inbound so there is a gap)
        inbound(oapp, src_eid, sender, 1, payload_hash);
        assert!(has_payload_hash(oapp, src_eid, sender, 1), 0);
        assert!(get_payload_hash(oapp, src_eid, sender, 1) == payload_hash, 1);

        assert!(inbound_nonce(oapp, src_eid, sender) == 1, 3);

        let empty_payload_hash = x"0000000000000000000000000000000000000000000000000000000000000000";
        // Nilify
        nilify(
            oapp,
            src_eid,
            sender,
            3,
            to_bytes32(empty_payload_hash),
        );
        assert!(was_event_emitted(
            &packet_nilified_event(src_eid, from_bytes32(sender), oapp, 3, empty_payload_hash)
        ), 4);

        // inbound nonce doesn't increment
        assert!(inbound_nonce(oapp, src_eid, sender) == 1, 3);
        assert!(
            get_payload_hash(oapp, src_eid, sender, 3) == bytes32::to_bytes32(
                x"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
            ),
            3,
        );  // 3 is nilified
    }

    #[test]
    fun test_can_skip_after_nillify() {
        let oapp = @123;
        let src_eid = 0x2;
        let sender = bytes32::from_address(@0x1234);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));
        channels::register_receive_pathway(oapp, src_eid, sender);

        inbound(oapp, src_eid, sender, 1, payload_hash);
        inbound(oapp, src_eid, sender, 2, payload_hash);

        nilify(oapp, src_eid, sender, 2, payload_hash);
        nilify(oapp, src_eid, sender, 1, payload_hash);

        skip(oapp, src_eid, sender, 3);

        assert!(inbound_nonce(oapp, src_eid, sender) == 3, 0);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::channels::EINVALID_NONCE)]
    fun test_cannot_skip_to_non_next_nonce() {
        let oapp = @123;
        let src_eid = 0x2;
        let sender = bytes32::from_address(@0x1234);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));
        channels::register_receive_pathway(oapp, src_eid, sender);

        inbound(oapp, src_eid, sender, 1, payload_hash);
        inbound(oapp, src_eid, sender, 2, payload_hash);

        assert!(inbound_nonce(oapp, src_eid, sender) == 2, 0);

        skip(oapp, src_eid, sender, 2);  // skip_to_nonce must be 3 to succeed
    }


    #[test]
    fun test_burn() {
        let oapp = @123;
        let src_eid = 0x2;
        let sender = bytes32::from_address(@0x1234);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));
        channels::register_receive_pathway(oapp, src_eid, sender);

        inbound(oapp, src_eid, sender, 1, payload_hash);
        inbound(oapp, src_eid, sender, 2, payload_hash);
        assert!(inbound_nonce(oapp, src_eid, sender) == 2, 0);

        skip(oapp, src_eid, sender, 3);

        burn(oapp, src_eid, sender, 1, payload_hash);
        assert!(
            was_event_emitted(&packet_burnt_event(src_eid, from_bytes32(sender), oapp, 1, from_bytes32(payload_hash))),
            1,
        );

        assert!(store::lazy_inbound_nonce(oapp, src_eid, sender) == 3, 2);
        assert!(!has_payload_hash(oapp, src_eid, sender, 1), 3);  // 1 is burnt
        assert!(has_payload_hash(oapp, src_eid, sender, 2), 4);  // 2 is not burnt
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::channels::EINVALID_NONCE)]
    fun test_cannot_burn_a_nonce_after_lazy_inbound_nonce() {
        let oapp = @123;
        let src_eid = 0x2;
        let sender = bytes32::from_address(@0x1234);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));
        channels::register_receive_pathway(oapp, src_eid, sender);

        inbound(oapp, src_eid, sender, 1, payload_hash);
        inbound(oapp, src_eid, sender, 2, payload_hash);
        assert!(inbound_nonce(oapp, src_eid, sender) == 2, 0);

        assert!(store::lazy_inbound_nonce(oapp, src_eid, sender) == 0, 1);
        burn(oapp, src_eid, sender, 1, payload_hash);  // lazy inbound is still 0
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::channels::ENO_PAYLOAD_HASH)]
    fun test_cannot_clear_a_burnt_nonce() {
        let oapp = @123;
        let src_eid = 0x2;
        let sender = bytes32::from_address(@0x1234);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));
        channels::register_receive_pathway(oapp, src_eid, sender);

        inbound(oapp, src_eid, sender, 1, payload_hash);
        inbound(oapp, src_eid, sender, 2, payload_hash);
        assert!(inbound_nonce(oapp, src_eid, sender) == 2, 0);

        clear_payload(oapp, src_eid, sender, 2, payload);  // clear 2
        assert!(!has_payload_hash(oapp, src_eid, sender, 2), 1);  // 2 is cleared
        assert!(has_payload_hash(oapp, src_eid, sender, 1), 2);  // still has hash #1

        burn(oapp, src_eid, sender, 1, payload_hash); // burn 1
        assert!(!has_payload_hash(oapp, src_eid, sender, 1), 3);  // 1 is burnt

        clear_payload(oapp, src_eid, sender, 1, payload);  // cannot clear 1
    }

    #[test]
    fun test_clear_payload() {
        let oapp = @123;
        let src_eid = 0x2;
        let sender = bytes32::from_address(@0x1234);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));
        channels::register_receive_pathway(oapp, src_eid, sender);

        inbound(oapp, src_eid, sender, 1, payload_hash);
        inbound(oapp, src_eid, sender, 2, payload_hash);
        assert!(store::lazy_inbound_nonce(oapp, src_eid, sender) == 0, 1);
        assert!(inbound_nonce(oapp, src_eid, sender) == 2, 0);

        // clear 2
        clear_payload(oapp, src_eid, sender, 2, payload);

        assert!(store::lazy_inbound_nonce(oapp, src_eid, sender) == 2, 1);
        assert!(inbound_nonce(oapp, src_eid, sender) == 2, 0);
        assert!(!has_payload_hash(oapp, src_eid, sender, 2), 2);

        inbound(oapp, src_eid, sender, 3, payload_hash);
        inbound(oapp, src_eid, sender, 4, payload_hash);

        // clear 1, 4, 3
        clear_payload(oapp, src_eid, sender, 1, payload);
        clear_payload(oapp, src_eid, sender, 4, payload);
        clear_payload(oapp, src_eid, sender, 3, payload);
    }

    #[test]
    fun test_can_clear_out_of_order() {
        let oapp = @123;
        let src_eid = 0x2;
        let sender = bytes32::from_address(@0x1234);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));
        channels::register_receive_pathway(oapp, src_eid, sender);

        inbound(oapp, src_eid, sender, 1, payload_hash);
        inbound(oapp, src_eid, sender, 2, payload_hash);
        assert!(store::lazy_inbound_nonce(oapp, src_eid, sender) == 0, 1);
        assert!(inbound_nonce(oapp, src_eid, sender) == 2, 0);

        clear_payload(oapp, src_eid, sender, 2, payload);
        assert!(has_payload_hash(oapp, src_eid, sender, 1), 2);  // still has hash #1
        assert!(!has_payload_hash(oapp, src_eid, sender, 2), 2);  // hash #2 removed

        clear_payload(oapp, src_eid, sender, 1, payload);
        assert!(!has_payload_hash(oapp, src_eid, sender, 1), 2);  // now hash #1 removed
        assert!(store::lazy_inbound_nonce(oapp, src_eid, sender) == 2, 1);
        assert!(inbound_nonce(oapp, src_eid, sender) == 2, 0);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::channels::EPAYLOAD_HASH_DOES_NOT_MATCH)]
    fun test_clear_payload_should_fail_with_invalid_payload() {
        let oapp = @123;
        let src_eid = 0x2;
        let sender = bytes32::from_address(@0x1234);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        let invalid_payload = b"invalid_payload";
        store::init_module_for_test();
        let oapp_signer = &create_signer_for_test(oapp);
        register_oapp(oapp_signer, string::utf8(b"receiver"));
        channels::register_receive_pathway(oapp, src_eid, sender);

        inbound(oapp, src_eid, sender, 1, payload_hash);
        inbound(oapp, src_eid, sender, 2, payload_hash);
        assert!(store::lazy_inbound_nonce(oapp, src_eid, sender) == 0, 1);
        assert!(inbound_nonce(oapp, src_eid, sender) == 2, 0);

        clear_payload(oapp, src_eid, sender, 2, invalid_payload);
        clear_payload(oapp, src_eid, sender, 1, invalid_payload);
    }

    #[test]
    fun test_verify() {
        // packet details
        let receiver_oapp = @123;
        let src_eid = 0x2;
        let dst_eid = 0x3;
        let sender = bytes32::from_address(@0x1234);
        let receiver = bytes32::from_address(receiver_oapp);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        let packet_header = packet_v1_codec::new_packet_v1_header_only(
            src_eid,
            sender,
            dst_eid,
            receiver,
            1,
        );
        universal_config::init_module_for_test(dst_eid);
        store::init_module_for_test();

        // register destination defaults
        msglib_manager::register_library(@simple_msglib);
        msglib_manager::set_default_receive_library(src_eid, @simple_msglib, 0);

        // register destination
        registration::register_oapp(receiver_oapp, string::utf8(b"receiver"));
        channels::register_receive_pathway(receiver_oapp, src_eid, sender);  // register pathway to receive from sender

        // initialize destination on simple_msglib
        simple_msglib::msglib::initialize_for_test();

        verify(
            @simple_msglib,
            packet_header,
            payload_hash,
            b"",
        );

        assert!(was_event_emitted(&packet_verified_event(
            src_eid,
            from_bytes32(sender),
            1,
            bytes32::to_address(receiver),
            from_bytes32(payload_hash),
        )), 0);
    }

    #[test]
    fun test_verify_internal() {
        // packet details
        let receiver_oapp = @0x123;
        let src_eid = 102;
        let sender = bytes32::from_address(@0x1234);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        let nonce = 11;
        // use blocked message lib to ensure that it's not actually called when using the internal verify function,
        // except the version() function, which is called upon library registration, but not in verify_internal()
        let msglib = @blocked_msglib;
        store::init_module_for_test();

        // register destination defaults
        msglib_manager::register_library(msglib);
        msglib_manager::set_default_receive_library(src_eid, msglib, 0);

        // register destination
        registration::register_oapp(receiver_oapp, string::utf8(b"receiver"));
        channels::register_receive_pathway(receiver_oapp, src_eid, sender);  // register pathway to receive from sender

        verify_internal(
            msglib,
            payload_hash,
            receiver_oapp,
            src_eid,
            sender,
            nonce,
        );

        assert!(was_event_emitted(&packet_verified_event(
            src_eid,
            from_bytes32(sender),
            nonce,
            receiver_oapp,
            from_bytes32(payload_hash),
        )), 0);
    }


    #[test]
    fun test_verifiable() {
        store::init_module_for_test();
        // returns false if pathway not registered
        assert!(!channels::verifiable(@222, 1, bytes32::from_address(@123), 1), 0);

        // still returns false if registered but no pathway
        registration::register_oapp(@123, string::utf8(b"receiver"));
        assert!(!channels::verifiable(@222, 1, bytes32::from_address(@123), 1), 1);

        // return true if nonce (1) > lazy inbound(0)
        channels::register_receive_pathway(@123, 1, bytes32::from_address(@222));
        assert!(channels::verifiable(@123, 1, bytes32::from_address(@222), 1), 1);

        // return false if nonce (0) <= lazy inbound(0)
        assert!(!channels::verifiable(@123, 1, bytes32::from_address(@222), 0), 2);

        // return true if nonce (0) > lazy inbound(0) but has payload hash
        channels::inbound(@123, 1, bytes32::from_address(@222), 0, bytes32::from_address(@999));
        assert!(channels::verifiable(@123, 1, bytes32::from_address(@222), 0), 2);
    }

    #[test]
    fun test_verify_allows_reverifying_if_not_executed() {
        // packet details
        let receiver_oapp = @123;
        let src_eid = 0x2;
        let dst_eid = 0x3;
        let sender = bytes32::from_address(@0x1234);
        let receiver = bytes32::from_address(receiver_oapp);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        let packet_header = packet_v1_codec::new_packet_v1_header_only(
            src_eid,
            sender,
            dst_eid,
            receiver,
            1,
        );
        store::init_module_for_test();
        universal_config::init_module_for_test(dst_eid);

        // register destination defaults
        msglib_manager::register_library(@simple_msglib);
        msglib_manager::set_default_receive_library(src_eid, @simple_msglib, 0);

        // register destination
        registration::register_oapp(receiver_oapp, string::utf8(b"receiver"));
        channels::register_receive_pathway(receiver_oapp, src_eid, sender);  // register pathway to receive from sender

        // initialize destination on simple_msglib
        simple_msglib::msglib::initialize_for_test();

        verify(
            @simple_msglib,
            packet_header,
            payload_hash,
            b"",
        );
        assert!(vector::length(&emitted_events<PacketVerified>()) == 1, 0);
        verify(
            @simple_msglib,
            packet_header,
            payload_hash,
            b"",
        );
        assert!(vector::length(&emitted_events<PacketVerified>()) == 2, 0);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::store::EUNREGISTERED_PATHWAY)]
    fun test_verify_fails_if_unregistered_pathway() {
        // packet details
        let receiver_oapp = @123;
        let src_eid = 0x2;
        let dst_eid = 0x3;
        let sender = bytes32::from_address(@0x1234);
        let receiver = bytes32::from_address(receiver_oapp);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        let packet_header = packet_v1_codec::new_packet_v1_header_only(
            src_eid,
            sender,
            dst_eid,
            receiver,
            1,
        );
        store::init_module_for_test();
        universal_config::init_module_for_test(dst_eid);

        // register destination defaults
        msglib_manager::register_library(@simple_msglib);
        msglib_manager::set_default_receive_library(src_eid, @simple_msglib, 0);

        // register destination
        registration::register_oapp(receiver_oapp, string::utf8(b"receiver"));

        // initialize destination on simple_msglib
        simple_msglib::msglib::initialize_for_test();

        verify(
            @simple_msglib,
            packet_header,
            payload_hash,
            b"",
        );
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::channels::EINVALID_MSGLIB)]
    fun test_verify_fails_receive_library_doesnt_match() {
        // packet details
        let receiver_oapp = @123;
        let src_eid = 0x2;
        let dst_eid = 0x3;
        let sender = bytes32::from_address(@0x1234);
        let receiver = bytes32::from_address(receiver_oapp);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        let packet_header = packet_v1_codec::new_packet_v1_header_only(
            src_eid,
            sender,
            dst_eid,
            receiver,
            1,
        );
        store::init_module_for_test();
        universal_config::init_module_for_test(dst_eid);

        // register destination
        registration::register_oapp(receiver_oapp, string::utf8(b"receiver"));
        channels::register_receive_pathway(receiver_oapp, src_eid, sender);  // register pathway to receive from sender

        // register destination defaults
        msglib_manager::register_library(@simple_msglib);
        msglib_manager::register_library(@blocked_msglib);
        msglib_manager::set_default_receive_library(src_eid, @simple_msglib, 0);
        // oapp registers a different library
        msglib_manager::set_receive_library(receiver_oapp, src_eid, @blocked_msglib, 0);


        // initialize destination on simple_msglib
        simple_msglib::msglib::initialize_for_test();

        verify(
            @simple_msglib,
            packet_header,
            payload_hash,
            b"",
        );
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::channels::ENOT_VERIFIABLE)]
    fun test_verify_fails_if_nonce_already_processed() {
        // packet details
        let receiver_oapp = @123;
        let src_eid = 0x2;
        let dst_eid = 0x3;
        let sender = bytes32::from_address(@0x1234);
        let receiver = bytes32::from_address(receiver_oapp);
        let payload = b"payload";
        let payload_hash = bytes32::keccak256(payload);
        let packet_header = packet_v1_codec::new_packet_v1_header_only(
            src_eid,
            sender,
            dst_eid,
            receiver,
            1,
        );
        store::init_module_for_test();
        universal_config::init_module_for_test(dst_eid);

        // register destination defaults
        msglib_manager::register_library(@simple_msglib);
        msglib_manager::set_default_receive_library(src_eid, @simple_msglib, 0);

        // register destination
        registration::register_oapp(receiver_oapp, string::utf8(b"receiver"));
        channels::register_receive_pathway(receiver_oapp, src_eid, sender);  // register pathway to receive from sender

        // initialize destination on simple_msglib
        simple_msglib::msglib::initialize_for_test();

        skip(receiver_oapp, src_eid, sender, 1);

        verify(
            @simple_msglib,
            packet_header,
            payload_hash,
            b"",
        );
    }
}
