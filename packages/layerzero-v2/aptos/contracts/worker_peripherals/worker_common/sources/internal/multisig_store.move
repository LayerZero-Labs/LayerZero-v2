module worker_common::multisig_store {
    use std::option;
    use std::signer::address_of;
    use std::table::{Self, Table};
    use std::vector;

    use endpoint_v2_common::assert_no_duplicates::assert_no_duplicates;
    use endpoint_v2_common::bytes32::{Bytes32, from_bytes32};

    friend worker_common::multisig;

    #[test_only]
    friend worker_common::signing_store_tests;

    const PUBKEY_SIZE: u64 = 64;
    const SIGNATURE_SIZE: u64 = 65;  // 64 bytes signature + 1 byte recovery id

    struct SigningStore has key {
        quorum: u64,
        signers: vector<vector<u8>>,
        used_hashes: Table<Bytes32, bool>,
    }

    public(friend) fun initialize_for_worker(worker_account: &signer) {
        let worker_address = address_of(worker_account);
        assert!(!exists<SigningStore>(worker_address), EWORKER_ALREADY_INITIALIZED);
        move_to<SigningStore>(move worker_account, SigningStore {
            quorum: 0,
            signers: vector[],
            used_hashes: table::new(),
        });
    }

    /// Mark the hash as used after asserting that the hash is not expired, signatures are verified, and the hash has
    /// not been previously used
    public(friend) fun assert_all_and_add_to_history(
        worker: address,
        signatures: &vector<u8>,
        expiry: u64,
        hash: Bytes32,
    ) acquires SigningStore {
        assert_not_expired(expiry);
        assert_signatures_verified(worker, signatures, hash);
        assert!(!was_hash_used(worker, hash), EHASH_ALREADY_USED);
        add_hash_to_used(worker, hash);
    }

    /// Asserts that multiple signatures match the provided pub keys at the provided quorum threshold
    fun assert_signatures_verified(
        worker: address,
        signatures_joined: &vector<u8>,
        hash: Bytes32,
    ) acquires SigningStore {
        let signatures = &split_signatures(signatures_joined);
        let quorum = get_quorum(worker);
        let signers = get_multisig_signers(worker);
        assert_signatures_verified_internal(signatures, hash, &signers, quorum);
    }

    /// Internal - asserts that multiple signatures match the provided pub keys at the provided quorum threshold
    public(friend) fun assert_signatures_verified_internal(
        signatures: &vector<vector<u8>>,
        hash: Bytes32,
        multisig_signers: &vector<vector<u8>>,
        quorum: u64,
    ) {
        let signatures_count = vector::length(signatures);
        assert!(signatures_count >= quorum, EDVN_LESS_THAN_QUORUM);

        let pub_keys_verified = &mut vector[];
        for (i in 0..signatures_count) {
            let pubkey_bytes = get_pubkey(vector::borrow(signatures, i), hash);
            assert!(vector::contains(multisig_signers, &pubkey_bytes), EDVN_INCORRECT_SIGNATURE);
            assert!(!vector::contains(pub_keys_verified, &pubkey_bytes), EDVN_DUPLICATE_PK);
            vector::push_back(pub_keys_verified, pubkey_bytes);
        }
    }

    /// Internal - gets the pubkey given a signature
    public(friend) fun get_pubkey(signature_with_recovery: &vector<u8>, hash: Bytes32): vector<u8> {
        let signature = vector::slice(signature_with_recovery, 0, 64);
        let recovery_id = *vector::borrow(signature_with_recovery, 64);

        let ecdsa_signature = std::secp256k1::ecdsa_signature_from_bytes(signature);
        let pubkey = std::secp256k1::ecdsa_recover(
            from_bytes32(hash),
            recovery_id,
            &ecdsa_signature,
        );
        assert!(std::option::is_some(&pubkey), EDVN_INCORRECT_SIGNATURE);
        std::secp256k1::ecdsa_raw_public_key_to_bytes(option::borrow(&pubkey))
    }

    /// Internal - splits a vector of signatures into a vector of vectors of signatures
    public(friend) fun split_signatures(signatures: &vector<u8>): vector<vector<u8>> {
        let bytes_length = vector::length(signatures);
        assert!(bytes_length % SIGNATURE_SIZE == 0, EINVALID_SIGNATURE_LENGTH);

        let signatures_vector = vector[];
        let i = 0;
        while (i < bytes_length) {
            let signature = vector::slice(signatures, i, i + SIGNATURE_SIZE);
            vector::push_back(&mut signatures_vector, signature);
            i = i + SIGNATURE_SIZE;
        };
        signatures_vector
    }

    public(friend) fun assert_not_expired(expiration: u64) {
        let current_time = std::timestamp::now_seconds();
        assert!(expiration > current_time, EEXPIRED_SIGNATURE);
    }

    public(friend) fun set_quorum(worker: address, quorum: u64) acquires SigningStore {
        let store = signing_store_mut(worker);
        let signer_count = vector::length(&store.signers);
        assert!(quorum > 0, EZERO_QUORUM);
        assert!(quorum <= signer_count, ESIGNERS_LESS_THAN_QUORUM);
        store.quorum = quorum;
    }

    public(friend) fun get_quorum(worker: address): u64 acquires SigningStore {
        signing_store(worker).quorum
    }

    public(friend) fun set_multisig_signers(
        worker: address,
        multisig_signers: vector<vector<u8>>,
    ) acquires SigningStore {
        assert_no_duplicates(&multisig_signers);
        vector::for_each_ref(&multisig_signers, |signer| {
            assert!(vector::length(signer) == PUBKEY_SIZE, EINVALID_SIGNER_LENGTH);
        });
        let store = signing_store_mut(worker);
        assert!(store.quorum <= vector::length(&multisig_signers), ESIGNERS_LESS_THAN_QUORUM);
        store.signers = multisig_signers;
    }

    public(friend) fun add_multisig_signer(worker: address, multisig_signer: vector<u8>) acquires SigningStore {
        let multisig_signers = &mut signing_store_mut(worker).signers;
        assert!(!vector::contains(multisig_signers, &multisig_signer), ESIGNER_ALREADY_EXISTS);
        assert!(vector::length(&multisig_signer) == PUBKEY_SIZE, EINVALID_SIGNER_LENGTH);
        vector::push_back(multisig_signers, multisig_signer);
    }

    public(friend) fun remove_multisig_signer(worker: address, multisig_signer: vector<u8>) acquires SigningStore {
        let (found, index) = vector::index_of(&signing_store(worker).signers, &multisig_signer);
        assert!(found, ESIGNER_NOT_FOUND);
        vector::swap_remove(&mut signing_store_mut(worker).signers, index);
        let store = signing_store(worker);
        assert!(vector::length(&store.signers) >= store.quorum, ESIGNERS_LESS_THAN_QUORUM);
    }

    public(friend) fun is_multisig_signer(worker: address, multisig_signer: vector<u8>): bool acquires SigningStore {
        let multisig_signers = &signing_store(worker).signers;
        vector::contains(multisig_signers, &multisig_signer)
    }

    public(friend) fun get_multisig_signers(worker: address): vector<vector<u8>> acquires SigningStore {
        signing_store(worker).signers
    }

    public(friend) fun was_hash_used(worker: address, hash: Bytes32): bool acquires SigningStore {
        let dvn_used_hashes = &signing_store(worker).used_hashes;
        table::contains(dvn_used_hashes, hash)
    }

    public(friend) fun add_hash_to_used(worker: address, hash: Bytes32) acquires SigningStore {
        let dvn_used_hashes = &mut signing_store_mut(worker).used_hashes;
        table::add(dvn_used_hashes, hash, true);
    }

    public(friend) fun assert_initialized(worker: address) {
        assert!(exists<SigningStore>(worker), EWORKER_MULTISIG_NOT_REGISTERED);
    }

    // ==================================================== Helpers ===================================================

    inline fun signing_store(worker: address): &SigningStore { borrow_global(worker) }

    inline fun signing_store_mut(worker: address): &mut SigningStore { borrow_global_mut(worker) }

    // ================================================== Error Codes =================================================

    const EWORKER_ALREADY_INITIALIZED: u64 = 1;
    const EDVN_INCORRECT_SIGNATURE: u64 = 2;
    const EWORKER_MULTISIG_NOT_REGISTERED: u64 = 3;
    const EDVN_DUPLICATE_PK: u64 = 4;
    const EDVN_LESS_THAN_QUORUM: u64 = 5;
    const EINVALID_SIGNATURE_LENGTH: u64 = 6;
    const EEXPIRED_SIGNATURE: u64 = 7;
    const EHASH_ALREADY_USED: u64 = 8;
    const ESIGNERS_LESS_THAN_QUORUM: u64 = 9;
    const ESIGNER_NOT_FOUND: u64 = 10;
    const ESIGNER_ALREADY_EXISTS: u64 = 11;
    const EINVALID_SIGNER_LENGTH: u64 = 12;
    const EZERO_QUORUM: u64 = 13;
}
