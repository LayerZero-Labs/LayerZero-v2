#[test_only]
module uln_302::configuration_tests {
    use std::event::was_event_emitted;
    use std::option;

    use endpoint_v2_common::serde::bytes_of;
    use msglib_types::configs_executor;
    use msglib_types::configs_executor::new_executor_config;
    use msglib_types::configs_uln;
    use msglib_types::configs_uln::new_uln_config;
    use uln_302::configuration;
    use uln_302::configuration::{
        assert_valid_default_executor_config, default_executor_config_set_event, default_uln_config_set_event,
        executor_config_set_event, get_executor_config, get_receive_uln_config, get_send_uln_config,
        merge_executor_configs, merge_uln_configs, set_default_executor_config, set_default_receive_uln_config,
        set_default_send_uln_config, set_executor_config, set_receive_uln_config, set_send_uln_config,
        supports_receive_eid, supports_send_eid,
    };
    use uln_302::uln_302_store;

    const ULN_SEND_SIDE: u8 = 0;
    const ULN_RECEIVE_SIDE: u8 = 1;

    fun setup() {
        uln_302_store::init_module_for_test();
    }

    public fun enable_receive_eid_for_test(eid: u32) {
        let config = configs_uln::new_uln_config(1, 0, vector[@dvn], vector[], false, false, false);
        set_default_receive_uln_config(eid, config);
    }

    public fun enable_send_eid_for_test(eid: u32) {
        let config = configs_uln::new_uln_config(1, 0, vector[@dvn], vector[], false, false, false);
        set_default_send_uln_config(eid, config);
    }

    #[test]
    fun test_set_default_receive_uln_config() {
        setup();

        // default config not set
        assert!(!supports_receive_eid(1), 0);
        let retrieved_config = uln_302_store::get_default_receive_uln_config(1);
        assert!(option::is_none(&retrieved_config), 0);

        // set config
        let config = new_uln_config(1, 1, vector[@0x20], vector[@0x30], false, false, false);
        set_default_receive_uln_config(1, config);
        assert!(was_event_emitted(&default_uln_config_set_event(1, config, ULN_RECEIVE_SIDE)), 0);
        assert!(supports_receive_eid(1), 1);

        let retrieved_config = uln_302_store::get_default_receive_uln_config(1);
        assert!(option::borrow(&retrieved_config) == &config, 2);
    }

    #[test]
    fun test_set_default_send_uln_config() {
        setup();

        // default config not set
        let retrieved_config = uln_302_store::get_default_send_uln_config(1);
        assert!(option::is_none(&retrieved_config), 0);
        assert!(!supports_send_eid(1), 0);

        // set config
        let config = new_uln_config(1, 1, vector[@0x20], vector[@0x30], false, false, false);
        set_default_send_uln_config(1, config);
        assert!(was_event_emitted(&default_uln_config_set_event(1, config, ULN_SEND_SIDE)), 0);
        assert!(supports_send_eid(1), 1);

        let retrieved_config = uln_302_store::get_default_send_uln_config(1);
        assert!(option::borrow(&retrieved_config) == &config, 2);
    }


    #[test]
    #[expected_failure(
        abort_code = uln_302::assert_valid_default_uln_config::EREQUESTING_USE_DEFAULT_REQUIRED_DVNS_FOR_DEFAULT_CONFIG
    )]
    fun test_set_default_receive_uln_config_fails_if_invalid() {
        setup();
        // cannot "use default" for default config
        let config = new_uln_config(1, 1, vector[@0x20], vector[@0x30], false, true, false);
        set_default_receive_uln_config(1, config);
    }

    #[test]
    #[expected_failure(
        abort_code = uln_302::assert_valid_default_uln_config::EREQUESTING_USE_DEFAULT_REQUIRED_DVNS_FOR_DEFAULT_CONFIG
    )]
    fun test_set_default_send_uln_config_fails_if_invalid() {
        setup();
        // cannot "use default" for default config
        let config = new_uln_config(1, 1, vector[@0x20], vector[@0x30], false, true, false);
        set_default_send_uln_config(1, config);
    }

    #[test]
    fun test_set_send_uln_config() {
        setup();
        let default_config = new_uln_config(1, 1, vector[@0x10], vector[@0x30, @0x50], false, false, false);
        set_default_send_uln_config(1, default_config);

        // before setting oapp config, it should pull default
        let retreived_config = get_send_uln_config(@9999, 1);
        assert!(retreived_config == default_config, 0);

        // setting a different sender has no effect
        let config = new_uln_config(2, 0, vector[@0x20], vector[], false, false, true);
        set_send_uln_config(@1111, 1, config);
        assert!(was_event_emitted(&uln_302::configuration::uln_config_set_event(@1111, 1, config, ULN_SEND_SIDE)), 0);
        let retreived_config = get_send_uln_config(@9999, 1);
        assert!(retreived_config == default_config, 0);

        // set same sender
        set_send_uln_config(@9999, 1, config);

        // should return merged config - using configured required and default optional
        let retrieved_config = get_send_uln_config(@9999, 1);
        let expected_merged_config = new_uln_config(2, 1, vector[@0x20], vector[@0x30, @0x50], false, false, true);
        assert!(retrieved_config == expected_merged_config, 1);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::configuration::EEID_NOT_CONFIGURED)]
    fun test_set_send_uln_config_fails_if_default_not_set() {
        setup();
        let config = new_uln_config(2, 0, vector[@0x20], vector[], false, false, true);
        set_send_uln_config(@9, 1, config);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::assert_valid_uln_config::ENO_EFFECTIVE_DVN_THRESHOLD)]
    fun test_set_send_uln_config_fails_if_default_and_config_merge_to_invalid_config() {
        setup();
        let default_config = new_uln_config(1, 1, vector[], vector[@0x30], false, false, false);
        set_default_send_uln_config(1, default_config);

        // combined, this has no dvns
        let config = new_uln_config(10, 0, vector[], vector[], false, true, false);
        set_send_uln_config(@9, 1, config);
    }

    #[test]
    fun test_set_receive_uln_config() {
        setup();
        let default_config = new_uln_config(1, 1, vector[@0x10], vector[@0x30, @0x50], false, false, false);
        set_default_receive_uln_config(1, default_config);

        // before setting oapp config, it should pull default
        let retreived_config = get_receive_uln_config(@9999, 1);
        assert!(retreived_config == default_config, 0);

        let config = new_uln_config(2, 0, vector[@0x20], vector[], false, false, true);

        // setting a different receiver has no effect
        set_receive_uln_config(@1234, 1, config);
        let retreived_config = get_receive_uln_config(@9999, 1);
        assert!(
            was_event_emitted(&uln_302::configuration::uln_config_set_event(@1234, 1, config, ULN_RECEIVE_SIDE)),
            0,
        );
        assert!(retreived_config == default_config, 0);

        // set the intended receiver
        set_receive_uln_config(@9999, 1, config);
        assert!(
            was_event_emitted(&uln_302::configuration::uln_config_set_event(@9999, 1, config, ULN_RECEIVE_SIDE)),
            0,
        );

        // should return merged config - using configured required and default optional
        let retrieved_config = get_receive_uln_config(@9999, 1);
        let expected_merged_config = new_uln_config(2, 1, vector[@0x20], vector[@0x30, @0x50], false, false, true);
        assert!(retrieved_config == expected_merged_config, 1);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::configuration::EEID_NOT_CONFIGURED)]
    fun test_set_receive_uln_config_fails_if_default_not_set() {
        setup();
        let config = new_uln_config(2, 0, vector[@0x20], vector[], false, false, true);
        set_receive_uln_config(@9, 1, config);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::assert_valid_uln_config::ENO_EFFECTIVE_DVN_THRESHOLD)]
    fun test_set_receive_uln_config_fails_if_default_and_config_merge_to_invalid_config() {
        setup();
        let default_config = new_uln_config(1, 1, vector[], vector[@0x30], false, false, false);
        set_default_receive_uln_config(1, default_config);

        // combined, this has no dvns
        let config = new_uln_config(10, 0, vector[], vector[], false, true, false);
        set_receive_uln_config(@9, 1, config);
    }

    #[test]
    fun test_get_send_uln_config_gets_default_if_oapp_not_set() {
        setup();
        let default_config = new_uln_config(1, 1, vector[@0x10], vector[@0x30, @0x50], false, false, false);
        set_default_send_uln_config(1, default_config);

        let retrieved_config = get_send_uln_config(@9999, 1);
        assert!(retrieved_config == default_config, 0);
    }

    #[test]
    fun test_get_receive_uln_config_gets_default_if_oapp_not_set() {
        setup();
        let default_config = new_uln_config(1, 1, vector[@0x10], vector[@0x30, @0x50], false, false, false);
        set_default_receive_uln_config(1, default_config);

        let retrieved_config = get_receive_uln_config(@9999, 1);
        assert!(retrieved_config == default_config, 0);
    }

    #[test]
    fun test_get_send_uln_config_gets_merged_if_oapp_is_set() {
        setup();
        let default_config = new_uln_config(1, 1, vector[@0x10], vector[@0x30, @0x50], false, false, false);
        set_default_send_uln_config(1, default_config);

        let oapp_config = new_uln_config(2, 0, vector[@0x20], vector[], false, false, true);
        set_send_uln_config(@9999, 1, oapp_config);

        let retrieved_config = get_send_uln_config(@9999, 1);
        let expected_config = new_uln_config(2, 1, vector[@0x20], vector[@0x30, @0x50], false, false, true);
        assert!(retrieved_config == expected_config, 0);
    }

    #[test]
    fun test_get_receive_uln_config_gets_merged_if_oapp_is_set() {
        setup();
        let default_config = new_uln_config(1, 1, vector[@0x10], vector[@0x30, @0x50], false, false, false);
        set_default_receive_uln_config(1, default_config);

        let oapp_config = new_uln_config(2, 0, vector[@0x20], vector[], false, false, true);
        set_receive_uln_config(@9999, 1, oapp_config);

        let retrieved_config = get_receive_uln_config(@9999, 1);
        let expected_config = new_uln_config(2, 1, vector[@0x20], vector[@0x30, @0x50], false, false, true);
        assert!(retrieved_config == expected_config, 0);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::configuration::EEID_NOT_CONFIGURED)]
    fun test_get_send_uln_config_fails_if_eid_not_configured() {
        setup();
        get_send_uln_config(@9999, 1);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::configuration::EEID_NOT_CONFIGURED)]
    fun test_get_receive_uln_config_fails_if_eid_not_configured() {
        setup();
        get_receive_uln_config(@9999, 1);
    }

    #[test]
    fun test_set_default_executor_config() {
        setup();

        // default config not set
        let retrieved_config = uln_302_store::get_default_executor_config(1);
        assert!(option::is_none(&retrieved_config), 0);

        // set config
        let config = new_executor_config(1000, @9001);
        set_default_executor_config(1, config);
        assert!(was_event_emitted(&default_executor_config_set_event(1, config)), 0);

        let retrieved_config = uln_302_store::get_default_executor_config(1);
        assert!(option::borrow(&retrieved_config) == &config, 0);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::configuration::EEXECUTOR_ADDRESS_IS_ZERO)]
    fun test_set_default_executor_config_fails_if_invalid_executor_address() {
        setup();
        let config = new_executor_config(1000, @0x0);
        set_default_executor_config(1, config);
    }

    #[test]
    fun test_set_executor_config() {
        setup();
        let default_config = new_executor_config(1000, @9001);
        set_default_executor_config(1, default_config);
        assert!(was_event_emitted(&default_executor_config_set_event(1, default_config)), 0);

        // before setting oapp config, it should pull default
        let retreived_config = get_executor_config(@9999, 1);
        assert!(retreived_config == default_config, 0);

        let config = new_executor_config(2000, @9002);

        // setting another receiver has no effect
        set_executor_config(@123, 1, config);
        let retreived_config = get_executor_config(@9999, 1);
        assert!(retreived_config == default_config, 0);

        // setting the correct receiver
        set_executor_config(@9999, 1, config);
        assert!(was_event_emitted(&executor_config_set_event(@9999, 1, config)), 0);

        // should return merged config - using configured required and default optional
        let retrieved_config = get_executor_config(@9999, 1);
        assert!(retrieved_config == config, 1);
    }

    #[test]
    fun test_get_executor_config_gets_default_if_oapp_not_set() {
        setup();
        let default_config = new_executor_config(1000, @9001);
        set_default_executor_config(1, default_config);

        let retrieved_config = get_executor_config(@9999, 1);
        assert!(retrieved_config == default_config, 0);
    }

    #[test]
    fun test_get_executor_config_gets_oapp_if_set() {
        setup();
        let default_config = new_executor_config(1000, @9001);
        set_default_executor_config(1, default_config);

        let oapp_config = new_executor_config(2000, @9002);
        set_executor_config(@9999, 1, oapp_config);

        let retrieved_config = get_executor_config(@9999, 1);
        assert!(retrieved_config == oapp_config, 0);
    }

    #[test]
    fun test_get_executor_config_gets_merged_if_oapp_max_message_size_set_to_zero() {
        setup();
        let default_config = new_executor_config(1000, @9001);
        set_default_executor_config(1, default_config);

        let oapp_config = new_executor_config(0, @9002);
        set_executor_config(@9999, 1, oapp_config);

        let retrieved_config = get_executor_config(@9999, 1);
        let expected_config = new_executor_config(1000, @9002);
        assert!(retrieved_config == expected_config, 0);
    }

    #[test]
    fun test_assert_valid_default_executor_config() {
        let config = new_executor_config(1000, @9001);
        assert_valid_default_executor_config(&config);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::configuration::EMAX_MESSAGE_SIZE_ZERO)]
    fun test_assert_valid_default_executor_config_fails_if_invalid_message_size() {
        let config = new_executor_config(0, @9001);
        assert_valid_default_executor_config(&config);
    }

    #[test]
    #[expected_failure(abort_code = uln_302::configuration::EEXECUTOR_ADDRESS_IS_ZERO)]
    fun test_assert_valid_default_executor_config_fails_if_invalid_executor_address() {
        let config = new_executor_config(1000, @0x0);
        assert_valid_default_executor_config(&config);
    }

    #[test]
    fun test_merge_executor_configs_uses_oapp_is_complete() {
        let default_config = new_executor_config(1000, @9001);
        let oapp_config = new_executor_config(2000, @9002);
        let merged_config = merge_executor_configs(&default_config, &oapp_config);
        assert!(merged_config == oapp_config, 0);
    }

    #[test]
    fun test_merge_executor_configs_uses_default_if_oapp_max_message_size_is_zero() {
        let default_config = new_executor_config(1000, @9001);
        let oapp_config = new_executor_config(0, @9002);
        let merged_config = merge_executor_configs(&default_config, &oapp_config);
        let expected_config = new_executor_config(1000, @9002);
        assert!(merged_config == expected_config, 0);
    }

    #[test]
    fun test_merge_executor_configs_uses_default_if_oapp_executor_address_is_zero() {
        let default_config = new_executor_config(1000, @9001);
        let oapp_config = new_executor_config(2000, @0x0);
        let merged_config = merge_executor_configs(&default_config, &oapp_config);
        let expected_config = new_executor_config(2000, @9001);
        assert!(merged_config == expected_config, 0);
    }

    #[test]
    fun test_merge_configs_should_squash_the_default_required_dvns_when_use_default_for_required_dvns_is_set_to_true() {
        let default_config = new_uln_config(2, 1, vector[@0x10], vector[@0x20], false, false, false);
        let oapp_config = new_uln_config(0, 1, vector[], vector[@0x40], false, true, false);
        let merged_config = merge_uln_configs(&default_config, &oapp_config);
        let expected_config = new_uln_config(0, 1, vector[@0x10], vector[@0x40], false, true, false);
        assert!(merged_config == expected_config, 0);
    }

    #[test]
    fun test_merge_configs_should_use_the_default_optional_dvns_and_threshold_when_use_default_for_optional_dvns_is_set_to_true(
    ) {
        let default_config = new_uln_config(2, 1, vector[@0x10], vector[@0x20], false, false, false);
        let oapp_config = new_uln_config(3, 0, vector[@0x40], vector[], false, false, true);
        let merged_config = merge_uln_configs(&default_config, &oapp_config);
        let expected_config = new_uln_config(3, 1, vector[@0x40], vector[@0x20], false, false, true);

        assert!(merged_config == expected_config, 0);
    }

    #[test]
    fun test_merge_configs_should_use_the_default_confirmations_when_use_default_for_confirmations_is_set_to_true() {
        let default_config = new_uln_config(2, 1, vector[@0x10], vector[@0x20], false, false, false);
        let oapp_config = new_uln_config(0, 1, vector[@0x40], vector[@0x50], true, false, false);
        let merged_config = merge_uln_configs(&default_config, &oapp_config);
        let expected_config = new_uln_config(2, 1, vector[@0x40], vector[@0x50], true, false, false);
        assert!(merged_config == expected_config, 0);
    }

    #[test]
    fun test_merge_configs_should_merge_multiple_fields() {
        let default_config = new_uln_config(2, 1, vector[@0x10], vector[@0x20], false, false, false);
        let oapp_config = new_uln_config(3, 0, vector[], vector[], true, true, true);
        let merged_config = merge_uln_configs(&default_config, &oapp_config);
        let expected_config = new_uln_config(2, 1, vector[@0x10], vector[@0x20], true, true, true);
        assert!(merged_config == expected_config, 0);
    }

    #[test]
    fun get_config_should_get_the_send_uln_config_if_that_is_requested() {
        setup();
        let send_config = new_uln_config(1, 1, vector[@0x10], vector[@0x30, @0x50], false, false, false);
        set_default_send_uln_config(1, send_config);
        let receive_config = new_uln_config(2, 1, vector[@0x20], vector[@0x40, @0x60], false, false, false);
        set_default_receive_uln_config(1, receive_config);
        let executor_config = new_executor_config(1000, @9001);
        set_default_executor_config(1, executor_config);

        let retrieved_config = configuration::get_config(@9999, 1, 2);
        let expected_config = bytes_of(|buf| configs_uln::append_uln_config(buf, send_config));
        assert!(expected_config == retrieved_config, 0);
    }

    #[test]
    fun get_config_should_get_the_receive_uln_config_if_that_is_requested() {
        setup();
        let send_config = new_uln_config(1, 1, vector[@0x10], vector[@0x30, @0x50], false, false, false);
        set_default_send_uln_config(1, send_config);
        let receive_config = new_uln_config(2, 1, vector[@0x20], vector[@0x40, @0x60], false, false, false);
        set_default_receive_uln_config(1, receive_config);
        let executor_config = new_executor_config(1000, @9001);
        set_default_executor_config(1, executor_config);

        let retrieved_config = configuration::get_config(@9999, 1, 3);
        let expected_config = bytes_of(|buf| configs_uln::append_uln_config(buf, receive_config));
        assert!(expected_config == retrieved_config, 0);
    }

    #[test]
    fun get_config_should_get_the_executor_config_if_that_is_requested() {
        setup();
        let send_config = new_uln_config(1, 1, vector[@0x10], vector[@0x30, @0x50], false, false, false);
        set_default_send_uln_config(1, send_config);
        let receive_config = new_uln_config(2, 1, vector[@0x20], vector[@0x40, @0x60], false, false, false);
        set_default_receive_uln_config(1, receive_config);
        let executor_config = new_executor_config(1000, @9001);
        set_default_executor_config(1, executor_config);

        let retrieved_config = configuration::get_config(@9999, 1, 1);
        let expected_config = bytes_of(|buf| configs_executor::append_executor_config(buf, executor_config));
        assert!(expected_config == retrieved_config, 0);
    }
}
