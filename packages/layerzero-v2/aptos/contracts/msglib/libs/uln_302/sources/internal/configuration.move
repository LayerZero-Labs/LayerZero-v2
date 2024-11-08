/// This module handles the configuration of the ULN for both the send and receive sides
module uln_302::configuration {
    use std::event::emit;
    use std::option;
    use std::vector;

    use endpoint_v2_common::config_eid_tagged;
    use endpoint_v2_common::serde;
    use msglib_types::configs_executor::{Self, ExecutorConfig, new_executor_config};
    use msglib_types::configs_uln::{Self, get_confirmations, get_optional_dvn_threshold,
        get_optional_dvns, get_required_dvns, get_use_default_for_confirmations,
        get_use_default_for_optional_dvns, get_use_default_for_required_dvns, new_uln_config, UlnConfig,
    };
    use uln_302::assert_valid_default_uln_config::assert_valid_default_uln_config;
    use uln_302::assert_valid_uln_config::assert_valid_uln_config;
    use uln_302::uln_302_store;

    friend uln_302::sending;
    friend uln_302::verification;
    friend uln_302::msglib;
    friend uln_302::admin;
    friend uln_302::router_calls;

    #[test_only]
    friend uln_302::verification_tests;

    #[test_only]
    friend uln_302::configuration_tests;

    // This is needed for tests of inline functions in the sending module, which call friend functions in this module
    #[test_only]
    friend uln_302::sending_tests;

    // Configuration Types as used in this message library
    public inline fun CONFIG_TYPE_EXECUTOR(): u32 { 1 }

    public inline fun CONFIG_TYPE_SEND_ULN(): u32 { 2 }

    public inline fun CONFIG_TYPE_RECV_ULN(): u32 { 3 }

    const ULN_SEND_SIDE: u8 = 0;
    const ULN_RECEIVE_SIDE: u8 = 1;

    // ===================================================== OApp =====================================================

    // Gets the serialized configuration for an OApp eid and config type
    public(friend) fun get_config(oapp: address, eid: u32, config_type: u32): vector<u8> {
        if (config_type == CONFIG_TYPE_SEND_ULN()) {
            let config = get_send_uln_config(oapp, eid);
            serde::bytes_of(|buf| configs_uln::append_uln_config(buf, config))
        } else if (config_type == CONFIG_TYPE_RECV_ULN()) {
            let config = get_receive_uln_config(oapp, eid);
            serde::bytes_of(|buf| configs_uln::append_uln_config(buf, config))
        } else if (config_type == CONFIG_TYPE_EXECUTOR()) {
            let config = get_executor_config(oapp, eid);
            serde::bytes_of(|buf| configs_executor::append_executor_config(buf, config))
        } else {
            abort EUNKNOWN_CONFIG_TYPE
        }
    }

    public(friend) fun set_config(oapp: address, config_type: u32, config: vector<u8>) {
        if (config_type == CONFIG_TYPE_SEND_ULN()) {
            let tagged_config = configs_uln::extract_uln_config_with_eid(&config, &mut 0);
            let (eid, uln_config) = config_eid_tagged::get_eid_and_config(tagged_config);
            set_send_uln_config(oapp, eid, uln_config);
        } else if (config_type == CONFIG_TYPE_RECV_ULN()) {
            let tagged_config = configs_uln::extract_uln_config_with_eid(&config, &mut 0);
            let (eid, uln_config) = config_eid_tagged::get_eid_and_config(tagged_config);
            set_receive_uln_config(oapp, eid, uln_config);
        } else if (config_type == CONFIG_TYPE_EXECUTOR()) {
            let tagged_config = configs_executor::extract_executor_config_with_eid(&config, &mut 0);
            let (eid, executor_config) = config_eid_tagged::get_eid_and_config(tagged_config);
            set_executor_config(oapp, eid, executor_config);
        } else {
            abort EUNKNOWN_CONFIG_TYPE
        }
    }

    // ================================================= Receive Side =================================================

    public(friend) fun supports_receive_eid(eid: u32): bool {
        uln_302_store::has_default_receive_uln_config(eid)
    }

    public(friend) fun set_default_receive_uln_config(eid: u32, config: UlnConfig) {
        assert_valid_default_uln_config(&config);
        uln_302_store::set_default_receive_uln_config(eid, config);
        emit(DefaultUlnConfigSet { eid, config, send_or_receive: ULN_RECEIVE_SIDE });
    }

    public(friend) fun set_receive_uln_config(receiver: address, eid: u32, config: UlnConfig) {
        let default = uln_302_store::get_default_receive_uln_config(eid);
        assert!(option::is_some(&default), EEID_NOT_CONFIGURED);
        assert_valid_uln_config(&config, option::borrow(&default));
        uln_302_store::set_receive_uln_config(receiver, eid, config);
        emit(UlnConfigSet { oapp: receiver, eid, config, send_or_receive: ULN_RECEIVE_SIDE });
    }

    public(friend) fun get_receive_uln_config(receiver: address, eid: u32): UlnConfig {
        let oapp_config = uln_302_store::get_receive_uln_config(receiver, eid);
        let default_config = uln_302_store::get_default_receive_uln_config(eid);

        if (option::is_some(&oapp_config) && option::is_some(&default_config)) {
            merge_uln_configs(option::borrow(&default_config), option::borrow(&oapp_config))
        } else if (option::is_some(&default_config)) {
            option::extract(&mut default_config)
        } else {
            abort EEID_NOT_CONFIGURED
        }
    }

    // =================================================== Send Side ==================================================

    public(friend) fun supports_send_eid(eid: u32): bool {
        uln_302_store::has_default_send_uln_config(eid)
    }

    public(friend) fun set_default_send_uln_config(eid: u32, config: UlnConfig) {
        assert_valid_default_uln_config(&config);
        uln_302_store::set_default_send_uln_config(eid, config);
        emit(DefaultUlnConfigSet { eid, config, send_or_receive: ULN_SEND_SIDE });
    }

    public(friend) fun set_send_uln_config(oapp: address, eid: u32, config: UlnConfig) {
        let default = uln_302_store::get_default_send_uln_config(eid);
        assert!(option::is_some(&default), EEID_NOT_CONFIGURED);
        assert_valid_uln_config(&config, option::borrow(&default));
        uln_302_store::set_send_uln_config(oapp, eid, config);
        emit(UlnConfigSet { oapp, eid, config, send_or_receive: ULN_SEND_SIDE });
    }

    public(friend) fun get_send_uln_config(sender: address, eid: u32): UlnConfig {
        let oapp_config = uln_302_store::get_send_uln_config(sender, eid);
        let default_config = uln_302_store::get_default_send_uln_config(eid);

        if (option::is_some(&oapp_config) && option::is_some(&default_config)) {
            merge_uln_configs(option::borrow(&default_config), option::borrow(&oapp_config))
        } else if (option::is_some(&default_config)) {
            option::extract(&mut default_config)
        } else {
            abort EEID_NOT_CONFIGURED
        }
    }

    // =================================================== Executor ===================================================

    public(friend) fun get_executor_config(sender: address, eid: u32): ExecutorConfig {
        let oapp_config = uln_302_store::get_executor_config(sender, eid);
        let default_config = uln_302_store::get_default_executor_config(eid);

        if (option::is_some(&oapp_config) && option::is_some(&default_config)) {
            // get correct merged config if oapp and default are both set
            merge_executor_configs(option::borrow(&default_config), option::borrow(&oapp_config))
        } else if (option::is_some(&default_config)) {
            option::extract(&mut default_config)
        } else {
            abort EEID_NOT_CONFIGURED
        }
    }


    public(friend) fun set_default_executor_config(eid: u32, config: ExecutorConfig) {
        assert_valid_default_executor_config(&config);
        uln_302_store::set_default_executor_config(eid, config);
        emit(DefaultExecutorConfigSet { eid, config });
    }

    public(friend) fun set_executor_config(sender: address, eid: u32, config: ExecutorConfig) {
        uln_302_store::set_executor_config(sender, eid, config);
        emit(ExecutorConfigSet { oapp: sender, eid, config });
    }

    public(friend) fun merge_executor_configs(
        default_config: &ExecutorConfig,
        oapp_config: &ExecutorConfig,
    ): ExecutorConfig {
        let default_max_message_size = configs_executor::get_max_message_size(default_config);
        let default_executor_address = configs_executor::get_executor_address(default_config);
        let oapp_max_message_size = configs_executor::get_max_message_size(oapp_config);
        let oapp_executor_address = configs_executor::get_executor_address(oapp_config);

        new_executor_config(
            if (oapp_max_message_size > 0) { oapp_max_message_size } else { default_max_message_size },
            if (oapp_executor_address != @0x0) { oapp_executor_address } else { default_executor_address }
        )
    }

    public(friend) fun assert_valid_default_executor_config(config: &ExecutorConfig) {
        let max_message_size = configs_executor::get_max_message_size(config);
        let executor_address = configs_executor::get_executor_address(config);
        assert!(max_message_size > 0, EMAX_MESSAGE_SIZE_ZERO);
        assert!(executor_address != @0x0, EEXECUTOR_ADDRESS_IS_ZERO);
    }

    // =================================================== Internal ===================================================

    /// Merges parts of the oapp config with the default config, where specified
    public(friend) fun merge_uln_configs(default_config: &UlnConfig, oapp_config: &UlnConfig): UlnConfig {
        let default_for_confirmations = get_use_default_for_confirmations(oapp_config);
        let default_for_required = get_use_default_for_required_dvns(oapp_config);
        let default_for_optional = get_use_default_for_optional_dvns(oapp_config);

        // handle situations where there the configuration requests a fallback to default
        let optional_dvn_threshold = if (!default_for_optional) {
            get_optional_dvn_threshold(oapp_config)
        } else {
            get_optional_dvn_threshold(default_config)
        };
        let optional_dvns = if (!default_for_optional) {
            get_optional_dvns(oapp_config)
        } else {
            get_optional_dvns(default_config)
        };
        let required_dvns = if (!default_for_required) {
            get_required_dvns(oapp_config)
        } else {
            get_required_dvns(default_config)
        };

        // Check that there is at least one DVN configured. This is also checked on setting the configuration, but this
        // could cease to be the case if the default configuration is changed after the OApp configuration is set.
        assert!((optional_dvn_threshold as u64) + vector::length(&required_dvns) > 0, EINSUFFICIENT_DVNS_CONFIGURED);

        let confirmations = if (!default_for_confirmations) {
            get_confirmations(oapp_config)
        } else {
            get_confirmations(default_config)
        };

        new_uln_config(
            confirmations,
            optional_dvn_threshold,
            required_dvns,
            optional_dvns,
            default_for_confirmations,
            default_for_required,
            default_for_optional,
        )
    }

    // ==================================================== Events ====================================================

    #[event]
    struct DefaultUlnConfigSet has store, drop {
        eid: u32,
        config: UlnConfig,
        send_or_receive: u8
    }

    #[event]
    struct DefaultExecutorConfigSet has store, drop {
        eid: u32,
        config: ExecutorConfig,
    }

    #[event]
    struct UlnConfigSet has store, drop {
        oapp: address,
        eid: u32,
        config: UlnConfig,
        send_or_receive: u8
    }

    #[event]
    struct ExecutorConfigSet has store, drop {
        oapp: address,
        eid: u32,
        config: ExecutorConfig,
    }

    #[test_only]
    public fun default_uln_config_set_event(eid: u32, config: UlnConfig, send_or_receive: u8): DefaultUlnConfigSet {
        DefaultUlnConfigSet { eid, config, send_or_receive }
    }

    #[test_only]
    public fun default_executor_config_set_event(eid: u32, config: ExecutorConfig): DefaultExecutorConfigSet {
        DefaultExecutorConfigSet { eid, config }
    }

    #[test_only]
    public fun uln_config_set_event(oapp: address, eid: u32, config: UlnConfig, send_or_receive: u8): UlnConfigSet {
        UlnConfigSet { oapp, eid, config, send_or_receive }
    }

    #[test_only]
    public fun executor_config_set_event(oapp: address, eid: u32, config: ExecutorConfig): ExecutorConfigSet {
        ExecutorConfigSet { oapp, eid, config }
    }

    // ================================================== Error Codes =================================================

    const EEID_NOT_CONFIGURED: u64 = 1;
    const EEXECUTOR_ADDRESS_IS_ZERO: u64 = 2;
    const EINSUFFICIENT_DVNS_CONFIGURED: u64 = 3;
    const EMAX_MESSAGE_SIZE_ZERO: u64 = 4;
    const EUNKNOWN_CONFIG_TYPE: u64 = 5;
}
