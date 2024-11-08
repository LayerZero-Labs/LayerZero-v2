/// This module provides a groud truth for EID and ZRO Metadata address
module endpoint_v2_common::universal_config {
    use std::event::emit;
    use std::fungible_asset::{Self, FungibleAsset, Metadata};
    use std::object::{Self, Object};
    use std::option::{Self, Option};
    use std::signer::address_of;

    #[test_only]
    use std::account::create_signer_for_test;

    #[test_only]
    friend endpoint_v2_common::universal_config_tests;

    struct UniversalStore has key {
        // The EID for this endpoint
        eid: u32,
        // The ZRO metadata if it has been set
        zro_data: Option<Object<Metadata>>,
        // Whether the ZRO address is locked. Once locked the zro metadata cannot be changed
        zro_locked: bool,
    }

    /// Initialize the UniversalStore must be called by endpoint_v2_common
    public entry fun initialize(admin: &signer, eid: u32) acquires UniversalStore {
        assert_admin(address_of(move admin));
        assert!(universal_store().eid == 0, EALREADY_INITIALIZED);
        universal_store_mut().eid = eid;
    }

    fun init_module(account: &signer) {
        move_to(account, UniversalStore {
            eid: 0,
            zro_data: option::none(),
            zro_locked: false,
        });
    }

    #[test_only]
    public fun init_module_for_test(eid: u32) acquires UniversalStore {
        init_module(&create_signer_for_test(@endpoint_v2_common));
        initialize(&create_signer_for_test(@layerzero_admin), eid);
    }

    #[view]
    /// Get the EID for the V2 Endpoint
    public fun eid(): u32 acquires UniversalStore {
        universal_store().eid
    }

    /// Set the ZRO address
    /// @param account: The layerzero admin account signer
    /// @param zro_address: The address of the ZRO metadata (@0x0 to unset)
    public entry fun set_zro_address(account: &signer, zro_address: address) acquires UniversalStore {
        assert_admin(address_of(move account));
        assert!(!universal_store().zro_locked, EZRO_ADDRESS_LOCKED);

        if (zro_address == @0x0) {
            // Unset the ZRO address
            assert!(option::is_some(&universal_store().zro_data), ENO_CHANGE);
            let zro_data_store = &mut universal_store_mut().zro_data;
            *zro_data_store = option::none();
        } else {
            // Set the ZRO address
            assert!(object::object_exists<Metadata>(zro_address), EINVALID_ZRO_ADDRESS);
            if (has_zro_metadata()) {
                assert!(get_zro_address() != zro_address, ENO_CHANGE);
            };
            let zro_metadata = object::address_to_object<Metadata>(zro_address);
            let zro_data_store = &mut universal_store_mut().zro_data;
            *zro_data_store = option::some(zro_metadata);
        };

        emit(ZroMetadataSet { zro_address });
    }

    /// Lock the ZRO address so it can no longer be set or unset
    public entry fun lock_zro_address(account: &signer) acquires UniversalStore {
        assert_admin(address_of(move account));

        assert!(option::is_some(&universal_store().zro_data), EZRO_ADDRESS_NOT_SET);
        let locked_store = &mut universal_store_mut().zro_locked;
        *locked_store = true;

        emit(ZroMetadataLocked {});
    }

    #[view]
    /// Check if ZRO address is set
    public fun has_zro_metadata(): bool acquires UniversalStore {
        option::is_some(&universal_store().zro_data)
    }

    #[view]
    /// Get the ZRO address
    public fun get_zro_address(): address acquires UniversalStore {
        object::object_address(&get_zro_metadata())
    }

    #[view]
    /// Get the ZRO metadata
    public fun get_zro_metadata(): Object<Metadata> acquires UniversalStore {
        assert_zro_metadata_set();
        *option::borrow(&universal_store().zro_data)
    }

    /// Assert that the ZRO metadata is set
    public fun assert_zro_metadata_set() acquires UniversalStore {
        assert!(has_zro_metadata(), EINVALID_ZRO_ADDRESS);
    }

    /// Check if the given FungibleAsset is the ZRO asset
    public fun is_zro(fa: &FungibleAsset): bool acquires UniversalStore {
        if (!has_zro_metadata()) { return false };
        let metadata = fungible_asset::asset_metadata(fa);
        metadata == get_zro_metadata()
    }

    /// Check if the given Metadata is the ZRO metadata
    public fun is_zro_metadata(metadata: Object<Metadata>): bool acquires UniversalStore {
        if (!has_zro_metadata()) { return false };
        metadata == get_zro_metadata()
    }

    // ==================================================== Helpers ===================================================

    inline fun assert_admin(admin: address) {
        assert!(admin == @layerzero_admin, EUNAUTHORIZED);
    }

    inline fun universal_store(): &UniversalStore { borrow_global(@endpoint_v2_common) }

    inline fun universal_store_mut(): &mut UniversalStore { borrow_global_mut(@endpoint_v2_common) }

    #[test_only]
    public fun change_eid_for_test(eid: u32) acquires UniversalStore { universal_store_mut().eid = eid; }

    // ==================================================== Events ====================================================

    #[event]
    struct ZroMetadataSet has drop, store {
        zro_address: address,
    }

    #[event]
    struct ZroMetadataLocked has drop, store {}

    #[test_only]
    public fun zro_metadata_set(zro_address: address): ZroMetadataSet {
        ZroMetadataSet { zro_address }
    }

    #[test_only]
    public fun zro_metadata_locked(): ZroMetadataLocked {
        ZroMetadataLocked {}
    }

    // ================================================== Error Codes =================================================

    const EALREADY_INITIALIZED: u64 = 1;
    const EUNAUTHORIZED: u64 = 2;
    const EINVALID_ZRO_ADDRESS: u64 = 3;
    const ENO_CHANGE: u64 = 4;
    const EZRO_ADDRESS_NOT_SET: u64 = 5;
    const EZRO_ADDRESS_LOCKED: u64 = 6;
}
