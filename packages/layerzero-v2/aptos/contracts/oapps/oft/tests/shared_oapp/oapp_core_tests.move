#[test_only]
module oft::oapp_core_tests {
    use std::account::create_account_for_test;
    use std::account::create_signer_for_test;
    use std::event::was_event_emitted;
    use std::fungible_asset::{Self, FungibleAsset};
    use std::option;
    use std::primary_fungible_store;
    use std::signer::address_of;

    use endpoint_v2::channels::packet_sent_event;
    use endpoint_v2::messaging_receipt;
    use endpoint_v2::test_helpers::setup_layerzero_for_test;
    use endpoint_v2_common::bytes32::{Self, from_address, from_bytes32};
    use endpoint_v2_common::guid;
    use endpoint_v2_common::native_token;
    use endpoint_v2_common::native_token_test_helpers::{burn_token_for_test, initialize_native_token_for_test,
        mint_native_token_for_test
    };
    use endpoint_v2_common::packet_v1_codec;
    use endpoint_v2_common::universal_config;
    use endpoint_v2_common::zro_test_helpers::create_fa;
    use oft::oapp_core::{Self, withdraw_lz_fees};
    use oft::oapp_store::OAPP_ADDRESS;
    use oft::oft_core::{SEND, SEND_AND_CALL};

    const SRC_EID: u32 = 101;
    const DST_EID: u32 = 201;

    fun setup(local_eid: u32, remote_eid: u32) {
        // Test the send function
        setup_layerzero_for_test(@simple_msglib, local_eid, remote_eid);
        let oft_admin = &create_signer_for_test(@oft_admin);
        initialize_native_token_for_test();
        oft::oapp_test_helper::init_oapp();
        oapp_core::set_peer(oft_admin, SRC_EID, from_bytes32(from_address(@1234)));
        oapp_core::set_peer(oft_admin, DST_EID, from_bytes32(from_address(@4321)));
    }

    #[test]
    fun test_send_internal() {
        setup(SRC_EID, DST_EID);

        let called_send = false;
        let called_inspect = false;
        assert!(!called_inspect && !called_send, 0);

        let native_fee = mint_native_token_for_test(100000);
        let zro_fee = option::none<FungibleAsset>();

        let messaging_receipt = oapp_core::lz_send(
            DST_EID,
            b"oapp-message",
            b"options",
            &mut native_fee,
            &mut zro_fee,
        );

        let expected_guid = guid::compute_guid(
            1,
            SRC_EID,
            bytes32::from_address(OAPP_ADDRESS()),
            DST_EID,
            bytes32::from_address(@4321),
        );

        assert!(messaging_receipt::get_guid(&messaging_receipt) == expected_guid, 0);

        // 0 fees in simple msglib
        assert!(messaging_receipt::get_native_fee(&messaging_receipt) == 0, 1);
        assert!(messaging_receipt::get_zro_fee(&messaging_receipt) == 0, 1);
        // nothing removed
        assert!(fungible_asset::amount(&native_fee) == 100000, 0);

        assert!(messaging_receipt::get_nonce(&messaging_receipt) == 1, 2);

        let packet = packet_v1_codec::new_packet_v1(
            SRC_EID,
            bytes32::from_address(OAPP_ADDRESS()),
            DST_EID,
            bytes32::from_address(@4321),
            1,
            expected_guid,
            b"oapp-message",
        );
        assert!(was_event_emitted(&packet_sent_event(
            packet,
            b"options",
            @simple_msglib,
        )), 0);

        burn_token_for_test(native_fee);
        option::destroy_none(zro_fee);
    }

    #[test]
    fun test_quote_internal() {
        setup(SRC_EID, DST_EID);

        let (native_fee, zro_fee) = oapp_core::lz_quote(
            DST_EID,
            b"oapp-message",
            b"options",
            false,
        );
        assert!(native_fee == 0, 0);
        assert!(zro_fee == 0, 1);
    }

    #[test]
    fun test_set_enforced_options() {
        setup(SRC_EID, DST_EID);

        // setup admin
        let oft_admin = &create_signer_for_test(@oft_admin);
        let admin = &create_account_for_test(@1111);
        oapp_core::transfer_admin(oft_admin, address_of(admin));

        oapp_core::set_enforced_options(admin, SRC_EID, SEND(), x"0003aaaa");
        oapp_core::set_enforced_options(admin, DST_EID, SEND(), x"0003bbbc");
        oapp_core::set_enforced_options(admin, DST_EID, SEND(), x"000355");
        oapp_core::set_enforced_options(admin, DST_EID, SEND_AND_CALL(), x"000344");
        assert!(oapp_core::get_enforced_options(DST_EID, SEND()) == x"000355", 0);
        assert!(oapp_core::get_enforced_options(DST_EID, SEND_AND_CALL()) == x"000344", 0);
        assert!(oapp_core::get_enforced_options(SRC_EID, SEND()) == x"0003aaaa", 0);
    }

    #[test]
    fun test_combine_options() {
        setup(SRC_EID, DST_EID);

        // setup admin
        let oft_admin = &create_signer_for_test(@oft_admin);
        let admin = &create_account_for_test(@1111);
        oapp_core::transfer_admin(oft_admin, address_of(admin));

        let enforced_options = x"0003aaaa";
        let options = x"0003bbbb";
        oapp_core::set_enforced_options(admin, DST_EID, SEND(), enforced_options);
        // unrelated option below just to make sure it doesn't get overwritten
        oapp_core::set_enforced_options(admin, DST_EID, SEND_AND_CALL(), x"0003235326");
        let combined = oapp_core::combine_options(DST_EID, SEND(), options);
        assert!(combined == x"0003aaaabbbb", 0);
    }

    #[test]
    fun test_peers() {
        // Test the send function
        setup(SRC_EID, DST_EID);

        // setup admin
        let oft_admin = &create_signer_for_test(@oft_admin);
        let admin = &create_account_for_test(@1111);
        oapp_core::transfer_admin(oft_admin, address_of(admin));

        assert!(!oapp_core::has_peer(1111), 0);
        oapp_core::set_peer(admin, 1111, from_bytes32(from_address(@1234)));
        oapp_core::set_peer(admin, 2222, from_bytes32(from_address(@2345)));
        assert!(oapp_core::has_peer(1111), 0);
        assert!(oapp_core::has_peer(2222), 0);
        assert!(oapp_core::get_peer_bytes32(1111) == from_address(@1234), 0);
        assert!(oapp_core::get_peer_bytes32(2222) == from_address(@2345), 0);
    }

    #[test]
    fun test_delegate() {
        setup(SRC_EID, DST_EID);

        // setup admin
        let oft_admin = &create_signer_for_test(@oft_admin);
        let admin = &create_account_for_test(@1111);
        oapp_core::transfer_admin(oft_admin, address_of(admin));

        let delegate = &create_signer_for_test(@2222);
        oapp_core::set_delegate(admin, address_of(delegate));
        assert!(oapp_core::get_delegate() == address_of(delegate), 0);

        let delegate2 = &create_signer_for_test(@3333);
        oapp_core::set_delegate(admin, address_of(delegate2));

        oapp_core::skip(delegate2, SRC_EID, from_bytes32(from_address(@1234)), 1);
    }

    #[test]
    fun test_withdraw_lz_fees() {
        let native_token = mint_native_token_for_test(1000);

        let (zro_address, zro_metadata, mint_ref) = create_fa(b"ZRO");
        universal_config::init_module_for_test(100);
        universal_config::set_zro_address(&create_signer_for_test(@layerzero_admin), zro_address);

        let zro_token = fungible_asset::mint(&mint_ref, 1000);

        primary_fungible_store::deposit(@0x1234, native_token);
        primary_fungible_store::deposit(@0x1234, zro_token);

        let account = &create_signer_for_test(@0x1234);

        let (native_token, zro_token) = withdraw_lz_fees(account, 600, 550);
        assert!(fungible_asset::amount(&native_token) == 600, 0);
        assert!(fungible_asset::amount(option::borrow(&zro_token)) == 550, 0);
        burn_token_for_test(native_token);
        burn_token_for_test(option::extract(&mut zro_token));
        option::destroy_none(zro_token);

        assert!(native_token::balance(@0x1234) == 400, 0);
        assert!(primary_fungible_store::balance(@0x1234, zro_metadata) == 450, 0);
    }

    #[test]
    fun test_withdraw_lz_fees_no_zro() {
        let native_token = mint_native_token_for_test(1000);
        primary_fungible_store::deposit(@0x1234, native_token);

        let account = &create_signer_for_test(@0x1234);

        let (native_token, zro_token) = withdraw_lz_fees(account, 600, 0);
        assert!(fungible_asset::amount(&native_token) == 600, 0);
        assert!(option::is_none(&zro_token), 0);
        burn_token_for_test(native_token);
        option::destroy_none(zro_token);

        assert!(native_token::balance(@0x1234) == 400, 0);
    }

    #[test]
    #[expected_failure(abort_code = oft::oapp_core::EINSUFFICIENT_NATIVE_TOKEN_BALANCE)]
    fun test_withdraw_lz_fees_fails_with_insufficient_native_balance() {
        let native_token = mint_native_token_for_test(100);

        let (zro_address, _, mint_ref) = create_fa(b"ZRO");
        universal_config::init_module_for_test(100);
        universal_config::set_zro_address(&create_signer_for_test(@layerzero_admin), zro_address);

        let zro_token = fungible_asset::mint(&mint_ref, 1000);

        primary_fungible_store::deposit(@0x1234, native_token);
        primary_fungible_store::deposit(@0x1234, zro_token);

        let account = &create_signer_for_test(@0x1234);

        let (native_token, zro_token) = withdraw_lz_fees(account, 600, 550);
        burn_token_for_test(native_token);
        burn_token_for_test(option::extract(&mut zro_token));
        option::destroy_none(zro_token);
    }

    #[test]
    #[expected_failure(abort_code = oft::oapp_core::EINSUFFICIENT_ZRO_BALANCE)]
    fun test_withdraw_lz_fees_fails_with_insufficient_zro_balance() {
        let native_token = mint_native_token_for_test(1000);

        let (zro_address, _, mint_ref) = create_fa(b"ZRO");
        universal_config::init_module_for_test(100);
        universal_config::set_zro_address(&create_signer_for_test(@layerzero_admin), zro_address);

        let zro_token = fungible_asset::mint(&mint_ref, 100);

        primary_fungible_store::deposit(@0x1234, native_token);
        primary_fungible_store::deposit(@0x1234, zro_token);

        let account = &create_signer_for_test(@0x1234);

        let (native_token, zro_token) = withdraw_lz_fees(account, 600, 550);
        burn_token_for_test(native_token);
        burn_token_for_test(option::extract(&mut zro_token));
        option::destroy_none(zro_token);
    }
}
