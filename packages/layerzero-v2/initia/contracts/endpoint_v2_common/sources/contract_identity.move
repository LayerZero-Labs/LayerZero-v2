/// This module defines structs for contracts to authenticate themselves and prove authorization for specific actions
///
/// The *ContractSigner* is stored by the contract after producing it in init_module(). It can only be generated one
/// time per address to defend against impersonation attacks. It is copiable however, so that it can be explicitly
/// shared if required.
///
/// This can be used to generate a *CallRef* which is passed to the callee. There is a generic CallRef<Target> struct,
/// in which the `Target` should be substituted with a struct defined in the callee module that represents the
/// authorization type granted by the caller.
///
/// The *DynamicCallRef* is used to pass the target contract address and an authorization byte-vector to the callee.
/// This is useful when the target contract address is not known at compile time. Upon receiving a DynamicCallRef,
/// the callee should use the `get_dynamic_call_ref_caller` function to identify the caller and verify the authorization
/// matches the expected authorization for the call.
///
/// The Target and the (address, authorization) pair are useful to mitigate the risk of a call ref being used to perform
/// an action that was not intended by the caller.
module endpoint_v2_common::contract_identity {
    use std::signer::address_of;

    struct SignerCreated has key {}

    /// Struct to persist the contract identity
    /// Access to the contract signer provides universal access to the contract's authority and should be protected
    struct ContractSigner has store, copy { contract_address: address }

    /// A Static call reference that can be used to identify the caller and statically validate the authorization
    struct CallRef<phantom Target> has drop { contract_address: address }

    /// A Dynamic call reference that can be used to identify the caller and validate the intended target contract
    /// and authorization
    struct DynamicCallRef has drop { contract_address: address, target_contract: address, authorization: vector<u8> }

    /// Creates a ContractSigner for the contract to store and use for generating ContractCallRefs
    /// Make a record of the creation to prevent future contract signer creation
    public fun create_contract_signer(account: &signer): ContractSigner {
        assert!(!exists<SignerCreated>(address_of(account)), ECONTRACT_SIGNER_ALREADY_EXISTS);
        move_to(account, SignerCreated {});
        ContractSigner { contract_address: address_of(account) }
    }

    /// Destroys the contract signer - once destroyed the contract signer cannot be recreated using
    /// `create_contract_signer`; however, any copies of the contract signer will continue to exist
    public fun irrecoverably_destroy_contract_signer(contract_signer: ContractSigner) {
        let ContractSigner { contract_address: _ } = contract_signer;
    }

    /// Make a static call ref from a ContractSigner
    /// Generally the target does not have to be specified as it can be inferred from the function signature it is
    /// used with
    public fun make_call_ref<Target>(contract: &ContractSigner): CallRef<Target> {
        CallRef { contract_address: contract.contract_address }
    }

    /// Get the calling contract address from a static CallRef
    public fun get_call_ref_caller<Target>(call_ref: &CallRef<Target>): address {
        call_ref.contract_address
    }

    /// This function is used to create a ContractCallRef from a ContractSigner
    public fun make_dynamic_call_ref(
        contract: &ContractSigner,
        target_contract: address,
        authorization: vector<u8>,
    ): DynamicCallRef {
        DynamicCallRef { contract_address: contract.contract_address, target_contract, authorization }
    }

    /// This function is used to get the calling contract address, while asserting that the recipient is the correct
    /// receiver contract
    public fun get_dynamic_call_ref_caller(
        call_ref: &DynamicCallRef,
        receiver_to_assert: address,
        authorization_to_assert: vector<u8>,
    ): address {
        assert!(call_ref.target_contract == receiver_to_assert, ETARGET_CONTRACT_MISMATCH);
        assert!(call_ref.authorization == authorization_to_assert, EAUTHORIZATION_MISMATCH);
        call_ref.contract_address
    }

    #[test_only]
    public fun make_call_ref_for_test<Target>(contract_address: address): CallRef<Target> {
        CallRef { contract_address }
    }

    #[test_only]
    public fun make_dynamic_call_ref_for_test(
        contract_address: address,
        target_contract: address,
        authorization: vector<u8>,
    ): DynamicCallRef {
        DynamicCallRef { contract_address, target_contract, authorization }
    }

    // ================================================== Error Codes =================================================

    const EAUTHORIZATION_MISMATCH: u64 = 1;
    const ECONTRACT_SIGNER_ALREADY_EXISTS: u64 = 2;
    const ETARGET_CONTRACT_MISMATCH: u64 = 2;
}
