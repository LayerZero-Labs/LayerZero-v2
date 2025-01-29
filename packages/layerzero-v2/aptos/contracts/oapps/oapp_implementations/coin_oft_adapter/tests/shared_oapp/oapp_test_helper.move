#[test_only]
module oft::oapp_test_helper {
    use oft::oapp_receive;
    use oft::oapp_store;

    public fun init_oapp() {
        oapp_store::init_module_for_test();
        oapp_receive::init_module_for_test();
    }
}
