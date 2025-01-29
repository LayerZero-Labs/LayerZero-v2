#[test_only]
module executor::executor_tests {
    use std::account::{create_account_for_test, create_signer_for_test};
    use std::event::was_event_emitted;
    use std::fungible_asset;
    use std::fungible_asset::Metadata;
    use std::object::address_to_object;
    use std::primary_fungible_store::ensure_primary_store_exists;

    use endpoint_v2_common::bytes32::{Self, from_bytes32};
    use endpoint_v2_common::native_token_test_helpers::mint_native_token_for_test;
    use executor::executor;
    use executor::executor::{get_fee_lib, native_drop, native_drop_applied_event};
    use executor::native_drop_params;
    use executor::native_drop_params::new_native_drop_params;
    use worker_common::worker_config;

    const EXECUTOR_FEE_LIB: address = @100000009;
    const PRICE_FEED_MODULE: address = @100000010;

    #[test]
    fun test_native_drop() {
        // initialize worker
        executor::init_module_for_test();
        executor::initialize(
            &create_account_for_test(@executor),
            @executor,
            @111111111,
            vector[@9999],
            vector[],
            EXECUTOR_FEE_LIB,
        );

        let params = vector[
            new_native_drop_params(@1111, 10),
            new_native_drop_params(@2222, 20),
            new_native_drop_params(@3333, 30),
        ];
        let fa = mint_native_token_for_test(1000);
        let metadata = address_to_object<Metadata>(@native_token_metadata_address);
        let admin_store = ensure_primary_store_exists(@9999, metadata);
        fungible_asset::deposit(admin_store, fa);

        let admin = &create_signer_for_test(@9999);
        native_drop(
            admin,
            10101,
            bytes32::from_bytes32(bytes32::from_address(@12345)),
            10,
            10202,
            @50000,
            native_drop_params::serialize_native_drop_params(params),
        );

        assert!(fungible_asset::balance(admin_store) == 940, 0);
        assert!(was_event_emitted(&native_drop_applied_event(
            10101, from_bytes32(bytes32::from_address(@12345)), 10, 10202, @50000, params)), 0);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EUNAUTHORIZED)]
    fun test_native_drop_fails_if_not_admin() {
        // initialize worker
        executor::init_module_for_test();
        executor::initialize(
            &create_account_for_test(@executor),
            @executor,
            @111111111,
            vector[@9999],
            vector[],
            EXECUTOR_FEE_LIB,
        );

        let params = vector[
            new_native_drop_params(@1111, 10),
            new_native_drop_params(@2222, 20),
            new_native_drop_params(@3333, 30),
        ];
        let fa = mint_native_token_for_test(1000);
        let metadata = address_to_object<Metadata>(@native_token_metadata_address);
        let admin_store = ensure_primary_store_exists(@9999, metadata);
        fungible_asset::deposit(admin_store, fa);

        let admin = &create_signer_for_test(@9900);
        native_drop(
            admin,
            10101,
            bytes32::from_bytes32(bytes32::from_address(@12345)),
            10,
            10202,
            @50000,
            native_drop_params::serialize_native_drop_params(params),
        );
    }

    #[test]
    #[expected_failure(abort_code = 0x10004, location = std::fungible_asset)]
    fun test_native_drop_fails_if_insufficient_balance() {
        // initialize worker
        executor::init_module_for_test();
        executor::initialize(
            &create_account_for_test(@executor),
            @executor,
            @111111111,
            vector[@9999],
            vector[],
            EXECUTOR_FEE_LIB,
        );

        let params = vector[
            new_native_drop_params(@1111, 10),
            new_native_drop_params(@2222, 20),
            new_native_drop_params(@3333, 30),
        ];
        let fa = mint_native_token_for_test(1);
        let metadata = address_to_object<Metadata>(@native_token_metadata_address);
        let admin_store = ensure_primary_store_exists(@9999, metadata);
        fungible_asset::deposit(admin_store, fa);

        let admin = &create_signer_for_test(@9999);
        native_drop(
            admin,
            10101,
            bytes32::from_bytes32(bytes32::from_address(@12345)),
            10,
            10202,
            @50000,
            native_drop_params::serialize_native_drop_params(params),
        );
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EUNAUTHORIZED)]
    fun test_set_price_feed_should_fail_if_not_admin() {
        // initialize worker
        executor::init_module_for_test();
        executor::initialize(
            &create_account_for_test(@executor),
            @executor,
            @111111111,
            vector[@9999],
            vector[],
            EXECUTOR_FEE_LIB,
        );

        let admin = &create_signer_for_test(@8888);
        executor::set_price_feed(admin, PRICE_FEED_MODULE, @1111);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EUNAUTHORIZED)]
    fun test_set_price_feed_delegate_should_fail_if_not_admin() {
        // initialize worker
        executor::init_module_for_test();
        executor::initialize(
            &create_account_for_test(@executor),
            @executor,
            @111111111,
            vector[@9999],
            vector[],
            EXECUTOR_FEE_LIB,
        );

        let admin = &create_signer_for_test(@8888);
        executor::set_price_feed_delegate(admin, PRICE_FEED_MODULE);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EUNAUTHORIZED)]
    fun test_set_allowlist_should_fail_if_not_admin() {
        // initialize worker
        executor::init_module_for_test();
        executor::initialize(
            &create_account_for_test(@executor),
            @executor,
            @111111111,
            vector[@9999],
            vector[],
            EXECUTOR_FEE_LIB,
        );

        let admin = &create_signer_for_test(@8888);
        executor::set_allowlist(admin, @1234, true);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EUNAUTHORIZED)]
    fun test_set_denylist_should_fail_is_not_admin() {
        // initialize worker
        executor::init_module_for_test();
        executor::initialize(
            &create_account_for_test(@executor),
            @executor,
            @111111111,
            vector[@9999],
            vector[],
            EXECUTOR_FEE_LIB,
        );

        let admin = &create_signer_for_test(@8888);
        executor::set_denylist(admin, @1234, true);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EUNAUTHORIZED)]
    fun test_set_supported_msglibs_should_fail_if_not_admin() {
        // initialize worker
        executor::init_module_for_test();
        executor::initialize(
            &create_account_for_test(@executor),
            @executor,
            @111111111,
            vector[@9999],
            vector[],
            EXECUTOR_FEE_LIB,
        );

        let admin = &create_signer_for_test(@8888);
        executor::set_supported_msglibs(admin, vector[@1234]);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EUNAUTHORIZED)]
    fun set_admin_should_fail_if_not_role_admin() {
        // initialize worker
        executor::init_module_for_test();
        executor::initialize(
            &create_account_for_test(@executor),
            @executor,
            @111111111,
            vector[@9999],
            vector[],
            EXECUTOR_FEE_LIB,
        );

        let admin = &create_signer_for_test(@9999);
        executor::set_admin(admin, @8888, true);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EUNAUTHORIZED)]
    fun set_role_admin_should_fail_if_not_role_admin() {
        // initialize worker
        executor::init_module_for_test();
        executor::initialize(
            &create_account_for_test(@executor),
            @executor,
            @111111111,
            vector[@9999],
            vector[],
            EXECUTOR_FEE_LIB,
        );

        let admin = &create_signer_for_test(@9999);
        executor::set_role_admin(admin, @8888, true);
    }

    #[test]
    fun set_fee_lib() {
        // initialize worker
        executor::init_module_for_test();
        executor::initialize(
            &create_account_for_test(@executor),
            @executor,
            @111111111,
            vector[@9999],
            vector[],
            EXECUTOR_FEE_LIB,
        );
        let fee_lib_from_worker_config = worker_config::get_worker_fee_lib(@executor);
        assert!(fee_lib_from_worker_config == EXECUTOR_FEE_LIB, 0);
        let fee_lib_from_executor = get_fee_lib();
        assert!(fee_lib_from_executor == EXECUTOR_FEE_LIB, 0);

        let admin = &create_signer_for_test(@9999);
        executor::set_fee_lib(admin, @1111);
        assert!(was_event_emitted(&worker_config::worker_fee_lib_updated_event(@executor, @1111)), 0);
        let fee_lib_from_worker_config = worker_config::get_worker_fee_lib(@executor);
        assert!(fee_lib_from_worker_config == @1111, 0);
        let fee_lib_from_executor = get_fee_lib();
        assert!(fee_lib_from_executor == @1111, 0);
    }
}
