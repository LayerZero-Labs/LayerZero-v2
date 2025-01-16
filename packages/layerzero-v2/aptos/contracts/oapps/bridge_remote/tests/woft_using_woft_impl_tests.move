#[test_only]
module bridge_remote::woft_using_woft_impl_tests {
    use std::account::create_signer_for_test;
    use std::event::was_event_emitted;
    use std::fungible_asset;
    use std::option;
    use std::primary_fungible_store::{Self, balance};
    use std::signer::address_of;
    use std::string::utf8;
    use std::vector;

    use bridge_remote::oapp_core::{set_pause_sending, set_peer};
    use bridge_remote::oapp_store::OAPP_ADDRESS;
    use bridge_remote::woft_impl::{fee_deposit_address_set_event, mint_tokens_for_test, set_fee_bps};
    use bridge_remote::woft_store;
    use bridge_remote::wrapped_assets::{
        Self, debit_view, metadata_for_token, quote_oft, quote_send, remove_dust, send, send_withdraw, to_ld, to_sd,
        unpack_oft_receipt,
    };
    use endpoint_v2::test_helpers::setup_layerzero_for_test;
    use endpoint_v2_common::bytes32::{Bytes32, from_address, from_bytes32};
    use endpoint_v2_common::contract_identity::make_dynamic_call_ref_for_test;
    use endpoint_v2_common::native_token_test_helpers::{burn_token_for_test, mint_native_token_for_test};
    use oft_common::oft_limit::{max_amount_ld, min_amount_ld};

    const MAXU64: u64 = 0xffffffffffffffff;
    const SRC_EID: u32 = 101;
    const DST_EID: u32 = 201;

    fun setup(local_eid: u32, remote_eid: u32) {
        let woft_admin = &create_signer_for_test(@bridge_remote_admin);
        setup_layerzero_for_test(@simple_msglib, local_eid, remote_eid);
        bridge_remote::oapp_test_helper::init_oapp();

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

        let remote_oapp = from_address(@2000);
        set_peer(woft_admin, DST_EID, from_bytes32(remote_oapp));
    }

    #[test]
    fun test_quote_oft() {
        setup(SRC_EID, DST_EID);

        let token: Bytes32 = from_address(@0x2000);
        let receipient = from_address(@2000);
        let amount_ld = 100u64 * 100_000_000;  // 100 TOKEN
        let compose_msg = vector[];
        let (limit, fees, amount_sent_ld, amount_received_ld) = quote_oft(
            from_bytes32(token),
            DST_EID,
            from_bytes32(receipient),
            amount_ld,
            0,
            vector[],
            compose_msg,
        );
        assert!(min_amount_ld(&limit) == 0, 0);
        assert!(max_amount_ld(&limit) == MAXU64, 1);
        assert!(vector::length(&fees) == 0, 2);

        assert!(amount_sent_ld == amount_ld, 3);
        assert!(amount_received_ld == amount_ld, 3);
    }

    #[test]
    fun test_quote_send() {
        setup(SRC_EID, DST_EID);

        let token: Bytes32 = from_address(@0x2000);
        let amount = 100u64 * 100_000_000;  // 100 TOKEN
        let (native_fee, zro_fee) = quote_send(
            from_bytes32(token),
            @1000,
            DST_EID,
            from_bytes32(from_address(@2000)),
            amount,
            amount,
            vector[],
            vector[],
            false,
        );
        assert!(native_fee == 0, 0);
        assert!(zro_fee == 0, 1);
    }

    #[test]
    fun test_send_fa() {
        setup(SRC_EID, DST_EID);

        let token: Bytes32 = from_address(@0x2000);
        let amount = 100u64 * 100_000_000;  // 100 TOKEN
        let alice = &create_signer_for_test(@1234);
        let fa = mint_native_token_for_test(100_000_000);  // mint 1 APT to alice
        primary_fungible_store::deposit(address_of(alice), fa);
        let bob = from_address(@5678);
        let tokens = mint_tokens_for_test(token, amount);

        let native_fee = mint_native_token_for_test(10000000);
        let zro_fee = option::none();
        send(
            &make_dynamic_call_ref_for_test(address_of(alice), OAPP_ADDRESS(), b"send"),
            DST_EID,
            bob,
            &mut tokens,
            amount,
            vector[],
            vector[],
            &mut native_fee,
            &mut zro_fee,
        );
        assert!(fungible_asset::amount(&tokens) == 0, 1); // after send balance

        burn_token_for_test(native_fee);
        option::destroy_none(zro_fee);
        burn_token_for_test(tokens);
    }

    #[test]
    fun test_send_fa_with_fee() {
        setup(SRC_EID, DST_EID);
        let token: Bytes32 = from_address(@0x2000);

        // 10% fee
        set_fee_bps(token, 1000);

        let amount = 100u64 * 100_000_000;  // 100 TOKEN
        let alice = &create_signer_for_test(@1234);
        let fa = mint_native_token_for_test(100_000_000);  // mint 1 APT to alice
        primary_fungible_store::deposit(address_of(alice), fa);
        let bob = from_address(@5678);
        let tokens = mint_tokens_for_test(token, amount);

        let native_fee = mint_native_token_for_test(10000000);
        let zro_fee = option::none();
        let (_messaging_receipt, woft_receipt) = send(
            &make_dynamic_call_ref_for_test(address_of(alice), OAPP_ADDRESS(), b"send"),
            DST_EID,
            bob,
            &mut tokens,
            9_000_000,
            vector[],
            vector[],
            &mut native_fee,
            &mut zro_fee,
        );
        assert!(fungible_asset::amount(&tokens) == 0, 1); // after send balance

        let (sent, received) = unpack_oft_receipt(&woft_receipt);
        assert!(sent == 10_000_000_000, 2);
        assert!(received == 9_000_000_000, 2);

        // the admin should have received the fee
        let admin_balance = balance(
            @bridge_remote_admin,
            metadata_for_token(from_bytes32(token))
        );
        assert!(admin_balance == 1_000_000_000, 3);

        // = Second Pass with a fee deposit address =

        wrapped_assets::set_fee_deposit_address(&create_signer_for_test(@bridge_remote_admin), @0x9898);
        assert!(was_event_emitted(&fee_deposit_address_set_event(@0x9898)), 4);

        burn_token_for_test(tokens);
        let tokens = mint_tokens_for_test(token, amount);

        let (_messaging_receipt, woft_receipt) = send(
            &make_dynamic_call_ref_for_test(address_of(alice), OAPP_ADDRESS(), b"send"),
            DST_EID,
            bob,
            &mut tokens,
            9_000_000,
            vector[],
            vector[],
            &mut native_fee,
            &mut zro_fee,
        );
        assert!(fungible_asset::amount(&tokens) == 0, 1); // after send balance

        let (sent, received) = unpack_oft_receipt(&woft_receipt);
        assert!(sent == 10_000_000_000, 2);
        assert!(received == 9_000_000_000, 2);

        // the admin balance should have not changed
        let admin_balance = balance(
            @bridge_remote_admin,
            metadata_for_token(from_bytes32(token))
        );
        assert!(admin_balance == 1_000_000_000, 3);

        // the deposit address should have received the fee
        let deposit_address_balance = balance(
            @0x9898,
            metadata_for_token(from_bytes32(token))
        );
        assert!(deposit_address_balance == 1_000_000_000, 3);

        burn_token_for_test(native_fee);
        option::destroy_none(zro_fee);
        burn_token_for_test(tokens);
    }

    #[test]
    fun test_send() {
        setup(SRC_EID, DST_EID);

        let token: Bytes32 = from_address(@0x2000);
        let amount = 100u64 * 100_000_000;  // 100 TOKEN
        let alice = &create_signer_for_test(@1234);
        let fa = mint_native_token_for_test(100_000_000);  // mint 1 APT to alice
        primary_fungible_store::deposit(address_of(alice), fa);
        let bob = from_bytes32(from_address(@5678));
        let tokens = mint_tokens_for_test(token, amount);
        primary_fungible_store::deposit(address_of(alice), tokens);
        assert!(
            balance(
                address_of(alice),
                bridge_remote::wrapped_assets::metadata_for_token(from_bytes32(token))
            ) == amount,
            0
        ); // before send balance

        send_withdraw(alice, from_bytes32(token), DST_EID, bob, amount, amount, vector[], vector[], 0, 0);
        assert!(
            balance(address_of(alice), bridge_remote::wrapped_assets::metadata_for_token(from_bytes32(token))) == 0,
            1
        ); // after send balance
    }

    #[test]
    #[expected_failure(abort_code = bridge_remote::woft_core::ETOKEN_NOT_SUPPORTED)]
    fun test_send_fails_if_unknown_token() {
        setup(SRC_EID, DST_EID);

        let token: Bytes32 = from_address(@native_token_metadata_address);  // non-bridge token
        let amount = 100u64 * 100_000_000;  // 100 TOKEN
        let alice = &create_signer_for_test(@1234);
        let fa = mint_native_token_for_test(100_000_000);  // mint 1 APT to alice
        primary_fungible_store::deposit(address_of(alice), fa);
        let bob = from_bytes32(from_address(@5678));

        let tokens = mint_native_token_for_test(amount);
        primary_fungible_store::deposit(address_of(alice), tokens);

        send_withdraw(alice, from_bytes32(token), DST_EID, bob, amount, amount, vector[], vector[], 0, 0);
    }

    #[test]
    #[expected_failure(abort_code = bridge_remote::oapp_core::ESEND_PAUSED)]
    fun test_send_paused() {
        setup(SRC_EID, DST_EID);
        set_pause_sending(&create_signer_for_test(@bridge_remote_admin), DST_EID, true);

        let token: Bytes32 = from_address(@0x2000);
        let amount = 100u64 * 100_000_000;  // 100 TOKEN
        let alice = &create_signer_for_test(@1234);
        let fa = mint_native_token_for_test(100_000_000);  // mint 1 APT to alice
        primary_fungible_store::deposit(address_of(alice), fa);
        let bob = from_bytes32(from_address(@5678));
        let tokens = mint_tokens_for_test(token, amount);
        primary_fungible_store::deposit(address_of(alice), tokens);
        assert!(
            balance(
                address_of(alice),
                bridge_remote::wrapped_assets::metadata_for_token(from_bytes32(token))
            ) == amount,
            0
        ); // before send balance

        send_withdraw(alice, from_bytes32(token), DST_EID, bob, amount, amount, vector[], vector[], 0, 0);
    }

    #[test]
    fun test_metadata_view_functions() {
        setup(SRC_EID, DST_EID);

        let token: Bytes32 = from_address(@0x2000);
        assert!(to_ld(from_bytes32(token), 123) == 123, 0);
        assert!(to_sd(from_bytes32(token), 123) == 123, 1);
        assert!(remove_dust(from_bytes32(token), 123) == 123, 2);

        let (sent, received) = debit_view(from_bytes32(token), 1234, 0, DST_EID);
        assert!(sent == 1234, 3);
        assert!(received == 1234, 4);
    }
}