#[test_only]
module worker_common::multisig_tests {
    use std::account::create_account_for_test;
    use std::event::was_event_emitted;

    use endpoint_v2_common::contract_identity::make_call_ref_for_test;
    use worker_common::multisig::{
        get_quorum, get_signers, initialize_for_worker_without_setting_signers, is_signer, set_quorum, set_signer,
        set_signers,
    };
    use worker_common::multisig::{
        initialize_for_worker_test_only as initialize_multisig, set_quorum_event, set_signers_event,
        update_signer_event,
    };
    use worker_common::worker_config::{initialize_for_worker_test_only as initialize_worker, WORKER_ID_DVN};

    const WORKER: address = @123456;

    #[test]
    fun test_initialize_for_worker_without_setting_signers() {
        let worker = &create_account_for_test(WORKER);
        initialize_for_worker_without_setting_signers(worker);
        assert!(get_quorum(WORKER) == 0, 0);
        assert!(get_signers(WORKER) == vector[], 0);

        let signers = vector[
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a",
            x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d"
        ];
        set_signers(&make_call_ref_for_test(WORKER), signers);
        assert!(was_event_emitted(&set_signers_event(WORKER, signers)), 0);

        set_quorum(&make_call_ref_for_test(WORKER), 1);
        assert!(was_event_emitted(&set_quorum_event(WORKER, 1)), 0);

        assert!(get_quorum(WORKER) == 1, 0);
        assert!(get_signers(WORKER) == signers, 0);
    }

    #[test]
    fun test_set_and_get_quorum() {
        initialize_worker(WORKER, WORKER_ID_DVN(), WORKER, @0x501ead, vector[@123], vector[], @0xfee11b);

        let signers = vector[
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a",
            x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d"
        ];
        initialize_multisig(WORKER, 1, signers);
        assert!(was_event_emitted(&set_signers_event(WORKER, signers)), 0);
        assert!(was_event_emitted(&set_quorum_event(WORKER, 1)), 0);
        assert!(get_quorum(WORKER) == 1, 0);
        set_quorum(&make_call_ref_for_test(WORKER), 2);
        assert!(was_event_emitted(&set_quorum_event(WORKER, 2)), 0);
        assert!(get_quorum(WORKER) == 2, 0);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::multisig_store::ESIGNERS_LESS_THAN_QUORUM)]
    fun test_initialize_fails_if_signers_less_than_quorum() {
        initialize_worker(WORKER, WORKER_ID_DVN(), WORKER, @0x501ead, vector[@123], vector[], @0xfee11b);

        let signers = vector[
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a",
            x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d"
        ];
        let quorum = 3;
        initialize_multisig(WORKER, quorum, signers);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::multisig_store::ESIGNERS_LESS_THAN_QUORUM)]
    fun test_set_quorum_fails_if_signers_less_than_quorum() {
        initialize_worker(WORKER, WORKER_ID_DVN(), WORKER, @0x501ead, vector[@123], vector[], @0xfee11b);

        let signers = vector[
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a",
            x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d"
        ];
        let quorum = 1;
        initialize_multisig(WORKER, quorum, signers);
        set_quorum(&make_call_ref_for_test(WORKER), 3);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::multisig_store::EZERO_QUORUM)]
    fun test_set_quorum_fails_if_zero() {
        initialize_worker(WORKER, WORKER_ID_DVN(), WORKER, @0x501ead, vector[@123], vector[], @0xfee11b);

        let signers = vector[
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a",
            x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d"
        ];
        let quorum = 1;
        initialize_multisig(WORKER, quorum, signers);
        set_quorum(&make_call_ref_for_test(WORKER), 0);
    }

    #[test]
    fun test_set_signers() {
        initialize_worker(WORKER, WORKER_ID_DVN(), WORKER, @0x501ead, vector[@123], vector[], @0xfee11b);
        let signers = vector[
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a",
        ];
        initialize_multisig(WORKER, 1, signers);
        assert!(was_event_emitted(&set_signers_event(WORKER, signers)), 0);
        assert!(was_event_emitted(&set_quorum_event(WORKER, 1)), 0);
        let signers = vector[
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a",
            x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d"
        ];
        set_signers(&make_call_ref_for_test(WORKER), signers);
        assert!(was_event_emitted(&set_signers_event(WORKER, signers)), 0);
        assert!(
            is_signer(
                WORKER,
                x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a"
            ),
            0,
        );
        assert!(
            is_signer(
                WORKER,
                x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d"
            ),
            1,
        );
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::assert_no_duplicates::EDUPLICATE_ITEM)]
    fun test_initialize_multisig_fails_if_duplicate_item() {
        initialize_worker(WORKER, WORKER_ID_DVN(), WORKER, @0x501ead, vector[@123], vector[], @0xfee11b);
        let signers = vector[
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a",
            x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d",
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a",
        ];
        initialize_multisig(WORKER, 1, signers);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::multisig_store::EINVALID_SIGNER_LENGTH)]
    fun test_initialize_fails_if_invalid_length() {
        initialize_worker(WORKER, WORKER_ID_DVN(), WORKER, @0x501ead, vector[@123], vector[], @0xfee11b);
        let signers = vector[
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a",
            x"1234567890", // invalid
            x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d",
        ];
        initialize_multisig(WORKER, 1, signers);
    }

    #[test]
    fun test_set_signer() {
        initialize_worker(WORKER, WORKER_ID_DVN(), WORKER, @0x501ead, vector[@123], vector[], @0xfee11b);
        let signers = vector[
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a",
            x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d"
        ];
        initialize_multisig(WORKER, 1, signers);


        // turn second signer on and off
        assert!(
            is_signer(
                WORKER,
                x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d"
            ),
            0,
        );
        set_signer(
            &make_call_ref_for_test(WORKER),
            x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d",
            false,
        );
        assert!(
            was_event_emitted(
                &update_signer_event(
                    WORKER,
                    x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d",
                    false,
                )
            ),
            0,
        );
        assert!(
            !is_signer(
                WORKER,
                x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d"
            ),
            0,
        );
        set_signer(
            &make_call_ref_for_test(WORKER),
            x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d",
            true,
        );
        assert!(
            was_event_emitted(
                &update_signer_event(
                    WORKER,
                    x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d",
                    true,
                )
            ),
            1,
        );
        assert!(
            is_signer(
                WORKER,
                x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d"
            ),
            0,
        );
    }

    #[test]
    #[expected_failure(abort_code = worker_common::multisig_store::ESIGNERS_LESS_THAN_QUORUM)]
    fun test_set_signer_fails_if_less_than_quorum() {
        initialize_worker(WORKER, WORKER_ID_DVN(), WORKER, @0x501ead, vector[@123], vector[], @0xfee11b);
        let signers = vector[
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a",
            x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d"
        ];
        initialize_multisig(WORKER, 2, signers);
        // try to turn second signer off: fails
        assert!(
            is_signer(
                WORKER,
                x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d"
            ),
            0,
        );
        set_signer(
            &make_call_ref_for_test(WORKER),
            x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d",
            false,
        );
    }

    #[test]
    #[expected_failure(abort_code = worker_common::multisig_store::EINVALID_SIGNER_LENGTH)]
    fun test_set_signer_fails_if_incorrect_length() {
        initialize_worker(WORKER, WORKER_ID_DVN(), WORKER, @0x501ead, vector[@123], vector[], @0xfee11b);
        let signers = vector[
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a",
            x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d"
        ];
        initialize_multisig(WORKER, 2, signers);
        set_signer(&make_call_ref_for_test(WORKER), x"1234567890", true);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::multisig_store::ESIGNER_ALREADY_EXISTS)]
    fun test_set_signer_fails_if_assigned_twice() {
        initialize_worker(WORKER, WORKER_ID_DVN(), WORKER, @0x501ead, vector[@123], vector[], @0xfee11b);
        let signers = vector[
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a",
        ];
        initialize_multisig(WORKER, 1, signers);
        let signer = x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d";
        set_signer(&make_call_ref_for_test(WORKER), signer, true);
        set_signer(&make_call_ref_for_test(WORKER), signer, true);
    }
}
