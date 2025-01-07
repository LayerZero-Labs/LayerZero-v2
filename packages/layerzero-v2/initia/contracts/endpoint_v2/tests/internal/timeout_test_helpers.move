#[test_only]
module endpoint_v2::timeout_test_helpers {
    #[test_only]
    public fun setup_for_timeouts() {
        let std = &std::account::create_account_for_test(@std);
        std::block::initialize_for_test(std, 1_000_000);
        std::reconfiguration::initialize_for_test(std);
        let vm = &std::account::create_account_for_test(@0x0);
        // genesis block
        std::block::emit_writeset_block_event(vm, @1234);
    }


    #[test_only]
    public fun set_block_height(target_height: u64) {
        let vm = &std::account::create_signer_for_test(@0x0);
        let start_height = std::block::get_current_block_height();
        for (i in start_height..target_height) {
            std::block::emit_writeset_block_event(vm, @1234);
        }
    }
}
