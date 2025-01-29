/// The message library manager is responsible for managing the message libraries and providing default message library
/// selections for the endpoint.
/// The registration of a message library happens in several steps:
/// 1. The message library is deployed and made available through the message library router.
/// 2. The message library address is registered with the message library manager: this irrevocably enables the use of
///    the message library through this endpoint (but not on any pathways).
/// 3. A default message library is registered for each individual pathway: this irreversibly enables the use of the
///    message library for the given pathway.
///
/// Once a message library's default is set, the OApp can override the default message library for any pathway through
/// the separate OApp configuration interface.
module endpoint_v2::msglib_manager {
    use std::event::emit;

    use endpoint_v2::store;
    use endpoint_v2::timeout;
    use endpoint_v2::timeout::{new_timeout_from_expiry, Timeout};
    use router_node_0::router_node;

    friend endpoint_v2::admin;
    friend endpoint_v2::endpoint;
    friend endpoint_v2::channels;

    #[test_only]
    friend endpoint_v2::msglib_manager_tests;
    #[test_only]
    friend endpoint_v2::test_helpers;
    #[test_only]
    friend endpoint_v2::channels_tests;

    // ==================================================== Helpers ===================================================

    inline fun assert_library_registered(lib: address) {
        assert!(store::is_registered_msglib(lib), EUNREGISTERED_MSGLIB);
    }

    inline fun is_in_grace_period(src_eid: u32): bool {
        store::has_default_receive_library_timeout(src_eid) &&
            timeout::is_active(&store::get_default_receive_library_timeout(src_eid))
    }

    inline fun get_default_receive_library_timeout_prior_lib(src_eid: u32): address {
        timeout::get_library(&store::get_default_receive_library_timeout(src_eid))
    }

    // ================================================ Core Functions ================================================

    /// Register a new message library
    public(friend) fun register_library(lib: address) {
        // Make sure it is available to be registered
        assert_connected_to_router(lib);
        // Make sure it is not already registered
        assert!(!store::is_registered_msglib(lib), EALREADY_REGISTERED);
        // Add the message library and emit
        store::add_msglib(lib);
        emit(LibraryRegistered { new_lib: lib });
    }

    /// Asserts that a library is connected to the router and not a placeholder.
    inline fun assert_connected_to_router(lib: address) {
        // The version call will fail if a message library is not in the router or if it is a placeholder.
        router_node::version(lib);
    }

    /// Gets a list of all message libraries that are registered
    public(friend) fun get_registered_libraries(start_index: u64, max_entries: u64): vector<address> {
        store::registered_msglibs(start_index, max_entries)
    }

    /// Checks if a particular library address is registered
    public(friend) fun is_registered_library(lib: address): bool {
        store::is_registered_msglib(lib)
    }

    public(friend) fun set_config(
        oapp: address,
        lib: address,
        eid: u32,
        config_type: u32,
        config: vector<u8>,
    ) {
        assert_library_registered(lib);
        let to_msglib_call_ref = &store::make_dynamic_call_ref(lib, b"set_config");
        router_node::set_config(lib, to_msglib_call_ref, oapp, eid, config_type, config);
    }

    public(friend) fun get_config(
        oapp: address,
        lib: address,
        eid: u32,
        config_type: u32,
    ): vector<u8> {
        assert_library_registered(lib);
        router_node::get_config(lib, oapp, eid, config_type)
    }

    // ============================================ Default Send Libraries ============================================

    fun assert_msglib_supports_send_eid(lib: address, dst_eid: u32) {
        assert!(router_node::is_supported_send_eid(lib, dst_eid), EUNSUPPORTED_DST_EID);
    }

    /// Gets the default send library
    public(friend) fun get_default_send_library(dst_eid: u32): address {
        store::get_default_send_library(dst_eid)
    }

    /// Set the default Endpoint default send library for a dest_eid.
    /// If there is no default send library set, the dest_eid is deemed to be unsupported.
    public(friend) fun set_default_send_library(dst_eid: u32, new_lib: address) {
        assert_library_registered(new_lib);
        assert_msglib_supports_send_eid(new_lib, dst_eid);

        if (store::has_default_send_library(dst_eid)) {
            let old_lib = store::get_default_send_library(dst_eid);
            assert!(old_lib != new_lib, EATTEMPTED_TO_SET_CURRENT_LIBRARY);
        };

        store::set_default_send_library(dst_eid, new_lib);
        emit(DefaultSendLibrarySet { eid: dst_eid, new_lib });
    }

    // ============================================== Oapp Send Libraries =============================================

    public(friend) fun set_send_library(
        sender: address,
        dst_eid: u32,
        msglib: address,
    ) {
        if (msglib == @0x0) {
            assert!(store::has_send_library(sender, dst_eid), EOAPP_SEND_LIB_NOT_SET);
            store::unset_send_library(sender, dst_eid);
        } else {
            assert_library_registered(msglib);
            assert_msglib_supports_send_eid(msglib, dst_eid);

            if (store::has_send_library(sender, dst_eid)) {
                let old_lib = store::get_send_library(sender, dst_eid);
                assert!(old_lib != msglib, EATTEMPTED_TO_SET_CURRENT_LIBRARY);
            };
            store::set_send_library(sender, dst_eid, msglib);
        };
        emit(SendLibrarySet { sender, eid: dst_eid, new_lib: msglib });
    }

    /// Gets the effective send library for the given destination EID, returns both the library and a flag indicating if
    /// this is a fallback to the default (meaning the library is not configured for the oapp)
    public(friend) fun get_effective_send_library(sender: address, dst_eid: u32): (address, bool) {
        if (store::has_send_library(sender, dst_eid)) {
            (store::get_send_library(sender, dst_eid), false)
        } else {
            (store::get_default_send_library(dst_eid), true)
        }
    }


    // =========================================== Default Receive Libraries ==========================================

    fun assert_msglib_supports_receive_eid(lib: address, src_eid: u32) {
        assert!(router_node::is_supported_receive_eid(lib, src_eid), EUNSUPPORTED_SRC_EID);
    }

    /// Set the default receive library.
    /// If the grace_period is non-zero, also set the grace message library and expiry
    public(friend) fun set_default_receive_library(src_eid: u32, new_lib: address, grace_period: u64) {
        assert_library_registered(new_lib);
        assert_msglib_supports_receive_eid(new_lib, src_eid);

        if (store::has_default_receive_library(src_eid)) {
            let old_lib = store::get_default_receive_library(src_eid);
            assert!(old_lib != new_lib, EATTEMPTED_TO_SET_CURRENT_LIBRARY);
        };

        let old_lib = if (store::has_default_receive_library(src_eid)) {
            store::get_default_receive_library(src_eid)
        } else @0x0;

        // Set the grace period if it is greater than 0
        if (grace_period > 0) {
            assert!(old_lib != @0x0, ENO_PRIOR_LIBRARY_FOR_FALLBACK);
            let timeout = timeout::new_timeout_from_grace_period(grace_period, old_lib);
            store::set_default_receive_library_timeout(src_eid, timeout);

            let expiry = timeout::get_expiry(&timeout);
            emit(DefaultReceiveLibraryTimeoutSet { eid: src_eid, old_lib, expiry });
        } else {
            if (store::has_default_receive_library_timeout(src_eid)) {
                store::unset_default_receive_library_timeout(src_eid);
            };
            emit(DefaultReceiveLibraryTimeoutSet { eid: src_eid, old_lib, expiry: 0 });
        };
        store::set_default_receive_library(src_eid, new_lib);
        emit(DefaultReceiveLibrarySet { eid: src_eid, new_lib });
    }

    public(friend) fun set_default_receive_library_timeout(
        src_eid: u32,
        lib: address,
        expiry: u64,
    ) {
        if (expiry == 0) {
            store::unset_default_receive_library_timeout(src_eid);
            emit(DefaultReceiveLibraryTimeoutSet { eid: src_eid, expiry: 0, old_lib: lib });
        } else {
            assert_library_registered(lib);
            assert_msglib_supports_receive_eid(lib, src_eid);
            let timeout = timeout::new_timeout_from_expiry(expiry, lib);
            assert!(timeout::is_active(&timeout), EEXPIRY_IS_IN_PAST);
            store::set_default_receive_library_timeout(src_eid, timeout);
            emit(DefaultReceiveLibraryTimeoutSet { eid: src_eid, expiry, old_lib: lib });
        };
    }

    /// Asserts that a given receive library is the default receive library for a given source EID.
    /// This will also check the grace period (prior library) if active.
    public(friend) fun matches_default_receive_library(src_eid: u32, actual_receive_lib: address): bool {
        if (actual_receive_lib == store::get_default_receive_library(src_eid)) { return true };

        // If no match, check the grace period
        if (!is_in_grace_period(src_eid)) { return false };

        get_default_receive_library_timeout_prior_lib(src_eid) == actual_receive_lib
    }

    public(friend) fun get_default_receive_library(src_eid: u32): address {
        store::get_default_receive_library(src_eid)
    }

    /// Get the default receive library timeout or return an empty Timeout if one is not set
    public(friend) fun get_default_receive_library_timeout(src_eid: u32): Timeout {
        if (store::has_default_receive_library_timeout(src_eid)) {
            store::get_default_receive_library_timeout(src_eid)
        } else {
            new_timeout_from_expiry(0, @0x0)
        }
    }

    // ================================================= Receive Oapp =================================================


    public(friend) fun set_receive_library(
        receiver: address,
        src_eid: u32,
        msglib: address,
        grace_period: u64,
    ) {
        // If MsgLib is @0x0, unset the library
        if (msglib == @0x0) {
            // Setting a grace period is not supported when unsetting the library to match EVM spec
            // This can still be achieved by explicitly setting the OApp to the default library with a grace period
            // And then after the grace period, unsetting the library by setting it to @0x0
            assert!(grace_period == 0, ECANNOT_SET_GRACE_PERIOD_ON_RECEIVE_LIBRARY_UNSET);

            assert!(store::has_receive_library(receiver, src_eid), ERECEIVE_LIB_NOT_SET);
            let old_lib = store::get_receive_library(receiver, src_eid);
            store::unset_receive_library(receiver, src_eid);
            emit(ReceiveLibrarySet { receiver, eid: src_eid, new_lib: @0x0 });
            if (store::has_receive_library_timeout(receiver, src_eid)) {
                store::unset_receive_library_timeout(receiver, src_eid);
            };
            emit(ReceiveLibraryTimeoutSet { receiver, eid: src_eid, old_lib, timeout: 0 });
            return
        };

        // Check if the library is registered and supports the receive EID
        assert_library_registered(msglib);
        assert_msglib_supports_receive_eid(msglib, src_eid);

        // Make sure we are not setting the same library
        if (store::has_receive_library(receiver, src_eid)) {
            let old_lib = store::get_receive_library(receiver, src_eid);
            assert!(old_lib != msglib, EATTEMPTED_TO_SET_CURRENT_LIBRARY);
        };

        let (old_lib, is_default) = get_effective_receive_library(receiver, src_eid);

        store::set_receive_library(receiver, src_eid, msglib);
        emit(ReceiveLibrarySet { receiver, eid: src_eid, new_lib: msglib });

        if (grace_period == 0) {
            // If there is a timeout and grace_period is 0, remove the current timeout
            if (store::has_receive_library_timeout(receiver, src_eid)) {
                store::unset_receive_library_timeout(receiver, src_eid);
            };
            let non_default_old_lib = if (is_default) { @0x0 } else { old_lib };
            emit(ReceiveLibraryTimeoutSet { receiver, eid: src_eid, old_lib: non_default_old_lib, timeout: 0 });
        } else {
            // Setting a grace period is not supported when setting the library from the default library
            // This can still be achieved by explicitly setting the OApp to the default library, then setting it to the
            // desired library with a default
            assert!(!is_default, ETIMEOUT_SET_FOR_DEFAULT_RECEIVE_LIBRARY);

            let grace_period = timeout::new_timeout_from_grace_period(grace_period, old_lib);
            store::set_receive_library_timeout(receiver, src_eid, grace_period);
            let expiry = timeout::get_expiry(&grace_period);
            emit(ReceiveLibraryTimeoutSet { receiver, eid: src_eid, old_lib, timeout: expiry });
        }
    }


    public(friend) fun set_receive_library_timeout(
        receiver: address,
        src_eid: u32,
        lib: address,
        expiry: u64,
    ) {
        if (expiry == 0) {
            // Abort if there is no timeout to delete
            assert!(store::has_receive_library_timeout(receiver, src_eid), ENO_TIMEOUT_TO_DELETE);
            let timeout = store::get_receive_library_timeout(receiver, src_eid);
            assert!(timeout::is_active(&timeout), ENO_TIMEOUT_TO_DELETE);
            store::unset_receive_library_timeout(receiver, src_eid);
            emit(ReceiveLibraryTimeoutSet { receiver, eid: src_eid, old_lib: lib, timeout: 0 });
        } else {
            assert!(store::has_receive_library(receiver, src_eid), ERECEIVE_LIB_NOT_SET);
            assert_msglib_supports_receive_eid(lib, src_eid);
            assert_library_registered(lib);
            let timeout = timeout::new_timeout_from_expiry(expiry, lib);
            assert!(timeout::is_active(&timeout), EEXPIRY_IS_IN_PAST);
            store::set_receive_library_timeout(receiver, src_eid, timeout);
            emit(ReceiveLibraryTimeoutSet { receiver, eid: src_eid, old_lib: lib, timeout: expiry });
        };
    }

    /// Get the receive library timeout or return an empty timeout if it is not set
    public(friend) fun get_receive_library_timeout(receiver: address, src_eid: u32): Timeout {
        if (store::has_receive_library_timeout(receiver, src_eid)) {
            store::get_receive_library_timeout(receiver, src_eid)
        } else {
            new_timeout_from_expiry(0, @0x0)
        }
    }

    /// Gets the effective receive library for the given source EID, returns both the library and a flag indicating if
    /// this is a fallback to the default (meaning the library is not configured)
    public(friend) fun get_effective_receive_library(receiver: address, src_eid: u32): (address, bool) {
        if (store::has_receive_library(receiver, src_eid)) {
            (store::get_receive_library(receiver, src_eid), false)
        } else {
            (store::get_default_receive_library(src_eid), true)
        }
    }

    /// Check if the provided message library is valid for the given OApp and source EID.
    public(friend) fun is_valid_receive_library_for_oapp(receiver: address, src_eid: u32, msglib: address): bool {
        if (!is_registered_library(msglib)) { return false };

        // 1. Check if it is the default library, if it is not already set
        if (!store::has_receive_library(receiver, src_eid)) {
            return matches_default_receive_library(src_eid, msglib)
        };

        // 2. Check if it is the configured library
        if (store::get_receive_library(receiver, src_eid) == msglib) { return true };

        // 3. If it is in the grace period, check the prior library
        if (store::has_receive_library_timeout(receiver, src_eid)) {
            let timeout = store::get_receive_library_timeout(receiver, src_eid);
            let is_active = timeout::is_active(&timeout);
            if (is_active && timeout::get_library(&timeout) == msglib) { return true };
        };

        // 4. Otherwise, it is invalid
        false
    }

    // ==================================================== Events ====================================================

    #[event]
    struct LibraryRegistered has drop, copy, store { new_lib: address }

    #[event]
    struct DefaultSendLibrarySet has drop, copy, store { eid: u32, new_lib: address }

    #[event]
    struct DefaultReceiveLibrarySet has drop, copy, store {
        eid: u32,
        new_lib: address,
    }

    #[event]
    struct DefaultReceiveLibraryTimeoutSet has drop, copy, store {
        eid: u32,
        old_lib: address,
        expiry: u64,
    }

    #[event]
    struct SendLibrarySet has drop, copy, store {
        sender: address,
        eid: u32,
        new_lib: address,
    }

    #[event]
    struct ReceiveLibrarySet has drop, copy, store {
        receiver: address,
        eid: u32,
        new_lib: address,
    }

    #[event]
    struct ReceiveLibraryTimeoutSet has drop, copy, store {
        receiver: address,
        eid: u32,
        old_lib: address,
        timeout: u64,
    }

    #[test_only]
    public fun library_registered_event(lib: address): LibraryRegistered { LibraryRegistered { new_lib: lib } }

    #[test_only]
    public fun default_send_library_set_event(
        eid: u32,
        new_lib: address,
    ): DefaultSendLibrarySet { DefaultSendLibrarySet { eid, new_lib } }

    #[test_only]
    public fun default_receive_library_set_event(
        eid: u32,
        new_lib: address,
    ): DefaultReceiveLibrarySet { DefaultReceiveLibrarySet { eid, new_lib } }

    #[test_only]
    public fun default_receive_library_timeout_set_event(
        eid: u32,
        old_lib: address,
        expiry: u64,
    ): DefaultReceiveLibraryTimeoutSet { DefaultReceiveLibraryTimeoutSet { eid, old_lib, expiry } }

    #[test_only]
    public fun send_library_set_event(
        sender: address,
        eid: u32,
        new_lib: address,
    ): SendLibrarySet { SendLibrarySet { sender, eid, new_lib } }

    #[test_only]
    public fun receive_library_set_event(
        receiver: address,
        eid: u32,
        new_lib: address,
    ): ReceiveLibrarySet { ReceiveLibrarySet { receiver, eid, new_lib } }

    #[test_only]
    public fun receive_library_timeout_set_event(
        receiver: address,
        eid: u32,
        old_lib: address,
        timeout: u64,
    ): ReceiveLibraryTimeoutSet { ReceiveLibraryTimeoutSet { receiver, eid, old_lib, timeout } }

    // ================================================== Error Codes =================================================

    const EALREADY_REGISTERED: u64 = 1;
    const EATTEMPTED_TO_SET_CURRENT_LIBRARY: u64 = 2;
    const ECANNOT_SET_GRACE_PERIOD_ON_RECEIVE_LIBRARY_UNSET: u64 = 3;
    const EEXPIRY_IS_IN_PAST: u64 = 4;
    const ENO_PRIOR_LIBRARY_FOR_FALLBACK: u64 = 5;
    const ENO_TIMEOUT_TO_DELETE: u64 = 6;
    const EOAPP_SEND_LIB_NOT_SET: u64 = 7;
    const ERECEIVE_LIB_NOT_SET: u64 = 8;
    const ETIMEOUT_SET_FOR_DEFAULT_RECEIVE_LIBRARY: u64 = 9;
    const EUNREGISTERED_MSGLIB: u64 = 10;
    const EUNSUPPORTED_DST_EID: u64 = 11;
    const EUNSUPPORTED_SRC_EID: u64 = 12;
}

