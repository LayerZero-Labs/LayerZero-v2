module executor::executor {
    use std::event::emit;
    use std::fungible_asset::{Self, Metadata};
    use std::object::address_to_object;
    use std::primary_fungible_store;
    use std::signer::address_of;
    use std::vector;

    use endpoint_v2_common::contract_identity::{
        CallRef,
        ContractSigner,
        create_contract_signer,
        make_call_ref,
    };
    use endpoint_v2_common::native_token;
    use executor::native_drop_params::{
        calculate_total_amount, deserialize_native_drop_params, NativeDropParams, unpack_native_drop_params,
    };
    use worker_common::worker_config::{Self, WORKER_ID_EXECUTOR};

    struct ExecutorConfig has key {
        contract_signer: ContractSigner,
    }

    fun init_module(account: &signer) {
        move_to(account, ExecutorConfig { contract_signer: create_contract_signer(account) });
    }

    #[test_only]
    public fun init_module_for_test() {
        let account = &std::account::create_signer_for_test(@executor);
        init_module(account);
    }

    /// Initializes the executor
    /// This function must be called before using the executor
    ///
    /// @param account the signer of the transaction
    /// @param role_admin the address of the default admin
    /// @param admins the list of admins
    /// @param suppored_msglibs the list of supported msglibs
    /// @param fee_lib the fee lib to use
    /// @param price_feed the price feed to use
    /// @param feed_address the address of the feed within the module
    /// @return the total fee and the deposit address
    /// @dev this function must be called before using the executor
    public entry fun initialize(
        account: &signer,
        deposit_address: address,
        role_admin: address,
        admins: vector<address>,
        supported_msglibs: vector<address>,
        fee_lib: address,
    ) {
        assert!(address_of(account) == @executor, EUNAUTHORIZED);
        worker_config::initialize_for_worker(
            account,
            WORKER_ID_EXECUTOR(),
            deposit_address,
            role_admin,
            admins,
            supported_msglibs,
            fee_lib,
        );
    }

    // ================================================ Role Admin Only ===============================================

    /// Sets the role admin for the executor
    /// A role admin can only be set by another role admin
    public entry fun set_role_admin(
        account: &signer,
        role_admin: address,
        active: bool,
    ) acquires ExecutorConfig {
        assert_role_admin(address_of(move account));
        worker_config::set_worker_role_admin(call_ref(), role_admin, active);
    }

    /// Sets the fee lib for the executor
    public entry fun set_admin(
        account: &signer,
        admin: address,
        active: bool,
    ) acquires ExecutorConfig {
        assert_role_admin(address_of(move account));
        worker_config::set_worker_admin(call_ref(), admin, active);
    }

    /// Pauses or unpauses the executor
    public entry fun set_pause(account: &signer, pause: bool) acquires ExecutorConfig {
        assert_role_admin(address_of(move account));
        worker_config::set_worker_pause(call_ref(), pause);
    }

    // ================================================== Admin Only ==================================================

    /// Applies a native drop
    /// This is intended to be called by the executor in concert with lz_receive (on the OApp), either separately from
    /// the offchain or in a ad-hoc script.
    /// This call will withdraw the total amount from the executor's primary fungible store and distribute it to the
    /// receivers specified in the params.
    public entry fun native_drop(
        account: &signer,
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        dst_eid: u32,
        oapp: address,
        serialized_params: vector<u8>,
    ) {
        assert_admin(address_of(account));

        let params = deserialize_native_drop_params(&serialized_params);
        let total_amount = calculate_total_amount(params);
        let metadata = address_to_object<Metadata>(@native_token_metadata_address);

        // Last signer use
        let fa_total = native_token::withdraw(account, total_amount);

        for (i in 0..vector::length(&params)) {
            let (receiver, amount) = unpack_native_drop_params(*vector::borrow(&params, i));
            let receiver_store = primary_fungible_store::ensure_primary_store_exists(receiver, metadata);
            let fa = fungible_asset::extract(&mut fa_total, amount);
            fungible_asset::deposit(receiver_store, fa);
        };
        fungible_asset::destroy_zero(fa_total);

        emit(NativeDropApplied {
            src_eid,
            sender,
            nonce,
            dst_eid,
            oapp,
            params,
        });
    }

    public fun emit_lz_receive_value_provided(
        admin: &signer,
        receiver: address,
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        guid: vector<u8>,
        lz_receive_value: u64,
    ) {
        assert_admin(address_of(move admin));
        emit(LzReceiveValueProvided { receiver, src_eid, sender, nonce, guid, lz_receive_value });
    }

    public fun emit_lz_compose_value_provided(
        admin: &signer,
        from: address,
        to: address,
        index: u16,
        guid: vector<u8>,
        lz_compose_value: u64,
    ) {
        assert_admin(address_of(move admin));
        emit(LzComposeValueProvided { from, to, index, guid, lz_compose_value });
    }

    /// Sets the deposit address to which the fee lib will send payment for the executor
    public entry fun set_deposit_address(account: &signer, deposit_address: address) acquires ExecutorConfig {
        assert_admin(address_of(move account));
        worker_config::set_deposit_address(call_ref(), deposit_address);
    }

    /// Sets the multiplier premium for the executor
    public entry fun set_default_multiplier_bps(account: &signer, default_multiplier_bps: u16) acquires ExecutorConfig {
        assert_admin(address_of(move account));
        worker_config::set_default_multiplier_bps(call_ref(), default_multiplier_bps);
    }

    /// Sets the supported option types for the executor
    public entry fun set_supported_option_types(account: &signer, option_types: vector<u8>) acquires ExecutorConfig {
        assert_admin(address_of(move account));
        worker_config::set_supported_option_types(call_ref(), option_types);
    }

    /// Sets the destination config for an eid on the executor
    ///
    /// @param account the signer of the transaction (must be admin)
    /// @param remote_eid the destination eid
    /// @param lz_receive_base_gas the base gas for lz receive
    /// @param multiplier_bps the multiplier in basis points
    /// @param floor_margin_usd the floor margin in USD
    /// @param native_cap the native cap
    /// @param lz_compose_base_gas the base gas for lz compose
    public entry fun set_dst_config(
        account: &signer,
        remote_eid: u32,
        lz_receive_base_gas: u64,
        multiplier_bps: u16,
        floor_margin_usd: u128,
        native_cap: u128,
        lz_compose_base_gas: u64,
    ) acquires ExecutorConfig {
        assert_admin(address_of(move account));
        worker_config::set_executor_dst_config(
            call_ref(),
            remote_eid,
            lz_receive_base_gas,
            multiplier_bps,
            floor_margin_usd,
            native_cap,
            lz_compose_base_gas,
        );
    }


    #[view]
    /// Checks whether the executor is paused
    public fun is_paused(): bool {
        worker_config::is_worker_paused(@executor)
    }

    /// Sets the price feed module address and the feed address for the executor
    public entry fun set_price_feed(
        account: &signer,
        price_feed: address,
        feed_address: address,
    ) acquires ExecutorConfig {
        assert_admin(address_of(move account));
        worker_config::set_price_feed(call_ref(), price_feed, feed_address);
    }

    /// Sets a price feed delegate for the executor
    /// This is used to allow the executor delegate to the configuration defined in another module
    /// When there is a delegation, the worker_config get_effective_price_feed will return the price feed of the
    /// delegate
    public entry fun set_price_feed_delegate(account: &signer, price_feed_delegate: address) acquires ExecutorConfig {
        assert_admin(address_of(move account));
        worker_config::set_price_feed_delegate(call_ref(), price_feed_delegate);
    }

    /// Add (allowed = true) or remove (allowed = false) a sender to/from the allowlist
    /// A non-empty allowlist restrict senders to only those on the list (minus any on the denylist)
    public entry fun set_allowlist(
        account: &signer,
        oapp: address,
        allowed: bool,
    ) acquires ExecutorConfig {
        assert_admin(address_of(move account));
        worker_config::set_allowlist(call_ref(), oapp, allowed);
    }

    /// Add (denied = true) or remove (denied = false) a sender from the denylist
    /// Denylist members will be disallowed from interacting with the executor regardless of allowlist status
    public entry fun set_denylist(
        account: &signer,
        oapp: address,
        denied: bool,
    ) acquires ExecutorConfig {
        assert_admin(address_of(move account));
        worker_config::set_denylist(call_ref(), oapp, denied);
    }

    /// Sets the supported message libraries for the executor
    /// The provided list will entirely replace the previously configured list
    public entry fun set_supported_msglibs(
        account: &signer,
        msglibs: vector<address>,
    ) acquires ExecutorConfig {
        assert_admin(address_of(move account));
        worker_config::set_supported_msglibs(call_ref(), msglibs);
    }

    /// Sets the fee lib for the executor
    public entry fun set_fee_lib(
        account: &signer,
        fee_lib: address,
    ) acquires ExecutorConfig {
        assert_admin(address_of(move account));
        worker_config::set_worker_fee_lib(call_ref(), fee_lib);
    }

    // ================================================ View Functions ================================================

    #[view]
    /// Gets the list of role admins for the executor
    public fun get_role_admins(): vector<address> {
        worker_config::get_worker_role_admins(@executor)
    }

    #[view]
    /// Gets the list of admins for the executor
    public fun get_admins(): vector<address> {
        worker_config::get_worker_admins(@executor)
    }

    #[view]
    /// Gets the deposit address for the executor
    public fun get_deposit_address(): address {
        worker_config::get_deposit_address(@executor)
    }

    #[view]
    /// Gets the list of supported message libraries for the executor
    public fun get_supported_msglibs(): vector<address> { worker_config::get_supported_msglibs(@executor) }

    #[view]
    /// Gets the fee lib address selected by the executor
    public fun get_fee_lib(): address {
        worker_config::get_worker_fee_lib(@executor)
    }

    #[view]
    /// Gets multiplier premium for the executor
    public fun get_default_multiplier_bps(): u16 {
        worker_config::get_default_multiplier_bps(@executor)
    }

    #[view]
    /// Gets the supported option types for the executor
    public fun get_supported_option_types(): vector<u8> {
        worker_config::get_supported_option_types(@executor)
    }

    #[view]
    /// Returns whether a sender is on the executor's allowlist
    public fun allowlist_contains(sender: address): bool { worker_config::allowlist_contains(@executor, sender) }

    #[view]
    /// Returns whether a sender is on the executor's denylist
    public fun denylist_contains(sender: address): bool { worker_config::denylist_contains(@executor, sender) }

    #[view]
    /// Returns whether a sender is allowed to interact with the executor based on the allowlist and denylist
    public fun is_allowed(sender: address): bool { worker_config::is_allowed(@executor, sender) }

    #[view]
    /// Gets the destination config for an eid on the executor
    /// @return the lz_receive_base_gas, multiplier_bps, floor_margin_usd, native_cap, lz_compose_base_gas
    public fun get_dst_config(dst_eid: u32): (u64, u16, u128, u128, u64) {
        worker_config::get_executor_dst_config_values(@executor, dst_eid)
    }

    #[view]
    /// Get the number of other workers that are currently delegating to this executor's price feed configuration
    public fun get_count_price_feed_delegate_dependents(): u64 {
        worker_config::get_count_price_feed_delegate_dependents(@executor)
    }

    // ================================================ Helper Functions ================================================

    /// Asserts that an an address is a role admin
    inline fun assert_role_admin(role_admin: address) {
        worker_config::assert_worker_role_admin(@executor, role_admin);
    }

    /// Asserts that an address is an admin
    inline fun assert_admin(admin: address) {
        worker_config::assert_worker_admin(@executor, admin);
    }

    /// Derives the call ref targetting the worker_common module
    inline fun call_ref<Target>(): &CallRef<Target> {
        let contract_signer = &borrow_global<ExecutorConfig>(@executor).contract_signer;
        &make_call_ref(contract_signer)
    }

    // ==================================================== Events ====================================================

    #[event]
    /// Emits when a Native Drop is Applied
    struct NativeDropApplied has store, drop {
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        dst_eid: u32,
        oapp: address,
        params: vector<NativeDropParams>,
    }

    #[event]
    struct LzReceiveValueProvided has store, drop {
        receiver: address,
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        guid: vector<u8>,
        lz_receive_value: u64,
    }

    #[event]
    struct LzComposeValueProvided has store, drop {
        from: address,
        to: address,
        index: u16,
        guid: vector<u8>,
        lz_compose_value: u64,
    }

    #[test_only]
    /// Creates a NativeDropApplied event for testing
    public fun native_drop_applied_event(
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        dst_eid: u32,
        oapp: address,
        params: vector<NativeDropParams>,
    ): NativeDropApplied {
        NativeDropApplied {
            src_eid,
            sender,
            nonce,
            dst_eid,
            oapp,
            params,
        }
    }

    #[test_only]
    public fun lz_receive_value_provided_event(
        receiver: address,
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        guid: vector<u8>,
        lz_receive_value: u64,
    ): LzReceiveValueProvided {
        LzReceiveValueProvided { receiver, src_eid, sender, nonce, guid, lz_receive_value }
    }

    #[test_only]
    public fun lz_compose_value_provided_event(
        from: address,
        to: address,
        index: u16,
        guid: vector<u8>,
        lz_compose_value: u64,
    ): LzComposeValueProvided {
        LzComposeValueProvided { from, to, index, guid, lz_compose_value }
    }

    // ================================================== Error Codes =================================================

    const EUNAUTHORIZED: u64 = 1;
}
