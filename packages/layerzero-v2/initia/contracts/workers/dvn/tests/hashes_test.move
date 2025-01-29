#[test_only]
module dvn::hashes_test {
    use dvn::hashes;
    use endpoint_v2_common::bytes32::to_bytes32;

    const VID: u32 = 1;
    const EXPIRATION: u64 = 2000;

    #[test]
    fun test_get_function_signature() {
        assert!(hashes::get_function_signature(b"verify") == x"7c40a351", 0);
        assert!(hashes::get_function_signature(b"set_dvn_signer") == x"1372c8d1", 1);
        assert!(hashes::get_function_signature(b"set_quorum") == x"17b7ccf9", 2);
        assert!(hashes::get_function_signature(b"set_allowlist") == x"934ff7eb", 3);
        assert!(hashes::get_function_signature(b"set_denylist") == x"8442b40b", 4);
        assert!(hashes::get_function_signature(b"quorum_change_admin") == x"73028773", 5);
    }

    #[test]
    fun test_create_verify_hash() {
        // Test params
        let packet_header = x"010000000000000001000000010000000000000000000000000000000000000000000000000000000000009099000000010000000000000000000000000000000000000000000000000000000000009099";
        let payload_hash = x"cc35f70cc84269e2bfe02824b3d69e4120e6a58302a8129c4e11d9d9777a38c0";
        let confirmations = 10;
        let target = @0x0000000000000000000000000000000000000000000000000000000000009005;
        // Expected results
        let expected_payload = x"7c40a351010000000000000001000000010000000000000000000000000000000000000000000000000000000000009099000000010000000000000000000000000000000000000000000000000000000000009099cc35f70cc84269e2bfe02824b3d69e4120e6a58302a8129c4e11d9d9777a38c0000000000000000a00000000000000000000000000000000000000000000000000000000000090050000000100000000000007d0";
        let expected_hash = to_bytes32(x"e3e8219995b9d75e7748415b6d54235f1d1cbec86f12d6602f423b7b20353799");
        assert!(
            hashes::build_verify_payload(
                packet_header,
                payload_hash,
                confirmations,
                target,
                VID,
                EXPIRATION,
            ) == expected_payload,
            0,
        );
        assert!(
            hashes::create_verify_hash(
                packet_header,
                payload_hash,
                confirmations,
                target,
                VID,
                EXPIRATION,
            ) == expected_hash,
            1,
        );
    }

    #[test]
    fun test_create_set_quorum_hash() {
        // Test params
        let quorum = 2;
        // Expected results
        let expected_payload = x"17b7ccf900000000000000020000000100000000000007d0";
        let expected_hash = to_bytes32(x"3064e840a7183166bb439dfb1de0f6befc2e1731efcbb90cc6178b6b42cf3584");
        assert!(hashes::build_set_quorum_payload(quorum, VID, EXPIRATION) == expected_payload, 0);
        assert!(hashes::create_set_quorum_hash(quorum, VID, EXPIRATION) == expected_hash, 1);
    }

    #[test]
    fun test_create_set_dvn_signer_hash() {
        // Test params
        let dvn_signer = x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d";
        let active = true;
        // Expected results
        let expected_payload = x"1372c8d1505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d010000000100000000000007d0";
        let expected_hash = to_bytes32(x"ad2262753ab5dab4d29c2437dd09d5bc6bdb4632e781d424f031d5cd5970728b");
        assert!(hashes::build_set_dvn_signer_payload(dvn_signer, active, VID, EXPIRATION) == expected_payload, 0);
        assert!(hashes::create_set_dvn_signer_hash(dvn_signer, active, VID, EXPIRATION) == expected_hash, 1);
    }

    #[test]
    fun test_create_set_allowlist_hash() {
        // Test params
        let sender = @9988;
        let allowed = true;
        // Expected results
        let expected_payload = x"934ff7eb0000000000000000000000000000000000000000000000000000000000002704010000000100000000000007d0";
        let expected_hash = to_bytes32(x"d418cb1c18cfd5d3fc1fbdac34a9d71fb4b56a8f2d074e36d497c8e0489c7a15");
        assert!(hashes::build_set_allowlist_payload(sender, allowed, VID, EXPIRATION) == expected_payload, 0);
        assert!(hashes::create_set_allowlist_hash(sender, allowed, VID, EXPIRATION) == expected_hash, 1);
    }

    #[test]
    fun test_create_set_denylist_hash() {
        // Test params
        let sender = @9988;
        let denied = true;
        // Expected results
        let expected_payload = x"8442b40b0000000000000000000000000000000000000000000000000000000000002704010000000100000000000007d0";
        let expected_hash = to_bytes32(x"67f702d40c8e4bd7c2d59cc2d772b0a8c2398a08336176f38118fd0f33704817");
        assert!(hashes::build_set_denylist_payload(sender, denied, VID, EXPIRATION) == expected_payload, 0);
        assert!(hashes::create_set_denylist_hash(sender, denied, VID, EXPIRATION) == expected_hash, 1);
    }

    #[test]
    fun test_create_quorum_change_admin_hash() {
        // Test params
        let admin = @0x0000000000000000000000000000000000000000000000000000000000002704;
        let active = true;
        // Expected results
        let expected_payload = x"730287730000000000000000000000000000000000000000000000000000000000002704010000000100000000000007d0";
        let expected_hash = to_bytes32(x"c8ee741967867d5a99e739baa2a57c8b480a438855a4fc0d7b5ea2e28a8deaa5");
        assert!(
            hashes::build_quorum_change_admin_payload(admin, active, VID, EXPIRATION) == expected_payload,
            0,
        );
        assert!(hashes::create_quorum_change_admin_hash(admin, active, VID, EXPIRATION) == expected_hash, 1);
    }

    #[test]
    fun test_create_set_msglibs_hash() {
        // Test params
        let msglibs = vector<address>[@1234, @2345];
        // Expected results
        let expected_payload = x"6456530e00000000000000000000000000000000000000000000000000000000000004d200000000000000000000000000000000000000000000000000000000000009290000000100000000000007d0";
        let expected_hash = to_bytes32(x"8796cf58bf29e0d42e08c3e9b3544b451c1881223d2d3e76ad6e39ff1ba8ec8b");
        assert!(hashes::build_set_msglibs_payload(msglibs, VID, EXPIRATION) == expected_payload, 0);
        assert!(hashes::create_set_msglibs_hash(msglibs, VID, EXPIRATION) == expected_hash, 1);
    }
}