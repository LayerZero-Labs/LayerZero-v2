module worker_common::worker_config_store {
    use std::option::{Self, Option};
    use std::signer::address_of;
    use std::table::{Self, Table};
    use std::vector;

    friend worker_common::worker_config;

    #[test_only]
    friend worker_common::worker_config_store_tests;

    struct WorkerStore has key {
        // The worker ID (either Executor: 1 or DVN: 2)
        worker_id: u8,
        // The feelib that should be used for this worker
        fee_lib: address,
        // The admins of this worker
        admins: vector<address>,
        // The role admins of this worker - role admins can add/remove admins and other role admins
        role_admins: vector<address>,
        // The supported message libraries for this worker
        supported_msglibs: vector<address>,
        // The allowlist of senders - if not empty, no senders not on allowlist will be allowed
        allowlist: Table<address, bool>,
        // The denylist of senders - senders on the denylist will not be allowed
        denylist: Table<address, bool>,
        // The number of items on the allowlist. This is needed to check whether the allowlist is empty
        allowlist_count: u64,
        // Whether the worker has been paused. If the worker is paused, any send transaction that involves this worker
        // will fail
        paused: bool,
        // The optional price feed module and feed selection for this worker
        price_feed_selection: Option<PriceFeedSelection>,
        // The optional price feed delegate selection for this worker
        price_feed_delegate_selection: Option<address>,
        // The number of workers delegating to this worker for price feed selection
        count_price_feed_delegating_workers: u64,
        // The deposit address for this worker: worker payments will be sent to this address
        deposit_address: address,
        // The default multiplier bps that will be used to calculate premiums for this worker
        default_multiplier_bps: u16,
        // The serialized supported option types for this worker
        supported_option_types: vector<u8>,
        // Per destination EID configuration (for executors only)
        executor_dst_config: Table<u32, ExecutorDstConfig>,
        // Per destination EID configuration (for DVNs only)
        dvn_dst_config: Table<u32, DvnDstConfig>,
    }

    struct PriceFeedSelection has drop, copy, store {
        price_feed_module: address,
        price_feed: address,
    }

    struct ExecutorDstConfig has store, copy, drop {
        lz_receive_base_gas: u64,
        multiplier_bps: u16,
        floor_margin_usd: u128,
        native_cap: u128,
        lz_compose_base_gas: u64,
    }

    struct DvnDstConfig has store, copy, drop {
        gas: u64,
        multiplier_bps: u16,
        floor_margin_usd: u128,
    }

    public(friend) fun initialize_store_for_worker(
        worker_account: &signer,
        worker_id: u8,
        deposit_address: address,
        role_admin: address,
        admins: vector<address>,
        supported_msglibs: vector<address>,
        fee_lib: address,
    ) {
        let worker_address = address_of(worker_account);
        assert!(!exists<WorkerStore>(worker_address), EWORKER_ALREADY_INITIALIZED);
        assert!(vector::length(&admins) > 0, ENO_ADMINS_PROVIDED);
        move_to<WorkerStore>(move worker_account, WorkerStore {
            worker_id,
            fee_lib,
            role_admins: vector[role_admin],
            admins,
            supported_msglibs,
            allowlist: table::new(),
            denylist: table::new(),
            allowlist_count: 0,
            paused: false,
            price_feed_selection: option::none(),
            price_feed_delegate_selection: option::none(),
            count_price_feed_delegating_workers: 0,
            deposit_address,
            default_multiplier_bps: 0,
            supported_option_types: vector[],
            executor_dst_config: table::new(),
            dvn_dst_config: table::new(),
        })
    }

    public(friend) fun assert_initialized(worker: address) {
        assert!(exists<WorkerStore>(worker), EWORKER_NOT_REGISTERED);
    }

    public(friend) fun is_worker_initialized(worker: address): bool {
        exists<WorkerStore>(worker)
    }

    public(friend) fun get_worker_id(worker: address): u8 acquires WorkerStore {
        worker_store(worker).worker_id
    }

    // ================================================ Worker General ================================================

    public(friend) fun set_supported_msglibs(worker: address, msglibs: vector<address>) acquires WorkerStore {
        worker_store_mut(worker).supported_msglibs = msglibs;
    }

    public(friend) fun get_supported_msglibs(worker: address): vector<address> acquires WorkerStore {
        worker_store(worker).supported_msglibs
    }

    public(friend) fun is_supported_msglib(worker: address, msglib: address): bool acquires WorkerStore {
        vector::contains(&worker_store(worker).supported_msglibs, &msglib)
    }

    public(friend) fun set_fee_lib(worker: address, fee_lib: address) acquires WorkerStore {
        worker_store_mut(worker).fee_lib = fee_lib;
    }

    public(friend) fun get_fee_lib(worker: address): address acquires WorkerStore {
        worker_store(worker).fee_lib
    }

    public(friend) fun set_pause_status(worker: address, paused: bool) acquires WorkerStore {
        worker_store_mut(worker).paused = paused;
    }

    public(friend) fun is_paused(worker: address): bool acquires WorkerStore {
        worker_store(worker).paused
    }

    public(friend) fun set_deposit_address(worker: address, deposit_address: address) acquires WorkerStore {
        worker_store_mut(worker).deposit_address = deposit_address;
    }

    public(friend) fun get_deposit_address(worker: address): address acquires WorkerStore {
        worker_store(worker).deposit_address
    }

    public(friend) fun set_default_multiplier_bps(worker: address, default_multiplier_bps: u16) acquires WorkerStore {
        worker_store_mut(worker).default_multiplier_bps = default_multiplier_bps;
    }

    public(friend) fun get_default_multiplier_bps(worker: address): u16 acquires WorkerStore {
        worker_store(worker).default_multiplier_bps
    }

    public(friend) fun set_supported_option_types(worker: address, option_types: vector<u8>) acquires WorkerStore {
        worker_store_mut(worker).supported_option_types = option_types;
    }

    public(friend) fun get_supported_option_types(worker: address): vector<u8> acquires WorkerStore {
        worker_store(worker).supported_option_types
    }

    // =================================================== Executor ===================================================

    public(friend) fun set_executor_dst_config(
        worker: address,
        dst_eid: u32,
        lz_receive_base_gas: u64,
        multiplier_bps: u16,
        floor_margin_usd: u128,
        native_cap: u128,
        lz_compose_base_gas: u64,
    ) acquires WorkerStore {
        let executor_dst_config = &mut worker_store_mut(worker).executor_dst_config;
        table::upsert(executor_dst_config, dst_eid, ExecutorDstConfig {
            lz_receive_base_gas,
            multiplier_bps,
            floor_margin_usd,
            native_cap,
            lz_compose_base_gas,
        });
    }

    public(friend) fun get_executor_dst_config_values(
        worker: address,
        dst_eid: u32,
    ): (u64, u16, u128, u128, u64) acquires WorkerStore {
        let config_store = &worker_store(worker).executor_dst_config;
        assert!(table::contains(config_store, dst_eid), EEXECUTOR_DST_EID_NOT_CONFIGURED);
        let executor_dst_config = table::borrow(config_store, dst_eid);
        (
            executor_dst_config.lz_receive_base_gas,
            executor_dst_config.multiplier_bps,
            executor_dst_config.floor_margin_usd,
            executor_dst_config.native_cap,
            executor_dst_config.lz_compose_base_gas,
        )
    }

    // ====================================================== DVN =====================================================

    public(friend) fun set_dvn_dst_config(
        worker: address,
        dst_eid: u32,
        gas: u64,
        multiplier_bps: u16,
        floor_margin_usd: u128,
    ) acquires WorkerStore {
        let dvn_dst_config = &mut worker_store_mut(worker).dvn_dst_config;
        table::upsert(dvn_dst_config, dst_eid, DvnDstConfig { gas, multiplier_bps, floor_margin_usd });
    }

    public(friend) fun get_dvn_dst_config_values(
        worker: address,
        dst_eid: u32,
    ): (u64, u16, u128) acquires WorkerStore {
        let config_store = &worker_store(worker).dvn_dst_config;
        assert!(table::contains(config_store, dst_eid), EDVN_DST_EID_NOT_CONFIGURED);
        let dvn_dst_config = table::borrow(&worker_store(worker).dvn_dst_config, dst_eid);
        (dvn_dst_config.gas, dvn_dst_config.multiplier_bps, dvn_dst_config.floor_margin_usd)
    }

    // ================================================== Price Feed ==================================================

    public(friend) fun set_price_feed(
        worker: address,
        price_feed_module: address,
        price_feed: address,
    ) acquires WorkerStore {
        worker_store_mut(worker).price_feed_selection = option::some(PriceFeedSelection {
            price_feed_module,
            price_feed,
        });
    }

    public(friend) fun has_price_feed(worker: address): bool acquires WorkerStore {
        option::is_some(&worker_store(worker).price_feed_selection)
    }

    public(friend) fun get_price_feed(worker: address): (address, address) acquires WorkerStore {
        let price_feed_selection = &worker_store(worker).price_feed_selection;
        assert!(option::is_some(price_feed_selection), ENO_PRICE_FEED_CONFIGURED);
        let selection = option::borrow(price_feed_selection);
        (selection.price_feed_module, selection.price_feed)
    }

    public(friend) fun set_price_feed_delegate(worker: address, delegate: address) acquires WorkerStore {
        let price_feed_delegate_selection = &mut worker_store_mut(worker).price_feed_delegate_selection;
        let prior_delegate = *price_feed_delegate_selection;

        assert!(option::is_none(&prior_delegate) || *option::borrow(&prior_delegate) != delegate, EUNCHANGED);
        *price_feed_delegate_selection = option::some(delegate);

        // subtract from prior delegate's count if it exists
        if (option::is_some(&prior_delegate)) {
            let prior = *option::borrow(&prior_delegate);
            let count_delegating = &mut worker_store_mut(prior).count_price_feed_delegating_workers;
            *count_delegating = *count_delegating - 1;
        };

        // add to new delegate's count
        let count_delegating = &mut worker_store_mut(delegate).count_price_feed_delegating_workers;
        *count_delegating = *count_delegating + 1;
    }

    public(friend) fun unset_price_feed_delegate(worker: address) acquires WorkerStore {
        let price_feed_delegate_selection = &mut worker_store_mut(worker).price_feed_delegate_selection;
        assert!(option::is_some(price_feed_delegate_selection), ENOT_DELEGATING);

        let prior_delegate = *option::borrow(price_feed_delegate_selection);
        *price_feed_delegate_selection = option::none();

        // subtract from prior delegate's count
        let count_delegating = &mut worker_store_mut(prior_delegate).count_price_feed_delegating_workers;
        *count_delegating = *count_delegating - 1;
    }

    public(friend) fun has_price_feed_delegate(worker: address): bool acquires WorkerStore {
        option::is_some(&worker_store(worker).price_feed_delegate_selection)
    }

    public(friend) fun get_price_feed_delegate(worker: address): address acquires WorkerStore {
        *option::borrow(&worker_store(worker).price_feed_delegate_selection)
    }

    public(friend) fun get_count_price_feed_delegate_dependents(worker: address): u64 acquires WorkerStore {
        worker_store(worker).count_price_feed_delegating_workers
    }

    // ==================================================== Admins ====================================================

    public(friend) fun add_role_admin(worker: address, role_admin: address) acquires WorkerStore {
        let role_admins = &mut worker_store_mut(worker).role_admins;
        assert!(!vector::contains(role_admins, &role_admin), EROLE_ADMIN_ALREADY_EXISTS);
        vector::push_back(role_admins, role_admin);
    }

    public(friend) fun remove_role_admin(worker: address, role_admin: address) acquires WorkerStore {
        let (found, index) = vector::index_of(&worker_store(worker).role_admins, &role_admin);
        assert!(found, EROLE_ADMIN_NOT_FOUND);
        vector::swap_remove(&mut worker_store_mut(worker).role_admins, index);
    }

    public(friend) fun get_role_admins(worker: address): vector<address> acquires WorkerStore {
        worker_store(worker).role_admins
    }

    public(friend) fun is_role_admin(worker: address, role_admin: address): bool acquires WorkerStore {
        vector::contains(&worker_store(worker).role_admins, &role_admin)
    }

    public(friend) fun add_admin(worker: address, admin: address) acquires WorkerStore {
        let admins = &mut worker_store_mut(worker).admins;
        assert!(!vector::contains(admins, &admin), EADMIN_ALREADY_EXISTS);
        vector::push_back(admins, admin);
    }

    public(friend) fun remove_admin(worker: address, admin: address) acquires WorkerStore {
        let (found, index) = vector::index_of(&worker_store(worker).admins, &admin);
        assert!(found, EADMIN_NOT_FOUND);
        let admins = &mut worker_store_mut(worker).admins;
        vector::swap_remove(admins, index);
        assert!(vector::length(admins) > 0, EATTEMPING_TO_REMOVE_ONLY_ADMIN);
    }

    public(friend) fun get_admins(worker: address): vector<address> acquires WorkerStore {
        worker_store(worker).admins
    }

    public(friend) fun is_admin(worker: address, admin: address): bool acquires WorkerStore {
        vector::contains(&worker_store(worker).admins, &admin)
    }

    // ====================================================== ACL =====================================================

    public(friend) fun add_to_allowlist(worker: address, sender: address) acquires WorkerStore {
        let allowlist = &mut worker_store_mut(worker).allowlist;
        assert!(!table::contains(allowlist, sender), EWORKER_ALREADY_ON_ALLOWLIST);
        table::add(allowlist, sender, true);
        let count_allowed = &mut worker_store_mut(worker).allowlist_count;
        *count_allowed = *count_allowed + 1;
    }

    public(friend) fun remove_from_allowlist(worker: address, sender: address) acquires WorkerStore {
        let allowlist = &mut worker_store_mut(worker).allowlist;
        assert!(table::contains(allowlist, sender), EWORKER_NOT_ON_ALLOWLIST);
        table::remove(allowlist, sender);
        let count_allowed = &mut worker_store_mut(worker).allowlist_count;
        *count_allowed = *count_allowed - 1;
    }

    public(friend) fun add_to_denylist(worker: address, sender: address) acquires WorkerStore {
        let denylist = &mut worker_store_mut(worker).denylist;
        assert!(!table::contains(denylist, sender), EWORKER_ALREADY_ON_DENYLIST);
        table::add(denylist, sender, true);
    }

    public(friend) fun remove_from_denylist(worker: address, sender: address) acquires WorkerStore {
        let denylist = &mut worker_store_mut(worker).denylist;
        assert!(table::contains(denylist, sender), EWORKER_NOT_ON_DENYLIST);
        table::remove(denylist, sender);
    }

    public(friend) fun is_on_allowlist(worker: address, sender: address): bool acquires WorkerStore {
        table::contains(&worker_store(worker).allowlist, sender)
    }

    public(friend) fun is_on_denylist(worker: address, sender: address): bool acquires WorkerStore {
        table::contains(&worker_store(worker).denylist, sender)
    }

    public(friend) fun has_allowlist(worker: address): bool acquires WorkerStore {
        worker_store(worker).allowlist_count > 0
    }

    // ==================================================== Helpers ===================================================

    inline fun worker_store(worker: address): &WorkerStore { borrow_global(worker) }

    inline fun worker_store_mut(worker: address): &mut WorkerStore { borrow_global_mut(worker) }

    // ==================================================Error Codes ==================================================

    const EADMIN_ALREADY_EXISTS: u64 = 1;
    const EADMIN_NOT_FOUND: u64 = 2;
    const EATTEMPING_TO_REMOVE_ONLY_ADMIN: u64 = 3;
    const EDVN_DST_EID_NOT_CONFIGURED: u64 = 4;
    const EEXECUTOR_DST_EID_NOT_CONFIGURED: u64 = 5;
    const ENOT_DELEGATING: u64 = 6;
    const ENO_ADMINS_PROVIDED: u64 = 7;
    const ENO_PRICE_FEED_CONFIGURED: u64 = 8;
    const EROLE_ADMIN_ALREADY_EXISTS: u64 = 9;
    const EROLE_ADMIN_NOT_FOUND: u64 = 10;
    const EUNCHANGED: u64 = 11;
    const EWORKER_ALREADY_INITIALIZED: u64 = 12;
    const EWORKER_ALREADY_ON_ALLOWLIST: u64 = 13;
    const EWORKER_ALREADY_ON_DENYLIST: u64 = 14;
    const EWORKER_NOT_ON_ALLOWLIST: u64 = 15;
    const EWORKER_NOT_ON_DENYLIST: u64 = 16;
    const EWORKER_NOT_REGISTERED: u64 = 17;
}
