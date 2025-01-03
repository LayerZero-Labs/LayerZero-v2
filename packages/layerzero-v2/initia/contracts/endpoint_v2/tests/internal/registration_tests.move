#[test_only]
module endpoint_v2::registration_tests {
    use std::event::was_event_emitted;
    use std::string::utf8;

    use endpoint_v2::registration::{
        composer_registered_event,
        is_registered_composer,
        is_registered_oapp,
        oapp_registered_event,
        register_composer,
        register_oapp
    };
    use endpoint_v2::store;

    #[test]
    fun test_register() {
        store::init_module_for_test();
        register_oapp(@1234, utf8(b"test_receive"));
        assert!(was_event_emitted(&oapp_registered_event(@1234, utf8(b"test_receive"))), 0);
        assert!(is_registered_oapp(@1234), 1);
        assert!(!is_registered_composer(@1234), 2);
        let receiver_module = store::lz_receive_module(@1234);
        assert!(receiver_module == utf8(b"test_receive"), 0);

        register_composer(@2234, utf8(b"test_compose"));
        assert!(was_event_emitted(&composer_registered_event(@2234, utf8(b"test_compose"))), 1);
        assert!(!is_registered_oapp(@2234), 2);
        assert!(is_registered_composer(@2234), 3);
        let composer_module = store::lz_compose_module(@2234);
        assert!(composer_module == utf8(b"test_compose"), 1);

        // register oapp in same address as composer
        register_oapp(@2234, utf8(b"test_receive"));
        assert!(was_event_emitted(&oapp_registered_event(@2234, utf8(b"test_receive"))), 2);
        assert!(is_registered_oapp(@2234), 3);
        assert!(is_registered_composer(@2234), 4);
        let receiver_module = store::lz_receive_module(@2234);
        assert!(receiver_module == utf8(b"test_receive"), 2);

        // register composer in same address as oapp
        register_composer(@1234, utf8(b"test_compose"));
        assert!(was_event_emitted(&composer_registered_event(@1234, utf8(b"test_compose"))), 3);
        assert!(is_registered_oapp(@1234), 4);
        assert!(is_registered_composer(@1234), 5);
        let composer_module = store::lz_compose_module(@1234);
        assert!(composer_module == utf8(b"test_compose"), 3);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::registration::EALREADY_REGISTERED)]
    fun test_register_oapp_fails_if_already_registered() {
        store::init_module_for_test();
        register_oapp(@1234, utf8(b"test"));
        register_oapp(@1234, utf8(b"test"));
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::registration::EALREADY_REGISTERED)]
    fun test_register_composer_fails_if_already_registered() {
        store::init_module_for_test();
        register_oapp(@1234, utf8(b"test"));
        register_composer(@1234, utf8(b"test"));
        register_composer(@1234, utf8(b"test"));
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::store::EEMPTY_MODULE_NAME)]
    fun test_register_fails_if_empty_lz_receive_module() {
        endpoint_v2::store::init_module_for_test();
        register_oapp(@1234, utf8(b""));
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::store::EEMPTY_MODULE_NAME)]
    fun test_register_fails_if_empty_lz_compose_module() {
        endpoint_v2::store::init_module_for_test();
        register_oapp(@1234, utf8(b"receive"));
        register_composer(@1234, utf8(b""));
    }
}
