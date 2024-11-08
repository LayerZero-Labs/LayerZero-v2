module uln_302::assert_valid_uln_config {
    use endpoint_v2_common::assert_no_duplicates;
    use msglib_types::configs_uln::{Self, UlnConfig};

    friend uln_302::configuration;

    #[test_only]
    friend uln_302::assert_valid_oapp_uln_config_tests;

    const MAX_DVNS: u64 = 127;

    public(friend) fun assert_valid_uln_config(oapp_config: &UlnConfig, default_config: &UlnConfig) {
        let use_default_for_required_dvns = configs_uln::get_use_default_for_required_dvns(oapp_config);
        let use_default_for_optional_dvns = configs_uln::get_use_default_for_optional_dvns(oapp_config);
        let use_default_for_confirmations = configs_uln::get_use_default_for_confirmations(oapp_config);
        let required_dvn_count = configs_uln::get_required_dvn_count(oapp_config);
        let optional_dvn_count = configs_uln::get_optional_dvn_count(oapp_config);
        let optional_dvn_threshold = configs_uln::get_optional_dvn_threshold(oapp_config);
        if (use_default_for_required_dvns) {
            assert!(required_dvn_count == 0, ENONEMPTY_REQUIRED_DVNS_WITH_USE_DEFAULT);
        };
        if (use_default_for_optional_dvns) {
            assert!(optional_dvn_count == 0, ENONEMPTY_OPTIONAL_DVNS_WITH_USE_DEFAULT);
        };
        if (use_default_for_confirmations) {
            assert!(configs_uln::get_confirmations(oapp_config) == 0,
                ENONZERO_CONFIRMATIONS_PROVIDED_FOR_DEFAULT_CONFIG,
            );
        };

        assert!(required_dvn_count <= MAX_DVNS, ETOO_MANY_REQUIRED_DVNS);
        assert!(optional_dvn_count <= MAX_DVNS, ETOO_MANY_OPTIONAL_DVNS);
        assert_no_duplicates::assert_no_duplicates(&configs_uln::get_required_dvns(oapp_config));
        assert_no_duplicates::assert_no_duplicates(&configs_uln::get_optional_dvns(oapp_config));

        // Optional threshold should not be greater than count of optional dvns
        assert!((optional_dvn_threshold as u64) <= optional_dvn_count, EOPTIONAL_DVN_THRESHOLD_EXCEEDS_COUNT);

        // make sure there is an effective DVN threshold (required + optional threshold) >= 1
        let effective_optional_threshold = if (!use_default_for_optional_dvns) optional_dvn_threshold else {
            configs_uln::get_optional_dvn_threshold(default_config)
        };
        let effective_required_count = if (!use_default_for_required_dvns) required_dvn_count else {
            configs_uln::get_required_dvn_count(default_config)
        };
        assert!(effective_optional_threshold > 0 || effective_required_count > 0, ENO_EFFECTIVE_DVN_THRESHOLD);
    }

    // ================================================== Error Codes =================================================

    const ENONEMPTY_OPTIONAL_DVNS_WITH_USE_DEFAULT: u64 = 1;
    const ENONEMPTY_REQUIRED_DVNS_WITH_USE_DEFAULT: u64 = 2;
    const ENONZERO_CONFIRMATIONS_PROVIDED_FOR_DEFAULT_CONFIG: u64 = 3;
    const ENO_EFFECTIVE_DVN_THRESHOLD: u64 = 4;
    const EOPTIONAL_DVN_THRESHOLD_EXCEEDS_COUNT: u64 = 5;
    const ETOO_MANY_OPTIONAL_DVNS: u64 = 6;
    const ETOO_MANY_REQUIRED_DVNS: u64 = 7;
}