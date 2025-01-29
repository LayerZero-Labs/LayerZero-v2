#[test_only]
module bridge_remote::oapp_test_helper {
    use bridge_remote::oapp_compose;
    use bridge_remote::oapp_receive;
    use bridge_remote::oapp_store;

    public fun init_oapp() {
        oapp_store::init_module_for_test();
        oapp_receive::init_module_for_test();
        oapp_compose::init_module_for_test();
    }
}
