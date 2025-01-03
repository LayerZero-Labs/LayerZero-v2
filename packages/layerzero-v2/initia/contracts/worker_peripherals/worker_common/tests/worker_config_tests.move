#[test_only]
module worker_common::worker_config_tests {
    use std::account;
    use std::event::was_event_emitted;
    use std::vector;

    use endpoint_v2_common::contract_identity::make_call_ref_for_test;
    use worker_common::worker_config::{
        Self,
        allowlist_contains,
        assert_allowed,
        assert_supported_msglib,
        denylist_contains,
        is_allowed,
        set_allowlist,
        set_denylist,
        WORKER_ID_EXECUTOR,
    };

    const WORKER: address = @123456;
    const DVN_WORKER_ID: u8 = 2;

    #[test]
    fun test_set_worker_pause() {
        let worker_address = @3001;
        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@111],
            vector[],
            @0xfee11b1,
        );
        // default state is unpaused
        assert!(!worker_config::is_worker_paused(worker_address), 0);

        assert!(!worker_config::is_worker_paused(worker_address), 0);
        worker_config::set_worker_pause(&make_call_ref_for_test(worker_address), true);
        assert!(was_event_emitted(&worker_config::paused_event(worker_address)), 0);
        assert!(!was_event_emitted(&worker_config::unpaused_event(worker_address)), 0);
        assert!(worker_config::is_worker_paused(worker_address), 0);

        worker_config::set_worker_pause(&make_call_ref_for_test(worker_address), false);
        assert!(was_event_emitted(&worker_config::unpaused_event(worker_address)), 0);
        assert!(!worker_config::is_worker_paused(worker_address), 0);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EPAUSE_STATUS_UNCHANGED)]
    fun test_set_pause_fails_if_no_state_change() {
        let worker_address = @3001;
        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@111],
            vector[],
            @0xfee11b1,
        );
        worker_config::set_worker_pause(&make_call_ref_for_test(worker_address), true);
        // fails on state change to the prior value
        worker_config::set_worker_pause(&make_call_ref_for_test(worker_address), true);
    }

    #[test]
    fun test_set_and_get_supported_msglibs() {
        let worker_address = @3001;
        let msglib1 = @1234;
        let msglib2 = @2345;
        let msglib3 = @3456;
        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@111],
            vector[msglib1, msglib2],
            @0xfee11b1,
        );

        let supported_msglibs = worker_config::get_supported_msglibs(worker_address);
        assert!(vector::contains(&supported_msglibs, &msglib1), 0);
        assert!(vector::contains(&supported_msglibs, &msglib2), 0);
        assert!(!vector::contains(&supported_msglibs, &msglib3), 0);
        assert_supported_msglib(worker_address, msglib1);
        assert_supported_msglib(worker_address, msglib2);

        worker_config::set_supported_msglibs(&make_call_ref_for_test(worker_address), vector[msglib1, msglib3]);
        let supported_msglibs = worker_config::get_supported_msglibs(worker_address);
        assert!(vector::contains(&supported_msglibs, &msglib1), 0);
        assert!(!vector::contains(&supported_msglibs, &msglib2), 0);
        assert!(vector::contains(&supported_msglibs, &msglib3), 0);
        assert_supported_msglib(worker_address, msglib1);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EWORKER_AUTH_UNSUPPORTED_MSGLIB)]
    fun test_assert_supported_msglib_fails_if_not_supported() {
        let worker_address = @3001;
        let msglib1 = @1234;
        let msglib2 = @2345;
        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@111],
            vector[msglib1],
            @0xfee11b1,
        );
        assert_supported_msglib(worker_address, msglib2);
    }

    #[test]
    fun test_get_and_set_deposit_address() {
        let worker_address = @3001;
        let deposit_address = @1234;
        account::create_account_for_test(deposit_address);

        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@111],
            vector[],
            @0xfee11b1,
        );
        // initializes to worker address
        assert!(worker_config::get_deposit_address(worker_address) == worker_address, 0);

        worker_config::set_deposit_address(&make_call_ref_for_test(worker_address), deposit_address);
        assert!(was_event_emitted(&worker_config::set_deposit_address_event(worker_address, deposit_address)), 0);
        let deposit_address_result = worker_config::get_deposit_address(worker_address);
        assert!(deposit_address == deposit_address_result, 0);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::ENOT_AN_ACCOUNT)]
    fun set_deposit_address_fails_if_invalid_account() {
        let worker_address = @3001;
        let deposit_address = @1234;
        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@111],
            vector[],
            @0xfee11b1,
        );

        // Attempt to set deposit address to an invalid account (expected failure)
        worker_config::set_deposit_address(&make_call_ref_for_test(worker_address), deposit_address);
    }

    #[test]
    fun test_set_and_get_price_feed() {
        let worker_address = @3001;
        let price_feed = @1234;
        let feed_address = @2345;
        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@111],
            vector[],
            @0xfee11b1,
        );

        worker_config::set_price_feed(&make_call_ref_for_test(worker_address), price_feed, feed_address);
        assert!(was_event_emitted(&worker_config::set_price_feed_event(worker_address, price_feed, feed_address)), 0);
        let (price_feed_result, feed_address_result) = worker_config::get_effective_price_feed(worker_address);
        assert!(price_feed == price_feed_result, 0);
        assert!(feed_address == feed_address_result, 0);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EWORKER_PRICE_FEED_NOT_CONFIGURED)]
    fun test_get_effective_price_feed_fails_if_not_configured() {
        let worker_address = @3001;
        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@111],
            vector[],
            @0xfee11b1,
        );

        worker_config::get_effective_price_feed(worker_address);
    }


    #[test]
    fun test_set_and_get_price_feed_delegate() {
        // register worker
        let first_worker_address = @3001;
        worker_common::worker_config::initialize_for_worker_test_only(
            first_worker_address,
            WORKER_ID_EXECUTOR(),
            first_worker_address,
            @0x501ead,
            vector[@111],
            vector[],
            @0xfee11b1,
        );

        // register delegate worker
        let second_worker_address = @3002;
        worker_common::worker_config::initialize_for_worker_test_only(
            second_worker_address,
            WORKER_ID_EXECUTOR(),
            second_worker_address,
            @0x501ead,
            vector[@111],
            vector[],
            @0xfee11b1,
        );

        // register third worker
        let third_worker_address = @3003;
        worker_common::worker_config::initialize_for_worker_test_only(
            third_worker_address,
            WORKER_ID_EXECUTOR(),
            third_worker_address,
            @0x501ead,
            vector[@111],
            vector[],
            @0xfee11b1,
        );

        // set price feed for second worker
        worker_config::set_price_feed(&make_call_ref_for_test(second_worker_address), @10002, @20002);
        assert!(was_event_emitted(&worker_config::set_price_feed_event(second_worker_address, @10002, @20002)), 0);
        let (price_feed_result, feed_address_result) = worker_config::get_effective_price_feed(second_worker_address);
        assert!(price_feed_result == @10002, 0);
        assert!(feed_address_result == @20002, 0);

        // delegate for the first worker not yet set
        let delegate_result = worker_config::get_price_feed_delegate(first_worker_address);
        assert!(delegate_result == @0x0, 0);
        let delegate_count = worker_config::get_count_price_feed_delegate_dependents(second_worker_address);
        assert!(delegate_count == 0, 0);

        // set delegate for first worker
        worker_config::set_price_feed_delegate(&make_call_ref_for_test(first_worker_address), second_worker_address);
        assert!(
            was_event_emitted(
                &worker_config::set_price_feed_delegate_event(first_worker_address, second_worker_address)
            ),
            0,
        );
        let delegate_result = worker_config::get_price_feed_delegate(first_worker_address);
        assert!(delegate_result == second_worker_address, 0);
        let delegate_count = worker_config::get_count_price_feed_delegate_dependents(second_worker_address);
        assert!(delegate_count == 1, 0);

        let (price_feed_result, feed_address_result) = worker_config::get_effective_price_feed(first_worker_address);
        assert!(price_feed_result == @10002, 0);
        assert!(feed_address_result == @20002, 0);

        // set the price feed for the first worker (should not override the delegate configuration)
        worker_config::set_price_feed(&make_call_ref_for_test(first_worker_address), @10001, @20001);
        assert!(was_event_emitted(&worker_config::set_price_feed_event(first_worker_address, @10001, @20001)), 0);
        let (price_feed_result, feed_address_result) = worker_config::get_effective_price_feed(first_worker_address);
        assert!(price_feed_result == @10002, 0);
        assert!(feed_address_result == @20002, 0);

        // have the third worker delegate to the first worker
        // the effective price feed should be the price feed of the first worker, not the price feed of the first
        // worker's delegate (no delegate chaining)
        worker_config::set_price_feed_delegate(&make_call_ref_for_test(third_worker_address), first_worker_address);
        assert!(
            was_event_emitted(
                &worker_config::set_price_feed_delegate_event(third_worker_address, first_worker_address)
            ),
            0,
        );
        let delegate_result = worker_config::get_price_feed_delegate(third_worker_address);
        assert!(delegate_result == first_worker_address, 0);

        let first_worker_delegate_count = worker_config::get_count_price_feed_delegate_dependents(first_worker_address);
        assert!(first_worker_delegate_count == 1, 0);
        let second_worker_delegate_count = worker_config::get_count_price_feed_delegate_dependents(
            second_worker_address,
        );
        assert!(second_worker_delegate_count == 1, 0);
        let third_worker_delegate_count = worker_config::get_count_price_feed_delegate_dependents(third_worker_address);
        assert!(third_worker_delegate_count == 0, 0);

        let (price_feed_result, feed_address_result) = worker_config::get_effective_price_feed(third_worker_address);
        assert!(price_feed_result == @10001, 0);
        assert!(feed_address_result == @20001, 0);

        // Set the third worker to delegate to the second worker (which will then have 2 delegates)
        worker_config::set_price_feed_delegate(&make_call_ref_for_test(third_worker_address), second_worker_address);
        assert!(
            was_event_emitted(
                &worker_config::set_price_feed_delegate_event(third_worker_address, second_worker_address)
            ),
            0,
        );
        let delegate_result = worker_config::get_price_feed_delegate(third_worker_address);
        assert!(delegate_result == second_worker_address, 0);

        let first_worker_delegate_count = worker_config::get_count_price_feed_delegate_dependents(first_worker_address);
        assert!(first_worker_delegate_count == 0, 0);
        let second_worker_delegate_count = worker_config::get_count_price_feed_delegate_dependents(
            second_worker_address,
        );
        assert!(second_worker_delegate_count == 2, 0);
        let third_worker_delegate_count = worker_config::get_count_price_feed_delegate_dependents(third_worker_address);
        assert!(third_worker_delegate_count == 0, 0);

        worker_config::set_price_feed(&make_call_ref_for_test(third_worker_address), @10003, @20003);

        // swap delegate of first to point to third (instead of second)
        worker_config::set_price_feed_delegate(&make_call_ref_for_test(first_worker_address), third_worker_address);
        assert!(
            was_event_emitted(
                &worker_config::set_price_feed_delegate_event(first_worker_address, third_worker_address)
            ),
            0,
        );
        let first_worker_delegate_count = worker_config::get_count_price_feed_delegate_dependents(first_worker_address);
        assert!(first_worker_delegate_count == 0, 0);
        let second_worker_delegate_count = worker_config::get_count_price_feed_delegate_dependents(
            second_worker_address,
        );
        assert!(second_worker_delegate_count == 1, 0);
        let third_worker_delegate_count = worker_config::get_count_price_feed_delegate_dependents(third_worker_address);
        assert!(third_worker_delegate_count == 1, 0);

        // remove the delegate
        worker_config::set_price_feed_delegate(&make_call_ref_for_test(first_worker_address), @0x0);
        assert!(was_event_emitted(&worker_config::set_price_feed_delegate_event(first_worker_address, @0x0)), 0);
        let delegate_result = worker_config::get_price_feed_delegate(first_worker_address);
        assert!(delegate_result == @0x0, 0);

        let first_worker_delegate_count = worker_config::get_count_price_feed_delegate_dependents(first_worker_address);
        assert!(first_worker_delegate_count == 0, 0);
        let second_worker_delegate_count = worker_config::get_count_price_feed_delegate_dependents(
            second_worker_address,
        );
        assert!(second_worker_delegate_count == 1, 0);
        let third_worker_delegate_count = worker_config::get_count_price_feed_delegate_dependents(third_worker_address);
        assert!(third_worker_delegate_count == 0, 0);

        // the effective price feed should be the price feed of the delegate worker should be unaffected
        let (price_feed_result, feed_address_result) = worker_config::get_effective_price_feed(second_worker_address);
        assert!(price_feed_result == @10002, 0);
        assert!(feed_address_result == @20002, 0);

        // the effective price feed should be the price feed of the worker should revert to its own
        let (price_feed_result, feed_address_result) = worker_config::get_effective_price_feed(first_worker_address);
        assert!(price_feed_result == @10001, 0);
        assert!(feed_address_result == @20001, 0);

        // the effective price feed should be the price feed of the send (delegate) worker should be unaffected
        let (price_feed_result, feed_address_result) = worker_config::get_effective_price_feed(third_worker_address);
        assert!(price_feed_result == @10002, 0);
        assert!(feed_address_result == @20002, 0);
    }


    #[test]
    fun test_is_worker_admin() {
        let admins = vector[@100, @200, @300];
        worker_config::initialize_for_worker_test_only(@0x1111, 1, @0x1111, @0x501ead, admins, vector[], @0xfee11b);
        assert!(worker_config::is_worker_admin(@0x1111, @100), 0);
        assert!(worker_config::is_worker_admin(@0x1111, @200), 1);
        assert!(worker_config::is_worker_admin(@0x1111, @300), 2);

        // Does not approve non-admin
        assert!(!worker_config::is_worker_admin(@0x1111, @11), 3);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config_store::EWORKER_NOT_REGISTERED)]
    fun test_is_worker_admin_fails_if_worker_not_initialized() {
        // Initialize one workerworker_config_store
        let admins = vector[@100, @200, @300];
        worker_config::initialize_for_worker_test_only(@0x1111, 1, @0x1111, @0x501ead, admins, vector[], @0xfee11b);

        // Attempt to check admin status of a different worker (expected failure)
        worker_config::is_worker_admin(@1112, @100);
    }

    #[test]
    fun test_assert_worker_admin_succeeds_if_is_admin() {
        let admins = vector[@100, @200, @300];
        worker_config::initialize_for_worker_test_only(@0x1111, 1, @0x1111, @0x501ead, admins, vector[], @0xfee11b);
        worker_config::assert_worker_admin(@0x1111, @100);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EUNAUTHORIZED)]
    fun test_assert_worker_admin_fails_if_not_admin() {
        let admins = vector[@100, @200, @300];
        worker_config::initialize_for_worker_test_only(@0x1111, 1, @0x1111, @0x501ead, admins, vector[], @0xfee11b);
        worker_config::assert_worker_admin(@0x1111, @150);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config_store::EWORKER_NOT_REGISTERED)]
    fun test_asset_worker_admin_fails_if_worker_not_registered() {
        let admins = vector[@100, @200, @300];
        worker_config::initialize_for_worker_test_only(@0x1111, 1, @0x1111, @0x501ead, admins, vector[], @0xfee11b);

        // different worker
        worker_config::assert_worker_admin(@2222, @100);
    }

    #[test]
    fun test_set_worker_admin_internal() {
        let admins = vector[@100, @200, @300];
        worker_config::initialize_for_worker_test_only(@0x1111, 1, @0x1111, @0x501ead, admins, vector[], @0xfee11b);

        // Add new admin
        worker_config::set_worker_admin(&make_call_ref_for_test(@0x1111), @400, true);
        assert!(was_event_emitted(&worker_config::set_worker_admin_event(@0x1111, @400, true)), 0);
        assert!(worker_config::is_worker_admin(@0x1111, @100), 0);
        assert!(worker_config::is_worker_admin(@0x1111, @400), 0);
        assert!(!worker_config::is_worker_admin(@0x1111, @500), 1);

        // Remove admin
        worker_config::set_worker_admin(&make_call_ref_for_test(@0x1111), @400, false);
        assert!(was_event_emitted(&worker_config::set_worker_admin_event(@0x1111, @400, false)), 0);
        assert!(worker_config::is_worker_admin(@0x1111, @100), 0);
        assert!(!worker_config::is_worker_admin(@0x1111, @400), 1);
        assert!(!worker_config::is_worker_admin(@0x1111, @500), 1);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config_store::EADMIN_ALREADY_EXISTS)]
    fun test_set_worker_admin_internal_fails_if_admin_already_exists() {
        let admins = vector[@100, @200, @300];
        worker_config::initialize_for_worker_test_only(@0x1111, 1, @0x1111, @0x501ead, admins, vector[], @0xfee11b);

        // Add new admin
        worker_config::set_worker_admin(&make_call_ref_for_test(@0x1111), @400, true);
        assert!(worker_config::is_worker_admin(@0x1111, @400), 0);

        // Attempt to add the same admin again (expected failure)
        worker_config::set_worker_admin(&make_call_ref_for_test(@0x1111), @400, true);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config_store::EADMIN_NOT_FOUND)]
    fun test_set_worker_admin_internal_fails_to_remove_an_admin_if_admin_not_found() {
        let admins = vector[@100, @200, @300];
        worker_config::initialize_for_worker_test_only(@0x1111, 1, @0x1111, @0x501ead, admins, vector[], @0xfee11b);

        // Attempt to remove non-existent admin (expected failure)
        worker_config::set_worker_admin(&make_call_ref_for_test(@0x1111), @400, false);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config_store::EATTEMPING_TO_REMOVE_ONLY_ADMIN)]
    fun test_set_worker_admin_internal_fails_to_remove_last_admin() {
        let admins = vector[@100];
        worker_config::initialize_for_worker_test_only(@0x1111, 1, @0x1111, @0x501ead, admins, vector[], @0xfee11b);

        // Attempt to remove last admin (expected failure)
        worker_config::set_worker_admin(&make_call_ref_for_test(@0x1111), @100, false);
    }

    #[test]
    fun test_set_worker_admin() {
        let admins = vector[@100, @200, @300];
        worker_config::initialize_for_worker_test_only(@0x1111, 1, @0x1111, @0x501ead, admins, vector[], @0xfee11b);
        assert!(worker_config::is_worker_admin(@0x1111, @100), 0);
        assert!(!worker_config::is_worker_admin(@0x1111, @400), 0);

        // Add new admin
        worker_config::set_worker_admin(&make_call_ref_for_test(@0x1111), @400, true);
        assert!(worker_config::is_worker_admin(@0x1111, @100), 0);
        assert!(worker_config::is_worker_admin(@0x1111, @400), 0);
        assert!(!worker_config::is_worker_admin(@0x1111, @500), 1);

        // Remove admins
        worker_config::set_worker_admin(&make_call_ref_for_test(@0x1111), @400, false);
        worker_config::set_worker_admin(&make_call_ref_for_test(@0x1111), @100, false);
        assert!(!worker_config::is_worker_admin(@0x1111, @100), 0);
        assert!(!worker_config::is_worker_admin(@0x1111, @400), 1);
        assert!(!worker_config::is_worker_admin(@0x1111, @500), 1);

        // Re-add admin
        worker_config::set_worker_admin(&make_call_ref_for_test(@0x1111), @400, true);
        assert!(!worker_config::is_worker_admin(@0x1111, @100), 0);
        assert!(worker_config::is_worker_admin(@0x1111, @400), 0);
        assert!(!worker_config::is_worker_admin(@0x1111, @500), 1);
    }

    #[test]
    fun test_set_worker_admin_with_call_ref() {
        let admins = vector[@100, @200, @300];
        worker_config::initialize_for_worker_test_only(@0x1111, 1, @0x1111, @0x501ead, admins, vector[], @0xfee11b);
        assert!(worker_config::is_worker_admin(@0x1111, @100), 0);
        assert!(!worker_config::is_worker_admin(@0x1111, @400), 0);

        // Add new admin
        worker_config::set_worker_admin(&make_call_ref_for_test(@0x1111), @400, true);
        assert!(worker_config::is_worker_admin(@0x1111, @100), 0);
        assert!(worker_config::is_worker_admin(@0x1111, @400), 0);
        assert!(!worker_config::is_worker_admin(@0x1111, @500), 1);

        // Remove admins
        worker_config::set_worker_admin(&make_call_ref_for_test(@0x1111), @400, false);
        worker_config::set_worker_admin(&make_call_ref_for_test(@0x1111), @100, false);
        assert!(!worker_config::is_worker_admin(@0x1111, @100), 0);
        assert!(!worker_config::is_worker_admin(@0x1111, @400), 1);
        assert!(!worker_config::is_worker_admin(@0x1111, @500), 1);

        // Readd admin
        worker_config::set_worker_admin(&make_call_ref_for_test(@0x1111), @400, true);
        assert!(!worker_config::is_worker_admin(@0x1111, @100), 0);
        assert!(worker_config::is_worker_admin(@0x1111, @400), 0);
        assert!(!worker_config::is_worker_admin(@0x1111, @500), 1);
    }

    #[test]
    fun test_set_worker_role_admin() {
        let admins = vector[@100, @200, @300];
        worker_config::initialize_for_worker_test_only(@0x1111, 1, @0x1111, @0x501ead, admins, vector[], @0xfee11b);
        assert!(!worker_config::is_worker_role_admin(@0x1111, @100), 0);
        assert!(worker_config::is_worker_role_admin(@0x1111, @0x501ead), 0);

        // Add new admin
        worker_config::set_worker_role_admin(&make_call_ref_for_test(@0x1111), @400, true);
        assert!(worker_config::is_worker_role_admin(@0x1111, @400), 0);
        assert!(worker_config::is_worker_role_admin(@0x1111, @0x501ead), 0);

        // Remove admins
        worker_config::set_worker_role_admin(&make_call_ref_for_test(@0x1111), @400, false);
        worker_config::set_worker_role_admin(&make_call_ref_for_test(@0x1111), @0x501ead, false);
        assert!(!worker_config::is_worker_role_admin(@0x1111, @400), 0);
        assert!(!worker_config::is_worker_role_admin(@0x1111, @0x501ead), 0);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config_store::EROLE_ADMIN_ALREADY_EXISTS)]
    fun test_set_worker_role_admin_fails_if_admin_already_exists() {
        let admins = vector[@100, @200, @300];
        worker_config::initialize_for_worker_test_only(@0x1111, 1, @0x1111, @0x501ead, admins, vector[], @0xfee11b);

        // Add new admin
        worker_config::set_worker_role_admin(&make_call_ref_for_test(@0x1111), @0x501ead, true);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config_store::EROLE_ADMIN_NOT_FOUND)]
    fun test_set_worker_role_admin_fails_to_remove_an_admin_if_admin_not_found() {
        let admins = vector[@100, @200, @300];
        worker_config::initialize_for_worker_test_only(@0x1111, 1, @0x1111, @0x501ead, admins, vector[], @0xfee11b);

        // Attempt to remove non-existent admin (expected failure)
        worker_config::set_worker_role_admin(&make_call_ref_for_test(@0x1111), @400, false);
    }

    #[test]
    fun test_set_allowlist() {
        let worker_address = @3001;
        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@1234, @2345],
            vector[],
            @0xfee11b1,
        );
        let alice = @1122;
        let bob = @3344;
        let carol = @5566;

        // add alice and bob to the allow list
        set_allowlist(&make_call_ref_for_test(worker_address), alice, true);
        set_allowlist(&make_call_ref_for_test(worker_address), bob, true);
        assert!(allowlist_contains(worker_address, alice), 0);
        assert!(allowlist_contains(worker_address, bob), 0);
        assert!(!allowlist_contains(worker_address, carol), 0);

        // remove alice from the allow list
        set_allowlist(&make_call_ref_for_test(worker_address), alice, false);
        assert!(!allowlist_contains(worker_address, alice), 0);
        assert!(allowlist_contains(worker_address, bob), 0);
        assert!(!allowlist_contains(worker_address, carol), 0);
    }

    #[test]
    fun test_set_denylist() {
        let worker_address = @3001;
        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@1234, @2345],
            vector[],
            @0xfee11b1,
        );
        let alice = @1122;
        let bob = @3344;
        let carol = @5566;

        // add alice and bob to the deny list
        set_denylist(&make_call_ref_for_test(worker_address), alice, true);
        set_denylist(&make_call_ref_for_test(worker_address), bob, true);
        assert!(denylist_contains(worker_address, alice), 0);
        assert!(denylist_contains(worker_address, bob), 0);
        assert!(!denylist_contains(worker_address, carol), 0);

        // remove alice from the deny list
        set_denylist(&make_call_ref_for_test(worker_address), alice, false);
        assert!(!denylist_contains(worker_address, alice), 0);
        assert!(denylist_contains(worker_address, bob), 0);
        assert!(!denylist_contains(worker_address, carol), 0);
    }

    #[test]
    fun test_is_allowed() {
        let worker_address = @3001;
        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@1234, @2345],
            vector[],
            @0xfee11b1,
        );
        let alice = @1122;
        let bob = @3344;
        let carol = @5566;


        // add carol to the deny list, then assert that alice and bob are allowed
        set_denylist(&make_call_ref_for_test(worker_address), carol, true);
        assert_allowed(worker_address, alice);
        assert_allowed(worker_address, bob);
        assert!(!is_allowed(worker_address, carol), 0);

        // add alice to the allow list, then assert that alice is allowed and bob is not
        set_allowlist(&make_call_ref_for_test(worker_address), alice, true);
        assert_allowed(worker_address, alice);
        assert!(!is_allowed(worker_address, bob), 0);

        // add bob to the allow list, then assert that alice and bob are allowed
        set_allowlist(&make_call_ref_for_test(worker_address), bob, true);
        assert_allowed(worker_address, alice);
        assert_allowed(worker_address, bob);

        // add bob to the deny list, then assert that bob is not allowed even though he was on allow list
        set_denylist(&make_call_ref_for_test(worker_address), bob, true);
        assert_allowed(worker_address, alice);
        assert!(!is_allowed(worker_address, bob), 0);
        assert!(!is_allowed(worker_address, carol), 0);

        // remove all from lists, then assert that all are allowed
        set_allowlist(&make_call_ref_for_test(worker_address), alice, false);
        set_allowlist(&make_call_ref_for_test(worker_address), bob, false);
        set_denylist(&make_call_ref_for_test(worker_address), bob, false);
        set_denylist(&make_call_ref_for_test(worker_address), carol, false);
        assert_allowed(worker_address, alice);
        assert_allowed(worker_address, bob);
        assert_allowed(worker_address, carol);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::ESENDER_DENIED)]
    fun test_assert_allowed_fails_if_denied() {
        let worker_address = @3001;
        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@1234, @2345],
            vector[],
            @0xfee11b1,
        );
        let carol = @5566;

        // add carol to the deny list, then assert that alice and bob are allowed
        set_denylist(&make_call_ref_for_test(worker_address), carol, true);
        assert_allowed(worker_address, carol);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::ESENDER_DENIED)]
    fun test_assert_allowed_fails_if_not_in_an_existing_allowlist() {
        let worker_address = @3001;
        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@1234, @2345],
            vector[],
            @0xfee11b1,
        );
        let alice = @1122;
        let bob = @3344;
        let carol = @5566;
        set_denylist(&make_call_ref_for_test(worker_address), bob, true);
        set_allowlist(&make_call_ref_for_test(worker_address), carol, true);

        // Since an allowlist exists, Alice must be on the allowlist to be authorized
        assert_allowed(worker_address, alice);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config_store::EWORKER_ALREADY_ON_ALLOWLIST)]
    fun test_set_allowlist_fails_if_already_on_allowlist() {
        let worker_address = @3001;
        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@1234, @2345],
            vector[],
            @0xfee11b1,
        );
        let alice = @1122;
        set_allowlist(&make_call_ref_for_test(worker_address), alice, true);
        set_allowlist(&make_call_ref_for_test(worker_address), alice, true);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config_store::EWORKER_ALREADY_ON_DENYLIST)]
    fun test_set_denylist_fails_if_already_on_denylist() {
        let worker_address = @3001;
        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@1234, @2345],
            vector[],
            @0xfee11b1,
        );
        let alice = @1122;
        set_denylist(&make_call_ref_for_test(worker_address), alice, true);
        set_denylist(&make_call_ref_for_test(worker_address), alice, true);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config_store::EWORKER_NOT_ON_ALLOWLIST)]
    fun test_set_allowlist_fails_if_not_on_allowlist() {
        let worker_address = @3001;
        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@1234, @2345],
            vector[],
            @0xfee11b1,
        );
        let alice = @1122;
        set_allowlist(&make_call_ref_for_test(worker_address), alice, false);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config_store::EWORKER_NOT_ON_DENYLIST)]
    fun test_set_denylist_fails_if_not_on_denylist() {
        let worker_address = @3001;
        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@1234, @2345],
            vector[],
            @0xfee11b1,
        );
        let alice = @1122;
        set_denylist(&make_call_ref_for_test(worker_address), alice, false);
    }

    #[test]
    fun test_set_worker_fee_lib() {
        let worker_address = @3001;
        let fee_lib = @1234;
        worker_common::worker_config::initialize_for_worker_test_only(
            worker_address,
            WORKER_ID_EXECUTOR(),
            worker_address,
            @0x501ead,
            vector[@1234, @2345],
            vector[],
            @0xfee11b1,
        );

        worker_config::set_worker_fee_lib(&make_call_ref_for_test(worker_address), fee_lib);
        assert!(was_event_emitted(&worker_config::worker_fee_lib_updated_event(worker_address, fee_lib)), 0);
        let fee_lib_result = worker_config::get_worker_fee_lib(worker_address);
        assert!(fee_lib == fee_lib_result, 0);
    }
}
