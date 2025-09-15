/// MultiSig module for handling signature verification and signer management
module dvn::multisig;

use sui::{ecdsa_k1, event, vec_set::{Self, VecSet}};

// === Constants ===

// Signer validation constants
const PUBKEY_SIZE: u64 = 64;
const SIGNATURE_SIZE: u64 = 65;

// === Errors ===

const EDuplicatedSigner: u64 = 1;
const EInvalidSignatureLength: u64 = 2;
const EInvalidSignerLength: u64 = 3;
const EQuorumIsZero: u64 = 4;
const ESignaturesLessThanQuorum: u64 = 5;
const ESignerAlreadyExists: u64 = 6;
const ESignerNotFound: u64 = 7;
const ESignerNotInCommittee: u64 = 8;
const ESignersSizeIsLessThanQuorum: u64 = 9;

// === Events ===

public struct UpdateSignerEvent has copy, drop {
    dvn: address,
    signer: vector<u8>,
    active: bool,
}

public struct UpdateQuorumEvent has copy, drop {
    dvn: address,
    quorum: u64,
}

// === Structs ===

/// MultiSig configuration and state
public struct MultiSig has store {
    /// Multisig signers (public keys)
    signers: VecSet<vector<u8>>,
    /// Required number of signatures (quorum)
    quorum: u64,
}

// === Initialization ===

/// Create a new MultiSig instance
public(package) fun new(initial_signers: vector<vector<u8>>, quorum: u64): MultiSig {
    let signer_count = initial_signers.length();
    assert!(quorum > 0, EQuorumIsZero);
    assert!(quorum <= signer_count, ESignersSizeIsLessThanQuorum);

    let mut signers = vec_set::empty();
    // Add initial signers with validation
    initial_signers.do!(|signer| {
        assert!(signer.length() == PUBKEY_SIZE, EInvalidSignerLength);
        signers.insert(signer);
    });

    MultiSig { signers, quorum }
}

// === Signer Management ===

/// Set signer status (add or remove)
public(package) fun set_signer(self: &mut MultiSig, dvn: address, signer: vector<u8>, active: bool) {
    assert!(signer.length() == PUBKEY_SIZE, EInvalidSignerLength);
    if (active) {
        assert!(!self.signers.contains(&signer), ESignerAlreadyExists);
        self.signers.insert(signer);
    } else {
        assert!(self.signers.contains(&signer), ESignerNotFound);
        self.signers.remove(&signer);
    };
    assert!(self.signers.size() >= self.quorum, ESignersSizeIsLessThanQuorum);
    event::emit(UpdateSignerEvent { dvn, signer, active });
}

/// Set quorum
public(package) fun set_quorum(self: &mut MultiSig, dvn: address, quorum: u64) {
    assert!(quorum > 0, EQuorumIsZero);
    assert!(quorum <= self.signers.size(), ESignersSizeIsLessThanQuorum);
    self.quorum = quorum;
    event::emit(UpdateQuorumEvent { dvn, quorum });
}

// === Signature Verification ===

/// Assert signatures are verified (aborts on failure)
public(package) fun assert_signatures_verified(self: &MultiSig, payload: vector<u8>, signatures: &vector<u8>) {
    assert!(signatures.length() % SIGNATURE_SIZE == 0, EInvalidSignatureLength);
    let signature_count = signatures.length() / SIGNATURE_SIZE;

    assert!(signature_count >= self.quorum, ESignaturesLessThanQuorum);

    let mut used_signers: vector<vector<u8>> = vector::empty();

    let mut i = 0;
    while (i < self.quorum) {
        let signature_start = i * SIGNATURE_SIZE;
        let signature = vector::tabulate!(SIGNATURE_SIZE, |i| signatures[signature_start + i]);

        let recovered_pubkey = ecdsa_k1::secp256k1_ecrecover(&signature, &payload, 0);
        // The recovered pubkey is compressed, so we need to decompress it
        let uncompressed_pubkey = decompress_pubkey(recovered_pubkey);
        assert!(!used_signers.contains(&uncompressed_pubkey), EDuplicatedSigner);
        assert!(self.signers.contains(&uncompressed_pubkey), ESignerNotInCommittee);
        used_signers.push_back(uncompressed_pubkey);

        i = i + 1;
    };
}

// === View Functions ===

/// Check if address is signer
public(package) fun is_signer(self: &MultiSig, signer: vector<u8>): bool {
    self.signers.contains(&signer)
}

/// Get number of signers
public(package) fun signer_count(self: &MultiSig): u64 {
    self.signers.size()
}

/// Get all signers as a vector
public(package) fun get_signers(self: &MultiSig): vector<vector<u8>> {
    self.signers.into_keys()
}

/// Get quorum
public(package) fun quorum(self: &MultiSig): u64 {
    self.quorum
}

// === Internal Functions ===

/// Decompress the pubkey from the compressed format to the uncompressed format
/// The uncompressed pubkey is 65 bytes, the first byte is the un-compressed prefix (0x04)
/// We need to skip the first byte and return the remaining 64 bytes
fun decompress_pubkey(pubkey: vector<u8>): vector<u8> {
    let uncompressed_pubkey = ecdsa_k1::decompress_pubkey(&pubkey);
    vector::tabulate!(64, |i| uncompressed_pubkey[i + 1])
}

// === Test Functions ===

#[test_only]
public(package) fun create_update_signer_event(dvn: address, signer: vector<u8>, active: bool): UpdateSignerEvent {
    UpdateSignerEvent { dvn, signer, active }
}

#[test_only]
public(package) fun create_update_quorum_event(dvn: address, quorum: u64): UpdateQuorumEvent {
    UpdateQuorumEvent { dvn, quorum }
}
