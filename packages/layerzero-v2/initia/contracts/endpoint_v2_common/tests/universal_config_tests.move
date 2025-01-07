#[test_only]
module endpoint_v2_common::universal_config_tests {
    use std::account::create_signer_for_test;
    use std::fungible_asset;

    use endpoint_v2_common::native_token_test_helpers::burn_token_for_test;
    use endpoint_v2_common::universal_config::{
        assert_zro_metadata_set, eid, get_zro_address, get_zro_metadata, has_zro_metadata, init_module_for_test,
        initialize, is_zro, is_zro_metadata, lock_zro_address, set_zro_address,
    };
    use endpoint_v2_common::zro_test_helpers::create_fa;

    #[test]
    fun test_eid() {
        let ep_common = &create_signer_for_test(@layerzero_admin);
        init_module_for_test(0);  // Initializing to 0 = not initialized state
        initialize(ep_common, 55);
        assert!(eid() == 55, 1);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::universal_config::EUNAUTHORIZED)]
    fun test_eid_should_fail_if_not_layerzero_admin() {
        let lz_admin = &create_signer_for_test(@endpoint_v2_common);
        init_module_for_test(0);  // Initializing to 0 = not initialized state
        initialize(lz_admin, 55);
    }

    #[test]
    fun test_set_zro_address() {
        let (other_addr, other_metadata, _) = create_fa(b"OTHER");
        let (zro_addr, zro_metadata, _) = create_fa(b"ZRO");
        init_module_for_test(55);
        let lz_admin = &create_signer_for_test(@layerzero_admin);
        assert!(!has_zro_metadata(), 0);

        set_zro_address(lz_admin, other_addr);
        assert!(get_zro_address() == other_addr, 0);
        assert!(has_zro_metadata(), 0);
        assert!(get_zro_metadata() == other_metadata, 1);
        assert!(has_zro_metadata(), 0);
        // can change setting if not locked
        set_zro_address(lz_admin, zro_addr);
        assert!(has_zro_metadata(), 0);
        // can unset if not locked
        set_zro_address(lz_admin, @0x0);
        assert!(!has_zro_metadata(), 0);

        set_zro_address(lz_admin, zro_addr);
        assert!(get_zro_address() == zro_addr, 0);
        assert!(get_zro_metadata() == zro_metadata, 0);
        assert_zro_metadata_set();
        assert!(has_zro_metadata(), 0);

        let fa = fungible_asset::zero(zro_metadata);
        let fa_other = fungible_asset::zero(other_metadata);

        assert!(is_zro_metadata(zro_metadata), 0);
        assert!(!is_zro_metadata(other_metadata), 0);

        assert!(is_zro(&fa), 0);
        assert!(!is_zro(&fa_other), 0);

        lock_zro_address(lz_admin);

        burn_token_for_test(fa);
        burn_token_for_test(fa_other);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::universal_config::EUNAUTHORIZED)]
    fun test_set_zro_address_should_fail_if_not_admin() {
        init_module_for_test(55);
        let lz = &create_signer_for_test(@layerzero_treasury_admin);

        let (zro_addr, _, _) = create_fa(b"ZRO");
        set_zro_address(lz, zro_addr);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::universal_config::EZRO_ADDRESS_LOCKED)]
    fun test_set_zro_address_fails_if_locked_when_setting() {
        let (zro_addr, _, _) = create_fa(b"ZRO");
        init_module_for_test(55);

        let lz_admin = &create_signer_for_test(@layerzero_admin);
        set_zro_address(lz_admin, zro_addr);
        lock_zro_address(lz_admin);
        set_zro_address(lz_admin, zro_addr);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::universal_config::ENO_CHANGE)]
    fun test_lock_zro_address_fails_if_no_change() {
        let (zro_addr, _, _) = create_fa(b"ZRO");
        init_module_for_test(55);

        let lz_admin = &create_signer_for_test(@layerzero_admin);
        set_zro_address(lz_admin, zro_addr);
        lock_zro_address(lz_admin);
        lock_zro_address(lz_admin);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::universal_config::EZRO_ADDRESS_LOCKED)]
    fun test_set_zro_address_fails_if_locked_when_unsetting() {
        let (zro_addr, _, _) = create_fa(b"ZRO");
        init_module_for_test(55);

        let lz_admin = &create_signer_for_test(@layerzero_admin);
        set_zro_address(lz_admin, zro_addr);
        lock_zro_address(lz_admin);
        set_zro_address(lz_admin, @0x0);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::universal_config::ENO_CHANGE)]
    fun test_set_zro_address_fails_if_no_change() {
        let (zro_addr, _, _) = create_fa(b"ZRO");
        init_module_for_test(55);

        let lz_admin = &create_signer_for_test(@layerzero_admin);
        set_zro_address(lz_admin, zro_addr);
        set_zro_address(lz_admin, zro_addr);
    }


    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::universal_config::ENO_CHANGE)]
    fun test_set_zro_address_fails_if_no_change_unsetting() {
        init_module_for_test(55);

        let lz_admin = &create_signer_for_test(@layerzero_admin);
        set_zro_address(lz_admin, @0x0);
    }
}
