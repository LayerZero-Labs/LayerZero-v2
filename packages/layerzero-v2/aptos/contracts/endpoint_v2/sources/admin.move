/// This module isolates functions related to Endpoint administration
module endpoint_v2::admin {
    use std::signer::address_of;

    use endpoint_v2::msglib_manager;
    use endpoint_v2_common::universal_config::assert_layerzero_admin;

    /// Register new message library
    /// A library must be registered to be called by this endpoint. Once registered, it cannot be unregistered. The
    /// library must be connected to the router node before it can be registered
    public entry fun register_library(account: &signer, lib: address) {
        assert_layerzero_admin(address_of(move account));
        msglib_manager::register_library(lib);
    }

    /// Sets the default sending message library for the given destination EID
    public entry fun set_default_send_library(account: &signer, dst_eid: u32, lib: address) {
        assert_layerzero_admin(address_of(move account));
        msglib_manager::set_default_send_library(dst_eid, lib);
    }

    /// Set the default receive message library for the given source EID
    public entry fun set_default_receive_library(
        account: &signer,
        src_eid: u32,
        lib: address,
        grace_period: u64,
    ) {
        assert_layerzero_admin(address_of(move account));
        msglib_manager::set_default_receive_library(src_eid, lib, grace_period);
    }

    /// Updates the default receive library timeout for the given source EID
    /// The provided expiry is in a specific block number. The fallback library will be disabled once the block height
    /// equals this block number
    public entry fun set_default_receive_library_timeout(
        account: &signer,
        src_eid: u32,
        fallback_lib: address,
        expiry: u64,
    ) {
        assert_layerzero_admin(address_of(move account));
        msglib_manager::set_default_receive_library_timeout(src_eid, fallback_lib, expiry);
    }

    // ==================================================== Helpers ===================================================

    #[test_only]
    /// Test-only function to initialize the endpoint and EID
    public fun initialize_endpoint_for_test() {
        endpoint_v2::store::init_module_for_test();
    }

    // ================================================== Error Codes =================================================

    const EUNAUTHORIZED: u64 = 1;
}
