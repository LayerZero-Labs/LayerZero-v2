#[test_only]
module endpoint_v2_common::contract_identity_tests {
    use std::account::create_signer_for_test;

    use endpoint_v2_common::contract_identity;
    use endpoint_v2_common::contract_identity::irrecoverably_destroy_contract_signer;

    #[test]
    fun test_contract_identity() {
        let account = create_signer_for_test(@1234);
        let contract_signer = contract_identity::create_contract_signer(&account);
        let call_ref = contract_identity::make_dynamic_call_ref(&contract_signer, @5555, b"general");
        let caller = contract_identity::get_dynamic_call_ref_caller(&call_ref, @5555, b"general");
        assert!(caller == @1234, 0);
        irrecoverably_destroy_contract_signer(contract_signer);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::contract_identity::ECONTRACT_SIGNER_ALREADY_EXISTS)]
    fun test_contract_identity_fails_if_already_exists() {
        let account = create_signer_for_test(@1234);
        let cs1 = contract_identity::create_contract_signer(&account);
        let cs2 = contract_identity::create_contract_signer(&account);
        irrecoverably_destroy_contract_signer(cs1);
        irrecoverably_destroy_contract_signer(cs2);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::contract_identity::ETARGET_CONTRACT_MISMATCH)]
    fun test_get_caller_fails_if_incorrect_receiver() {
        let account = create_signer_for_test(@1234);
        let contract_signer = contract_identity::create_contract_signer(&account);
        let call_ref = contract_identity::make_dynamic_call_ref(&contract_signer, @5555, b"general");
        // shoud be @5555
        contract_identity::get_dynamic_call_ref_caller(&call_ref, @6666, b"general");
        irrecoverably_destroy_contract_signer(contract_signer);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::contract_identity::EAUTHORIZATION_MISMATCH)]
    fun test_get_caller_fails_if_incorrect_authorization() {
        let account = create_signer_for_test(@1234);
        let contract_signer = contract_identity::create_contract_signer(&account);
        let call_ref = contract_identity::make_dynamic_call_ref(&contract_signer, @5555, b"general");
        let caller = contract_identity::get_dynamic_call_ref_caller(&call_ref, @5555, b"other");
        assert!(caller == @1234, 0);
        irrecoverably_destroy_contract_signer(contract_signer);
    }

    struct TestTarget {}

    #[test]
    fun test_get_call_ref() {
        let account = create_signer_for_test(@3333);
        let contract_signer = contract_identity::create_contract_signer(&account);
        let call_ref = contract_identity::make_call_ref<TestTarget>(&contract_signer);
        let caller = contract_identity::get_call_ref_caller(&call_ref);
        assert!(caller == @3333, 0);
        irrecoverably_destroy_contract_signer(contract_signer);
    }
}
