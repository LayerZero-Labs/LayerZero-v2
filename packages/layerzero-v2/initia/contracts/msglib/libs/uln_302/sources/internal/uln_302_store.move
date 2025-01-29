module uln_302::uln_302_store {
    use std::option::{Self, Option};
    use std::table::{Self, Table};

    use endpoint_v2_common::bytes32::Bytes32;
    use msglib_types::configs_executor::ExecutorConfig;
    use msglib_types::configs_uln::UlnConfig;

    friend uln_302::configuration;
    friend uln_302::verification;
    friend uln_302::msglib;

    #[test_only]
    friend uln_302::configuration_tests;

    #[test_only]
    friend uln_302::verification_tests;

    #[test_only]
    friend uln_302::sending_tests;

    struct Store has key {
        default_configs: Table<u32, DefaultConfig>,
        oapp_configs: Table<OAppEid, OAppConfig>,
        confirmations: Table<ConfirmationsKey, u64>,
        worker_config_opt_in_out: Table<address, bool>,
    }

    struct OAppEid has store, drop, copy {
        oapp: address,
        eid: u32,
    }

    struct DefaultConfig has store, drop, copy {
        executor_config: Option<ExecutorConfig>,
        receive_uln_config: Option<UlnConfig>,
        send_uln_config: Option<UlnConfig>,
    }

    struct OAppConfig has store, drop, copy {
        executor_config: Option<ExecutorConfig>,
        receive_uln_config: Option<UlnConfig>,
        send_uln_config: Option<UlnConfig>,
    }

    struct ConfirmationsKey has store, drop, copy {
        header_hash: Bytes32,
        payload_hash: Bytes32,
        dvn_address: address,
    }

    fun init_module(account: &signer) {
        move_to<Store>(account, Store {
            default_configs: table::new(),
            oapp_configs: table::new(),
            confirmations: table::new(),
            worker_config_opt_in_out: table::new(),
        });
    }

    // ============================================= General Configuration ============================================

    // the following functions are used to facilitate working with a nested data structure in the store. The
    // initialization of certain table fields does not have a mapping to an exposed initialization process and are
    // strictly implementation details.

    #[test_only]
    // Initializes the module for testing purposes
    public(friend) fun init_module_for_test() {
        let admin = &std::account::create_signer_for_test(@uln_302);
        init_module(admin);
    }

    /// Internal function that checks whether the default config table is initialized for a given EID
    fun is_eid_default_config_table_initialized(eid: u32): bool acquires Store {
        table::contains(&store().default_configs, eid)
    }

    /// Internal function that checks whether the oapp config table is initialized for a given EID and OApp
    fun is_eid_oapp_config_table_initialized(eid: u32, oapp: address): bool acquires Store {
        table::contains(&store().oapp_configs, OAppEid { oapp, eid })
    }

    /// Internal function that initializes the default config table for a given EID if it is not already
    fun ensure_eid_default_config_table_initialized(eid: u32) acquires Store {
        if (!is_eid_default_config_table_initialized(eid)) {
            table::add(&mut store_mut().default_configs, eid, DefaultConfig {
                executor_config: option::none(),
                receive_uln_config: option::none(),
                send_uln_config: option::none(),
            });
        }
    }

    /// Internal function that initializes the oapp config table for a given EID and OApp if it is not already
    fun ensure_oapp_config_table_initialized(eid: u32, oapp: address) acquires Store {
        if (!is_eid_oapp_config_table_initialized(eid, oapp)) {
            table::add(&mut store_mut().oapp_configs, OAppEid { eid, oapp }, OAppConfig {
                executor_config: option::none(),
                receive_uln_config: option::none(),
                send_uln_config: option::none(),
            });
        }
    }

    // ================================================= Worker Config ================================================


    public(friend) fun set_worker_config_for_fee_lib_routing_opt_in(worker: address, opt_in_out: bool) acquires Store {
        table::upsert(&mut store_mut().worker_config_opt_in_out, worker, opt_in_out)
    }

    public(friend) fun get_worker_config_for_fee_lib_routing_opt_in(worker: address): bool acquires Store {
        *table::borrow_with_default(&store().worker_config_opt_in_out, worker, &false)
    }

    // ================================================ Send ULN Config ===============================================

    public(friend) fun has_default_send_uln_config(dst_eid: u32): bool acquires Store {
        is_eid_default_config_table_initialized(dst_eid) &&
            option::is_some(&default_configs(dst_eid).send_uln_config)
    }

    /// Gets the default send configuration for a given EID
    public(friend) fun get_default_send_uln_config(dst_eid: u32): Option<UlnConfig> acquires Store {
        if (!is_eid_default_config_table_initialized(dst_eid)) { return option::none() };
        default_configs(dst_eid).send_uln_config
    }

    /// Sets the default send configuration for a given EID. This is a raw setter and should not be used directly
    public(friend) fun set_default_send_uln_config(eid: u32, config: UlnConfig) acquires Store {
        ensure_eid_default_config_table_initialized(eid);
        default_configs_mut(eid).send_uln_config = option::some(config);
    }

    /// Sets the send configuration for a given EID. This is a raw setter and should not be used directly
    public(friend) fun set_send_uln_config(oapp_address: address, eid: u32, config: UlnConfig) acquires Store {
        ensure_oapp_config_table_initialized(eid, oapp_address);
        oapp_configs_mut(eid, oapp_address).send_uln_config = option::some(config);
    }

    /// Gets the oapp send configuration for an EID if it is set. This is a raw getter and should not be used directly
    public(friend) fun get_send_uln_config(sender: address, dst_eid: u32): Option<UlnConfig> acquires Store {
        if (!is_eid_oapp_config_table_initialized(dst_eid, sender)) { return option::none() };
        oapp_configs(dst_eid, sender).send_uln_config
    }

    // ============================================== Receive ULN Config ==============================================

    public(friend) fun has_default_receive_uln_config(eid: u32): bool acquires Store {
        is_eid_default_config_table_initialized(eid) &&
            option::is_some(&default_configs(eid).receive_uln_config)
    }

    /// Gets the default receive configuration for a given EID
    public(friend) fun get_default_receive_uln_config(eid: u32): Option<UlnConfig> acquires Store {
        if (!is_eid_default_config_table_initialized(eid)) { return option::none() };
        default_configs(eid).receive_uln_config
    }

    /// Sets the default receive configuration for a given EID. This is a raw setter and should not be used directly
    public(friend) fun set_default_receive_uln_config(eid: u32, config: UlnConfig) acquires Store {
        ensure_eid_default_config_table_initialized(eid);
        default_configs_mut(eid).receive_uln_config = option::some(config);
    }

    /// Gets the oapp receive configuration for an EID if it is set. This is a raw getter and should not be used
    /// directly
    public(friend) fun get_receive_uln_config(oapp_address: address, eid: u32): Option<UlnConfig> acquires Store {
        if (!is_eid_oapp_config_table_initialized(eid, oapp_address)) { return option::none() };
        oapp_configs(eid, oapp_address).receive_uln_config
    }

    /// Sets the oapp receive configuration for an EID. This is a raw setter and should not be used directly
    public(friend) fun set_receive_uln_config(oapp: address, eid: u32, config: UlnConfig) acquires Store {
        ensure_oapp_config_table_initialized(eid, oapp);
        oapp_configs_mut(eid, oapp).receive_uln_config = option::some(config);
    }

    // ================================================ Executor Config ===============================================

    /// Gets the default executor configuration for a given EID
    public(friend) fun get_default_executor_config(eid: u32): Option<ExecutorConfig> acquires Store {
        if (!is_eid_default_config_table_initialized(eid)) { return option::none() };
        default_configs(eid).executor_config
    }

    /// Sets the default executor configuration for a given EID. This is a raw setter and should not be used directly
    public(friend) fun set_default_executor_config(eid: u32, config: ExecutorConfig) acquires Store {
        ensure_eid_default_config_table_initialized(eid);
        default_configs_mut(eid).executor_config = option::some(config);
    }

    /// Gets the oapp executor configuration for an EID if it is set. This is a raw getter and should not be used
    public(friend) fun get_executor_config(sender: address, eid: u32): Option<ExecutorConfig> acquires Store {
        if (!is_eid_oapp_config_table_initialized(eid, sender)) { return option::none() };
        oapp_configs(eid, sender).executor_config
    }

    /// Sets the oapp executor configuration for an EID. This is a raw setter and should not be used directly
    public(friend) fun set_executor_config(sender: address, eid: u32, config: ExecutorConfig) acquires Store {
        ensure_oapp_config_table_initialized(eid, sender);
        oapp_configs_mut(eid, sender).executor_config = option::some(config);
    }

    // ============================================== Receive Side State ==============================================

    /// Checks if a message has received confirmations from a given DVN
    public(friend) fun has_verification_confirmations(
        header_hash: Bytes32, payload_hash: Bytes32, dvn_address: address,
    ): bool acquires Store {
        table::contains(confirmations(), ConfirmationsKey { header_hash, payload_hash, dvn_address })
    }

    /// Gets the number of verification confirmations received for a message from a given DVN
    public(friend) fun get_verification_confirmations(
        header_hash: Bytes32, payload_hash: Bytes32, dvn_address: address,
    ): u64 acquires Store {
        *table::borrow(confirmations(), ConfirmationsKey { header_hash, payload_hash, dvn_address })
    }

    /// Sets the number of verification confirmations received for a message from a given DVN. This is a raw setter and
    /// should not be used directly
    public(friend) fun set_verification_confirmations(
        header_hash: Bytes32, payload_hash: Bytes32, dvn_address: address, confirmations: u64,
    ) acquires Store {
        table::upsert(
            confirmations_mut(),
            ConfirmationsKey { header_hash, payload_hash, dvn_address },
            confirmations,
        )
    }

    /// Removes the verification confirmations for a message from a given DVN. This is a raw setter and should not be
    /// used directly
    public(friend) fun remove_verification_confirmations(
        header_hash: Bytes32, payload_hash: Bytes32, dvn_address: address,
    ): u64 acquires Store {
        table::remove(confirmations_mut(), ConfirmationsKey { header_hash, payload_hash, dvn_address })
    }

    // ==================================================== Helpers ===================================================

    inline fun store(): &Store { borrow_global(@uln_302) }

    inline fun store_mut(): &mut Store { borrow_global_mut(@uln_302) }

    inline fun default_configs(eid: u32): &DefaultConfig { table::borrow(&store().default_configs, eid) }

    inline fun default_configs_mut(eid: u32): &mut DefaultConfig {
        table::borrow_mut(&mut store_mut().default_configs, eid)
    }

    inline fun oapp_configs(eid: u32, oapp: address): &OAppConfig {
        table::borrow(&store().oapp_configs, OAppEid { oapp, eid })
    }

    inline fun oapp_configs_mut(eid: u32, oapp: address): &mut OAppConfig {
        table::borrow_mut(&mut store_mut().oapp_configs, OAppEid { oapp, eid })
    }

    inline fun confirmations(): &Table<ConfirmationsKey, u64> { &store().confirmations }

    inline fun confirmations_mut(): &mut Table<ConfirmationsKey, u64> { &mut store_mut().confirmations }

    // ================================================== Error Codes =================================================

    const EALREADY_SET: u64 = 1;
    const EINVALID_INPUT: u64 = 2;
}
