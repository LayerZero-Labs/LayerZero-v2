#[test_only]
module oft::oft_using_oft_adapter_fa_tests {
    use std::account::{create_account_for_test, create_signer_for_test};
    use std::fungible_asset;
    use std::fungible_asset::MintRef;
    use std::option;
    use std::primary_fungible_store::{Self, balance};
    use std::signer::address_of;
    use std::vector;

    use endpoint_v2::endpoint;
    use endpoint_v2::test_helpers::setup_layerzero_for_test;
    use endpoint_v2_common::bytes32::{Self, from_address, from_bytes32};
    use endpoint_v2_common::contract_identity::make_dynamic_call_ref_for_test;
    use endpoint_v2_common::guid;
    use endpoint_v2_common::native_token_test_helpers::{burn_token_for_test, mint_native_token_for_test};
    use endpoint_v2_common::packet_raw;
    use endpoint_v2_common::packet_v1_codec::{Self, compute_payload};
    use endpoint_v2_common::zro_test_helpers::create_fa;
    use oft::oapp_core::set_peer;
    use oft::oapp_receive::lz_receive;
    use oft::oapp_store::OAPP_ADDRESS;
    use oft::oft::{
        debit_view, quote_oft, quote_send, remove_dust, send, send_withdraw, to_ld, to_sd, token, unpack_oft_receipt,
    };
    use oft::oft_adapter_fa;
    use oft::oft_adapter_fa::{set_fee_bps, set_rate_limit};
    use oft::oft_store;
    use oft_common::oft_limit::{max_amount_ld, min_amount_ld};
    use oft_common::oft_msg_codec;

    const MAXU64: u64 = 0xffffffffffffffff;
    const SRC_EID: u32 = 101;
    const DST_EID: u32 = 201;

    fun setup(local_eid: u32, remote_eid: u32): MintRef {
        let oft_admin = &create_signer_for_test(@oft_admin);
        setup_layerzero_for_test(@simple_msglib, local_eid, remote_eid);
        oft::oapp_test_helper::init_oapp();

        oft::oft_impl_config::init_module_for_test();
        oft_store::init_module_for_test();
        oft::oft_adapter_fa::init_module_for_test();

        // Generates a fungible asset with 8 decimals
        let (fa, _, mint_ref) = create_fa(b"My Test Token");
        oft_adapter_fa::initialize(oft_admin, fa, 6);

        let remote_oapp = from_address(@2000);
        set_peer(oft_admin, DST_EID, from_bytes32(remote_oapp));

        mint_ref
    }

    #[test]
    fun test_quote_oft() {
        let _mint_ref = setup(SRC_EID, DST_EID);

        let receipient = from_address(@2000);
        let amount_ld = 100u64 * 100_000_000;  // 100 TOKEN
        let compose_msg = vector[];
        let (limit, fees, amount_sent_ld, amount_received_ld) = quote_oft(
            DST_EID,
            from_bytes32(receipient),
            amount_ld,
            0,
            vector[],
            compose_msg,
            vector[]
        );
        assert!(min_amount_ld(&limit) == 0, 0);
        assert!(max_amount_ld(&limit) == MAXU64, 1);
        assert!(vector::length(&fees) == 0, 2);

        assert!(amount_sent_ld == amount_ld, 3);
        assert!(amount_received_ld == amount_ld, 3);
    }

    #[test]
    fun test_quote_send() {
        let _mint_ref = setup(SRC_EID, DST_EID);

        let amount = 100u64 * 100_000_000;  // 100 TOKEN
        let (native_fee, zro_fee) = quote_send(
            @1000,
            DST_EID,
            from_bytes32(from_address(@2000)),
            amount,
            amount,
            vector[],
            vector[],
            vector[],
            false,
        );
        assert!(native_fee == 0, 0);
        assert!(zro_fee == 0, 1);
    }

    #[test]
    fun test_send_fa() {
        let mint_ref = setup(SRC_EID, DST_EID);

        let amount = 100u64 * 100_000_000;  // 100 TOKEN
        let alice = &create_signer_for_test(@1234);
        let fa = mint_native_token_for_test(100_000_000);  // mint 1 APT to alice
        primary_fungible_store::deposit(address_of(alice), fa);
        let bob = from_address(@5678);
        let tokens = fungible_asset::mint(&mint_ref, amount);

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
        let mint_ref = setup(SRC_EID, DST_EID);
        // 10% fee
        set_fee_bps(&create_signer_for_test(@oft_admin), 1000);

        let amount = 100u64 * 100_000_000;  // 100 TOKEN
        let alice = &create_signer_for_test(@1234);
        let fa = mint_native_token_for_test(100_000_000);  // mint 1 APT to alice
        primary_fungible_store::deposit(address_of(alice), fa);
        let bob = from_address(@5678);
        let tokens = fungible_asset::mint(&mint_ref, amount);

        let native_fee = mint_native_token_for_test(10000000);
        let zro_fee = option::none();
        let (_messaging_receipt, oft_receipt) = send(
            &make_dynamic_call_ref_for_test(address_of(alice), OAPP_ADDRESS(), b"send"),
            DST_EID,
            bob,
            &mut tokens,
            9_000_000,
            vector[],
            vector[],
            vector[],
            &mut native_fee,
            &mut zro_fee,
        );
        assert!(fungible_asset::amount(&tokens) == 0, 1); // after send balance

        let (sent, received) = unpack_oft_receipt(&oft_receipt);
        assert!(sent == 10_000_000_000, 2);
        assert!(received == 9_000_000_000, 2);

        // Fee transferred to admin
        assert!(balance(@oft_admin, oft::oft::metadata()) == 1_000_000_000, 3); // fee balance

        // send again with different deposit address
        create_account_for_test(@9999);
        oft::oft_adapter_fa::set_fee_deposit_address(&create_signer_for_test(@oft_admin), @9999);

        burn_token_for_test(tokens);

        let tokens = fungible_asset::mint(&mint_ref, amount);

        let (_messaging_receipt, oft_receipt) = send(
            &make_dynamic_call_ref_for_test(address_of(alice), OAPP_ADDRESS(), b"send"),
            DST_EID,
            bob,
            &mut tokens,
            9_000_000,
            vector[],
            vector[],
            vector[],
            &mut native_fee,
            &mut zro_fee,
        );
        assert!(fungible_asset::amount(&tokens) == 0, 1); // after send balance

        let (sent, received) = unpack_oft_receipt(&oft_receipt);
        assert!(sent == 10_000_000_000, 2);
        assert!(received == 9_000_000_000, 2);

        // Admin balance unchanged
        assert!(balance(@oft_admin, oft::oft::metadata()) == 1_000_000_000, 3); // fee balance
        // Fee transferred to new deposit address
        assert!(balance(@9999, oft::oft::metadata()) == 1_000_000_000, 3); // fee balance

        burn_token_for_test(native_fee);
        option::destroy_none(zro_fee);
        burn_token_for_test(tokens);
    }

    #[test]
    fun test_send() {
        let mint_ref = setup(SRC_EID, DST_EID);

        let amount = 100u64 * 100_000_000;  // 100 TOKEN
        let alice = &create_signer_for_test(@1234);
        let fa = mint_native_token_for_test(100_000_000);  // mint 1 APT to alice
        primary_fungible_store::deposit(address_of(alice), fa);
        let bob = from_bytes32(from_address(@5678));
        let tokens = fungible_asset::mint(&mint_ref, amount);
        primary_fungible_store::deposit(address_of(alice), tokens);
        assert!(balance(address_of(alice), oft::oft::metadata()) == amount, 0); // before send balance

        send_withdraw(alice, DST_EID, bob, amount, amount, vector[], vector[], vector[], 0, 0);
        assert!(balance(address_of(alice), oft::oft::metadata()) == 0, 1); // after send balance
    }

    #[test]
    #[expected_failure(abort_code = oft::oft::EINSUFFICIENT_BALANCE)]
    fun test_send_fails_if_insufficient_balance() {
        let mint_ref = setup(SRC_EID, DST_EID);

        let amount = 100u64 * 100_000_000;  // 100 TOKENS
        let amount_balance = 50u64 * 100_000_000;  // 50 TOKENS
        let alice = &create_signer_for_test(@1234);
        let fa = mint_native_token_for_test(100_000_000);  // mint 1 APT to alice
        primary_fungible_store::deposit(address_of(alice), fa);
        let bob = from_bytes32(from_address(@5678));
        let tokens = fungible_asset::mint(&mint_ref, amount_balance);
        primary_fungible_store::deposit(address_of(alice), tokens);
        assert!(balance(address_of(alice), oft::oft::metadata()) == amount_balance, 0); // before send balance

        send_withdraw(alice, DST_EID, bob, amount, amount, vector[], vector[], vector[], 0, 0);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_impl_config::EEXCEEDED_RATE_LIMIT)]
    fun test_send_exceed_rate_limit() {
        let mint_ref = setup(SRC_EID, DST_EID);
        set_rate_limit(&create_signer_for_test(@oft_admin), DST_EID, 19_000_000_000, 10);

        let amount = 100u64 * 100_000_000;  // 100 TOKEN
        let alice = &create_signer_for_test(@1234);
        let fa = mint_native_token_for_test(100_000_000);  // mint 1 APT to alice
        primary_fungible_store::deposit(address_of(alice), fa);
        let bob = from_bytes32(from_address(@5678));
        // 3x the required tokens
        let tokens = fungible_asset::mint(&mint_ref, amount * 3);
        primary_fungible_store::deposit(address_of(alice), tokens);

        // Succeeds: consumes 10_000_000_000 of 19_000_000_000
        send_withdraw(alice, DST_EID, bob, amount, amount, vector[], vector[], vector[], 0, 0);
        // Fails (rate limit exceeded): consumes 20_000_000_000 of 19_000_000_000
        send_withdraw(alice, DST_EID, bob, amount, amount, vector[], vector[], vector[], 0, 0);
    }

    #[test]
    fun test_send_rate_limit_netted_by_receive() {
        let mint_ref = setup(SRC_EID, DST_EID);
        set_rate_limit(&create_signer_for_test(@oft_admin), DST_EID, 19_000_000_000, 10);

        let amount = 100u64 * 100_000_000;  // 100 TOKEN
        let alice = &create_signer_for_test(@1234);
        let fa = mint_native_token_for_test(100_000_000);  // mint 1 APT to alice
        primary_fungible_store::deposit(address_of(alice), fa);
        let bob = from_bytes32(from_address(@5678));
        // 3x the required tokens
        let tokens = fungible_asset::mint(&mint_ref, amount * 3);
        primary_fungible_store::deposit(address_of(alice), tokens);

        // Succeeds: consumes 10_000_000_000 of 19_000_000_000 in flight
        send_withdraw(alice, DST_EID, bob, amount, amount, vector[], vector[], vector[], 0, 0);

        // Receive 5_000_000_000 (50_000_000 * 100 conversion factor) of 19_000_000_000 in flight
        let message = oft_msg_codec::encode(
            from_address(@1234),
            50_000_000,
            from_address(@0xffff),
            b"",
        );
        // Reverse the EIDs to simulate a receive from the remote OFT
        let packet = packet_v1_codec::new_packet_v1(
            DST_EID,
            from_address(@2000), // remote OFT
            SRC_EID,
            from_address(@oft),
            1,
            guid::compute_guid(
                1,
                DST_EID,
                from_address(@2000),
                SRC_EID,
                from_address(@oft),
            ),
            message,
        );
        endpoint::verify(
            @simple_msglib,
            packet_raw::get_packet_bytes(packet_v1_codec::extract_header(&packet)),
            from_bytes32(bytes32::keccak256(compute_payload(
                packet_v1_codec::get_guid(&packet),
                packet_v1_codec::get_message(&packet),
            ))),
            b""
        );


        lz_receive(
            packet_v1_codec::get_src_eid(&packet),
            from_bytes32(packet_v1_codec::get_sender(&packet)),
            packet_v1_codec::get_nonce(&packet),
            from_bytes32(packet_v1_codec::get_guid(&packet)),
            message,
            vector[],
        );

        // Succeeds: consumes 15_000_000_000 of 19_000_000_000 in flight
        send_withdraw(alice, DST_EID, bob, amount, amount, vector[], vector[], vector[], 0, 0);
    }

    #[test]
    fun test_metadata_view_functions() {
        let _mint_ref = setup(SRC_EID, DST_EID);

        // token is unknown at time of test - just calling to check it doesn't abort
        token();

        assert!(to_ld(100) == 10000, 0);
        assert!(to_sd(100) == 1, 1);
        assert!(remove_dust(123) == 100, 2);

        let (sent, received) = debit_view(1234, 0, DST_EID);
        assert!(sent == 1200, 3);
        assert!(received == 1200, 4);
    }
}