#[test_only]
module uln_302::assert_valid_oapp_uln_config_tests {
    use std::bcs::to_bytes;
    use std::from_bcs::to_address;
    use std::vector;

    use msglib_types::configs_uln::new_uln_config;
    use uln_302::assert_valid_uln_config::assert_valid_uln_config;

    const MAX_DVNS: u64 = 127;

    #[test]
    #[expected_failure(abort_code = uln_302::assert_valid_uln_config::ENO_EFFECTIVE_DVN_THRESHOLD)]
    fun invalid_if_less_than_one_effective_dvn_theshold() {
        let default_config = new_uln_config(2, 1, vector[@0x10], vector[@0x20], false, false, false);
        let oapp_config = new_uln_config(2, 0, vector[], vector[], false, false, false);
        assert_valid_uln_config(&oapp_config, &default_config);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::assert_valid_uln_config::ENO_EFFECTIVE_DVN_THRESHOLD)]
    fun invalid_if_no_effective_dvn_threshold_because_of_use_default_optional_dvns() {
        let default_config = new_uln_config(2, 0, vector[@0x10], vector[@0x20], false, false, false);
        let oapp_config = new_uln_config(2, 0, vector[], vector[], false, false, true);
        assert_valid_uln_config(&oapp_config, &default_config);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::assert_valid_uln_config::ENO_EFFECTIVE_DVN_THRESHOLD)]
    fun invalid_if_no_effective_dvn_threshold_because_of_use_default_required_dvns() {
        let default_config = new_uln_config(2, 1, vector[], vector[@0x20], false, false, false);
        let oapp_config = new_uln_config(2, 0, vector[], vector[], false, true, false);
        assert_valid_uln_config(&oapp_config, &default_config);
    }

    #[test]
    fun valid_if_one_effective_dvn_threshold_because_use_default_optional_dvns() {
        let default_config = new_uln_config(2, 1, vector[@0x10], vector[@0x20], false, false, false);
        let oapp_config = new_uln_config(2, 0, vector[], vector[], false, false, true);
        assert_valid_uln_config(&oapp_config, &default_config);
    }

    #[test]
    fun valid_if_one_effective_dvn_threshold_because_use_default_required_dvns() {
        let default_config = new_uln_config(2, 0, vector[@0x10], vector[@0x20], false, false, false);
        let oapp_config = new_uln_config(2, 0, vector[], vector[], false, true, false);
        assert_valid_uln_config(&oapp_config, &default_config);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::assert_valid_uln_config::ENONEMPTY_REQUIRED_DVNS_WITH_USE_DEFAULT)]
    fun invalid_if_required_dvns_specified_when_using_default() {
        let default_config = new_uln_config(1, 1, vector[@0x20], vector[@0x30], false, false, false);
        let oapp_config = new_uln_config(2, 3, vector[@0x10], vector[@0x20], false, true, false);
        assert_valid_uln_config(&oapp_config, &default_config);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::assert_valid_uln_config::ENONEMPTY_OPTIONAL_DVNS_WITH_USE_DEFAULT)]
    fun invalid_if_optional_dvns_specified_when_using_default() {
        let default_config = new_uln_config(1, 1, vector[@0x20], vector[@0x30], false, false, false);
        let oapp_config = new_uln_config(2, 3, vector[@0x10], vector[@0x20], false, false, true);
        assert_valid_uln_config(&oapp_config, &default_config);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::assert_valid_uln_config::ETOO_MANY_REQUIRED_DVNS)]
    fun invalid_if_more_than_max_required_dvns() {
        let default_config = new_uln_config(1, 1, vector[@0x20], vector[@0x30], false, false, false);
        let required_dvns = vector<address>[];
        for (i in 0..(MAX_DVNS + 1)) {
            vector::push_back(&mut required_dvns, to_address(to_bytes(&(i as u256))));
        };
        let oapp_config = new_uln_config(2, 3, required_dvns, vector[@0x20], false, false, false);
        assert_valid_uln_config(&oapp_config, &default_config);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::assert_valid_uln_config::ETOO_MANY_OPTIONAL_DVNS)]
    fun invalid_if_more_than_max_optional_dvns() {
        let default_config = new_uln_config(1, 1, vector[@0x20], vector[@0x30], false, false, false);
        let optional_dvns = vector<address>[];
        for (i in 0..(MAX_DVNS + 1)) {
            vector::push_back(&mut optional_dvns, to_address(to_bytes(&(i as u256))));
        };
        let oapp_config = new_uln_config(2, 3, vector[@0x10], optional_dvns, false, false, false);
        assert_valid_uln_config(&oapp_config, &default_config);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::assert_no_duplicates::EDUPLICATE_ITEM)]
    fun invalid_if_duplicate_addresses_in_required_dvns() {
        let default_config = new_uln_config(1, 1, vector[@0x20], vector[@0x30], false, false, false);
        let required_dvns = vector<address>[@1, @2, @3, @1, @5];
        let oapp_config = new_uln_config(2, 1, required_dvns, vector[@0x30], false, false, false);
        assert_valid_uln_config(&oapp_config, &default_config);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::assert_no_duplicates::EDUPLICATE_ITEM)]
    fun invalid_if_duplicate_addresses_in_optional_dvns() {
        let default_config = new_uln_config(1, 1, vector[@0x20], vector[@0x30], false, false, false);
        let optional_dvns = vector<address>[@1, @2, @3, @1, @5];
        let oapp_config = new_uln_config(2, 1, vector[@0x20], optional_dvns, false, false, false);
        assert_valid_uln_config(&oapp_config, &default_config);
    }

    #[test]
    #[expected_failure(
        abort_code = uln_302::assert_valid_uln_config::ENONZERO_CONFIRMATIONS_PROVIDED_FOR_DEFAULT_CONFIG
    )]
    fun invalid_if_use_default_for_confirmations_but_provide_confirmations() {
        let default_config = new_uln_config(1, 1, vector[@0x20], vector[@0x30], false, false, false);
        let oapp_config = new_uln_config(2, 1, vector[@0x10], vector[@0x20], true, false, false);
        assert_valid_uln_config(&oapp_config, &default_config);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::assert_valid_uln_config::EINVALID_DVN_THRESHOLD)]
    fun test_assert_valid_default_uln_config_fails_if_no_threshold_with_optional_dvns_defined() {
        let default_config = new_uln_config(1, 1, vector[@0x20], vector[@0x30], false, false, false);
        let config = new_uln_config(1, 0, vector[@0x20], vector[@0x20], false, false, false);
        assert_valid_uln_config(&config, &default_config);
    }
}
