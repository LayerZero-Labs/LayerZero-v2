#[test_only]
module endpoint_v2::msglib_manager_tests {
    use std::account::create_signer_for_test;
    use std::event::was_event_emitted;
    use std::string;
    use std::timestamp;

    use endpoint_v2::endpoint::{get_effective_send_library, get_registered_libraries, is_registered_library};
    use endpoint_v2::msglib_manager::{
        default_receive_library_set_event,
        default_receive_library_timeout_set_event,
        default_send_library_set_event,
        get_default_receive_library,
        get_default_send_library,
        get_effective_receive_library,
        is_valid_receive_library_for_oapp,
        library_registered_event,
        matches_default_receive_library,
        receive_library_set_event,
        receive_library_timeout_set_event,
        register_library,
        send_library_set_event,
        set_default_receive_library,
        set_default_receive_library_timeout,
        set_default_send_library,
        set_receive_library,
        set_receive_library_timeout,
        set_send_library,
    };
    use endpoint_v2::store;
    use endpoint_v2::timeout;
    use endpoint_v2::timeout_test_helpers::{Self, set_block_height};
    use uln_302::configuration_tests::enable_receive_eid_for_test;

    const OAPP_ADDRESS: address = @0x1234;

    #[test_only]
    /// Initialize the test environment
    fun init_for_test() {
        let native_framework = &create_signer_for_test(@std);
        // start the clock
        timestamp::set_time_has_started_for_testing(native_framework);
        timeout_test_helpers::setup_for_timeouts();
        // initialize
        endpoint_v2_common::universal_config::init_module_for_test(100);
        store::init_module_for_test();
        // register some libraries
        register_library(@blocked_msglib);
        register_library(@simple_msglib);
        register_library(@uln_302);
        uln_302::msglib::initialize_for_test();// register an OApp
        store::register_oapp(OAPP_ADDRESS, string::utf8(b"test"));
    }

    // ================================================= Registration =================================================

    #[test]
    fun test_register_library() {
        store::init_module_for_test();

        // Register a new library
        register_library(@blocked_msglib);
        assert!(was_event_emitted(&library_registered_event(@blocked_msglib)), 2);
        assert!(is_registered_library(@blocked_msglib), 0);
        assert!(!is_registered_library(@simple_msglib), 1);

        // Register another library
        register_library(@simple_msglib);
        assert!(was_event_emitted(&library_registered_event(@simple_msglib)), 2);
        assert!(is_registered_library(@blocked_msglib), 3);
        assert!(is_registered_library(@simple_msglib), 4);

        let msglibs = get_registered_libraries(0, 10);
        assert!(msglibs == vector[@blocked_msglib, @simple_msglib], 5);

        let msglibs = get_registered_libraries(0, 1);
        assert!(msglibs == vector[@blocked_msglib], 6);

        let msglibs = get_registered_libraries(1, 5);
        assert!(msglibs == vector[@simple_msglib], 7);

        let msglibs = get_registered_libraries(4, 5);
        assert!(msglibs == vector[], 8);

        let msglibs = get_registered_libraries(1, 0);
        assert!(msglibs == vector[], 8);
    }

    #[test]
    #[expected_failure(abort_code = router_node_1::router_node::ENOT_IMPLEMENTED)]
    fun test_register_library_fails_if_unroutable() {
        store::init_module_for_test();

        // Register an unroutable library
        register_library(@0x9874123);
    }

    // ================================================ Send Libraries ================================================

    #[test]
    fun test_set_default_send_library() {
        init_for_test();
        let dst_eid = 1;

        // Set the default send library
        set_default_send_library(dst_eid, @blocked_msglib);
        assert!(was_event_emitted(&default_send_library_set_event(dst_eid, @blocked_msglib)), 1);
        assert!(store::get_default_send_library(dst_eid) == @blocked_msglib, 0);

        // Update the default send library
        set_default_send_library(dst_eid, @simple_msglib);
        assert!(was_event_emitted(&default_send_library_set_event(dst_eid, @simple_msglib)), 2);
        assert!(store::get_default_send_library(dst_eid) == @simple_msglib, 1);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EATTEMPTED_TO_SET_CURRENT_LIBRARY)]
    fun test_set_default_send_library_fails_if_setting_to_current_value() {
        init_for_test();
        let dst_eid = 1;

        // Set the default send library twice to same value
        set_default_send_library(dst_eid, @blocked_msglib);
        set_default_send_library(dst_eid, @blocked_msglib);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EUNREGISTERED_MSGLIB)]
    fun test_set_default_send_library_fails_if_library_not_registered() {
        store::init_module_for_test();
        register_library(@blocked_msglib);

        // Set the default send library to an unregistered library
        set_default_send_library(1, @simple_msglib);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EUNSUPPORTED_DST_EID)]
    fun test_set_default_send_library_fails_if_library_does_not_support_eid() {
        init_for_test();
        let dst_eid = 1;
        // only enable receive side, not send side
        uln_302::configuration_tests::enable_receive_eid_for_test(dst_eid);

        // Set the default send library to a library that does not support the EID
        set_default_send_library(dst_eid, @uln_302);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EUNREGISTERED_MSGLIB)]
    fun test_set_default_send_library_fails_if_attempting_to_unset() {
        init_for_test();

        // Attempt to unset
        set_default_send_library(1, @0x0);
    }

    #[test]
    fun test_set_send_library() {
        init_for_test();
        let dst_eid = 1;
        uln_302::configuration_tests::enable_send_eid_for_test(dst_eid);

        // Set the default send library
        set_default_send_library(dst_eid, @blocked_msglib);
        assert!(was_event_emitted(&default_send_library_set_event(dst_eid, @blocked_msglib)), 3);
        assert!(get_default_send_library(dst_eid) == @blocked_msglib, 0);
        let (lib, is_default) = get_effective_send_library(OAPP_ADDRESS, dst_eid);
        assert!(lib == @blocked_msglib, 1);
        assert!(is_default, 2);

        // Set the OApp send library
        set_send_library(OAPP_ADDRESS, dst_eid, @simple_msglib);
        assert!(was_event_emitted(&send_library_set_event(OAPP_ADDRESS, dst_eid, @simple_msglib)), 4);
        let (lib, is_default) = get_effective_send_library(OAPP_ADDRESS, dst_eid);
        assert!(lib == @simple_msglib, 3);
        assert!(!is_default, 4);

        // Update the OApp send library
        set_send_library(OAPP_ADDRESS, dst_eid, @uln_302);
        assert!(was_event_emitted(&send_library_set_event(OAPP_ADDRESS, dst_eid, @uln_302)), 7);
        let (lib, is_default) = get_effective_send_library(OAPP_ADDRESS, dst_eid);
        assert!(lib == @uln_302, 5);
        assert!(!is_default, 6);

        // Unset the OApp send library
        set_send_library(OAPP_ADDRESS, dst_eid, @0x0);
        assert!(was_event_emitted(&send_library_set_event(OAPP_ADDRESS, dst_eid, @0x0)), 9);
        let (lib, is_default) = get_effective_send_library(OAPP_ADDRESS, dst_eid);
        assert!(lib == @blocked_msglib, 7);
        assert!(is_default, 8);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EUNREGISTERED_MSGLIB)]
    fun test_set_send_library_fails_if_library_not_registered() {
        store::init_module_for_test();
        register_library(@blocked_msglib);

        // Set the OApp send library to an unregistered library
        set_send_library(OAPP_ADDRESS, 1, @simple_msglib);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EATTEMPTED_TO_SET_CURRENT_LIBRARY)]
    fun test_set_send_library_fails_if_setting_to_current_value() {
        init_for_test();
        let dst_eid = 1;
        set_default_send_library(dst_eid, @simple_msglib);

        // Set the OApp send library twice to same value
        set_send_library(OAPP_ADDRESS, dst_eid, @simple_msglib);
        set_send_library(OAPP_ADDRESS, dst_eid, @simple_msglib);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EUNSUPPORTED_DST_EID)]
    fun test_set_send_library_fails_if_library_does_not_support_eid() {
        init_for_test();
        let dst_eid = 1;
        // only enable receive side, not send side
        uln_302::configuration_tests::enable_receive_eid_for_test(dst_eid);

        // Set the OApp send library to a library that does not support the EID
        set_send_library(OAPP_ADDRESS, dst_eid, @uln_302);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EOAPP_SEND_LIB_NOT_SET)]
    fun test_set_send_library_fails_if_trying_to_unset_library_that_isnt_set() {
        init_for_test();
        let dst_eid = 1;

        // Attempt to unset without having already set
        set_send_library(OAPP_ADDRESS, dst_eid, @0x0);
    }

    // Requires Manual Verification:
    // * set_default_send_library_fails_if_attempting_to_set_to_receive_only_library
    // * set_send_library_fails_if_attempting_to_set_to_receive_only_library

    // =============================================== Receive Libraries ==============================================

    #[test]
    fun test_set_default_receive_library() {
        init_for_test();
        let src_eid = 1;

        // Set the default receive library
        set_default_receive_library(src_eid, @blocked_msglib, 0);
        assert!(was_event_emitted(&default_receive_library_set_event(src_eid, @blocked_msglib)), 0);
        assert!(get_default_receive_library(src_eid) == @blocked_msglib, 0);
        assert!(matches_default_receive_library(src_eid, @blocked_msglib), 0);

        // Update the default receive library (no timeout)
        set_default_receive_library(src_eid, @simple_msglib, 0);
        assert!(was_event_emitted(&default_receive_library_set_event(src_eid, @simple_msglib)), 1);
        assert!(get_default_receive_library(src_eid) == @simple_msglib, 1);
        assert!(matches_default_receive_library(src_eid, @simple_msglib), 0);
        assert!(!matches_default_receive_library(src_eid, @blocked_msglib), 0);

        // Update the default receive library (with timeout)
        enable_receive_eid_for_test(src_eid);
        set_default_receive_library(src_eid, @uln_302, 10);
        assert!(was_event_emitted(&default_receive_library_set_event(src_eid, @uln_302)), 2);
        assert!(was_event_emitted(&default_receive_library_timeout_set_event(src_eid, @simple_msglib, 10)), 3);
        assert!(get_default_receive_library(src_eid) == @uln_302, 2);
        // matches both
        assert!(matches_default_receive_library(src_eid, @simple_msglib), 1);
        assert!(matches_default_receive_library(src_eid, @uln_302), 1);

        // Update the default receive library (no timeout)
        set_default_receive_library(src_eid, @blocked_msglib, 0);
        assert!(was_event_emitted(&default_receive_library_set_event(src_eid, @blocked_msglib)), 4);
        assert!(was_event_emitted(&default_receive_library_timeout_set_event(src_eid, @0x0, 0)), 5);
        assert!(get_default_receive_library(src_eid) == @blocked_msglib, 3);
        // does not preserve old timemout library or prior library
        assert!(matches_default_receive_library(src_eid, @blocked_msglib), 2);
        assert!(!matches_default_receive_library(src_eid, @simple_msglib), 2);
        assert!(!matches_default_receive_library(src_eid, @uln_302), 2);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EUNREGISTERED_MSGLIB)]
    fun test_set_default_receive_libraries_fails_if_not_registered() {
        store::init_module_for_test();
        register_library(@blocked_msglib);

        // Set the default receive library to an unregistered library
        set_default_receive_library(1, @simple_msglib, 0);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EATTEMPTED_TO_SET_CURRENT_LIBRARY)]
    fun test_set_default_receive_libraries_fails_if_setting_to_current_value() {
        init_for_test();
        let src_eid = 1;

        // Set the default receive library twice to same value
        set_default_receive_library(src_eid, @simple_msglib, 0);
        set_default_receive_library(src_eid, @simple_msglib, 0);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EUNSUPPORTED_SRC_EID)]
    fun test_set_default_receive_libraries_fails_if_library_does_not_support_eid() {
        init_for_test();
        let src_eid = 1;
        // only enable send side, not receive side
        uln_302::configuration_tests::enable_send_eid_for_test(src_eid);

        // Set the default receive library to a library that does not support the EID
        set_default_receive_library(src_eid, @uln_302, 0);
    }

    #[test]
    fun test_set_receive_library() {
        init_for_test();

        // Set the OApp receive library
        set_default_receive_library(1, @blocked_msglib, 0);
        let (lib, is_default) = get_effective_receive_library(OAPP_ADDRESS, 1);
        assert!(lib == @blocked_msglib, 0);
        assert!(is_default, 0);

        set_receive_library(OAPP_ADDRESS, 1, @simple_msglib, 0);
        assert!(was_event_emitted(&receive_library_set_event(OAPP_ADDRESS, 1, @simple_msglib)), 0);
        assert!(was_event_emitted(&receive_library_timeout_set_event(OAPP_ADDRESS, 1, @0x0, 0)), 4);
        let (lib, is_default) = get_effective_receive_library(OAPP_ADDRESS, 1);
        assert!(lib == @simple_msglib, 0);
        assert!(!is_default, 0);

        // Use a timeout
        set_receive_library(OAPP_ADDRESS, 1, @blocked_msglib, 10);
        assert!(was_event_emitted(&receive_library_set_event(OAPP_ADDRESS, 1, @blocked_msglib)), 1);
        assert!(was_event_emitted(&receive_library_timeout_set_event(OAPP_ADDRESS, 1, @simple_msglib, 10)), 2);
        let (lib, is_default) = get_effective_receive_library(OAPP_ADDRESS, 1);
        assert!(lib == @blocked_msglib, 0);
        assert!(!is_default, 0);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @simple_msglib), 0);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @blocked_msglib), 0);

        // Setting without a timeout removes the old timeout
        uln_302::configuration_tests::enable_receive_eid_for_test(1);
        set_receive_library(OAPP_ADDRESS, 1, @uln_302, 0);
        assert!(was_event_emitted(&receive_library_set_event(OAPP_ADDRESS, 1, @uln_302)), 3);
        assert!(was_event_emitted(&receive_library_timeout_set_event(OAPP_ADDRESS, 1, @blocked_msglib, 0)), 4);
        let (lib, is_default) = get_effective_receive_library(OAPP_ADDRESS, 1);
        assert!(lib == @uln_302, 0);
        assert!(!is_default, 0);
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @simple_msglib), 0);
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @blocked_msglib), 0);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @uln_302), 0);

        // Setting with timeout
        set_receive_library(OAPP_ADDRESS, 1, @simple_msglib, 10);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @uln_302), 0);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @simple_msglib), 0);

        // Unsetting removes the timeout also
        set_receive_library(OAPP_ADDRESS, 1, @0x0, 0);
        assert!(was_event_emitted(&receive_library_set_event(OAPP_ADDRESS, 1, @0x0)), 5);
        assert!(was_event_emitted(&receive_library_timeout_set_event(OAPP_ADDRESS, 1, @simple_msglib, 0)), 6);
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @uln_302), 0);
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @simple_msglib), 0);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EUNREGISTERED_MSGLIB)]
    fun test_set_receive_library_fails_if_not_registered() {
        store::init_module_for_test();
        register_library(@blocked_msglib);

        // Set the OApp receive library to an unregistered library
        set_receive_library(OAPP_ADDRESS, 1, @simple_msglib, 0);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EATTEMPTED_TO_SET_CURRENT_LIBRARY)]
    fun test_set_receive_library_fails_if_setting_to_current_value() {
        init_for_test();
        let src_eid = 1;
        set_default_receive_library(src_eid, @simple_msglib, 0);

        // Set the OApp receive library twice to same value
        set_receive_library(OAPP_ADDRESS, src_eid, @simple_msglib, 0);
        set_receive_library(OAPP_ADDRESS, src_eid, @simple_msglib, 0);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EUNSUPPORTED_SRC_EID)]
    fun test_set_receive_library_fails_if_library_does_not_support_eid() {
        init_for_test();
        let src_eid = 1;
        // only enable send side, not receive side
        uln_302::configuration_tests::enable_send_eid_for_test(src_eid);

        // Set the OApp receive library to a library that does not support the EID
        // Note this would fail in either case, because the default is not set (and could not be set, because it would
        // fail for the same reason)
        set_receive_library(OAPP_ADDRESS, src_eid, @uln_302, 0);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::ERECEIVE_LIB_NOT_SET)]
    fun test_set_receive_library_fails_if_trying_to_unset_library_that_is_not_set() {
        init_for_test();
        let src_eid = 1;
        set_default_receive_library(src_eid, @simple_msglib, 0);

        // Attempt to unset without having already set
        set_receive_library(OAPP_ADDRESS, src_eid, @0x0, 0);
    }

    #[test]
    #[expected_failure(
        abort_code = endpoint_v2::msglib_manager::ECANNOT_SET_GRACE_PERIOD_ON_RECEIVE_LIBRARY_UNSET
    )]
    fun test_set_receive_library_aborts_if_provided_a_grace_period_time_for_unset() {
        init_for_test();
        let src_eid = 1;
        set_default_receive_library(src_eid, @simple_msglib, 0);

        set_receive_library(OAPP_ADDRESS, src_eid, @simple_msglib, 0);

        // Attempt to unset with a grace period
        set_receive_library(OAPP_ADDRESS, src_eid, @0x0, 10);
    }

    #[test]
    fun test_matches_default_receive_library() {
        init_for_test();

        let src_eid = 2;
        uln_302::configuration_tests::enable_receive_eid_for_test(src_eid);
        set_default_receive_library(src_eid, @simple_msglib, 0);
        assert!(was_event_emitted(&default_receive_library_set_event(src_eid, @simple_msglib)), 0);

        // No OApp specific config set
        assert!(matches_default_receive_library(src_eid, @simple_msglib), 0);

        // Update default without grace period
        set_default_receive_library(src_eid, @uln_302, 0);
        assert!(was_event_emitted(&default_receive_library_set_event(src_eid, @uln_302)), 1);
        assert!(!matches_default_receive_library(src_eid, @simple_msglib), 1);
        assert!(matches_default_receive_library(src_eid, @uln_302), 2);

        // Update default with grace period
        set_default_receive_library(src_eid, @blocked_msglib, 10);
        assert!(was_event_emitted(&default_receive_library_set_event(src_eid, @blocked_msglib)), 2);
        assert!(was_event_emitted(&default_receive_library_timeout_set_event(src_eid, @uln_302, 10)), 3);
        set_block_height(9);
        assert!(matches_default_receive_library(src_eid, @uln_302), 3);
        assert!(matches_default_receive_library(src_eid, @blocked_msglib), 4);

        // Grace period expired
        set_block_height(11);
        assert!(!matches_default_receive_library(src_eid, @uln_302), 5);
        assert!(matches_default_receive_library(src_eid, @blocked_msglib), 6);
    }

    #[test]
    fun test_is_valid_receive_library() {
        init_for_test();
        uln_302::configuration_tests::enable_receive_eid_for_test(1);

        set_default_receive_library(1, @blocked_msglib, 0);
        assert!(was_event_emitted(&default_receive_library_set_event(1, @blocked_msglib)), 0);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @blocked_msglib), 0);

        // Set a new library for the OApp - if there is no grace period, the other is immediately invalid
        set_receive_library(OAPP_ADDRESS, 1, @simple_msglib, 0);
        assert!(was_event_emitted(&receive_library_set_event(OAPP_ADDRESS, 1, @simple_msglib)), 1);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @simple_msglib), 0);
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @blocked_msglib), 0);

        // Updating with a grace period, leaves the prior one valid up to the grace period end time
        set_receive_library(OAPP_ADDRESS, 1, @uln_302, 10);
        assert!(was_event_emitted(&receive_library_set_event(OAPP_ADDRESS, 1, @uln_302)), 2);
        assert!(was_event_emitted(&receive_library_timeout_set_event(OAPP_ADDRESS, 1, @simple_msglib, 10)), 3);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @uln_302), 0);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @simple_msglib), 0);
        set_block_height(9);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @uln_302), 0);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @simple_msglib), 0);

        // After the grace period, only the new library is valid
        set_block_height(10);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @uln_302), 0);
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @simple_msglib), 0);

        // Unsetting for oapp
        set_receive_library(OAPP_ADDRESS, 1, @0x0, 0);
        assert!(was_event_emitted(&receive_library_set_event(OAPP_ADDRESS, 1, @0x0)), 4);
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @uln_302), 0);  // prior immediately invalid
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @blocked_msglib), 0);  // default also valid

        // Set again
        set_receive_library(OAPP_ADDRESS, 1, @uln_302, 0);
        assert!(was_event_emitted(&receive_library_set_event(OAPP_ADDRESS, 1, @uln_302)), 5);
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @blocked_msglib), 0);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @uln_302), 0);

        // Unset again
        set_receive_library(OAPP_ADDRESS, 1, @0x0, 0);
        assert!(was_event_emitted(&receive_library_set_event(OAPP_ADDRESS, 1, @0x0)), 6);
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @uln_302), 0);  // prior not valid
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, 1, @blocked_msglib), 0);  // default valid
    }

    #[test]
    fun test_set_default_receive_library_timeout() {
        init_for_test();

        let src_eid = 2;
        uln_302::configuration_tests::enable_receive_eid_for_test(src_eid);

        // t = 0 blocks
        set_default_receive_library(src_eid, @blocked_msglib, 0);
        assert!(was_event_emitted(&default_receive_library_set_event(src_eid, @blocked_msglib)), 0);
        assert!(was_event_emitted(&default_receive_library_timeout_set_event(src_eid, @0x0, 0)), 3);

        // Set the grace period to 10 blocks
        set_default_receive_library(src_eid, @simple_msglib, 10);
        assert!(was_event_emitted(&default_receive_library_set_event(src_eid, @simple_msglib)), 1);

        // Grace period should be active
        assert!(matches_default_receive_library(src_eid, @blocked_msglib), 0);
        assert!(matches_default_receive_library(src_eid, @simple_msglib), 1);
        let grace_period_config = store::get_default_receive_library_timeout(src_eid);
        assert!(timeout::is_active(&grace_period_config), 2);

        // Reset the expiry to 20 blocks
        set_default_receive_library_timeout(src_eid, @blocked_msglib, 20);
        assert!(was_event_emitted(&default_receive_library_timeout_set_event(src_eid, @blocked_msglib, 20)), 3);
        assert!(matches_default_receive_library(src_eid, @blocked_msglib), 2);
        assert!(matches_default_receive_library(src_eid, @simple_msglib), 3);
        grace_period_config = store::get_default_receive_library_timeout(src_eid);
        assert!(timeout::is_active(&grace_period_config), 2);

        // t = 19 blocks: grace period should still be active
        set_block_height(19);
        assert!(matches_default_receive_library(src_eid, @blocked_msglib), 4);
        assert!(matches_default_receive_library(src_eid, @simple_msglib), 5);
        let grace_period_config = store::get_default_receive_library_timeout(src_eid);
        assert!(timeout::is_active(&grace_period_config), 2);

        // t = 20 blocks (at the expiry): grace period should be expired
        set_block_height(21);
        assert!(!matches_default_receive_library(src_eid, @blocked_msglib), 6);
        assert!(matches_default_receive_library(src_eid, @simple_msglib), 7);
        let grace_period_config = store::get_default_receive_library_timeout(src_eid);
        assert!(!timeout::is_active(&grace_period_config), 8);

        // Adding timeout at any point can revive the grace period and the fallback can be updated to any library
        set_block_height(100);
        set_default_receive_library_timeout(src_eid, @uln_302, 101);
        assert!(was_event_emitted(&default_receive_library_timeout_set_event(src_eid, @uln_302, 101)), 9);
        assert!(matches_default_receive_library(src_eid, @uln_302), 9);
        assert!(matches_default_receive_library(src_eid, @simple_msglib), 10);
        let grace_period_config = store::get_default_receive_library_timeout(src_eid);
        assert!(timeout::is_active(&grace_period_config), 11);

        // After the timeout ends, the fallback should be invlid
        set_block_height(1002);
        assert!(!matches_default_receive_library(src_eid, @uln_302), 12);
        assert!(matches_default_receive_library(src_eid, @simple_msglib), 13);
        let grace_period_config = store::get_default_receive_library_timeout(src_eid);
        assert!(!timeout::is_active(&grace_period_config), 14);

        // Clear the grace period config
        // This should not fail despite the lib being unknown
        set_default_receive_library_timeout(src_eid, @0x9999, 0);
        assert!(was_event_emitted(&default_receive_library_timeout_set_event(src_eid, @0x9999, 0)), 15);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EEXPIRY_IS_IN_PAST)]
    fun test_set_default_receive_library_timeout_fails_if_in_the_past() {
        init_for_test();
        let src_eid = 2;
        uln_302::configuration_tests::enable_receive_eid_for_test(src_eid);
        set_default_receive_library(src_eid, @simple_msglib, 0);

        set_block_height(20);

        // Attempt to set a grace period that is in the past
        set_default_receive_library_timeout(src_eid, @simple_msglib, 10);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EUNSUPPORTED_SRC_EID)]
    fun test_set_default_receive_library_timeout_fails_if_msglib_doesnt_support_eid() {
        init_for_test();
        let src_eid = 2;
        // only enable send side, not receive side
        uln_302::configuration_tests::enable_send_eid_for_test(src_eid);

        // Set the grace period to 10 blocks
        set_default_receive_library(src_eid, @uln_302, 10);

        // Reset the expiry to 20 blocks
        set_default_receive_library_timeout(src_eid, @uln_302, 20);
    }

    #[test]
    fun test_set_receive_library_timeout() {
        init_for_test();

        let src_eid = 2;
        uln_302::configuration_tests::enable_receive_eid_for_test(src_eid);

        set_default_receive_library(src_eid, @simple_msglib, 0);

        // Both default and receive should be valid after setting the oapp lib with a timeout
        set_receive_library(OAPP_ADDRESS, src_eid, @uln_302, 0);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @uln_302), 0);
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @simple_msglib), 1);
        // unrelated msglib
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @blocked_msglib), 2);

        // Reset the grace period to 20 blocks from current block (0) and to a different lib
        set_receive_library_timeout(OAPP_ADDRESS, src_eid, @blocked_msglib, 20);
        assert!(was_event_emitted(&receive_library_timeout_set_event(OAPP_ADDRESS, src_eid, @blocked_msglib, 20)), 3);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @blocked_msglib), 2);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @uln_302), 3);
        // old grace period msglib
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @simple_msglib), 4);

        // t = 19 blocks (before the expiry): grace period should still be active
        set_block_height(19);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @blocked_msglib), 5);

        // t = 20 blocks (at the expiry): grace period should be expired
        set_block_height(20);
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @blocked_msglib), 6);

        // set a new timout
        set_receive_library_timeout(OAPP_ADDRESS, src_eid, @simple_msglib, 30);
        assert!(was_event_emitted(&receive_library_timeout_set_event(OAPP_ADDRESS, src_eid, @simple_msglib, 30)), 7);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @simple_msglib), 8);

        // unset the timeout
        set_receive_library_timeout(OAPP_ADDRESS, src_eid, @1234567, 0);
        assert!(was_event_emitted(&receive_library_timeout_set_event(OAPP_ADDRESS, src_eid, @0x0, 0)), 8);
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @simple_msglib), 8);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EEXPIRY_IS_IN_PAST)]
    fun test_set_receive_library_timeout_fails_if_in_the_past() {
        init_for_test();
        let src_eid = 2;
        uln_302::configuration_tests::enable_receive_eid_for_test(src_eid);

        set_default_receive_library(src_eid, @simple_msglib, 0);
        set_receive_library(OAPP_ADDRESS, src_eid, @simple_msglib, 0);
        set_block_height(20);

        // Attempt to set a grace period that is in the past
        set_receive_library_timeout(OAPP_ADDRESS, src_eid, @simple_msglib, 10);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::ERECEIVE_LIB_NOT_SET)]
    fun test_set_receive_library_timeout_fails_if_trying_to_unset_library_that_is_not_set() {
        init_for_test();
        let src_eid = 2;
        set_default_receive_library(src_eid, @simple_msglib, 0);

        // Attempt to unset without having already set
        set_receive_library_timeout(OAPP_ADDRESS, src_eid, @0x0, 10);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::ENO_TIMEOUT_TO_DELETE)]
    fun test_set_receive_library_timeout_fails_if_no_grace_period_config_to_delete() {
        init_for_test();
        let src_eid = 2;

        set_default_receive_library(src_eid, @simple_msglib, 0);
        set_receive_library(OAPP_ADDRESS, src_eid, @blocked_msglib, 0);
        // Attempt to unset without having already set
        set_receive_library_timeout(OAPP_ADDRESS, src_eid, @0x0, 0);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::ERECEIVE_LIB_NOT_SET)]
    fun test_set_receive_library_timeout_fails_if_no_oapp_receive_library_already_set() {
        init_for_test();
        let src_eid = 2;
        set_default_receive_library(src_eid, @simple_msglib, 0);

        // Attempt to set a grace period without having already set
        set_receive_library_timeout(OAPP_ADDRESS, src_eid, @simple_msglib, 10);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::msglib_manager::EUNSUPPORTED_SRC_EID)]
    fun test_set_receive_library_timeout_fails_if_msglib_doesnt_support_eid() {
        init_for_test();
        let src_eid = 2;
        // only enable send side, not receive side
        uln_302::configuration_tests::enable_send_eid_for_test(src_eid);

        set_default_receive_library(src_eid, @simple_msglib, 0);
        set_receive_library(OAPP_ADDRESS, src_eid, @simple_msglib, 0);

        // Attempt to set a grace period to a library that does not support the EID
        set_receive_library_timeout(OAPP_ADDRESS, src_eid, @uln_302, 10);
    }

    #[test]
    fun test_get_effective_receive_library() {
        init_for_test();

        let src_eid = 2;
        uln_302::configuration_tests::enable_receive_eid_for_test(src_eid);

        set_default_receive_library(src_eid, @simple_msglib, 0);
        let (lib, is_default) = get_effective_receive_library(OAPP_ADDRESS, src_eid);
        assert!(lib == @simple_msglib, 0);
        assert!(is_default, 1);

        // set for oapp
        set_receive_library(
            OAPP_ADDRESS,
            src_eid,
            @uln_302,
            0,
        );

        let (lib, is_default) = get_effective_receive_library(OAPP_ADDRESS, src_eid);
        assert!(lib == @uln_302, 2);
        assert!(!is_default, 3);

        // remove the oapp setting
        set_receive_library(
            OAPP_ADDRESS,
            src_eid,
            @0x0,
            0,
        );

        let (lib, is_default) = get_effective_receive_library(OAPP_ADDRESS, src_eid);
        assert!(lib == @simple_msglib, 4);
        assert!(is_default, 5);
    }

    #[test]
    fun test_is_valid_receive_library_for_oapp() {
        init_for_test();

        let src_eid = 2;
        uln_302::configuration_tests::enable_receive_eid_for_test(src_eid);

        // An unregistered library is not ever valid
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @0x983721498743), 0);

        // The default is valid if one is not set for OApp
        set_default_receive_library(src_eid, @simple_msglib, 0);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @simple_msglib), 0);
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @uln_302), 1);

        // set for oapp
        set_receive_library(
            OAPP_ADDRESS,
            src_eid,
            @uln_302,
            0,
        );

        // Only the oapp setting is valid
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @uln_302), 3);
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @simple_msglib), 4);

        // Switch with a grace period
        set_receive_library(
            OAPP_ADDRESS,
            src_eid,
            @simple_msglib,
            10,
        );

        // Both are valid during grace period
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @simple_msglib), 5);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @uln_302), 6);

        // After the grace period, only the new one is valid
        set_block_height(11);
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @simple_msglib), 7);
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @uln_302), 8);

        // remove the oapp setting
        set_receive_library(
            OAPP_ADDRESS,
            src_eid,
            @0x0,
            0,
        );

        // After unsetting, only the default is valid
        assert!(is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @simple_msglib), 3);
        assert!(!is_valid_receive_library_for_oapp(OAPP_ADDRESS, src_eid, @uln_302), 4);
    }
}