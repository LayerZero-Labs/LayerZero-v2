// **Important** These tests are only valid for the default configuration of OFT Native Coin. If the configuration is
// changed, these tests will need to be updated to reflect those changes
#[test_only]
module oft::oft_coin_tests {
    use std::account::{create_account_for_test, create_signer_for_test};
    use std::aptos_account;
    use std::aptos_coin::AptosCoin;
    use std::coin;
    use std::event::was_event_emitted;
    use std::fungible_asset::Metadata;
    use std::object::address_to_object;
    use std::option;
    use std::primary_fungible_store;
    use std::timestamp;
    use std::vector;

    use endpoint_v2::test_helpers::setup_layerzero_for_test;
    use endpoint_v2_common::bytes32;
    use endpoint_v2_common::native_token_test_helpers::mint_native_token_for_test;
    use oft::oapp_core;
    use oft::oft::remove_dust;
    use oft::oft_coin::{
        Self,
        burn_token_for_test,
        fee_bps,
        fee_deposit_address,
        is_blocklisted,
        mint_tokens_for_test,
        PlaceholderCoin,
        set_fee_bps,
        set_fee_deposit_address,
    };
    use oft::oft_impl_config;
    use oft::oft_store;
    use oft_common::oft_limit::new_unbounded_oft_limit;

    const MAXU64: u64 = 0xffffffffffffffff;
    const LOCAL_EID: u32 = 101;

    fun setup() {
        // Initialize AptosCoin - this is necessary because some of the coin internals
        let (burn_cap, mint_cap) = std::aptos_coin::initialize_for_test(&create_account_for_test(@std));
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        setup_layerzero_for_test(@simple_msglib, LOCAL_EID, LOCAL_EID);

        oft::oapp_test_helper::init_oapp();

        oft_store::init_module_for_test();
        oft_coin::init_module_for_test();
        oft_impl_config::init_module_for_test();
    }

    #[test]
    fun test_debit() {
        setup();

        let dst_eid = 2u32;
        // This configuration function (debit) is not resposible for handling dust, therefore the tested amount excludes
        // the dust amount (last two digits)
        let amount_ld = 123456700;
        let min_amount_ld = 0u64;

        let coin = mint_tokens_for_test<PlaceholderCoin>(amount_ld);

        let dust_removed = remove_dust(amount_ld);
        let (sent, received) = oft_coin::debit_coin(
            @444,
            &mut coin,
            min_amount_ld,
            dst_eid,
        );

        // amount sent and received should reflect the amount debited
        assert!(sent == dust_removed, 0);
        assert!(received == dust_removed, 0);

        // no remaining balance
        let remaining_balance = coin::value(&coin);
        assert!(remaining_balance == amount_ld - dust_removed, 0);

        burn_token_for_test(coin);
    }

    #[test]
    fun test_credit() {
        setup();

        let amount_ld = 123456700;
        let lz_receive_value = option::none();
        let src_eid = 12345;

        let to = @555;
        create_account_for_test(to);

        // 0 balance before crediting
        let balance = coin::balance<PlaceholderCoin>(to);
        assert!(balance == 0, 0);

        let credited = oft_coin::credit(
            to,
            amount_ld,
            src_eid,
            lz_receive_value,
        );
        // amount credited should reflect the amount credited
        assert!(credited == 123456700, 0);

        // balance should appear in account
        let balance = coin::balance<PlaceholderCoin>(to);
        assert!(balance == 123456700, 0);
    }

    #[test]
    fun test_credit_with_extra_lz_receive_drop() {
        setup();

        let amount_ld = 0;
        let lz_receive_value = option::some(mint_native_token_for_test(100));
        let src_eid = 12345;

        let to = @555;
        let to_signer = &create_account_for_test(to);
        coin::register<PlaceholderCoin>(to_signer);

        // 0 balance before crediting
        let balance = coin::balance<PlaceholderCoin>(to);
        assert!(balance == 0, 0);

        oft_coin::credit(
            to,
            amount_ld,
            src_eid,
            lz_receive_value,
        );
        let native_token_metadata = address_to_object<Metadata>(@native_token_metadata_address);
        assert!(primary_fungible_store::balance(@oft_admin, native_token_metadata) == 100, 1)
    }

    #[test]
    fun test_debit_view() {
        setup();

        // shouldn't take a fee
        let (sent, received) = oft_coin::debit_view(123456700, 100, 2);
        let dust_removed = remove_dust(123456700);
        assert!(sent == dust_removed, 0);
        assert!(received == dust_removed, 0);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_core::ESLIPPAGE_EXCEEDED)]
    fun test_debit_view_fails_if_less_than_min() {
        setup();

        oft_coin::debit_view(32, 100, 2);
    }

    #[test]
    fun test_build_options() {
        setup();
        let dst_eid = 103;

        let message_type = 2;

        let options = oft_coin::build_options(
            message_type,
            dst_eid,
            // OKAY that it's not type 3 if no enforced options are set
            x"1234",
            @123,
            123324,
            bytes32::from_address(@444),
            x"8888",
            x"34"
        );
        // should pass through the options if none configured
        assert!(options == x"1234", 0);

        let oft_admin = &create_signer_for_test(@oft_admin);
        oapp_core::set_enforced_options(
            oft_admin,
            dst_eid,
            message_type,
            x"00037777"
        );

        let options = oft_coin::build_options(
            message_type,
            dst_eid,
            x"00031234",
            @123,
            123324,
            bytes32::from_address(@444),
            x"8888",
            x"34"
        );

        // should append to configured options
        assert!(options == x"000377771234", 0);
    }

    #[test]
    fun test_inspect_message() {
        // doesn't do anything, just tests that it doesn't fail
        oft_coin::inspect_message(
            &x"1234",
            &x"1234",
            true,
        );
    }

    #[test]
    fun test_oft_limit_and_fees() {
        setup();

        timestamp::set_time_has_started_for_testing(&create_signer_for_test(@std));
        let (limit, fees) = oft_coin::oft_limit_and_fees(
            123,
            x"1234",
            123,
            100,
            x"1234",
            x"1234",
            x"1234"
        );

        // always unbounded and empty for this oft configuration
        assert!(limit == new_unbounded_oft_limit(), 0);
        assert!(vector::length(&fees) == 0, 0);
    }

    #[test]
    fun test_set_fee_bps() {
        setup();

        let oft_admin = &create_signer_for_test(@oft_admin);
        let fee_bps = 500; // 5%

        set_fee_bps(
            oft_admin,
            fee_bps,
        );

        let fee_bps_result = fee_bps();
        assert!(fee_bps_result == fee_bps, 0);

        let (oft_limit, oft_fee_details) = oft_coin::oft_limit_and_fees(
            123,
            x"1234",
            100_000_000,
            100,
            x"1234",
            x"1234",
            x"1234"
        );

        // Check fee detail
        assert!(vector::length(&oft_fee_details) == 1, 1);
        let fee_detail = *vector::borrow(&oft_fee_details, 0);
        let (fee_amount, is_reward) = oft_common::oft_fee_detail::fee_amount_ld(&fee_detail);
        assert!(fee_amount == 5_000_000, 2);
        assert!(is_reward == false, 3);

        // Check limit
        assert!(oft_limit == new_unbounded_oft_limit(), 4);

        let deposit_address = @5555;
        create_account_for_test(deposit_address);
        set_fee_deposit_address(
            oft_admin,
            deposit_address,
        );
        assert!(fee_deposit_address() == @5555, 1);

        // debit with fee
        let dst_eid = 2u32;
        // This configuration function (debit) is not resposible for handling dust, therefore the tested amount excludes
        // the dust amount (last two digits)
        let amount_ld = 123456700;
        let min_amount_ld = 0u64;

        let coin_value = mint_tokens_for_test(amount_ld);

        let (sent, received) = oft_coin::debit_coin(
            @444,
            &mut coin_value,
            min_amount_ld,
            dst_eid,
        );

        // amount sent and received should reflect the amount debited
        assert!(sent == 123456700, 0);
        // Any dust is also included in the fee
        assert!(received == 117283800, 0); // 123456700 * 0.95 = 117283865 - remove dust -> 117283800

        // no remaining balance
        let remaining_balance = coin::value<PlaceholderCoin>(&coin_value);
        assert!(remaining_balance == 00, 0);
        burn_token_for_test(coin_value);

        // check that the fee was deposited
        let fee_deposited = coin::balance<PlaceholderCoin>(deposit_address);
        assert!(fee_deposited == 6172900, 0); // 123456700 - 117283800 = 6172900

        // check the invariant that the total amount is conserved
        assert!(received + fee_deposited == sent, 1);
    }

    #[test]
    fun test_set_blocklist_credit() {
        setup();

        let blocklisted_address = @0x1234;
        assert!(is_blocklisted(blocklisted_address) == false, 0);

        let admin = &create_signer_for_test(@oft_admin);
        create_account_for_test(blocklisted_address);
        oft_coin::set_blocklist(
            admin,
            blocklisted_address,
            true,
        );
        assert!(was_event_emitted(&oft_impl_config::blocklist_set_event(blocklisted_address, true)), 1);
        assert!(is_blocklisted(blocklisted_address), 1);

        // Admin must exist as an account to redirect the blocked amount
        create_account_for_test(@oft_admin);

        oft_coin::credit(
            blocklisted_address,
            1234,
            12345,
            option::none(),
        );

        assert!(
            was_event_emitted(&oft_impl_config::blocked_amount_redirected_event(1234, blocklisted_address, @oft_admin)),
            2
        );

        let admin_balance = coin::balance<PlaceholderCoin>(@oft_admin);
        assert!(admin_balance == 1234, 3);

        oft_coin::set_blocklist(
            admin,
            blocklisted_address,
            false,
        );
        assert!(was_event_emitted(&oft_impl_config::blocklist_set_event(blocklisted_address, false)), 4);
        assert!(is_blocklisted(blocklisted_address) == false, 5);

        oft_coin::credit(
            blocklisted_address,
            1234,
            12345,
            option::none(),
        );

        let to_balance = coin::balance<PlaceholderCoin>(blocklisted_address);
        assert!(to_balance == 1234, 6);

        let admin_balance = coin::balance<PlaceholderCoin>(@oft_admin);
        // unchanged
        assert!(admin_balance == 1234, 7);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_impl_config::EADDRESS_BLOCKED)]
    fun test_set_blocklist_debit() {
        setup();

        let blocklisted_address = @0x1234;
        std::account::create_account_for_test(blocklisted_address);
        std::aptos_account::deposit_coins<PlaceholderCoin>(blocklisted_address, oft_coin::mint_tokens_for_test(10_000));

        assert!(is_blocklisted(blocklisted_address) == false, 0);

        let admin = &create_signer_for_test(@oft_admin);
        oft_coin::set_blocklist(
            admin,
            blocklisted_address,
            true,
        );

        let debit_tokens = mint_tokens_for_test<PlaceholderCoin>(1234);
        oft_coin::debit_coin(
            blocklisted_address,
            &mut debit_tokens,
            0,
            12345,
        );
        burn_token_for_test(debit_tokens);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_impl_config::EBLOCKLIST_DISABLED)]
    fun test_disable_blocklist() {
        setup();

        let admin = &create_signer_for_test(@oft_admin);
        oft_coin::irrevocably_disable_blocklist(admin);
        assert!(was_event_emitted(&oft_impl_config::blocklisting_disabled_event()), 1);

        let blocklisted_address = @0x1234;
        oft_coin::set_blocklist(
            admin,
            blocklisted_address,
            true,
        );
    }

    #[test]
    fun test_rate_limit() {
        setup();

        let (limit, window) = oft_coin::rate_limit_config(30100);
        assert!(limit == 0 && window == 0, 0);

        let admin = &create_signer_for_test(@oft_admin);
        oft_coin::set_rate_limit(admin, 30100, 2500, 100);
        assert!(was_event_emitted(&oft_impl_config::rate_limit_set_event(30100, 2500, 100)), 1);

        let (limit, window) = oft_coin::rate_limit_config(30100);
        assert!(limit == 2500 && window == 100, 1);

        let (oft_limit, fee_detail) = oft_coin::oft_limit_and_fees(
            30100,
            x"1234",
            123,
            100,
            x"1234",
            x"1234",
            x"1234"
        );

        // no fee
        assert!(vector::length(&fee_detail) == 0, 2);

        // rate limit
        let (min_amount_ld, max_amount_ld) = oft_common::oft_limit::unpack_oft_limit(oft_limit);
        assert!(min_amount_ld == 0 && max_amount_ld == 2500, 3);
    }

    #[test]
    fun test_withdraw_coin() {
        let (burn_cap, mint_cap) = std::aptos_coin::initialize_for_test(&create_account_for_test(@std));
        let account = &create_account_for_test(@0x1234);
        aptos_account::deposit_coins(@0x1234, coin::mint(100, &mint_cap));
        let coin = oft_coin::withdraw_coin<AptosCoin>(account, 90);
        assert!(coin::balance<AptosCoin>(@0x1234) == 10, 10);
        assert!(coin::value(&coin) == 90, 20);
        coin::burn(coin, &burn_cap);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_coin::EINSUFFICIENT_BALANCE)]
    fun test_withdraw_coin_fails_if_insufficient() {
        let (burn_cap, mint_cap) = std::aptos_coin::initialize_for_test(&create_account_for_test(@std));
        let account = &create_account_for_test(@0x1234);
        aptos_account::deposit_coins(@0x1234, coin::mint(100, &mint_cap));
        let coin = oft_coin::withdraw_coin<AptosCoin>(account, 110);
        coin::burn(coin, &burn_cap);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_coin::EINSUFFICIENT_BALANCE)]
    fun test_withdraw_coin_fails_with_insufficient_balance_if_not_registered() {
        let (burn_cap, mint_cap) = std::aptos_coin::initialize_for_test(&create_account_for_test(@std));
        let account = &create_account_for_test(@0x1234);
        let coin = oft_coin::withdraw_coin<AptosCoin>(account, 110);
        coin::burn(coin, &burn_cap);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test]
    #[expected_failure(abort_code = 0x5000A, location = std::coin)]
    fun test_freeze_coin_store() {
        setup();
        create_account_for_test(@0x1234);
        let admin = &create_account_for_test(@oft_admin);

        // Set up initial state
        aptos_account::deposit_coins<PlaceholderCoin>(@0x1234, oft_coin::mint_tokens_for_test<PlaceholderCoin>(100));
        assert!(coin::balance<PlaceholderCoin>(@0x1234) == 100, 1);

        // Freeze the account
        assert!(!oft_coin::is_account_frozen(@0x1234), 2);
        oft_coin::set_coin_store_frozen(admin, @0x1234, true);
        assert!(oft_coin::is_account_frozen(@0x1234), 3);

        // Try to deposit coins - should fail
        let coin = oft_coin::mint_tokens_for_test<PlaceholderCoin>(50);
        coin::deposit(@0x1234, coin);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_coin::EFREEZE_ACCOUNT_DISABLED)]
    fun test_freeze_coin_store_should_fail_when_disabled() {
        setup();
        coin::register<PlaceholderCoin>(&create_account_for_test(@0x1234));
        let admin = &create_account_for_test(@oft_admin);
        oft_coin::permanently_disable_coin_store_freezing(admin);
        assert!(was_event_emitted(&oft_coin::coin_store_freezing_permanently_disabled_event()), 1);
        oft_coin::set_coin_store_frozen(admin, @0x1234, true);
    }

    #[test]
    fun test_unfreeze_coin_store_works_even_if_freeze_disabled() {
        setup();
        create_account_for_test(@0x1234);
        let admin = &create_account_for_test(@oft_admin);

        // Set up initial state
        aptos_account::deposit_coins<PlaceholderCoin>(@0x1234, oft_coin::mint_tokens_for_test<PlaceholderCoin>(100));

        // Freeze the account
        oft_coin::set_coin_store_frozen(admin, @0x1234, true);
        assert!(oft_coin::is_account_frozen(@0x1234), 0);
        assert!(was_event_emitted(&oft_coin::coin_store_freeze_status_changed_event(@0x1234, true)), 1);

        // Disable account freezing
        oft_coin::permanently_disable_coin_store_freezing(admin);

        // Unfreeze the account
        oft_coin::set_coin_store_frozen(admin, @0x1234, false);
        assert!(!oft_coin::is_account_frozen(@0x1234), 0);
        assert!(was_event_emitted(&oft_coin::coin_store_freeze_status_changed_event(@0x1234, false)), 1);

        // Try to deposit coins - should succeed
        let coin = oft_coin::mint_tokens_for_test<PlaceholderCoin>(50);
        coin::deposit(@0x1234, coin);
    }
}
