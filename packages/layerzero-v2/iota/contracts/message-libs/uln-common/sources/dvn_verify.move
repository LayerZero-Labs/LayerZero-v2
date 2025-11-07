/// DVN Verify Module
///
/// This module defines parameters for DVN message verification. DVNs use these parameters
/// to verify cross-chain messages by confirming packet details and block confirmations
/// before committing the verification to the Endpoint.
module uln_common::dvn_verify;

use utils::bytes32::Bytes32;

// === Structs ===

/// Parameters for DVN message verification requests.
public struct VerifyParam has copy, drop, store {
    // Encoded packet header containing packet information (source/destination chains, nonce, etc.)
    packet_header: vector<u8>,
    // Hash of the message payload for verification
    payload_hash: Bytes32,
    // Number of block confirmations the DVN observed for this message
    confirmations: u64,
}

// === Creation ===

/// Creates a new VerifyParam from existing parameters.
public fun create_param(packet_header: vector<u8>, payload_hash: Bytes32, confirmations: u64): VerifyParam {
    VerifyParam { packet_header, payload_hash, confirmations }
}

// === Getters ===

/// Returns the packet header.
public fun packet_header(self: &VerifyParam): &vector<u8> {
    &self.packet_header
}

/// Returns the payload hash.
public fun payload_hash(self: &VerifyParam): Bytes32 {
    self.payload_hash
}

/// Returns the number of confirmations.
public fun confirmations(self: &VerifyParam): u64 {
    self.confirmations
}
