#[test_only]
module worker_common::worker_config_store_tests {
    use std::account::create_signer_for_test;

    use worker_common::worker_config_store;

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config_store::ENO_ADMINS_PROVIDED)]
    fun test_initialize_for_worker_fails_if_no_admins_provided() {
        let account = &create_signer_for_test(@0x1111);
        worker_config_store::initialize_store_for_worker(account, 1, @0x1111, @0xdefad, vector[], vector[], @0xfee11b);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config_store::EWORKER_ALREADY_INITIALIZED)]
    fun test_initialize_for_worker_fails_if_already_initialized() {
        let account = &create_signer_for_test(@0x1111);
        worker_config_store::initialize_store_for_worker(
            account,
            1,
            @0xdefad,
            @0x1111,
            vector[@100],
            vector[],
            @0xfee11b,
        );
        worker_config_store::initialize_store_for_worker(
            account,
            1,
            @0xdefad,
            @0x1111,
            vector[@200],
            vector[],
            @0xfee11b,
        );
    }
}
