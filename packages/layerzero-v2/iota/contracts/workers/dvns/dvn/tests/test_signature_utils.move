#[test_only]
module dvn::test_signature_utils;

use dvn::hashes;
use ptb_move_call::move_call::MoveCall;
use iota::ecdsa_k1::{Self, KeyPair};

// Test constants
const VID: u32 = 1001;
const TEST_EXPIRATION: u64 = 9999999999;
const PAST_EXPIRATION: u64 = 1000;

// === Keypair Generation ===

/// Generate a test keypair from an index (1, 2, 3, etc.)
public fun generate_test_keypair(index: u8): KeyPair {
    let mut seed = vector::empty<u8>();
    // Pad with zeros (31 bytes)
    let mut i = 0;
    while (i < 31) {
        vector::push_back(&mut seed, 0u8);
        i = i + 1;
    };
    // Add the index as the last byte
    vector::push_back(&mut seed, index);

    ecdsa_k1::secp256k1_keypair_from_seed(&seed)
}

/// Get public key from keypair (64 bytes without compression prefix)
public fun get_public_key(keypair: &KeyPair): vector<u8> {
    let pubkey = ecdsa_k1::decompress_pubkey(keypair.public_key());
    // Remove the first byte (compression prefix) to get 64 bytes
    vector::tabulate!(64, |i| pubkey[i + 1])
}

/// Get signer1 public key
public fun signer1(): vector<u8> {
    get_public_key(&generate_test_keypair(1))
}

/// Get signer2 public key
public fun signer2(): vector<u8> {
    get_public_key(&generate_test_keypair(2))
}

/// Get signer3 public key
public fun signer3(): vector<u8> {
    get_public_key(&generate_test_keypair(3))
}

// === Signature Generation ===

/// Generate a signature for a payload using a keypair
public fun sign_payload(keypair: &KeyPair, payload: vector<u8>): vector<u8> {
    ecdsa_k1::secp256k1_sign(
        keypair.private_key(),
        &payload,
        0, // KECCAK256 hash function
        true, // recoverable signature (65 bytes with recovery id)
    )
}

/// Generate multiple signatures for a payload
public fun sign_payload_with_multiple(payload: vector<u8>, keypair_indices: vector<u8>): vector<u8> {
    let mut signatures = vector::empty();
    let mut i = 0;
    while (i < keypair_indices.length()) {
        let keypair = generate_test_keypair(keypair_indices[i]);
        let sig = sign_payload(&keypair, payload);
        vector::append(&mut signatures, sig);
        i = i + 1;
    };
    signatures
}

// === Convenience Functions for Common Operations ===

/// Generate signature for set_allowlist(oapp, allowed)
public fun sign_set_allowlist(oapp: address, allowed: bool, signer_index: u8): vector<u8> {
    let keypair = generate_test_keypair(signer_index);
    let payload = hashes::build_set_allowlist_payload(oapp, allowed, VID, TEST_EXPIRATION);
    sign_payload(&keypair, payload)
}

/// Generate signature for set_denylist(oapp, denied)
public fun sign_set_denylist(oapp: address, denied: bool, signer_index: u8): vector<u8> {
    let keypair = generate_test_keypair(signer_index);
    let payload = hashes::build_set_denylist_payload(oapp, denied, VID, TEST_EXPIRATION);
    sign_payload(&keypair, payload)
}

/// Generate signature for set_paused(paused)
public fun sign_set_paused(paused: bool, signer_index: u8): vector<u8> {
    let keypair = generate_test_keypair(signer_index);
    let payload = hashes::build_set_pause_payload(paused, VID, TEST_EXPIRATION);
    sign_payload(&keypair, payload)
}

/// Generate signature for set_quorum(quorum)
public fun sign_set_quorum(quorum: u64, signer_index: u8): vector<u8> {
    let keypair = generate_test_keypair(signer_index);
    let payload = hashes::build_set_quorum_payload(quorum, VID, TEST_EXPIRATION);
    sign_payload(&keypair, payload)
}

/// Generate multiple signatures for set_quorum(quorum)
public fun sign_set_quorum_multi(quorum: u64, signer_indices: vector<u8>): vector<u8> {
    let payload = hashes::build_set_quorum_payload(quorum, VID, TEST_EXPIRATION);
    sign_payload_with_multiple(payload, signer_indices)
}

/// Generate signature for set_signer(signer, active)
public fun sign_set_signer(signer: vector<u8>, active: bool, signer_index: u8): vector<u8> {
    let keypair = generate_test_keypair(signer_index);
    let payload = hashes::build_set_dvn_signer_payload(signer, active, VID, TEST_EXPIRATION);
    sign_payload(&keypair, payload)
}

/// Generate multiple signatures for set_signer(signer, active)
public fun sign_set_signer_multi(signer: vector<u8>, active: bool, signer_indices: vector<u8>): vector<u8> {
    let payload = hashes::build_set_dvn_signer_payload(signer, active, VID, TEST_EXPIRATION);
    sign_payload_with_multiple(payload, signer_indices)
}

/// Generate signature for quorum_change_admin(admin, active)
public fun sign_quorum_change_admin(admin: address, active: bool, signer_index: u8): vector<u8> {
    let keypair = generate_test_keypair(signer_index);
    let payload = hashes::build_quorum_change_admin_payload(admin, active, VID, TEST_EXPIRATION);
    sign_payload(&keypair, payload)
}

/// Generate signature for verify operation
public fun sign_verify(
    packet_header: vector<u8>,
    payload_hash: vector<u8>,
    confirmations: u64,
    uln302: address,
    signer_index: u8,
): vector<u8> {
    let keypair = generate_test_keypair(signer_index);
    let payload = hashes::build_verify_payload(
        packet_header,
        payload_hash,
        confirmations,
        uln302,
        VID,
        TEST_EXPIRATION,
    );
    sign_payload(&keypair, payload)
}

/// Generate signature for set_ptb_builder_move_calls function
public fun sign_set_ptb_builder_move_calls(
    target_ptb_builder: address,
    get_fee_move_calls: vector<MoveCall>,
    assign_job_move_calls: vector<MoveCall>,
    signer_index: u8,
): vector<u8> {
    let keypair = generate_test_keypair(signer_index);
    let payload = hashes::build_set_ptb_builder_move_calls_payload(
        target_ptb_builder,
        get_fee_move_calls,
        assign_job_move_calls,
        VID,
        TEST_EXPIRATION,
    );
    sign_payload(&keypair, payload)
}

/// Generate signature for set_supported_message_lib(message_lib, supported)
public fun sign_set_supported_message_lib(message_lib: address, supported: bool, signer_index: u8): vector<u8> {
    let keypair = generate_test_keypair(signer_index);
    let payload = hashes::build_set_supported_message_lib_payload(message_lib, supported, VID, TEST_EXPIRATION);
    sign_payload(&keypair, payload)
}

/// Generate signature with expired timestamp
public fun sign_set_allowlist_expired(oapp: address, allowed: bool, signer_index: u8): vector<u8> {
    let keypair = generate_test_keypair(signer_index);
    let payload = hashes::build_set_allowlist_payload(oapp, allowed, VID, PAST_EXPIRATION);
    sign_payload(&keypair, payload)
}
