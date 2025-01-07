#[test_only]
module uln_302::assert_valid_default_uln_config_tests {
    use std::bcs::to_bytes;
    use std::from_bcs::to_address;
    use std::vector;

    use msglib_types::configs_uln::new_uln_config;
    use uln_302::assert_valid_default_uln_config::assert_valid_default_uln_config;

    const MAX_DVNS: u64 = 127;

    #[test]
    fun test_assert_valid_default_uln_config_valid_if_zero_required_dvs_if_optional_threshold_exists() {
        let config = new_uln_config(1, 1, vector[], vector[@0x20], false, false, false);
        assert_valid_default_uln_config(&config);
    }

    #[test]
    fun test_assert_valid_default_uln_config_allows_zero_confirmations() {
        let config = new_uln_config(0, 1, vector[@0x20], vector[@0x20], false, false, false);
        assert_valid_default_uln_config(&config);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::assert_valid_default_uln_config::ENO_EFFECTIVE_DVN_THRESHOLD)]
    fun test_assert_valid_default_uln_config_fails_in_no_required_dvns_and_no_effective_dvn_threshold() {
        let config = new_uln_config(1, 0, vector[], vector[@0x10, @0x20], false, false, false);
        assert_valid_default_uln_config(&config);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::assert_valid_default_uln_config::EOPTIONAL_DVN_THRESHOLD_EXCEEDS_COUNT)]
    fun test_assert_valid_default_uln_config_fails_if_optional_dvn_threshold_exceeds_optional_dvn_count() {
        let config = new_uln_config(1, 3, vector[@0x20], vector[@0x10, @0x20], false, false, false);
        assert_valid_default_uln_config(&config);
    }


    #[test]
    #[expected_failure(
        abort_code = uln_302::assert_valid_default_uln_config::EREQUESTING_USE_DEFAULT_REQUIRED_DVNS_FOR_DEFAULT_CONFIG
    )]
    fun test_assert_valid_default_uln_config_fails_if_enabled_default_for_required_dvns() {
        let config = new_uln_config(1, 1, vector[@0x20], vector[@0x20], false, true, false);
        assert_valid_default_uln_config(&config);
    }

    #[test]
    #[expected_failure(
        abort_code = uln_302::assert_valid_default_uln_config::EREQUESTING_USE_DEFAULT_OPTIONAL_DVNS_FOR_DEFAULT_CONFIG
    )]
    fun test_assert_valid_default_uln_config_fails_if_enabled_use_default_for_optional_dvns() {
        let config = new_uln_config(1, 1, vector[@0x20], vector[@0x20], false, false, true);
        assert_valid_default_uln_config(&config);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::assert_valid_default_uln_config::ETOO_MANY_REQUIRED_DVNS)]
    fun test_assert_valid_default_uln_config_fails_if_required_dvns_exceeds_max() {
        let required_dvns = vector<address>[];
        for (i in 0..(MAX_DVNS + 1)) {
            vector::push_back(&mut required_dvns, to_address(to_bytes(&(i as u256))));
        };
        let config = new_uln_config(1, 1, required_dvns, vector[@0x20], false, false, false);
        assert_valid_default_uln_config(&config);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::assert_valid_default_uln_config::ETOO_MANY_OPTIONAL_DVNS)]
    fun test_assert_valid_default_uln_config_fails_if_optional_dvns_exceeds_max() {
        let optional_dvns = vector<address>[];
        for (i in 0..(MAX_DVNS + 1)) {
            vector::push_back(&mut optional_dvns, to_address(to_bytes(&(i as u256))));
        };
        let config = new_uln_config(1, 1, vector[@0x10], optional_dvns, false, false, false);
        assert_valid_default_uln_config(&config);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::assert_no_duplicates::EDUPLICATE_ITEM)]
    fun test_assert_valid_default_uln_config_fails_if_duplicate_required_dvn() {
        let required_dvns = vector<address>[@1, @2, @3, @1, @5];
        let config = new_uln_config(2, 1, required_dvns, vector[@0x30], false, false, false);
        assert_valid_default_uln_config(&config);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::assert_no_duplicates::EDUPLICATE_ITEM)]
    fun test_assert_valid_default_uln_config_fails_if_duplicate_optional_dvn() {
        let optional_dvns = vector<address>[@1, @2, @3, @1, @5];
        let config = new_uln_config(2, 1, vector[@0x20], optional_dvns, false, false, false);
        assert_valid_default_uln_config(&config);
    }

    #[test]
    #[expected_failure(
        abort_code = uln_302::assert_valid_default_uln_config::EREQUESTING_USE_DEFAULT_CONFIRMATIONS_FOR_DEFAULT_CONFIG
    )]
    fun test_assert_valid_default_uln_config_fails_if_enabled_use_default_for_confirmations() {
        let config = new_uln_config(1, 1, vector[@0x20], vector[@0x20], true, false, false);
        assert_valid_default_uln_config(&config);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::assert_valid_default_uln_config::EINVALID_DVN_THRESHOLD)]
    fun test_assert_valid_default_uln_config_fails_if_no_threshold_with_optional_dvns_defined() {
        let config = new_uln_config(1, 0, vector[@0x20], vector[@0x20], false, false, false);
        assert_valid_default_uln_config(&config);
    }
}
