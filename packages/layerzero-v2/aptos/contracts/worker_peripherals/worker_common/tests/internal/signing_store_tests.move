#[test_only]
module worker_common::signing_store_tests {
    use std::account::create_signer_for_test;
    use std::vector;

    use endpoint_v2_common::bytes32::Bytes32;
    use endpoint_v2_common::serde::{Self, flatten};
    use worker_common::multisig_store::{
        assert_not_expired,
        assert_signatures_verified_internal,
        get_pubkey,
        split_signatures,
    };

    const DVN_WORKER_ID: u8 = 2;

    #[test]
    public fun test_assert_not_expired() {
        let native_framework = &create_signer_for_test(@std);
        std::timestamp::set_time_has_started_for_testing(native_framework);
        std::timestamp::update_global_time_for_test_secs(1000);

        assert_not_expired(1000000);
        assert_not_expired(1500);
        assert_not_expired(1001);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::multisig_store::EEXPIRED_SIGNATURE)]
    public fun test_assert_not_expired_fails_if_expired() {
        let native_framework = &create_signer_for_test(@std);
        std::timestamp::set_time_has_started_for_testing(native_framework);
        std::timestamp::update_global_time_for_test_secs(1000);

        assert_not_expired(1000);
    }

    #[test]
    fun test_get_pubkey() {
        let expiration = 1677465966;
        let expected_pubkey = x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a";
        let signature_with_recovery = x"ee6c9646b2c55672734f06acb7347548f605046adcdf9ff080287ed0699779f6246c167cd30c6630cf5aa2cb157398b7b74237b18415cbd2e66bc0b2bff08f1a00";
        let quorum = 2;
        let hash = create_set_quorum_hash(quorum, expiration);
        let generated_pubkey = get_pubkey(&signature_with_recovery, hash);
        assert!(generated_pubkey == expected_pubkey, 0);
    }


    #[test]
    fun test_assert_signatures_verified_internal() {
        let expiration = 1677465966;
        let pubkey1 = x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a";
        let pubkey2 = x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d";
        let pubkey3 = x"37bdab42a45e9d6cc56f7d0cc7897e871a0357bce3f0f4c99c93c54291b259a29a92111167a25ae188ef49b2f3df880d8aae8522e29cb6c299745258a200cfff";
        let dvn_signers = &mut vector<vector<u8>>[pubkey1, pubkey2, pubkey3];

        let signature1 = x"ee6c9646b2c55672734f06acb7347548f605046adcdf9ff080287ed0699779f6246c167cd30c6630cf5aa2cb157398b7b74237b18415cbd2e66bc0b2bff08f1a00";
        let signature2 = x"b3d37d05832d808934f88e3f53ff2002e71125031543806964c0b1537f3abb694593f3b6b49f87caa1ca96e0cb955c24cb0865be8fc331b44a0afaf95480031f01";
        let signature3 = x"535e6f18117f1940ba3afef15d72dfc28cd0ab88ffa6d276c04c9d639f744352224f1c5a52046ef3962d444d15c6462dfe123665586e704b74704be22bcc8e1c00";
        let signatures = vector[signature1, signature2, signature3];

        let quorum = 2;
        let hash = create_set_quorum_hash(quorum, expiration);
        assert_signatures_verified_internal(&signatures, hash, dvn_signers, quorum);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::multisig_store::EDVN_LESS_THAN_QUORUM)]
    fun test_assert_signatures_verified_internal_fails_if_quorum_not_met() {
        let expiration = 1677465966;
        let pubkey1 = x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a";
        let pubkey2 = x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d";
        let pubkey3 = x"37bdab42a45e9d6cc56f7d0cc7897e871a0357bce3f0f4c99c93c54291b259a29a92111167a25ae188ef49b2f3df880d8aae8522e29cb6c299745258a200cfff";
        let dvn_signers = &mut vector[pubkey1, pubkey2, pubkey3];

        let signature1 = x"ee6c9646b2c55672734f06acb7347548f605046adcdf9ff080287ed0699779f6246c167cd30c6630cf5aa2cb157398b7b74237b18415cbd2e66bc0b2bff08f1a00";
        let signatures = vector[signature1];

        let quorum = 2;
        let hash = create_set_quorum_hash(quorum, expiration);
        assert_signatures_verified_internal(&signatures, hash, dvn_signers, quorum);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::multisig_store::EDVN_INCORRECT_SIGNATURE)]
    fun test_assert_signatures_verified_internal_fails_if_any_signature_is_invalid() {
        let expiration = 1677465966;
        let pubkey1 = x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a";
        let pubkey2 = x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d";
        let pubkey3 = x"37bdab42a45e9d6cc56f7d0cc7897e871a0357bce3f0f4c99c93c54291b259a29a92111167a25ae188ef49b2f3df880d8aae8522e29cb6c299745258a200cfff";
        let dvn_signers = &mut vector[pubkey1, pubkey2, pubkey3];

        let signature1 = x"ee6c9646b2c55672734f06acb7347548f605046adcdf9ff080287ed0699779f6246c167cd30c6630cf5aa2cb157398b7b74237b18415cbd2e66bc0b2bff08f1a00";
        let signature2 = x"aaaa7d05832d808934f88e3f53ff2002e71125031543806964c0b1537f3abb694593f3b6b49f87caa1ca96e0cb955c24cb0865be8fc331b44a0afaf95480031f01";  // invalid
        let signature3 = x"535e6f18117f1940ba3afef15d72dfc28cd0ab88ffa6d276c04c9d639f744352224f1c5a52046ef3962d444d15c6462dfe123665586e704b74704be22bcc8e1c00";
        let signatures = vector[signature1, signature2, signature3];

        let quorum = 2;
        let hash = create_set_quorum_hash(quorum, expiration);
        assert_signatures_verified_internal(&signatures, hash, dvn_signers, quorum);
    }

    #[test]
    fun test_split_and_join_signatures() {
        let signature1 = x"ee6c9646b2c55672734f06acb7347548f605046adcdf9ff080287ed0699779f6246c167cd30c6630cf5aa2cb157398b7b74237b18415cbd2e66bc0b2bff08f1a00";
        let signature2 = x"b3d37d05832d808934f88e3f53ff2002e71125031543806964c0b1537f3abb694593f3b6b49f87caa1ca96e0cb955c24cb0865be8fc331b44a0afaf95480031f01";
        let signature3 = x"535e6f18117f1940ba3afef15d72dfc28cd0ab88ffa6d276c04c9d639f744352224f1c5a52046ef3962d444d15c6462dfe123665586e704b74704be22bcc8e1c00";
        let joined = flatten(vector[signature1, signature2, signature3]);

        let expected = vector[signature1, signature2, signature3];
        assert!(split_signatures(&joined) == expected, 0);
    }


    #[test]
    #[expected_failure(abort_code = worker_common::multisig_store::EINVALID_SIGNATURE_LENGTH)]
    fun test_split_signatures_fails_if_invalid_length() {
        // 64 bytes instead of 65
        let signatures = x"ee6c9646b2c55672734f06acb7347548f605046adcdf9ff080287ed0699779f6246c167cd30c6630cf5aa2cb157398b7b74237b18415cbd2e66bc0b2bff08f1a";
        split_signatures(&signatures);
    }


    public fun create_set_quorum_hash(quorum: u64, expiration: u64): Bytes32 {
        endpoint_v2_common::bytes32::keccak256(
            build_set_quorum_payload(quorum, expiration)
        )
    }

    fun build_set_quorum_payload(quorum: u64, expiration: u64): vector<u8> {
        let payload = vector[];
        serde::append_bytes(&mut payload, get_function_signature(b"set_quorum"));
        serde::append_u64(&mut payload, quorum);
        serde::append_u64(&mut payload, expiration);
        payload
    }

    fun get_function_signature(function_name: vector<u8>): vector<u8> {
        vector::slice(&std::aptos_hash::keccak256(std::bcs::to_bytes(&function_name)), 0, 4)
    }
}
