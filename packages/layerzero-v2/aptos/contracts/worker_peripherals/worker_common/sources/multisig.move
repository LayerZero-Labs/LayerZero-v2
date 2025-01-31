// This multisig module was developed for use with DVN workers. It is used to manage the quorum and signers for
// a worker and to verify that the required number of signatures are present and valid when a change is made. It
// keeps track of used hashes to prevent the same command being replayed (all hashes should be hashed with an expiration
// time, which allows two of the otherwise same command to be called at different times).
// The important place where the configuration is used beyond direct multisig activity is that the fee_lib_0 depends on
// the quorum number set here to compute the send fee for the DVN, which scale with the quorum of signers required.
module worker_common::multisig {
    use std::event::emit;
    use std::signer::address_of;

    use endpoint_v2_common::bytes32::{Bytes32, to_bytes32};
    use endpoint_v2_common::contract_identity::{
        CallRef,
        get_call_ref_caller,
    };
    use worker_common::multisig_store;

    struct WorkerMultisigTarget {}

    /// Initialize the worker signing / multisig store without setting the signers
    /// This is useful for object deployment where the object signer may not be available after init_module.
    /// Note: The worker will be responsible for ensuring all fields are initialized, for example, the quorum will be
    /// 0 until set by the worker.
    public fun initialize_for_worker_without_setting_signers(account: &signer) {
        multisig_store::initialize_for_worker(account);
    }

    /// Initialize the worker signing / multisig store
    /// The signers provided are the public keys of the signers that are allowed to sign for the worker
    /// A quorum of signatures is required to sign for a transaction to succeed
    public fun initialize_for_worker(account: &signer, quorum: u64, signers: vector<vector<u8>>) {
        multisig_store::initialize_for_worker(account);
        let worker = address_of(move account);
        multisig_store::set_multisig_signers(worker, signers);
        emit(SetSigners { worker, multisig_signers: signers });
        multisig_store::set_quorum(worker, quorum);
        emit(SetQuorum { worker, quorum });
    }

    #[test_only]
    /// Initialize the worker signing / multisig store for testing purposes
    public fun initialize_for_worker_test_only(worker: address, quorum: u64, signers: vector<vector<u8>>) {
        let account = &std::account::create_signer_for_test(worker);
        initialize_for_worker(account, quorum, signers);
    }

    /// Assert that all signatures are valid, it is not expired, and add the hash to the history or abort if it is
    /// present. This will abort if the hash has already been used, expired, or the signatures are invalid
    /// *Important*: The `hash` must be the result of a hash operation to be secure. The caller should ensure that the
    /// expiry time provided is a component of the hash provided
    public fun assert_all_and_add_to_history(
        call_ref: &CallRef<WorkerMultisigTarget>,
        signatures: &vector<u8>,
        expiration: u64,
        hash: Bytes32,
    ) {
        let worker = get_call_ref_caller(call_ref);
        multisig_store::assert_initialized(worker);
        multisig_store::assert_all_and_add_to_history(worker, signatures, expiration, hash);
    }

    /// Set the quorum required for a worker
    public fun set_quorum(call_ref: &CallRef<WorkerMultisigTarget>, quorum: u64) {
        let worker = get_call_ref_caller(call_ref);
        multisig_store::assert_initialized(worker);
        multisig_store::set_quorum(worker, quorum);
        emit(SetQuorum { worker, quorum });
    }

    /// Set the signers (public keys) for a worker
    public fun set_signers(call_ref: &CallRef<WorkerMultisigTarget>, multisig_signers: vector<vector<u8>>) {
        let worker = get_call_ref_caller(call_ref);
        multisig_store::assert_initialized(worker);
        multisig_store::set_multisig_signers(worker, multisig_signers);
        emit(SetSigners { worker, multisig_signers });
    }

    /// Set a signer (public key) for a worker
    /// `active` param refers to whether the signer should be added (true) or deleted (false)
    public fun set_signer(call_ref: &CallRef<WorkerMultisigTarget>, multisig_signer: vector<u8>, active: bool) {
        let worker = get_call_ref_caller(call_ref);
        multisig_store::assert_initialized(worker);
        if (active) {
            multisig_store::add_multisig_signer(worker, multisig_signer);
        } else {
            multisig_store::remove_multisig_signer(worker, multisig_signer);
        };
        emit(UpdateSigner { worker, multisig_signer, active });
    }

    #[view]
    /// Get the quorum required for a worker
    public fun get_quorum(worker: address): u64 {
        multisig_store::assert_initialized(worker);
        multisig_store::get_quorum(worker)
    }

    #[view]
    /// Get the signers (public keys) for a worker
    public fun get_signers(worker: address): vector<vector<u8>> {
        multisig_store::assert_initialized(worker);
        multisig_store::get_multisig_signers(worker)
    }

    #[view]
    /// Check if a signer (public key) is a signer for a worker
    public fun is_signer(worker: address, multisig_signer: vector<u8>): bool {
        multisig_store::assert_initialized(worker);
        multisig_store::is_multisig_signer(worker, multisig_signer)
    }

    #[view]
    /// Check if a specific hash has already been used to submit a transaction
    public fun was_hash_used(worker: address, hash: vector<u8>): bool {
        multisig_store::assert_initialized(worker);
        multisig_store::was_hash_used(worker, to_bytes32(hash))
    }


    // ==================================================== Events ====================================================

    #[event]
    /// Emitted when the quorum is set for a worker
    struct SetQuorum has store, drop { worker: address, quorum: u64 }

    #[event]
    /// Emitted when the signers are set for a worker
    struct SetSigners has store, drop { worker: address, multisig_signers: vector<vector<u8>> }

    #[event]
    /// Emitted when a signer is added or removed for a worker
    struct UpdateSigner has store, drop {
        worker: address,
        multisig_signer: vector<u8>,
        active: bool,
    }

    #[test_only]
    /// Generates a SetQuorum event for testing
    public fun set_quorum_event(worker: address, quorum: u64): SetQuorum {
        SetQuorum { worker, quorum }
    }

    #[test_only]
    /// Generates a SetSigners event for testing
    public fun set_signers_event(worker: address, multisig_signers: vector<vector<u8>>): SetSigners {
        SetSigners { worker, multisig_signers }
    }

    #[test_only]
    /// Generates an UpdateSigner event for testing
    public fun update_signer_event(worker: address, multisig_signer: vector<u8>, active: bool): UpdateSigner {
        UpdateSigner { worker, multisig_signer, active }
    }
}
