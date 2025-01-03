#[test_only]
module uln_302::msglib_tests {
    use std::option;

    use msglib_types::configs_executor::new_executor_config;
    use msglib_types::configs_uln::new_uln_config;
    use uln_302::configuration::{
        set_default_executor_config, set_default_receive_uln_config, set_default_send_uln_config, set_executor_config,
        set_receive_uln_config, set_send_uln_config,
    };
    use uln_302::msglib;

    fun setup() {
        msglib::initialize_for_test();
    }

    #[test]
    fun test_get_app_send_config() {
        setup();
        let send_config = new_uln_config(1, 1, vector[@0x10], vector[@0x30, @0x50], false, false, false);
        set_default_send_uln_config(1, send_config);

        set_send_uln_config(@9999, 1, send_config);

        let retrieved_config = msglib::get_app_send_config(@9999, 1);
        assert!(retrieved_config == option::some(send_config), 0);
    }

    #[test]
    fun test_get_app_send_config_should_return_option_none_if_only_default_is_set() {
        setup();
        let send_config = new_uln_config(1, 1, vector[@0x10], vector[@0x30, @0x50], false, false, false);
        set_default_send_uln_config(1, send_config);

        let retrieved_config = msglib::get_app_send_config(@9999, 1);
        assert!(retrieved_config == option::none(), 0);
    }

    #[test]
    fun get_app_send_config_should_return_option_none_if_default_not_set() {
        setup();
        let retrieved_config = msglib::get_app_send_config(@9999, 1);
        assert!(retrieved_config == option::none(), 0);
    }

    #[test]
    fun test_get_app_receive_config() {
        setup();
        let receive_config = new_uln_config(2, 1, vector[@0x20], vector[@0x40, @0x60], false, false, false);
        set_default_receive_uln_config(1, receive_config);

        set_receive_uln_config(@9999, 1, receive_config);

        let retrieved_config = msglib::get_app_receive_config(@9999, 1);
        assert!(retrieved_config == option::some(receive_config), 0);
    }

    #[test]
    fun test_get_app_receive_config_should_return_option_none_if_only_default_is_set() {
        setup();
        let receive_config = new_uln_config(2, 1, vector[@0x20], vector[@0x40, @0x60], false, false, false);
        set_default_receive_uln_config(1, receive_config);

        let retrieved_config = msglib::get_app_receive_config(@9999, 1);
        assert!(retrieved_config == option::none(), 0);
    }

    #[test]
    fun get_app_receive_config_should_return_option_none_if_default_not_set() {
        setup();
        let retrieved_config = msglib::get_app_receive_config(@9999, 1);
        assert!(retrieved_config == option::none(), 0);
    }

    #[test]
    fun test_get_app_executor_config() {
        setup();
        let executor_config = new_executor_config(1000, @9001);
        set_default_executor_config(1, executor_config);
        set_executor_config(@9999, 1, executor_config);

        let retrieved_config = msglib::get_app_executor_config(@9999, 1);
        assert!(retrieved_config == option::some(executor_config), 0);
    }

    #[test]
    fun test_get_app_executor_config_should_return_option_none_if_only_default_is_set() {
        setup();
        let executor_config = new_executor_config(1000, @9001);
        set_default_executor_config(1, executor_config);

        let retrieved_config = msglib::get_app_executor_config(@9999, 1);
        assert!(retrieved_config == option::none(), 0);
    }

    #[test]
    fun get_app_executor_config_should_return_option_none_if_default_not_set() {
        setup();
        let retrieved_config = msglib::get_app_executor_config(@9999, 1);
        assert!(retrieved_config == option::none(), 0);
    }
}