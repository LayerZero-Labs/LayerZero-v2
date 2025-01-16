#[test_only]
module oapp::oapp_test_helper {
    use oapp::oapp_compose;
    use oapp::oapp_receive;
    use oapp::oapp_store;

    public fun init_oapp() {
        oapp_store::init_module_for_test();
        oapp_receive::init_module_for_test();
        oapp_compose::init_module_for_test();
    }
}
