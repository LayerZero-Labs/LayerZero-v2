#[test_only]
module uln_302::verification_tests {
    use endpoint_v2_common::bytes32;
    use endpoint_v2_common::guid::compute_guid;
    use endpoint_v2_common::packet_raw::{bytes_to_raw_packet, get_packet_bytes};
    use endpoint_v2_common::packet_v1_codec;
    use endpoint_v2_common::universal_config;
    use msglib_types::configs_uln;
    use uln_302::configuration;
    use uln_302::uln_302_store;
    use uln_302::verification::{
        check_verifiable,
        commit_verification,
        get_receive_uln_config_from_packet_header,
        is_verified,
        reclaim_storage,
        verify,
        verify_and_reclaim_storage,
    };

    fun setup() {
        universal_config::init_module_for_test(33333);
        uln_302_store::init_module_for_test();
    }

    #[test]
    fun test_verify_saves_entry_and_emits_event() {
        setup();

        verify(
            @1111,
            bytes_to_raw_packet(b"header"),
            bytes32::keccak256(b"payload_hash"),
            5,
        );

        let expected_header_hash = bytes32::to_bytes32(
            x"1fe1673da51f096dc3720c34d3002519bd6c4e0d13dc62302f0d04c06d30786e"
        );
        let confirmations = uln_302_store::get_verification_confirmations(
            expected_header_hash,
            bytes32::keccak256(b"payload_hash"),
            @1111,
        );

        assert!(confirmations == 5, 0);
    }

    #[test]
    fun test_check_verifiable_returns_true_when_verified() {
        setup();

        let config = configs_uln::new_uln_config(
            2,
            0,
            vector[@123],
            vector[],
            false,
            false,
            false,
        );
        configuration::set_default_receive_uln_config(1, config);

        verify(@123, bytes_to_raw_packet(b"header"), bytes32::keccak256(b"payload_hash"), 2);

        let verifiable = check_verifiable(
            &config,
            bytes32::keccak256(b"header"),
            bytes32::keccak256(b"payload_hash"),
        );

        assert!(verifiable, 0);
    }

    #[test]
    fun test_check_verifiable_returns_false_when_not_verified() {
        setup();

        let config = configs_uln::new_uln_config(
            2,
            2,
            vector[@123],
            vector[@456, @567, @678],
            false,
            false,
            false,
        );
        configuration::set_default_receive_uln_config(1, config);

        let packet_header = bytes_to_raw_packet(b"header");
        verify(@123, packet_header, bytes32::keccak256(b"payload_hash"), 2);
        verify(@456, packet_header, bytes32::keccak256(b"payload_hash"), 3);
        verify(@567, packet_header, bytes32::keccak256(b"payload_hash"), 1 /* insufficient confirmations */);

        let verifiable = check_verifiable(
            &config,
            bytes32::keccak256(b"header"),
            bytes32::keccak256(b"payload_hash"),
        );

        assert!(!verifiable, 0);
    }

    #[test]
    fun test_is_verified_returns_false_when_not_verified() {
        setup();

        let verified = is_verified(
            @1111,
            bytes32::keccak256(b"header"),
            bytes32::keccak256(b"payload_hash"),
            2,
        );

        assert!(!verified, 0);
    }

    #[test]
    fun test_commit_verification_reclaims_storage() {
        setup();

        let default_config = configs_uln::new_uln_config(
            2,
            2,
            vector[@123],
            vector[@456, @567, @678],
            false,
            false,
            false,
        );
        configuration::set_default_receive_uln_config(22222, default_config);

        // Store an oapp specific config
        let oapp_config = configs_uln::new_uln_config(
            2,
            0,
            vector[@712], // Intentionally different from default, to make sure Oapp config is used
            vector[],
            false,
            false,
            false,
        );
        configuration::set_receive_uln_config(@0x999999, 22222, oapp_config);
        let header = packet_v1_codec::new_packet_v1_header_only(
            22222, // matches eid in config
            bytes32::to_bytes32(x"0000000000000000000000000000000000000000000000000000000001111111"),
            33333,
            bytes32::to_bytes32(
                x"0000000000000000000000000000000000000000000000000000000000999999"
            ), // matches the oapp address
            123456,
        );
        let header_hash = bytes32::keccak256(get_packet_bytes(header));
        let payload_hash = bytes32::keccak256(b"payload_hash");
        let dvn_address = @712;

        // Receive a verification from the oapp selected required DVN
        verify(
            dvn_address,
            header,
            payload_hash,
            2,
        );

        // Confirmations should be present before reclaiming
        assert!(uln_302_store::has_verification_confirmations(header_hash, payload_hash, dvn_address), 0);

        commit_verification(
            header,
            bytes32::keccak256(b"payload_hash"),
        );

        // Confirmations should be removed after reclaiming
        assert!(!uln_302_store::has_verification_confirmations(header_hash, payload_hash, dvn_address), 0);

        let verifiable = check_verifiable(
            &oapp_config,
            header_hash,
            bytes32::keccak256(b"payload_hash"),
        );

        assert!(!verifiable, 0);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::packet_v1_codec::EINVALID_PACKET_HEADER)]
    fun test_commit_verification_asserts_packet_header() {
        setup();

        commit_verification(
            bytes_to_raw_packet(b"header"),
            bytes32::keccak256(b"payload_hash"),
        );
    }

    #[test]
    fun test_is_verified_returns_false_when_verified_but_insufficient_confirmations() {
        setup();

        verify(
            @1111,
            bytes_to_raw_packet(b"header"),
            bytes32::keccak256(b"payload_hash"),
            1,
        );

        let verified = is_verified(
            @1111,
            bytes32::keccak256(b"header"),
            bytes32::keccak256(b"payload_hash"),
            2,
        );

        assert!(!verified, 0);
    }


    #[test]
    fun test_is_verified_returns_true_when_verified() {
        setup();

        verify(
            @1111,
            bytes_to_raw_packet(b"header"),
            bytes32::keccak256(b"payload_hash"),
            5,
        );

        let verified = is_verified(
            @1111,
            bytes32::keccak256(b"header"),
            bytes32::keccak256(b"payload_hash"),
            2,
        );

        assert!(verified, 0);
    }

    #[test]
    fun test_get_receive_uln_config_from_packet_header_returns_default_config() {
        setup();

        let default_config = configs_uln::new_uln_config(
            2,
            2,
            vector[@123],
            vector[@456, @567, @678],
            false,
            false,
            false,
        );
        configuration::set_default_receive_uln_config(22222, default_config);

        let guid = compute_guid(
            123456,
            22222,
            bytes32::from_address(@0x654321),
            33333,
            bytes32::from_address(@0x123456)
        );
        let header = packet_v1_codec::new_packet_v1(
            22222,
            bytes32::from_address(@0x654321),
            33333,
            bytes32::from_address(@0x123456),
            123456,
            guid,
            b"",
        );
        let config = get_receive_uln_config_from_packet_header(&header);
        assert!(config == default_config, 0);
    }


    #[test]
    fun test_verify_and_reclaim_storage_reclaims_when_verified() {
        setup();

        let config = configs_uln::new_uln_config(
            2,
            0,
            vector[@123],
            vector[],
            false,
            false,
            false,
        );
        configuration::set_default_receive_uln_config(1, config);

        let dvn_address = @123;
        let payload_hash = bytes32::keccak256(b"payload");
        verify(
            dvn_address,
            bytes_to_raw_packet(b"header"),
            payload_hash,
            2,
        );

        let header_hash = bytes32::keccak256(b"header");

        // Confirmations should be present before reclaiming
        assert!(uln_302_store::has_verification_confirmations(header_hash, payload_hash, dvn_address), 0);
        assert!(uln_302_store::get_verification_confirmations(header_hash, payload_hash, dvn_address) == 2, 0);

        verify_and_reclaim_storage(
            &config,
            header_hash,
            payload_hash,
        );

        // Confirmations should be removed after reclaiming
        assert!(!uln_302_store::has_verification_confirmations(header_hash, payload_hash, dvn_address), 0);

        let verifiable = check_verifiable(
            &config,
            bytes32::keccak256(b"header"),
            bytes32::keccak256(b"payload_hash"),
        );

        assert!(!verifiable, 0);
    }

    #[test]
    fun test_reclaim_storage_removes_required_and_optional_confirmations() {
        setup();

        let required_dvns = vector[@123, @456];
        let optional_dvns = vector[@789];
        let header = bytes_to_raw_packet(b"header");
        let header_hash = bytes32::keccak256(get_packet_bytes(header));
        let payload_hash = bytes32::keccak256(b"payload_hash");

        verify(@123, header, payload_hash, 2);
        verify(@456, header, payload_hash, 2);
        verify(@789, header, payload_hash, 2);

        // Confirmations should be present before reclaiming
        assert!(uln_302_store::has_verification_confirmations(header_hash, payload_hash, @123), 0);
        assert!(uln_302_store::has_verification_confirmations(header_hash, payload_hash, @456), 1);
        assert!(uln_302_store::has_verification_confirmations(header_hash, payload_hash, @789), 2);

        reclaim_storage(&required_dvns, &optional_dvns, header_hash, payload_hash);

        // Confirmations should be removed after reclaiming
        assert!(!uln_302_store::has_verification_confirmations(header_hash, payload_hash, @123), 3);
        assert!(!uln_302_store::has_verification_confirmations(header_hash, payload_hash, @456), 4);
        assert!(!uln_302_store::has_verification_confirmations(header_hash, payload_hash, @789), 4);
    }

    #[test]
    fun test_check_verifiable_returns_true_verified_larger_set() {
        setup();

        let config = configs_uln::new_uln_config(
            2,
            2,
            vector[@123],
            vector[@456, @567, @678],
            false,
            false,
            false,
        );
        configuration::set_default_receive_uln_config(1, config);

        let header = bytes_to_raw_packet(b"header");
        verify(@123, header, bytes32::keccak256(b"payload_hash"), 2);
        verify(@456, header, bytes32::keccak256(b"payload_hash"), 3);
        verify(@567, header, bytes32::keccak256(b"payload_hash"), 2);

        let verifiable = check_verifiable(
            &config,
            bytes32::keccak256(b"header"),
            bytes32::keccak256(b"payload_hash"),
        );

        assert!(verifiable, 0);
    }
}