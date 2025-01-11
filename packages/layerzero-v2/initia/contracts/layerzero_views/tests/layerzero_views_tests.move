#[test_only]
module layerzero_views::layerzero_views_tests {
    use std::account::{create_account_for_test, create_signer_for_test};
    use std::event::was_event_emitted;
    use std::fungible_asset::{Self, FungibleAsset, Metadata};
    use std::object::address_to_object;
    use std::option;
    use std::primary_fungible_store;

    use endpoint_v2::channels::{
        packet_delivered_event,
        packet_sent_event,
        packet_verified_event,
    };
    use endpoint_v2::endpoint::{Self, register_oapp, wrap_guid};
    use endpoint_v2_common::bytes32::{Self, from_bytes32};
    use endpoint_v2_common::contract_identity::{Self, irrecoverably_destroy_contract_signer, make_call_ref_for_test};
    use endpoint_v2_common::guid::compute_guid;
    use endpoint_v2_common::native_token_test_helpers::{
        burn_token_for_test,
        mint_native_token_for_test
    };
    use endpoint_v2_common::packet_raw::{Self, get_packet_bytes};
    use endpoint_v2_common::packet_v1_codec::{Self, new_packet_v1};
    use executor_fee_lib_0::executor_option::{append_executor_options, new_executor_options, new_lz_receive_option};
    use layerzero_views::endpoint_views;
    use layerzero_views::uln_302;
    use msglib_types::worker_options;
    use worker_common::worker_config;

    #[test]
    fun test_verifiable() {
        // account setup
        let src_eid = 1;
        let dst_eid = 1;
        let oapp_address = @9112;
        let account = &create_signer_for_test(oapp_address);
        let sender = bytes32::from_address(oapp_address);
        let receiver = bytes32::from_address(oapp_address);
        let nonce = 1u64;
        let guid = compute_guid(
            nonce,
            src_eid,
            sender,
            dst_eid,
            receiver,
        );

        // init test context
        endpoint_v2::test_helpers::setup_layerzero_for_test_uln(dst_eid, src_eid);

        // DVN Config
        let pubkey1 = x"618d6c6d3b7bd345563636f27db50a39a7fe80c712d22d92aa3485264c9d8446b68db4661092205507a2a39cf3008c23e416cc4f41d87f4431a7cbc0d516f1a4";
        dvn::dvn::init_module_for_test();
        dvn::dvn::initialize(
            &create_account_for_test(@dvn),
            @dvn,
            vector[@111],
            vector[pubkey1],
            1,
            vector[@uln_302],
            @dvn_fee_lib_0,
        );
        worker_config::set_dvn_dst_config(
            &make_call_ref_for_test(@dvn),
            src_eid,
            1000,
            1000,
            1000,
        );
        // opt into using worker config for dvn feelib routing
        uln_302::msglib::set_worker_config_for_fee_lib_routing_opt_in(&create_signer_for_test(@dvn), true);

        let feed_address = @1234;
        worker_config::set_price_feed(
            &make_call_ref_for_test(@dvn),
            @price_feed_module_0,
            feed_address,
        );

        let contract_signer = contract_identity::create_contract_signer(account);
        let call_ref = &contract_identity::make_call_ref(&contract_signer);
        register_oapp(
            account,
            std::string::utf8(b"test_oapp")
        );
        endpoint::register_receive_pathway(call_ref, dst_eid, receiver);

        let options = worker_options::new_empty_type_3_options();
        append_executor_options(
            &mut options,
            &new_executor_options(
                vector[new_lz_receive_option(100, 0)],
                vector[],
                vector[],
                false,
            )
        );

        let message = vector<u8>[1, 2, 3, 4];

        let (fee_in_native, _) = endpoint::quote(
            oapp_address,
            dst_eid,
            bytes32::from_address(oapp_address),
            message,
            options,
            false // pay_in_zro,
        );

        let packet = new_packet_v1(
            src_eid,
            sender,
            dst_eid,
            receiver,
            nonce,
            guid,
            message,
        );
        let packet_header = packet_v1_codec::extract_header(&packet);
        let payload_hash = packet_v1_codec::get_payload_hash(&packet);

        // send test

        // deposit into account
        let fee = mint_native_token_for_test(fee_in_native);
        primary_fungible_store::ensure_primary_store_exists(
            oapp_address,
            fungible_asset::asset_metadata(&fee)
        );
        burn_token_for_test(fee);
        let zro_fee = option::none<FungibleAsset>();

        let native_metadata = address_to_object<Metadata>(@native_token_metadata_address);
        let native_fee = primary_fungible_store::withdraw(
            account,
            native_metadata,
            fee_in_native,
        );

        let sending_call_ref = &contract_identity::make_call_ref(&contract_signer);
        assert!(
            uln_302::verifiable(
                packet_raw::get_packet_bytes(packet_header),
                bytes32::from_bytes32(payload_hash)
            ) == 0, // VERIFYING
            1,
        );
        assert!(
            endpoint_views::executable(
                src_eid,
                bytes32::from_bytes32(sender),
                nonce,
                bytes32::to_address(receiver)
            ) == 0, // NOT_EXECUTABLE
            1,
        );
        // send(oapp, dst_eid, type, options, native_fee);
        endpoint::send(
            sending_call_ref,
            dst_eid,
            receiver,
            message,
            options,
            &mut native_fee,
            &mut zro_fee,
        );
        burn_token_for_test(native_fee);
        option::destroy_none(zro_fee);

        assert!(
            was_event_emitted(
                &packet_sent_event(packet, options, @uln_302)
            ),
            0,
        );
        assert!(
            uln_302::verifiable(
                packet_raw::get_packet_bytes(packet_header),
                bytes32::from_bytes32(payload_hash)
            ) == 0, // VERIFYING
            1,
        );
        assert!(
            endpoint_views::executable(
                src_eid,
                bytes32::from_bytes32(sender),
                nonce,
                bytes32::to_address(receiver)
            ) == 0, // NOT_EXECUTABLE
            1,
        );

        let admin = &create_signer_for_test(@111);
        dvn::dvn::verify(
            admin,
            packet_raw::get_packet_bytes(packet_header),
            bytes32::from_bytes32(payload_hash),
            100,
            @uln_302,
            123456789123,
            x"a13c94e82fc009f71f152f137bed7fb799fa7d75a91a0e3a4ed2000fd408ba052743f3b91ee00cf6a5e98cd4d12b3b2e4984213c0c1c5a251b4e98eeec54f7a800",
        );

        assert!(
            uln_302::verifiable(
                packet_raw::get_packet_bytes(packet_header),
                bytes32::from_bytes32(payload_hash)
            ) == 1, // VERIFIABLE
            2,
        );
        assert!(
            endpoint_views::executable(
                src_eid,
                bytes32::from_bytes32(sender),
                nonce,
                bytes32::to_address(receiver)
            ) == 0, // NOT_EXECUTABLE
            1,
        );

        // - verify packet
        endpoint_v2::endpoint::verify(
            @uln_302,
            get_packet_bytes(packet_header),
            bytes32::from_bytes32(payload_hash),
            b"",
        );

        assert!(
            was_event_emitted(
                &packet_verified_event(
                    src_eid,
                    from_bytes32(sender),
                    nonce,
                    oapp_address,
                    from_bytes32(payload_hash),
                )
            ),
            1,
        );

        assert!(
            uln_302::verifiable(
                packet_raw::get_packet_bytes(packet_header),
                bytes32::from_bytes32(payload_hash)
            ) == 2, // VERIFIED
            3,
        );
        assert!(
            endpoint_views::executable(
                src_eid,
                bytes32::from_bytes32(sender),
                nonce,
                bytes32::to_address(receiver)
            ) == 2, // NOT_EXECUTABLE
            1,
        );

        let receiving_call_ref = &contract_identity::make_call_ref(&contract_signer);
        // - execute packet
        // - check that counter has incremented
        // doesn't matter who the caller of lz_receive
        endpoint::clear(
            receiving_call_ref,
            src_eid,
            sender,
            nonce,
            wrap_guid(guid),
            message,
        );
        assert!(
            was_event_emitted(
                &packet_delivered_event(src_eid, from_bytes32(sender), nonce, oapp_address)
            ),
            2,
        );
        assert!(
            endpoint_views::executable(
                src_eid,
                bytes32::from_bytes32(sender),
                nonce,
                bytes32::to_address(receiver)
            ) == 3, // NOT_EXECUTABLE
            1,
        );
        irrecoverably_destroy_contract_signer(contract_signer);
    }
}
