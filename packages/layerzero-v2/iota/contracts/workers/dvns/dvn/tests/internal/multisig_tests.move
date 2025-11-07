#[test_only]
module dvn::multisig_tests;

use dvn::multisig::{
    Self,
    EQuorumIsZero,
    ESignersSizeIsLessThanQuorum,
    EInvalidSignerLength,
    ESignerAlreadyExists,
    ESignerNotFound,
    ESignaturesLessThanQuorum,
    EInvalidSignatureLength,
    ESignerNotInCommittee,
    EDuplicatedSigner,
    UpdateSignerEvent,
    UpdateQuorumEvent
};
use iota::{ecdsa_k1::{Self, KeyPair}, event, test_scenario::{Self, Scenario}, test_utils, vec_set};

// === Test Data ===

const DVN_ADDRESS: address = @0x123;

// Valid KeyPairs for testing created from deterministic seeds
fun valid_signer_1(): KeyPair {
    let seed = x"0000000000000000000000000000000000000000000000000000000000000001";
    ecdsa_k1::secp256k1_keypair_from_seed(&seed)
}

fun valid_signer_2(): KeyPair {
    let seed = x"0000000000000000000000000000000000000000000000000000000000000002";
    ecdsa_k1::secp256k1_keypair_from_seed(&seed)
}

fun valid_signer_3(): KeyPair {
    let seed = x"0000000000000000000000000000000000000000000000000000000000000003";
    ecdsa_k1::secp256k1_keypair_from_seed(&seed)
}

// Helper function to extract public key from KeyPair
fun get_public_key(keypair: &KeyPair): vector<u8> {
    let pubkey = ecdsa_k1::decompress_pubkey(keypair.public_key());
    // KeyPair.public_key() returns 65 bytes (uncompressed), but multisig expects 64 bytes
    // Remove the first byte (compression prefix) to get 64 bytes
    vector::tabulate!(64, |i| pubkey[i + 1])
}

fun invalid_signer(): vector<u8> {
    x"123456789a" // Only 5 bytes, should be 64
}

// Create real cryptographic signatures using provided keypairs
fun create_test_signatures(payload: vector<u8>, keypairs: vector<KeyPair>): vector<u8> {
    let mut signatures = vector::empty();

    let mut i = 0;
    while (i < keypairs.length()) {
        let keypair = &keypairs[i];
        let signature = ecdsa_k1::secp256k1_sign(
            keypair.private_key(),
            &payload,
            0, // KECCAK256 hash function
            true, // recoverable signature (65 bytes with recovery id)
        );
        signatures.append(signature);
        i = i + 1;
    };
    signatures
}

fun create_test_payload(): vector<u8> {
    x"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
}

// === Helper Functions ===

fun setup(): Scenario {
    test_scenario::begin(@0x0)
}

fun clean(scenario: Scenario) {
    test_scenario::end(scenario);
}

// === Constructor Tests ===

#[test]
fun test_new_signers() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signer2 = valid_signer_2();
    let signer3 = valid_signer_3();
    let signers = vector[get_public_key(&signer1), get_public_key(&signer2), get_public_key(&signer3)];
    let multisig = multisig::new(signers, 2);

    // Verify initial state
    assert!(multisig.signer_count() == 3, 0);
    assert!(multisig.quorum() == 2, 1);
    assert!(multisig.is_signer(get_public_key(&signer1)), 2);
    assert!(multisig.is_signer(get_public_key(&signer2)), 3);
    assert!(multisig.is_signer(get_public_key(&signer3)), 4);

    // Test get_signers functionality - VecSet may return in different order, so check membership
    let actual_signers = multisig.get_signers();
    assert!(actual_signers.length() == 3, 5);
    assert!(actual_signers.contains(&get_public_key(&signer1)), 6);
    assert!(actual_signers.contains(&get_public_key(&signer2)), 7);
    assert!(actual_signers.contains(&get_public_key(&signer3)), 8);

    // Test non-existent signer
    let non_existent_signer = ecdsa_k1::secp256k1_keypair_from_seed(
        &x"0000000000000000000000000000000000000000000000000000000000000004",
    );
    assert!(!multisig.is_signer(get_public_key(&non_existent_signer)), 9);

    test_utils::destroy(multisig);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EQuorumIsZero)] // EQuorumIsZero
fun test_new_fails_with_zero_quorum() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signers = vector[get_public_key(&signer1)];
    let multisig = multisig::new(signers, 0);

    test_utils::destroy(multisig);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = ESignersSizeIsLessThanQuorum)]
fun test_new_fails_when_quorum_exceeds_signers() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signer2 = valid_signer_2();
    let signers = vector[get_public_key(&signer1), get_public_key(&signer2)];
    let multisig = multisig::new(signers, 3); // Quorum > signer count

    test_utils::destroy(multisig);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EInvalidSignerLength)]
fun test_new_fails_with_invalid_signer_length() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signers = vector[get_public_key(&signer1), invalid_signer()];
    let multisig = multisig::new(signers, 1);

    test_utils::destroy(multisig);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = vec_set::EKeyAlreadyExists)]
fun test_new_fails_with_duplicate_signers() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signer2 = valid_signer_2();
    let signers = vector[get_public_key(&signer1), get_public_key(&signer2), get_public_key(&signer1)];
    let multisig = multisig::new(signers, 2);

    test_utils::destroy(multisig);
    clean(scenario);
}

// === Signer Management Tests ===

#[test]
fun test_set_signer_add_new() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signer2 = valid_signer_2();
    let signer3 = valid_signer_3();
    let signers = vector[get_public_key(&signer1)];
    let mut multisig = multisig::new(signers, 1);

    // Add first new signer
    multisig.set_signer(DVN_ADDRESS, get_public_key(&signer2), true);

    // Verify first signer was added
    assert!(multisig.signer_count() == 2, 0);
    assert!(multisig.is_signer(get_public_key(&signer2)), 1);

    // Check first signer addition event
    let events = event::events_by_type<UpdateSignerEvent>();
    let expected_event = multisig::create_update_signer_event(DVN_ADDRESS, get_public_key(&signer2), true);
    test_utils::assert_eq(events[events.length() - 1], expected_event);

    // Add second new signer for comprehensive signer management sequence
    multisig.set_signer(DVN_ADDRESS, get_public_key(&signer3), true);
    assert!(multisig.signer_count() == 3, 2);
    assert!(multisig.is_signer(get_public_key(&signer3)), 3);

    // Check second signer addition event
    let events = event::events_by_type<UpdateSignerEvent>();
    let expected_event = multisig::create_update_signer_event(DVN_ADDRESS, get_public_key(&signer3), true);
    test_utils::assert_eq(events[events.length() - 1], expected_event);

    // Increase quorum as part of management sequence
    multisig.set_quorum(DVN_ADDRESS, 2);
    assert!(multisig.quorum() == 2, 4);

    // Check quorum update event
    let quorum_events = event::events_by_type<UpdateQuorumEvent>();
    let expected_quorum_event = multisig::create_update_quorum_event(DVN_ADDRESS, 2);
    test_utils::assert_eq(quorum_events[quorum_events.length() - 1], expected_quorum_event);

    // Remove one signer (should still meet quorum)
    multisig.set_signer(DVN_ADDRESS, get_public_key(&signer3), false);
    assert!(multisig.signer_count() == 2, 5);
    assert!(!multisig.is_signer(get_public_key(&signer3)), 6);
    assert!(multisig.quorum() == 2, 7);

    // Check signer removal event
    let events = event::events_by_type<UpdateSignerEvent>();
    let expected_event = multisig::create_update_signer_event(DVN_ADDRESS, get_public_key(&signer3), false);
    test_utils::assert_eq(events[events.length() - 1], expected_event);

    test_utils::destroy(multisig);
    clean(scenario);
}

#[test]
fun test_set_signer_remove_existing() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signer2 = valid_signer_2();
    let signers = vector[get_public_key(&signer1), get_public_key(&signer2)];
    let mut multisig = multisig::new(signers, 1);

    // Remove existing signer
    multisig.set_signer(DVN_ADDRESS, get_public_key(&signer2), false);

    // Verify signer was removed
    assert!(multisig.signer_count() == 1, 0);
    assert!(!multisig.is_signer(get_public_key(&signer2)), 1);
    assert!(multisig.is_signer(get_public_key(&signer1)), 2);

    // Check signer removal event
    let events = event::events_by_type<UpdateSignerEvent>();
    let expected_event = multisig::create_update_signer_event(DVN_ADDRESS, get_public_key(&signer2), false);
    test_utils::assert_eq(events[events.length() - 1], expected_event);

    test_utils::destroy(multisig);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = ESignerAlreadyExists)]
fun test_set_signer_fails_when_adding_existing() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signers = vector[get_public_key(&signer1)];
    let mut multisig = multisig::new(signers, 1);

    // Try to add existing signer
    multisig.set_signer(DVN_ADDRESS, get_public_key(&signer1), true);

    test_utils::destroy(multisig);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = ESignerNotFound)]
fun test_set_signer_fails_when_removing_nonexistent() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signer2 = valid_signer_2();
    let signers = vector[get_public_key(&signer1)];
    let mut multisig = multisig::new(signers, 1);

    // Try to remove non-existent signer
    multisig.set_signer(DVN_ADDRESS, get_public_key(&signer2), false);

    test_utils::destroy(multisig);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = ESignersSizeIsLessThanQuorum)]
fun test_set_signer_fails_when_removal_breaks_quorum() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signer2 = valid_signer_2();
    let signers = vector[get_public_key(&signer1), get_public_key(&signer2)];
    let mut multisig = multisig::new(signers, 2);

    // Try to remove signer when it would break quorum requirement
    multisig.set_signer(DVN_ADDRESS, get_public_key(&signer2), false);

    test_utils::destroy(multisig);
    clean(scenario);
}

// === Quorum Management Tests ===

#[test]
fun test_set_quorum_valid() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signer2 = valid_signer_2();
    let signer3 = valid_signer_3();
    let signers = vector[get_public_key(&signer1), get_public_key(&signer2), get_public_key(&signer3)];
    let mut multisig = multisig::new(signers, 2);

    // Test initial quorum getter functionality
    assert!(multisig.quorum() == 2, 0);
    assert!(multisig.signer_count() == 3, 1);

    // Change quorum to valid value (max quorum = signer count)
    multisig.set_quorum(DVN_ADDRESS, 3);

    // Verify quorum was changed and test max quorum functionality
    assert!(multisig.quorum() == 3, 2); // Quorum equals signer count
    assert!(multisig.signer_count() == 3, 3);

    // Check quorum update event
    let events = event::events_by_type<UpdateQuorumEvent>();
    let expected_event = multisig::create_update_quorum_event(DVN_ADDRESS, 3);
    test_utils::assert_eq(events[events.length() - 1], expected_event);

    test_utils::destroy(multisig);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EQuorumIsZero)]
fun test_set_quorum_fails_with_zero() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signer2 = valid_signer_2();
    let signers = vector[get_public_key(&signer1), get_public_key(&signer2)];
    let mut multisig = multisig::new(signers, 1);

    // Try to set quorum to zero
    multisig.set_quorum(DVN_ADDRESS, 0);

    test_utils::destroy(multisig);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = ESignersSizeIsLessThanQuorum)]
fun test_set_quorum_fails_when_exceeds_signers() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signer2 = valid_signer_2();
    let signers = vector[get_public_key(&signer1), get_public_key(&signer2)];
    let mut multisig = multisig::new(signers, 1);

    // Try to set quorum greater than signer count
    multisig.set_quorum(DVN_ADDRESS, 3);

    test_utils::destroy(multisig);
    clean(scenario);
}

// === Signature Verification Tests ===

#[test]
#[expected_failure(abort_code = ESignaturesLessThanQuorum)]
fun test_assert_signatures_verified_fails_insufficient_signatures() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signer2 = valid_signer_2();
    let signers = vector[get_public_key(&signer1), get_public_key(&signer2)];
    let multisig = multisig::new(signers, 2);

    let payload = create_test_payload();
    let signatures = create_test_signatures(payload, vector[signer1]); // Only 1 signature, need 2

    // This should fail due to insufficient signatures
    multisig.assert_signatures_verified(payload, &signatures);

    test_utils::destroy(multisig);
    clean(scenario);
}

#[test]
fun test_assert_signatures_verified_exact_quorum() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signer2 = valid_signer_2();
    let signer3 = valid_signer_3();
    let signers = vector[get_public_key(&signer1), get_public_key(&signer2), get_public_key(&signer3)];
    let multisig = multisig::new(signers, 2);

    let payload = create_test_payload();
    let signatures = create_test_signatures(payload, vector[signer1, signer2]);

    multisig.assert_signatures_verified(payload, &signatures);

    // Test with signatures in different order
    let signatures = create_test_signatures(payload, vector[valid_signer_2(), valid_signer_1()]);
    multisig.assert_signatures_verified(payload, &signatures);

    test_utils::destroy(multisig);
    clean(scenario);
}

#[test]
fun test_assert_signatures_verified_more_than_quorum() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signer2 = valid_signer_2();
    let signer3 = valid_signer_3();
    let signers = vector[get_public_key(&signer1), get_public_key(&signer2), get_public_key(&signer3)];
    let multisig = multisig::new(signers, 1);

    let payload = create_test_payload();
    let keypairs = vector[signer1, signer2];
    let signatures = create_test_signatures(payload, keypairs);

    multisig.assert_signatures_verified(payload, &signatures);

    test_utils::destroy(multisig);
    clean(scenario);
}

// Test with more than quorum, but signer3 is not in committee
// The same logic as EVM
#[test]
fun test_assert_signatures_verified_additional_wrong_signatures() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signer2 = valid_signer_2();
    let signer3 = valid_signer_3();
    let signers = vector[get_public_key(&signer1), get_public_key(&signer2)];
    let multisig = multisig::new(signers, 1);

    let payload = create_test_payload();
    // more than quorum, but signer3 is not in committee
    let keypairs = vector[signer1, signer3];
    let signatures = create_test_signatures(payload, keypairs);

    multisig.assert_signatures_verified(payload, &signatures);

    test_utils::destroy(multisig);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EInvalidSignatureLength)]
fun test_signature_with_invalid_signature_length() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signers = vector[get_public_key(&signer1)];
    let multisig = multisig::new(signers, 1);

    let payload = create_test_payload();

    // Test with signatures that aren't multiples of 65 bytes
    let invalid_signatures = vector::tabulate!(64, |i| i as u8); // 64 bytes instead of 65

    // This should fail during signature parsing/verification
    multisig.assert_signatures_verified(payload, &invalid_signatures);

    test_utils::destroy(multisig);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = ESignerNotInCommittee)]
fun test_signatures_with_wrong_signature() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signer2 = valid_signer_2();
    let signer3 = valid_signer_3();
    let signers = vector[get_public_key(&signer1), get_public_key(&signer2)];
    let multisig = multisig::new(signers, 2);

    let payload = create_test_payload();

    let keypairs = vector[signer1, signer3];
    let signatures = create_test_signatures(payload, keypairs);

    multisig.assert_signatures_verified(payload, &signatures);

    test_utils::destroy(multisig);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EDuplicatedSigner)]
fun test_signatures_with_duplicated_signers() {
    let scenario = setup();

    let signer1 = valid_signer_1();
    let signer2 = valid_signer_2();
    let signer3 = valid_signer_1(); // duplicated signer
    let signers = vector[get_public_key(&signer1), get_public_key(&signer2)];
    let multisig = multisig::new(signers, 2);

    let payload = create_test_payload();
    let keypairs = vector[signer1, signer3];
    let signatures = create_test_signatures(payload, keypairs);

    multisig.assert_signatures_verified(payload, &signatures);

    test_utils::destroy(multisig);
    clean(scenario);
}
