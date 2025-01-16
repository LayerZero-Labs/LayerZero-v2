#[test_only]
module oft::oft_adapter_coin_tests {
    use std::account::{create_account_for_test, create_signer_for_test};
    use std::aptos_account;
    use std::aptos_coin::AptosCoin;
    use std::coin;
    use std::event::was_event_emitted;
    use std::option;
    use std::timestamp;
    use std::vector;

    use endpoint_v2::test_helpers::setup_layerzero_for_test;
    use endpoint_v2_common::bytes32;
    use endpoint_v2_common::native_token_test_helpers::mint_native_token_for_test;
    use oft::oapp_core;
    use oft::oft::remove_dust;
    use oft::oft_adapter_coin::{
        Self,
        escrow_address,
        fee_bps,
        fee_deposit_address,
        is_blocklisted,
        set_fee_bps,
        set_fee_deposit_address,
    };
    use oft::oft_impl_config;
    use oft::oft_store;
    use oft::placeholder_coin;
    use oft::placeholder_coin::{burn_for_test, mint_for_test, PlaceholderCoin};
    use oft_common::oft_limit::new_unbounded_oft_limit;

    const MAXU64: u64 = 0xffffffffffffffff;
    const LOCAL_EID: u32 = 101;

    fun setup() {
        placeholder_coin::init_module_for_test();

        // Initialize AptosCoin - this is necessary because some of the coin internals
        let (burn_cap, mint_cap) = std::aptos_coin::initialize_for_test(&create_account_for_test(@std));
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        // Initialize
        setup_layerzero_for_test(@simple_msglib, LOCAL_EID, LOCAL_EID);
        oft::oapp_test_helper::init_oapp();

        oft_store::init_module_for_test();
        oft_adapter_coin::init_module_for_test();
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

        let coin = mint_for_test(amount_ld);
        let (sent, received) = oft_adapter_coin::debit_coin(
            @444,
            &mut coin,
            min_amount_ld,
            dst_eid,
        );

        // Amount sent and received should reflect the amount debited
        let dust_removed = remove_dust(amount_ld);
        assert!(sent == dust_removed, 0);
        assert!(received == dust_removed, 0);

        // Only dust remains in debited account
        let dust_left = coin::value(&coin);
        let remaining_balance = coin::value(&coin);
        assert!(remaining_balance == dust_left, 0);
        burn_for_test(coin);

        // sEcrow balance should increase to match
        let balance = coin::balance<PlaceholderCoin>(escrow_address());
        assert!(balance == dust_removed, 0);
    }

    #[test]
    fun test_credit() {
        setup();

        let amount_ld = 123456700;
        let lz_receive_value = option::none();
        let src_eid = 12345;

        // debit first to make sure account has balance
        let deposit = mint_for_test(amount_ld);
        oft_adapter_coin::debit_coin(
            @444,
            &mut deposit,
            0,
            src_eid,
        );
        burn_for_test(deposit);

        let balance = coin::balance<PlaceholderCoin>(escrow_address());
        let dust_removed = remove_dust(amount_ld);
        assert!(balance == dust_removed, 0);

        let to = @555;
        create_account_for_test(to);

        // 0 balance before crediting
        let balance = coin::balance<PlaceholderCoin>(to);
        assert!(balance == 0, 0);

        let credited = oft_adapter_coin::credit(
            to,
            dust_removed,
            src_eid,
            lz_receive_value,
        );
        // amount credited should reflect the amount credited
        assert!(credited == dust_removed, 0);

        // balance should appear in recipient account
        let balance = coin::balance<PlaceholderCoin>(to);
        assert!(balance == dust_removed, 0);

        // escrow balance should be back to 0
        let balance = coin::balance<PlaceholderCoin>(escrow_address());
        assert!(balance == 0, 0);
    }

    #[test]
    #[expected_failure(abort_code = 0x10006, location = std::coin)]
    fun test_credit_fails_if_insufficient_balance() {
        setup();

        let amount_ld = 123456700;
        let lz_receive_value = option::none();
        let src_eid = 12345;

        let to = @555;
        create_account_for_test(to);

        // 0 balance before crediting
        let balance = coin::balance<PlaceholderCoin>(to);
        assert!(balance == 0, 0);

        // register to Coin store
        coin::register<PlaceholderCoin>(&create_signer_for_test(to));

        let credited = oft_adapter_coin::credit(
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

        let amount_ld = 123456700;
        let lz_receive_value = option::some(mint_native_token_for_test(100));
        let src_eid = 12345;

        let to = @555;
        create_account_for_test(to);

        // 0 balance before crediting
        let balance = coin::balance<PlaceholderCoin>(to);
        assert!(balance == 0, 0);

        let initial_deposit = mint_for_test(amount_ld);
        let dust_removed = remove_dust(amount_ld);
        oft_adapter_coin::debit_coin(@444, &mut initial_deposit, dust_removed, src_eid);
        burn_for_test(initial_deposit);

        oft_adapter_coin::credit(
            to,
            dust_removed,
            src_eid,
            lz_receive_value,
        );


        assert!(coin::balance<std::aptos_coin::AptosCoin>(@oft_admin) == 100, 1);
    }

    #[test]
    fun test_debit_view() {
        setup();

        // shouldn't take a fee
        let (sent, received) = oft_adapter_coin::debit_view(123456700, 100, 2);
        let dust_removed = remove_dust(123456700);
        assert!(sent == dust_removed, 0);
        assert!(received == dust_removed, 0);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_core::ESLIPPAGE_EXCEEDED)]
    fun test_debit_view_fails_if_less_than_min() {
        setup();

        oft_adapter_coin::debit_view(32, 100, 2);
    }

    #[test]
    fun test_build_options() {
        setup();

        let dst_eid = 103;
        let message_type = 2;

        let options = oft_adapter_coin::build_options(
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

        let options = oft_adapter_coin::build_options(
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
        setup();
        // doesn't do anything, just tests that it doesn't fail
        oft_adapter_coin::inspect_message(
            &x"1234",
            &x"1234",
            true,
        );
    }

    #[test]
    fun test_oft_limit_and_fees() {
        setup();

        timestamp::set_time_has_started_for_testing(&create_signer_for_test(@std));
        let (limit, fees) = oft_adapter_coin::oft_limit_and_fees(
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

        let (oft_limit, oft_fee_details) = oft_adapter_coin::oft_limit_and_fees(
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

        let coin_value = mint_for_test(amount_ld);
        let (sent, received) = oft_adapter_coin::debit_coin<PlaceholderCoin>(
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
        let remaining_balance = coin::value(&coin_value);
        assert!(remaining_balance == 00, 0);
        burn_for_test(coin_value);

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
        oft_adapter_coin::set_blocklist(
            admin,
            blocklisted_address,
            true,
        );
        assert!(was_event_emitted(&oft_impl_config::blocklist_set_event(blocklisted_address, true)), 1);
        assert!(is_blocklisted(blocklisted_address), 1);

        let to_escrow = mint_for_test(10_000_000);
        oft_adapter_coin::debit_coin(
            @123456,
            &mut to_escrow,
            0,
            12345,
        );
        burn_for_test(to_escrow);

        oft_adapter_coin::credit(
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

        oft_adapter_coin::set_blocklist(
            admin,
            blocklisted_address,
            false,
        );
        assert!(was_event_emitted(&oft_impl_config::blocklist_set_event(blocklisted_address, false)), 4);
        assert!(is_blocklisted(blocklisted_address) == false, 5);

        oft_adapter_coin::credit(
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
        std::aptos_account::deposit_coins<PlaceholderCoin>(blocklisted_address, mint_for_test(10_000));

        assert!(is_blocklisted(blocklisted_address) == false, 0);

        let admin = &create_signer_for_test(@oft_admin);
        oft_adapter_coin::set_blocklist(
            admin,
            blocklisted_address,
            true,
        );

        let debit_tokens = mint_for_test(1234);
        oft_adapter_coin::debit_coin(
            blocklisted_address,
            &mut debit_tokens,
            0,
            12345,
        );
        burn_for_test(debit_tokens);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_impl_config::EBLOCKLIST_DISABLED)]
    fun test_disable_blocklist() {
        setup();

        let admin = &create_signer_for_test(@oft_admin);
        oft_adapter_coin::irrevocably_disable_blocklist(admin);
        assert!(was_event_emitted(&oft_impl_config::blocklisting_disabled_event()), 1);

        let blocklisted_address = @0x1234;
        oft_adapter_coin::set_blocklist(
            admin,
            blocklisted_address,
            true,
        );
    }

    #[test]
    fun test_rate_limit() {
        setup();

        let (limit, window) = oft_adapter_coin::rate_limit_config(30100);
        assert!(limit == 0 && window == 0, 0);

        let admin = &create_signer_for_test(@oft_admin);
        oft_adapter_coin::set_rate_limit(admin, 30100, 2500, 100);
        assert!(was_event_emitted(&oft_impl_config::rate_limit_set_event(30100, 2500, 100)), 1);

        let (limit, window) = oft_adapter_coin::rate_limit_config(30100);
        assert!(limit == 2500 && window == 100, 1);

        let (oft_limit, fee_detail) = oft_adapter_coin::oft_limit_and_fees(
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
        setup();

        let account = &create_account_for_test(@0x1234);
        aptos_account::deposit_coins<PlaceholderCoin>(@0x1234, mint_for_test(100));
        let coin = oft_adapter_coin::withdraw_coin<PlaceholderCoin>(account, 90);
        assert!(coin::balance<PlaceholderCoin>(@0x1234) == 10, 10);
        assert!(coin::value(&coin) == 90, 20);

        aptos_account::deposit_coins<PlaceholderCoin>(@0x1234, coin);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_adapter_coin::EINSUFFICIENT_BALANCE)]
    fun test_withdraw_coin_fails_if_insufficient() {
        setup();

        let account = &create_account_for_test(@0x1234);
        aptos_account::deposit_coins<PlaceholderCoin>(@0x1234, mint_for_test(100));
        let coin = oft_adapter_coin::withdraw_coin<AptosCoin>(account, 110);

        aptos_account::deposit_coins<AptosCoin>(@0x1234, coin);
    }
}
