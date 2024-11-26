#[test_only]
module treasury::treasury_tests {
    use std::account::{Self, create_signer_for_test};
    use std::event::was_event_emitted;
    use std::fungible_asset;
    use std::primary_fungible_store;

    use endpoint_v2_common::native_token_test_helpers::{burn_token_for_test, mint_native_token_for_test};
    use endpoint_v2_common::universal_config;
    use endpoint_v2_common::zro_test_helpers::create_fa;
    use treasury::treasury::{
        deposit_address_updated_event, get_native_bp, get_zro_fee, init_module_for_test, native_bp_set_event, pay_fee,
        set_native_bp, set_zro_enabled, set_zro_fee, update_deposit_address, zro_enabled_set_event, zro_fee_set_event,
    };

    #[test]
    fun test_fee_payment_using_native() {
        let lz = &create_signer_for_test(@layerzero_treasury_admin);
        init_module_for_test();
        let (zro_addr, _, _) = create_fa(b"ZRO");
        set_native_bp(lz, 100);

        universal_config::init_module_for_test(100);
        let lz_admin = &create_signer_for_test(@layerzero_admin);
        universal_config::set_zro_address(lz_admin, zro_addr);
        set_zro_enabled(lz, true);

        let new_deposit_address = @0x1234;
        account::create_account_for_test(new_deposit_address);
        update_deposit_address(lz, new_deposit_address);
        assert!(was_event_emitted(&deposit_address_updated_event(new_deposit_address)), 0);

        let payment_native = mint_native_token_for_test(2222);
        pay_fee(2000, &mut payment_native);
        // a 2000 worker fee * 100 BP = 20 native treasury fee
        // remaining amount = 2222 - 20 = 2202
        assert!(fungible_asset::amount(&payment_native) == 2202, 0);

        let metadata = fungible_asset::metadata_from_asset(&payment_native);
        let treasury_balance = primary_fungible_store::balance(new_deposit_address, metadata);
        assert!(treasury_balance == 20, 1);

        // test cleanup
        burn_token_for_test(payment_native);
    }

    #[test]
    #[expected_failure(abort_code = treasury::treasury::EPAY_IN_ZRO_NOT_ENABLED)]
    fun test_fee_payment_using_zro_fails_when_zro_disabled() {
        init_module_for_test();
        let (_, metadata, _) = create_fa(b"ZRO");
        let payment_zro = fungible_asset::zero(metadata);
        pay_fee(1000, &mut payment_zro);
        fungible_asset::destroy_zero(payment_zro);
    }

    #[test]
    fun test_pay_fee_works_in_zro() {
        let lz = &create_signer_for_test(@layerzero_treasury_admin);
        init_module_for_test();
        set_zro_fee(lz, 300);
        let (zro_addr, metadata, mint_ref) = create_fa(b"ZRO");

        universal_config::init_module_for_test(100);
        let lz_admin = &create_signer_for_test(@layerzero_admin);
        universal_config::set_zro_address(lz_admin, zro_addr);
        set_zro_enabled(lz, true);

        let payment_zro = fungible_asset::mint(&mint_ref, 3000);

        pay_fee(3000, &mut payment_zro);
        // 20 spent
        assert!(fungible_asset::amount(&payment_zro) == 2700, 0);
        let treasury_balance = primary_fungible_store::balance(@layerzero_treasury_admin, metadata);
        assert!(treasury_balance == 300, 1);

        // cleanup
        burn_token_for_test(payment_zro)
    }

    #[test]
    #[expected_failure(abort_code = treasury::treasury::EUNAUTHORIZED)]
    fun test_update_deposit_address_fails_for_non_admin() {
        init_module_for_test();
        let new_deposit_address = @0x1234;
        account::create_account_for_test(new_deposit_address);
        let non_admin = &create_signer_for_test(@0x1234);
        update_deposit_address(non_admin, new_deposit_address);
    }

    #[test]
    #[expected_failure(abort_code = treasury::treasury::EINVALID_ACCOUNT_ADDRESS)]
    fun test_update_deposit_address_fails_for_invalid_address() {
        let lz = &create_signer_for_test(@layerzero_treasury_admin);
        init_module_for_test();
        let new_deposit_address = @0x1234;
        account::create_account_for_test(new_deposit_address);
        update_deposit_address(lz, @0x0);
    }

    #[test]
    fun test_set_zro_enabled() {
        let lz = &create_signer_for_test(@layerzero_treasury_admin);
        init_module_for_test();
        let (zro_addr, _, _) = create_fa(b"ZRO");

        universal_config::init_module_for_test(100);
        let lz_admin = &create_signer_for_test(@layerzero_admin);
        universal_config::set_zro_address(lz_admin, zro_addr);

        set_zro_enabled(lz, true);
        assert!(was_event_emitted(&zro_enabled_set_event(true)), 0);

        set_zro_enabled(lz, false);
        assert!(was_event_emitted(&zro_enabled_set_event(true)), 0);
    }

    #[test]
    fun test_set_zro_fee() {
        let lz = &create_signer_for_test(@layerzero_treasury_admin);
        init_module_for_test();
        let (zro_addr, _, _) = create_fa(b"ZRO");

        universal_config::init_module_for_test(100);
        let lz_admin = &create_signer_for_test(@layerzero_admin);
        universal_config::set_zro_address(lz_admin, zro_addr);
        set_zro_enabled(lz, true);

        set_zro_fee(lz, 120);
        assert!(was_event_emitted(&zro_fee_set_event(120)), 0);
        assert!(get_zro_fee() == 120, 1);
    }

    #[test]
    fun test_set_native_bp() {
        let lz = &create_signer_for_test(@layerzero_treasury_admin);
        init_module_for_test();
        set_native_bp(lz, 124);

        let bp = get_native_bp();
        assert!(bp == 124, 0);
        assert!(was_event_emitted(&native_bp_set_event(124)), 1)
    }

    #[test]
    #[expected_failure(abort_code = treasury::treasury::EINVALID_FEE)]
    fun test_set_native_bp_above_10000() {
        let lz = &create_signer_for_test(@layerzero_treasury_admin);
        init_module_for_test();
        set_native_bp(lz, 10001);
    }
}