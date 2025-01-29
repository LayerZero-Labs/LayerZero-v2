#[test_only]
module bridge_remote::woft_impl_tests {
    use std::account::{create_account_for_test, create_signer_for_test};
    use std::fungible_asset::{Self, Metadata};
    use std::object::address_to_object;
    use std::option;
    use std::primary_fungible_store;
    use std::string::utf8;
    use std::timestamp;
    use std::vector;

    use bridge_remote::oapp_core;
    use bridge_remote::woft_impl::{Self, mint_tokens_for_test};
    use bridge_remote::woft_store;
    use endpoint_v2::test_helpers::setup_layerzero_for_test;
    use endpoint_v2_common::bytes32::{Self, Bytes32, from_address};
    use endpoint_v2_common::native_token_test_helpers::{burn_token_for_test, mint_native_token_for_test};
    use oft_common::oft_limit::new_unbounded_oft_limit;

    const MAXU64: u64 = 0xffffffffffffffff;

    const LOCAL_EID: u32 = 101;

    fun setup() {
        setup_layerzero_for_test(@simple_msglib, LOCAL_EID, LOCAL_EID);

        let token: Bytes32 = from_address(@0x2000);
        bridge_remote::oapp_test_helper::init_oapp();

        woft_store::init_module_for_test();
        woft_impl::init_module_for_test();
        woft_impl::initialize(
            &create_signer_for_test(@bridge_remote_admin),
            token,
            utf8(b"My Test Token"),
            utf8(b"MYT"),
            6,
            6,
        );

        assert!(
            fungible_asset::name(
                bridge_remote::wrapped_assets::metadata_for_token(bytes32::from_bytes32(token))
            ) == utf8(
                b"My Test Token"
            ),
            0
        );
        assert!(
            fungible_asset::symbol(
                bridge_remote::wrapped_assets::metadata_for_token(bytes32::from_bytes32(token))
            ) == utf8(
                b"MYT"
            ),
            0
        );
        assert!(
            fungible_asset::icon_uri(
                bridge_remote::wrapped_assets::metadata_for_token(bytes32::from_bytes32(token))
            ) == utf8(b""),
            0
        );
        assert!(
            fungible_asset::project_uri(
                bridge_remote::wrapped_assets::metadata_for_token(bytes32::from_bytes32(token))
            ) == utf8(b""),
            0
        );
        assert!(
            fungible_asset::decimals(
                bridge_remote::wrapped_assets::metadata_for_token(bytes32::from_bytes32(token))
            ) == 6,
            0
        );
    }

    #[test]
    fun test_debit() {
        setup();

        let token: Bytes32 = from_address(@0x2000);
        let dst_eid = 2u32;
        // This configuration function (debit) is not resposible for handling dust, therefore the tested amount excludes
        // the dust amount (last two digits)
        let amount_ld = 123456700;
        let min_amount_ld = 0u64;

        let fa = mint_tokens_for_test(token, amount_ld);
        let (sent, received) = woft_impl::debit_fungible_asset(
            token,
            @444,
            &mut fa,
            min_amount_ld,
            dst_eid,
        );

        // amount sent and received should reflect the amount debited
        assert!(sent == 123456700, 0);
        assert!(received == 123456700, 0);

        // no remaining balance
        let remaining_balance = fungible_asset::amount(&fa);
        assert!(remaining_balance == 0, 0);
        burn_token_for_test(fa);
    }

    #[test]
    fun test_credit() {
        setup();

        let token: Bytes32 = from_address(@0x2000);
        let amount_ld = 123456700;
        let lz_receive_value = option::none();
        let src_eid = 12345;

        let to = @555;
        create_account_for_test(to);

        // 0 balance before crediting
        let balance = primary_fungible_store::balance(to, woft_impl::metadata(token));
        assert!(balance == 0, 0);

        let credited = woft_impl::credit(
            token,
            to,
            amount_ld,
            src_eid,
            lz_receive_value,
        );
        // amount credited should reflect the amount credited
        assert!(credited == 123456700, 0);

        // balance should appear in account
        let balance = primary_fungible_store::balance(to, woft_impl::metadata(token));
        assert!(balance == 123456700, 0);
    }

    #[test]
    fun test_credit_with_extra_lz_receive_drop() {
        setup();

        let token: Bytes32 = from_address(@0x2000);
        let amount_ld = 123456700;
        let lz_receive_value = option::some(mint_native_token_for_test(100));
        let src_eid = 12345;

        let to = @555;
        create_account_for_test(to);

        // 0 balance before crediting
        let balance = primary_fungible_store::balance(to, woft_impl::metadata(token));
        assert!(balance == 0, 0);

        woft_impl::credit(
            token,
            to,
            amount_ld,
            src_eid,
            lz_receive_value,
        );

        let native_token_metadata = address_to_object<Metadata>(@native_token_metadata_address);
        assert!(primary_fungible_store::balance(@bridge_remote_admin, native_token_metadata) == 100, 1)
    }

    #[test]
    fun test_debit_view() {
        setup();

        let token: Bytes32 = from_address(@0x2000);
        // shouldn't take a fee
        let (sent, received) = woft_impl::debit_view(token, 123456700, 100, 2);
        assert!(sent == 123456700, 0);
        assert!(received == 123456700, 0);
    }

    #[test]
    #[expected_failure(abort_code = bridge_remote::woft_core::ESLIPPAGE_EXCEEDED)]
    fun test_debit_view_fails_if_less_than_min() {
        setup();

        let token: Bytes32 = from_address(@0x2000);
        woft_impl::debit_view(token, 32, 100, 2);
    }

    #[test]
    fun test_build_options() {
        setup();
        let dst_eid = 103;

        let message_type = 2;

        let options = woft_impl::build_options(
            message_type,
            dst_eid,
            // OKAY that it's not type 3 if no enforced options are set
            x"1234",
            @123,
            123324,
            bytes32::from_address(@444),
            x"34"
        );
        // should pass through the options if none configured
        assert!(options == x"1234", 0);

        let woft_admin = &create_signer_for_test(@bridge_remote_admin);
        oapp_core::set_enforced_options(
            woft_admin,
            dst_eid,
            message_type,
            x"00037777"
        );

        let options = woft_impl::build_options(
            message_type,
            dst_eid,
            x"00031234",
            @123,
            123324,
            bytes32::from_address(@444),
            x"34"
        );

        // should append to configured options
        assert!(options == x"000377771234", 0);
    }

    #[test]
    fun test_inspect_message() {
        // doesn't do anything, just tests that it doesn't fail
        woft_impl::inspect_message(
            &x"1234",
            &x"1234",
            true,
        );
    }

    #[test]
    fun test_oft_limit_and_fees() {
        setup();

        let token: Bytes32 = from_address(@0x2000);
        timestamp::set_time_has_started_for_testing(&create_signer_for_test(@std));
        let (limit, fees) = woft_impl::woft_limit_and_fees(
            token,
            123,
            x"1234",
            123,
            100,
            x"1234",
            x"1234"
        );

        // always unbounded and empty for this woft configuration
        assert!(limit == new_unbounded_oft_limit(), 0);
        assert!(vector::length(&fees) == 0, 0);
    }
}
