/// Worker Config is a shared module that provides configuration for workers
module worker_common::worker_config {
    use std::account;
    use std::event::emit;
    use std::fungible_asset::{Self, Metadata};
    use std::math128::pow;
    use std::object::address_to_object;

    use endpoint_v2_common::contract_identity::{
        CallRef,
        get_call_ref_caller,
    };
    use worker_common::worker_config_store;

    #[test_only]
    use std::account::create_signer_for_test;

    #[test_only]
    friend worker_common::worker_config_tests;

    // Worker Ids
    public inline fun WORKER_ID_EXECUTOR(): u8 { 1 }

    public inline fun WORKER_ID_DVN(): u8 { 2 }

    // ================================================ Initialization ================================================

    #[test_only]
    /// Initialize the worker for testing purposes (does not require a signer, and accepts fewer params)
    public fun initialize_for_worker_test_only(
        worker: address,
        worker_id: u8,
        deposit_address: address,
        role_admin: address,
        admins: vector<address>,
        supported_msglibs: vector<address>,
        fee_lib: address,
    ) {
        let account = &create_signer_for_test(worker);
        worker_config_store::initialize_store_for_worker(
            account,
            worker_id,
            deposit_address,
            role_admin,
            admins,
            supported_msglibs,
            fee_lib,
        );
    }

    /// Initialize the worker - this must be called an can be called most once
    public fun initialize_for_worker(
        account: &signer,
        worker_id: u8,
        deposit_address: address,
        role_admin: address,
        admins: vector<address>,
        supported_msglibs: vector<address>,
        fee_lib: address,
    ) {
        assert!(account::exists_at(deposit_address), ENOT_AN_ACCOUNT);
        worker_config_store::initialize_store_for_worker(
            account,
            worker_id,
            deposit_address,
            role_admin,
            admins,
            supported_msglibs,
            fee_lib,
        );
    }

    #[view]
    // Check whether the worker is initialized
    public fun is_worker_initialized(worker: address): bool {
        worker_config_store::is_worker_initialized(worker)
    }

    /// Assert that the fee lib supports a transaction
    /// This checks that the worker is initialized, unpaused, the sender is allowed, that the msglib is supported, and
    /// that the worker id matches the expected worker id
    public fun assert_fee_lib_supports_transaction(worker: address, worker_id: u8, sender: address, msglib: address) {
        worker_config_store::assert_initialized(worker);
        assert_worker_unpaused(worker);
        assert_allowed(worker, sender);
        assert_supported_msglib(worker, msglib);
        assert!(worker_config_store::get_worker_id(worker) == worker_id, EUNEXPECTED_WORKER_ID);
    }

    #[view]
    /// Get the worker id for the given worker address
    public fun get_worker_id_from_worker_address(worker: address): u8 {
        worker_config_store::assert_initialized(worker);
        worker_config_store::get_worker_id(worker)
    }

    #[view]
    /// Get the worker's price feed and feed address
    public fun get_worker_price_feed_config(worker: address): (address, address) {
        worker_config_store::assert_initialized(worker);
        worker_config_store::get_price_feed(worker)
    }

    // ==================================================== Admins ====================================================

    struct WorkerAdminsTarget {}

    /// Set the admin status for the given address using the worker's CallRef
    public fun set_worker_admin(
        call_ref: &CallRef<WorkerAdminsTarget>,
        admin: address,
        active: bool,
    ) {
        let worker = get_call_ref_caller(call_ref);
        worker_config_store::assert_initialized(worker);
        if (active) {
            worker_config_store::add_admin(worker, admin);
        } else {
            worker_config_store::remove_admin(worker, admin);
        };
        emit(SetWorkerAdmin { worker, admin, active });
    }

    #[view]
    /// Check if the given address is an admin for the worker
    public fun is_worker_admin(worker: address, admin: address): bool {
        worker_config_store::assert_initialized(worker);
        worker_config_store::is_admin(worker, admin)
    }

    #[view]
    /// Get a list of the worker's admins
    public fun get_worker_admins(worker: address): vector<address> {
        worker_config_store::assert_initialized(worker);
        worker_config_store::get_admins(worker)
    }

    /// Assert that the given address is an admin for the worker
    public fun assert_worker_admin(worker: address, admin: address) {
        worker_config_store::assert_initialized(worker);
        assert!(worker_config_store::is_admin(worker, admin), EUNAUTHORIZED);
    }

    /// Set a role admin for the worker using the worker's CallRef
    public fun set_worker_role_admin(
        call_ref: &CallRef<WorkerAdminsTarget>,
        role_admin: address,
        active: bool,
    ) {
        let worker = get_call_ref_caller(call_ref);
        worker_config_store::assert_initialized(worker);
        if (active) {
            worker_config_store::add_role_admin(worker, role_admin);
        } else {
            worker_config_store::remove_role_admin(worker, role_admin);
        };
        emit(SetWorkerRoleAdmin { worker, role_admin, active });
    }

    #[view]
    /// Check if the given address is a role admin for the worker
    public fun is_worker_role_admin(worker: address, role_admin: address): bool {
        worker_config_store::assert_initialized(worker);
        worker_config_store::is_role_admin(worker, role_admin)
    }

    #[view]
    /// Get a list of the role admins for the worker
    public fun get_worker_role_admins(worker: address): vector<address> {
        worker_config_store::assert_initialized(worker);
        worker_config_store::get_role_admins(worker)
    }

    /// Assert that the given address is a role admin for the worker
    public fun assert_worker_role_admin(worker: address, role_admin: address) {
        worker_config_store::assert_initialized(worker);
        assert!(worker_config_store::is_role_admin(worker, role_admin), EUNAUTHORIZED);
    }

    // ==================================================== Pausing ===================================================

    struct WorkerPauseTarget {}

    /// Pauses the worker on the send side - will cause get_fee() functions to abort
    public fun set_worker_pause(
        call_ref: &CallRef<WorkerPauseTarget>,
        paused: bool,
    ) {
        let worker = get_call_ref_caller(call_ref);
        let previous_status = worker_config_store::is_paused(worker);
        assert!(previous_status != paused, EPAUSE_STATUS_UNCHANGED);
        worker_config_store::set_pause_status(worker, paused);
        if (paused) {
            emit(Paused { worker });
        } else {
            emit(Unpaused { worker });
        }
    }

    /// Assert that the worker is not paused
    public fun assert_worker_unpaused(worker: address) {
        assert!(!is_worker_paused(worker), EWORKER_PAUSED);
    }

    #[view]
    /// Check if the worker is paused
    public fun is_worker_paused(worker: address): bool {
        worker_config_store::assert_initialized(worker);
        worker_config_store::is_paused(worker)
    }


    // =============================================== Message Libraries ==============================================

    struct WorkerMsgLibsTarget {}

    /// Set the supported message libraries for the worker
    public fun set_supported_msglibs(
        call_ref: &CallRef<WorkerMsgLibsTarget>,
        msglibs: vector<address>,
    ) {
        let worker = get_call_ref_caller(call_ref);
        worker_config_store::set_supported_msglibs(worker, msglibs);
        emit(SetSupportedMsglibs { worker, msglibs });
    }

    #[view]
    /// Get the supported message libraries for the worker
    public fun get_supported_msglibs(worker: address): vector<address> {
        worker_config_store::assert_initialized(worker);
        worker_config_store::get_supported_msglibs(worker)
    }

    /// Assert that the worker supports the given message library
    public fun assert_supported_msglib(worker: address, msglib: address) {
        assert!(
            worker_config_store::is_supported_msglib(worker, msglib),
            EWORKER_AUTH_UNSUPPORTED_MSGLIB,
        );
    }

    // ================================================ Deposit Address ===============================================

    struct WorkerDepositAddressTarget {}

    /// Set the deposit address for the worker
    public fun set_deposit_address(call_ref: &CallRef<WorkerDepositAddressTarget>, deposit_address: address) {
        let worker = get_call_ref_caller(call_ref);
        assert!(account::exists_at(deposit_address), ENOT_AN_ACCOUNT);
        worker_config_store::set_deposit_address(worker, deposit_address);
        emit(SetDepositAddress { worker, deposit_address });
    }

    #[view]
    /// Get the deposit address for the worker
    public fun get_deposit_address(worker: address): address {
        worker_config_store::assert_initialized(worker);
        worker_config_store::get_deposit_address(worker)
    }

    // ================================================== Price Feed ==================================================

    struct WorkerPriceFeedTarget {}

    /// Set the price feed module and price feed for the worker
    public fun set_price_feed(
        call_ref: &CallRef<WorkerPriceFeedTarget>,
        price_feed: address,
        feed_address: address,
    ) {
        let worker = get_call_ref_caller(call_ref);
        worker_config_store::set_price_feed(worker, price_feed, feed_address);
        emit(SetPriceFeed {
            worker,
            price_feed,
            feed_address,
        });
    }

    #[view]
    /// Get the effective price feed module and price feed for the worker, providing the delegated price feed details
    /// if the worker has delegated the price feed; otherwise it provides what is directly configured for the worker
    public fun get_effective_price_feed(worker: address): (address, address) {
        worker_config_store::assert_initialized(worker);
        if (worker_config_store::has_price_feed_delegate(worker)) {
            let delegate = worker_config_store::get_price_feed_delegate(worker);
            assert!(worker_config_store::has_price_feed(delegate), EWORKER_PRICE_FEED_DELEGATE_NOT_CONFIGURED);
            worker_config_store::get_price_feed(delegate)
        } else if (worker_config_store::has_price_feed(worker)) {
            worker_config_store::get_price_feed(worker)
        } else {
            abort EWORKER_PRICE_FEED_NOT_CONFIGURED
        }
    }

    /// Sets a price feed delegate for the worker. This is another worker's address that has a price feed configured.
    /// If the delegate is set to @0x0, the delegate is unset. When a worker has delegated to another worker, it will
    /// use whatever is configured for the delegate worker when a fee is calculated
    public fun set_price_feed_delegate(call_ref: &CallRef<WorkerPriceFeedTarget>, delegate: address) {
        let worker = get_call_ref_caller(call_ref);
        if (delegate == @0x0) {
            // Unset
            assert!(worker_config_store::has_price_feed_delegate(worker), ENO_DELEGATE_TO_UNSET);
            worker_config_store::unset_price_feed_delegate(worker);
        } else {
            // Set
            worker_config_store::assert_initialized(delegate);
            let (price_feed, feed_address) = worker_config_store::get_price_feed(delegate);
            assert!(price_feed != @0x0, EDELEGATE_PRICE_FEED_NOT_CONFIGURED);
            assert!(feed_address != @0x0, EDELEGATE_FEED_ADDRESS_NOT_CONFIGURED);
            worker_config_store::set_price_feed_delegate(worker, delegate);
        };
        emit(SetPriceFeedDelegate { worker, delegate });
    }

    #[view]
    /// Get the price feed delegate for the worker
    /// This will return @0x0 if the worker does not have a price feed delegate
    public fun get_price_feed_delegate(worker: address): address {
        worker_config_store::assert_initialized(worker);
        if (!worker_config_store::has_price_feed_delegate(worker)) {
            @0x0
        } else {
            worker_config_store::get_price_feed_delegate(worker)
        }
    }

    #[view]
    /// Get the count of other workers delegating to a worker for the price feed configuration
    public fun get_count_price_feed_delegate_dependents(worker: address): u64 {
        worker_config_store::get_count_price_feed_delegate_dependents(worker)
    }

    // ============================================ Fee Libs Worker Config ============================================

    struct WorkerFeeLibTarget {}

    /// Set the fee lib used for the worker
    public fun set_worker_fee_lib(call_ref: &CallRef<WorkerFeeLibTarget>, fee_lib: address) {
        let worker = get_call_ref_caller(call_ref);
        worker_config_store::set_fee_lib(worker, fee_lib);
        emit(WorkerFeeLibUpdated { worker, fee_lib });
    }

    #[view]
    /// Get the fee lib for the worker
    public fun get_worker_fee_lib(worker: address): address {
        worker_config_store::assert_initialized(worker);
        worker_config_store::get_fee_lib(worker)
    }

    /// Set the default basis-points multiplier (for premium calculation) for the worker
    public fun set_default_multiplier_bps(call_ref: &CallRef<WorkerFeeLibTarget>, default_multiplier_bps: u16) {
        let worker = get_call_ref_caller(call_ref);
        worker_config_store::assert_initialized(worker);
        worker_config_store::set_default_multiplier_bps(worker, default_multiplier_bps);
        emit(SetMultiplierBps { worker, default_multiplier_bps });
    }

    #[view]
    /// Get the default basis-points multiplier for the worker
    public fun get_default_multiplier_bps(worker: address): u16 {
        worker_config_store::assert_initialized(worker);
        worker_config_store::get_default_multiplier_bps(worker)
    }

    /// Set the supported option types for the worker
    public fun set_supported_option_types(call_ref: &CallRef<WorkerFeeLibTarget>, option_types: vector<u8>) {
        let worker = get_call_ref_caller(call_ref);
        worker_config_store::assert_initialized(worker);
        worker_config_store::set_supported_option_types(worker, option_types);
        emit(SetSupportedOptionTypes { worker, option_types });
    }

    #[view]
    /// Get the supported option types for the worker
    public fun get_supported_option_types(worker: address): vector<u8> {
        worker_config_store::assert_initialized(worker);
        worker_config_store::get_supported_option_types(worker)
    }

    #[view]
    /// Get the native decimals rate for the gas token on this chain
    public fun get_native_decimals_rate(): u128 {
        let decimals = fungible_asset::decimals(address_to_object<Metadata>(@native_token_metadata_address));
        pow(10, (decimals as u128))
    }

    // ================================================ Executor Config ===============================================

    struct WorkerExecutorTarget {}

    /// Set the executor destination config for the worker
    /// @param call_ref The CallRef for the worker (should be addressed to @worker_common)
    /// @param dst_eid The destination EID
    /// @param lz_receive_base_gas The base gas for receiving a message
    /// @param multiplier_bps The multiplier in basis points
    /// @param floor_margin_usd The floor margin in USD
    /// @param native_cap The native cap
    /// @param lz_compose_base_gas The base gas for composing a message
    public fun set_executor_dst_config(
        call_ref: &CallRef<WorkerExecutorTarget>,
        dst_eid: u32,
        lz_receive_base_gas: u64,
        multiplier_bps: u16,
        floor_margin_usd: u128,
        native_cap: u128,
        lz_compose_base_gas: u64,
    ) {
        let worker = get_call_ref_caller(call_ref);
        worker_config_store::assert_initialized(worker);
        worker_config_store::set_executor_dst_config(
            worker,
            dst_eid,
            lz_receive_base_gas,
            multiplier_bps,
            floor_margin_usd,
            native_cap,
            lz_compose_base_gas,
        );
        emit(SetExecutorDstConfig {
            worker,
            dst_eid,
            lz_receive_base_gas,
            multiplier_bps,
            floor_margin_usd,
            native_cap,
            lz_compose_base_gas,
        });
    }

    #[view]
    /// Get the executor destination config for the worker
    /// @return (lz_receive_base_gas, multiplier_bps, floor_margin_usd, native_cap, lz_compose_base_gas)
    public fun get_executor_dst_config_values(
        worker: address,
        dst_eid: u32,
    ): (u64, u16, u128, u128, u64) {
        worker_config_store::assert_initialized(worker);
        worker_config_store::get_executor_dst_config_values(worker, dst_eid)
    }

    // ================================================== DVN Config ==================================================

    struct WorkerDvnTarget {}

    /// Set the DVN destination config for the worker
    /// @param call_ref The CallRef for the worker (should be addressed to @worker_common)
    /// @param dst_eid The destination EID
    /// @param gas The gas
    /// @param multiplier_bps The multiplier in basis points
    /// @param floor_margin_usd The floor margin in USD
    public fun set_dvn_dst_config(
        call_ref: &CallRef<WorkerDvnTarget>,
        dst_eid: u32,
        gas: u64,
        multiplier_bps: u16,
        floor_margin_usd: u128,
    ) {
        let worker = get_call_ref_caller(call_ref);
        worker_config_store::assert_initialized(worker);
        worker_config_store::set_dvn_dst_config(
            worker,
            dst_eid,
            gas,
            multiplier_bps,
            floor_margin_usd,
        );
        emit(SetDvnDstConfig {
            worker,
            dst_eid,
            gas,
            multiplier_bps,
            floor_margin_usd,
        });
    }

    #[view]
    /// Get the DVN destination config for the worker and destination EID
    /// @return (gas, multiplier_bps, floor_margin_usd)
    public fun get_dvn_dst_config_values(
        worker: address,
        dst_eid: u32,
    ): (u64, u16, u128) {
        worker_config_store::assert_initialized(worker);
        worker_config_store::get_dvn_dst_config_values(worker, dst_eid)
    }

    // ====================================================== ACL =====================================================

    struct WorkerAclTarget {}

    /// Add or remove a sender from the worker allowlist
    /// If the allowlist is empty, any sender, except those on the denylist, are allowed
    /// Once there is at least one sender on the allowlist, only those on the allowlist are allowed, minus any that are
    /// also on the denylist
    public fun set_allowlist(
        call_ref: &CallRef<WorkerAclTarget>,
        sender: address,
        allowed: bool,
    ) {
        let worker = get_call_ref_caller(call_ref);
        if (allowed) {
            worker_config_store::add_to_allowlist(worker, sender);
        } else {
            worker_config_store::remove_from_allowlist(worker, sender);
        };
        emit(SetAllowList { worker, sender, allowed });
    }

    /// Add or remove a sender from the worker denylist
    /// Any sender on the denylist will not be allowed, regardless of whether they are also on the allowlist
    public fun set_denylist(call_ref: &CallRef<WorkerAclTarget>, sender: address, denied: bool) {
        let worker = get_call_ref_caller(call_ref);
        if (denied) {
            worker_config_store::add_to_denylist(worker, sender);
        } else {
            worker_config_store::remove_from_denylist(worker, sender);
        };
        emit(SetDenyList { worker, sender, denied });
    }

    #[view]
    /// Check if a sender is allowed to use the worker based on the allowlist and denylist configuration
    public fun is_allowed(worker: address, sender: address): bool {
        if (worker_config_store::is_on_denylist(worker, sender)) {
            false
        } else if (worker_config_store::is_on_allowlist(worker, sender)) {
            true
        } else {
            // if there is no allow list, an unlisted sender is allowed, otherwise they must be on the allow list
            !worker_config_store::has_allowlist(worker)
        }
    }

    #[view]
    /// Check if a sender is on the worker allowlist
    public fun allowlist_contains(worker: address, sender: address): bool {
        worker_config_store::is_on_allowlist(worker, sender)
    }

    #[view]
    /// Check if a sender is on the worker denylist
    public fun denylist_contains(worker: address, sender: address): bool {
        worker_config_store::is_on_denylist(worker, sender)
    }

    /// Assert that the sender is allowed to use the worker
    public fun assert_allowed(worker: address, sender: address) {
        assert!(is_allowed(worker, sender), ESENDER_DENIED);
    }

    // ==================================================== Events ====================================================

    #[event]
    /// Event emitted when the worker admin status is set
    struct SetWorkerAdmin has store, drop { worker: address, admin: address, active: bool }

    #[event]
    /// Event emitted when the worker role admin status is set
    struct SetWorkerRoleAdmin has store, drop { worker: address, role_admin: address, active: bool }

    #[event]
    /// Event emitted when the worker deposit address is set
    struct SetDepositAddress has store, drop { worker: address, deposit_address: address }

    #[event]
    /// Event emitted when the worker is paused
    struct Paused has store, drop { worker: address }

    #[event]
    /// Event emitted when the worker is unpaused
    struct Unpaused has store, drop { worker: address }

    #[event]
    /// Event emitted when the worker supported message libraries are set
    struct SetSupportedMsglibs has store, drop { worker: address, msglibs: vector<address> }

    #[event]
    /// Event emitted when the worker price feed is set
    struct SetPriceFeed has store, drop { worker: address, price_feed: address, feed_address: address }

    #[event]
    /// Event emitted when the worker price feed delegate is set
    struct SetPriceFeedDelegate has store, drop { worker: address, delegate: address }

    #[event]
    /// Event emitted when the worker default multiplier is set
    struct SetMultiplierBps has store, drop { worker: address, default_multiplier_bps: u16 }

    #[event]
    /// Event emitted when the worker supported option types are set
    struct SetSupportedOptionTypes has store, drop { worker: address, option_types: vector<u8> }

    #[event]
    /// Event emitted when the worker executor destination config is set
    struct SetExecutorDstConfig has store, drop {
        worker: address,
        dst_eid: u32,
        lz_receive_base_gas: u64,
        multiplier_bps: u16,
        floor_margin_usd: u128,
        native_cap: u128,
        lz_compose_base_gas: u64,
    }

    #[event]
    /// Event emitted when the worker DVN destination config is set
    struct SetDvnDstConfig has store, drop {
        worker: address,
        dst_eid: u32,
        gas: u64,
        multiplier_bps: u16,
        floor_margin_usd: u128,
    }

    #[event]
    /// Event emitted when worker adds/removes an oapp sender to allowlist
    /// allowed = false means the sender is removed from the allowlist
    struct SetAllowList has store, drop { worker: address, sender: address, allowed: bool }

    #[event]
    /// Event emitted when the worker DVN destination config is set
    /// denied = false means the sender is removed from the denylist
    struct SetDenyList has store, drop { worker: address, sender: address, denied: bool }

    #[event]
    /// Event emitted when the worker fee lib is set
    struct WorkerFeeLibUpdated has store, drop { worker: address, fee_lib: address }

    // ============================================== Event Test Helpers ==============================================

    #[test_only]
    /// Generate a SetWorkerAdmin event for testing
    public fun set_worker_admin_event(worker: address, admin: address, active: bool): SetWorkerAdmin {
        SetWorkerAdmin { worker, admin, active }
    }

    #[test_only]
    /// Generate a SetWorkerRoleAdmin event for testing
    public fun set_worker_role_admin_event(worker: address, role_admin: address, active: bool): SetWorkerRoleAdmin {
        SetWorkerRoleAdmin { worker, role_admin, active }
    }

    #[test_only]
    /// Generate a SetDepositAddress event for testing
    public fun set_deposit_address_event(worker: address, deposit_address: address): SetDepositAddress {
        SetDepositAddress { worker, deposit_address }
    }

    #[test_only]
    /// Generate a Paused event for testing
    public fun paused_event(worker: address): Paused {
        Paused { worker }
    }

    #[test_only]
    /// Generate a Unpaused event for testing
    public fun unpaused_event(worker: address): Unpaused {
        Unpaused { worker }
    }

    #[test_only]
    /// Generate a SetSupportedMsglibs event for testing
    public fun set_supported_msglibs_event(worker: address, msglibs: vector<address>): SetSupportedMsglibs {
        SetSupportedMsglibs { worker, msglibs }
    }

    #[test_only]
    /// Generate a SetPriceFeed event for testing
    public fun set_price_feed_event(worker: address, price_feed: address, feed_address: address): SetPriceFeed {
        SetPriceFeed { worker, price_feed, feed_address }
    }

    #[test_only]
    /// Generate a SetPriceFeedDelegate event for testing
    public fun set_price_feed_delegate_event(worker: address, delegate: address): SetPriceFeedDelegate {
        SetPriceFeedDelegate { worker, delegate }
    }

    #[test_only]
    /// Generate a SetMultiplierBps event for testing
    public fun set_multiplier_bps_event(worker: address, default_multiplier_bps: u16): SetMultiplierBps {
        SetMultiplierBps { worker, default_multiplier_bps }
    }

    #[test_only]
    /// Generate a SetSupportedOptionTypes event for testing
    public fun set_supported_option_types_event(worker: address, option_types: vector<u8>): SetSupportedOptionTypes {
        SetSupportedOptionTypes { worker, option_types }
    }

    #[test_only]
    /// Generate a SetExecutorDstConfig event for testing
    public fun set_executor_dst_config_event(
        worker: address,
        dst_eid: u32,
        lz_receive_base_gas: u64,
        multiplier_bps: u16,
        floor_margin_usd: u128,
        native_cap: u128,
        lz_compose_base_gas: u64,
    ): SetExecutorDstConfig {
        SetExecutorDstConfig {
            worker,
            dst_eid,
            lz_receive_base_gas,
            multiplier_bps,
            floor_margin_usd,
            native_cap,
            lz_compose_base_gas,
        }
    }

    #[test_only]
    /// Generate a SetDvnDstConfig event for testing
    public fun set_dvn_dst_config_event(
        worker: address,
        dst_eid: u32,
        gas: u64,
        multiplier_bps: u16,
        floor_margin_usd: u128,
    ): SetDvnDstConfig {
        SetDvnDstConfig {
            worker,
            dst_eid,
            gas,
            multiplier_bps,
            floor_margin_usd,
        }
    }

    #[test_only]
    /// Generate a WorkerFeeLibUpdated event for testing
    public fun worker_fee_lib_updated_event(worker: address, fee_lib: address): WorkerFeeLibUpdated {
        WorkerFeeLibUpdated { worker, fee_lib }
    }

    // ================================================== Error Codes =================================================

    const EDELEGATE_FEED_ADDRESS_NOT_CONFIGURED: u64 = 1;
    const EDELEGATE_PRICE_FEED_NOT_CONFIGURED: u64 = 2;
    const ENOT_AN_ACCOUNT: u64 = 3;
    const ENO_DELEGATE_TO_UNSET: u64 = 4;
    const EPAUSE_STATUS_UNCHANGED: u64 = 5;
    const ESENDER_DENIED: u64 = 6;
    const EUNAUTHORIZED: u64 = 7;
    const EUNEXPECTED_WORKER_ID: u64 = 8;
    const EWORKER_AUTH_UNSUPPORTED_MSGLIB: u64 = 9;
    const EWORKER_PAUSED: u64 = 10;
    const EWORKER_PRICE_FEED_DELEGATE_NOT_CONFIGURED: u64 = 11;
    const EWORKER_PRICE_FEED_NOT_CONFIGURED: u64 = 12;
}
