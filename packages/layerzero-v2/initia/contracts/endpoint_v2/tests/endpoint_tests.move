#[test_only]
module endpoint_v2::endpoint_tests {
    use std::account::create_signer_for_test;
    use std::fungible_asset::FungibleAsset;
    use std::option;
    use std::signer::address_of;
    use std::string;

    use endpoint_v2::admin;
    use endpoint_v2::channels;
    use endpoint_v2::endpoint::{
        Self,
        EndpointOAppConfigTarget,
        quote,
        register_composer,
        register_oapp, send,
    };
    use endpoint_v2::test_helpers;
    use endpoint_v2_common::bytes32;
    use endpoint_v2_common::contract_identity::make_call_ref_for_test;
    use endpoint_v2_common::guid::compute_guid;
    use endpoint_v2_common::native_token_test_helpers::{burn_token_for_test, mint_native_token_for_test};
    use endpoint_v2_common::packet_v1_codec::new_packet_v1;
    use endpoint_v2_common::universal_config;

    #[test]
    fun test_quote() {
        let oapp = &create_signer_for_test(@1234);
        let local_eid = 1u32;
        endpoint_v2::test_helpers::setup_layerzero_for_test(@simple_msglib, local_eid, local_eid);
        register_oapp(oapp, string::utf8(b"test"));

        let sender = std::signer::address_of(oapp);
        let receiver = bytes32::from_address(sender);
        let message = vector<u8>[1, 2, 3, 4];
        let options = vector[];
        let (native_fee, zro_fee) = quote(sender, local_eid, receiver, message, options, false);
        assert!(native_fee == 0, 0);
        assert!(zro_fee == 0, 1);
    }

    #[test]
    fun test_send() {
        let oapp = &create_signer_for_test(@1234);
        // account setup
        let sender = std::signer::address_of(oapp);

        let local_eid = 1u32;
        test_helpers::setup_layerzero_for_test(@simple_msglib, local_eid, local_eid);
        register_oapp(oapp, string::utf8(b"test"));

        let receiver = bytes32::from_address(sender);
        let message = vector<u8>[1, 2, 3, 4];
        let options = vector[];

        let (native_fee, _) = quote(sender, local_eid, receiver, message, options, false);

        let payment_native = mint_native_token_for_test(native_fee);
        let payment_zro = option::none<FungibleAsset>();
        send(
            &make_call_ref_for_test(sender),
            local_eid,
            receiver,
            message,
            options,
            &mut payment_native,
            &mut payment_zro,
        );
        burn_token_for_test(payment_native);

        // check that the packet was emitted
        let guid = compute_guid(1, local_eid, bytes32::from_address(sender), local_eid, receiver);
        let packet = new_packet_v1(
            universal_config::eid(),
            bytes32::from_address(sender),
            local_eid,
            receiver,
            1,
            guid,
            message,
        );
        let expected_event = channels::packet_sent_event(packet, options, @simple_msglib);
        assert!(std::event::was_event_emitted(&expected_event), 0);

        option::destroy_none(payment_zro);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::endpoint::EUNREGISTERED)]
    fun test_get_oapp_caller_fails_if_not_registered() {
        test_helpers::setup_layerzero_for_test(@simple_msglib, 100, 100);
        let oapp = &create_signer_for_test(@1234);
        // registering composer should not count as registering oapp
        register_composer(oapp, string::utf8(b"test"));
        // Must provide type since get_oapp_caller is generic
        let call_ref = &make_call_ref_for_test<EndpointOAppConfigTarget>(address_of(oapp));
        endpoint_v2::endpoint::get_oapp_caller(call_ref);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::endpoint::EUNREGISTERED)]
    fun test_get_compose_caller_fails_if_not_registered() {
        test_helpers::setup_layerzero_for_test(@simple_msglib, 100, 100);
        let composer = &create_signer_for_test(@1234);
        // registering oapp should not count as registering composer
        register_oapp(composer, string::utf8(b"test"));
        let call_ref = &make_call_ref_for_test<EndpointOAppConfigTarget>(address_of(composer));
        // Must provide type since get_oapp_caller is generic
        endpoint_v2::endpoint::get_compose_caller(call_ref);
    }

    #[test]
    fun get_default_receive_library_timeout_should_return_none_if_not_set() {
        test_helpers::setup_layerzero_for_test(@simple_msglib, 100, 100);
        let (timeout, library) = endpoint::get_default_receive_library_timeout(1);
        assert!(library == @0x0, 0);
        assert!(timeout == 0, 1);
    }

    #[test]
    fun get_default_receive_library_timeout_should_return_the_timeout_if_set() {
        let std = &std::account::create_account_for_test(@std);
        std::block::initialize_for_test(std, 1_000_000);
        std::reconfiguration::initialize_for_test(std);

        test_helpers::setup_layerzero_for_test(@simple_msglib, 100, 100);
        admin::set_default_receive_library_timeout(
            &create_signer_for_test(@layerzero_admin),
            12,
            @simple_msglib,
            10000
        );
        let (timeout, library) = endpoint::get_default_receive_library_timeout(12);
        assert!(library == @simple_msglib, 0);
        assert!(timeout == 10000, 1);
    }
}
