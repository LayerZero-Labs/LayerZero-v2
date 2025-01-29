module simple_msglib::msglib {
    use endpoint_v2_common::universal_config::assert_layerzero_admin;

    // Simple message lib has globally fixed fees
    struct SimpleMessageLibConfig has key {
        native_fee: u64,
        zro_fee: u64,
    }

    fun init_module(account: &signer) {
        move_to(move account, SimpleMessageLibConfig { native_fee: 0, zro_fee: 0 });
    }

    #[test_only]
    public fun initialize_for_test() {
        init_module(&std::account::create_signer_for_test(@simple_msglib));
    }

    public entry fun set_messaging_fee(
        account: &signer,
        native_fee: u64,
        zro_fee: u64,
    ) acquires SimpleMessageLibConfig {
        assert_layerzero_admin(std::signer::address_of(move account));
        let msglib_config = borrow_global_mut<SimpleMessageLibConfig>(@simple_msglib);
        msglib_config.native_fee = native_fee;
        msglib_config.zro_fee = zro_fee;
    }

    #[view]
    public fun get_messaging_fee(): (u64, u64) acquires SimpleMessageLibConfig {
        let msglib_config = borrow_global<SimpleMessageLibConfig>(@simple_msglib);
        (msglib_config.native_fee, msglib_config.zro_fee)
    }

    // ================================================== Error Codes =================================================

    const EUNAUTHORIZED: u64 = 1;
}
