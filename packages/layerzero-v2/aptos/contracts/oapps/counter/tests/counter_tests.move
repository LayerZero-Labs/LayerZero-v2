#[test_only]
module counter::counter_tests {
    use std::event::was_event_emitted;
    use std::fungible_asset;
    use std::option;
    use std::primary_fungible_store;

    use counter::counter::{Self, get_compose_count, get_inbound_count, get_outbound_count, quote, send};
    use counter::oapp_compose::{Self, lz_compose};
    use counter::oapp_core::set_peer;
    use counter::oapp_receive::{Self, lz_receive};
    use counter::oapp_store;
    use endpoint_v2::channels::{
        packet_delivered_event,
        packet_sent_event,
        packet_verified_event,
    };
    use endpoint_v2_common::bytes32::{Self, from_bytes32};
    use endpoint_v2_common::guid::compute_guid;
    use endpoint_v2_common::native_token_test_helpers::{burn_token_for_test, mint_native_token_for_test};
    use endpoint_v2_common::packet_raw::get_packet_bytes;
    use endpoint_v2_common::packet_v1_codec::{Self, get_guid, new_packet_v1};

    const LOCAL_EID: u32 = 1;

    fun setup() {
        endpoint_v2::test_helpers::setup_layerzero_for_test(@simple_msglib, LOCAL_EID, LOCAL_EID);
        counter::init_module_for_test();
        oapp_store::init_module_for_test();
        oapp_receive::init_module_for_test();
        oapp_compose::init_module_for_test();
        let oapp = &std::account::create_signer_for_test(@oapp_admin);
        set_peer(oapp, LOCAL_EID, bytes32::from_bytes32(bytes32::from_address(@counter)));
        set_peer(oapp, LOCAL_EID, bytes32::from_bytes32(bytes32::from_address(@counter)));
    }

    #[test]
    fun test_quote() {
        setup();

        let options = vector[];
        let type: u8 = 1; // VANILLA_TYPE
        let (native_fee, zro_fee) = quote(LOCAL_EID, type, options, false);
        assert!(native_fee == 0, 0);
        assert!(zro_fee == 0, 1);
    }

    #[test(oapp = @counter)]
    fun test_end_to_end(oapp: &signer) {
        // account setup
        let oapp_address = std::signer::address_of(oapp);
        let sender = bytes32::from_address(oapp_address);
        let receiver = bytes32::from_address(oapp_address);
        let nonce = 1u64;
        let guid = compute_guid(nonce, LOCAL_EID, sender, LOCAL_EID, receiver);

        // init test context
        setup();

        let options = vector[];
        let type: u8 = 1; // VANILLA_TYPE

        let (native_fee, _) = quote(LOCAL_EID, type, options, false);
        let message = counter::msg_codec::encode_msg_type(type, LOCAL_EID, option::none());

        let packet = new_packet_v1(
            LOCAL_EID,
            sender,
            LOCAL_EID,
            receiver,
            nonce,
            guid,
            message,
        );

        let payload_hash = packet_v1_codec::get_payload_hash(&packet);

        // send test
        assert!(get_outbound_count(LOCAL_EID) == 0, 0);

        // deposit into account
        let fee = mint_native_token_for_test(native_fee);
        primary_fungible_store::ensure_primary_store_exists(oapp_address, fungible_asset::asset_metadata(&fee));
        burn_token_for_test(fee);

        send(oapp, LOCAL_EID, type, options, native_fee);
        assert!(get_outbound_count(LOCAL_EID) == 1, 0);
        assert!(was_event_emitted(&packet_sent_event(packet, options, @simple_msglib)), 0);

        // - verify packet
        let packet_header = packet_v1_codec::extract_header(&packet);
        endpoint_v2::endpoint::verify(
            @simple_msglib,
            get_packet_bytes(packet_header),
            bytes32::from_bytes32(payload_hash),
            b"",
        );

        assert!(was_event_emitted(
            &packet_verified_event(LOCAL_EID, from_bytes32(sender), nonce, oapp_address, from_bytes32(payload_hash))
        ), 1);

        // - execute packet
        // - check that counter has incremented
        // doesn't matter who the caller of lz_receive
        assert!(get_inbound_count(LOCAL_EID) == 0, 0);
        lz_receive(
            LOCAL_EID,
            bytes32::from_bytes32(sender),
            nonce,
            bytes32::from_bytes32(get_guid(&packet)),
            message,
            vector[],
        );
        assert!(get_inbound_count(LOCAL_EID) == 1, 0);
        assert!(was_event_emitted(&packet_delivered_event(LOCAL_EID, from_bytes32(sender), nonce, oapp_address)), 2);
    }

    #[test(oapp = @counter)]
    fun test_end_to_end_compose(oapp: &signer) {
        // account setup
        let oapp_address = std::signer::address_of(oapp);
        let sender = bytes32::from_address(oapp_address);
        let receiver = bytes32::from_address(oapp_address);
        let nonce = 1u64;
        let guid = compute_guid(nonce, LOCAL_EID, sender, LOCAL_EID, receiver);

        setup();

        let options = vector[];
        let type: u8 = 2; // COMPOSE_TYPE

        let (native_fee, _) = quote(LOCAL_EID, type, options, false);
        let message = counter::msg_codec::encode_msg_type(type, LOCAL_EID, option::none());

        let packet = new_packet_v1(
            LOCAL_EID,
            sender,
            LOCAL_EID,
            receiver,
            nonce,
            guid,
            message,
        );

        let payload_hash = packet_v1_codec::get_payload_hash(&packet);

        // send test
        assert!(get_outbound_count(LOCAL_EID) == 0, 0);

        // deposit into account
        let fee = mint_native_token_for_test(native_fee);
        primary_fungible_store::ensure_primary_store_exists(oapp_address, fungible_asset::asset_metadata(&fee));
        burn_token_for_test(fee);

        send(oapp, LOCAL_EID, type, options, native_fee);
        assert!(get_outbound_count(LOCAL_EID) == 1, 0);
        assert!(was_event_emitted(&packet_sent_event(packet, options, @simple_msglib)), 0);

        // - verify packet
        let packet_header = packet_v1_codec::extract_header(&packet);
        endpoint_v2::endpoint::verify(
            @simple_msglib,
            get_packet_bytes(packet_header),
            bytes32::from_bytes32(payload_hash),
            b"",
        );

        assert!(was_event_emitted(
            &packet_verified_event(LOCAL_EID, from_bytes32(sender), nonce, oapp_address, from_bytes32(payload_hash))
        ), 1);

        // - execute packet
        // - check that counter has incremented
        // doesn't matter who the caller of lz_receive
        assert!(get_inbound_count(LOCAL_EID) == 0, 0);
        lz_receive(
            LOCAL_EID,
            bytes32::from_bytes32(sender),
            nonce,
            bytes32::from_bytes32(get_guid(&packet)),
            message,
            vector[],
        );
        assert!(get_inbound_count(LOCAL_EID) == 1, 0);
        assert!(was_event_emitted(&packet_delivered_event(LOCAL_EID, from_bytes32(sender), nonce, oapp_address)), 2);
        assert!(get_compose_count() == 0, 0);
        lz_compose(
            @counter,
            bytes32::from_bytes32(get_guid(&packet)),
            0,
            message,
            vector[]
        );
        assert!(get_compose_count() == 1, 0);
    }
}