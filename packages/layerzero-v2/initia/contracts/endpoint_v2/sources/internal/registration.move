module endpoint_v2::registration {
    use std::event::emit;
    use std::string::{Self, String};

    use endpoint_v2::store;

    friend endpoint_v2::endpoint;

    #[test_only]
    friend endpoint_v2::registration_tests;
    #[test_only]
    friend endpoint_v2::channels_tests;

    /// Initialize the OApp with registering the lz_receive function
    /// register_oapp() must also be called before the OApp can receive messages
    public(friend) fun register_oapp(oapp: address, lz_receive_module: String) {
        assert!(string::length(&lz_receive_module) <= 100, EEXCESSIVE_STRING_LENGTH);
        assert!(!store::is_registered_oapp(oapp), EALREADY_REGISTERED);
        store::register_oapp(oapp, lz_receive_module);
        emit(OAppRegistered {
            oapp,
            lz_receive_module,
        });
    }

    /// Registers the Composer with the lz_compose function
    public(friend) fun register_composer(composer: address, lz_compose_module: String) {
        assert!(string::length(&lz_compose_module) <= 100, EEXCESSIVE_STRING_LENGTH);
        assert!(!store::is_registered_composer(composer), EALREADY_REGISTERED);
        store::register_composer(composer, lz_compose_module);
        emit(ComposerRegistered {
            composer,
            lz_compose_module,
        });
    }

    /// Checks if the OApp is registered
    public(friend) fun is_registered_oapp(oapp: address): bool {
        store::is_registered_oapp(oapp)
    }

    /// Checks if the Composer is registered
    public(friend) fun is_registered_composer(composer: address): bool {
        store::is_registered_composer(composer)
    }

    /// Returns the lz_receive_module of the OApp
    public(friend) fun lz_receive_module(oapp: address): String {
        store::lz_receive_module(oapp)
    }

    /// Returns the lz_compose_module of the Composer
    public(friend) fun lz_compose_module(composer: address): String {
        store::lz_compose_module(composer)
    }

    // ==================================================== Events ====================================================

    #[event]
    struct OAppRegistered has drop, store {
        oapp: address,
        lz_receive_module: String,
    }

    #[event]
    struct ComposerRegistered has drop, store {
        composer: address,
        lz_compose_module: String,
    }

    #[test_only]
    public fun oapp_registered_event(oapp: address, lz_receive_module: String): OAppRegistered {
        OAppRegistered { oapp, lz_receive_module }
    }

    #[test_only]
    public fun composer_registered_event(composer: address, lz_compose_module: String): ComposerRegistered {
        ComposerRegistered { composer, lz_compose_module }
    }

    // ================================================== Error Codes =================================================

    const EALREADY_REGISTERED: u64 = 1;
    const EEXCESSIVE_STRING_LENGTH: u64 = 2;
}
