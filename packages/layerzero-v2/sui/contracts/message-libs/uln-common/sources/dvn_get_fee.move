/// DVN Get Fee Module
///
/// This module defines parameters for querying DVN verification fees. It provides the data
/// structure needed to request fee calculations from DVN for cross-chain message verification.
module uln_common::dvn_get_fee;

use utils::bytes32::Bytes32;

// === Structs ===

/// Parameters for DVN fee calculation requests.
public struct GetFeeParam has copy, drop, store {
    // Destination endpoint ID where the message will be verified
    dst_eid: u32,
    // Encoded packet header containing routing information
    packet_header: vector<u8>,
    // Hash of the message payload to be verified
    payload_hash: Bytes32,
    // Number of block confirmations required for verification
    confirmations: u64,
    // Address of the message sender on the source chain
    sender: address,
    // DVN-specific options and parameters
    options: vector<u8>,
}

// === Creation ===

/// Creates a new GetFeeParam with the specified parameters.
public fun create_param(
    dst_eid: u32,
    packet_header: vector<u8>,
    payload_hash: Bytes32,
    confirmations: u64,
    sender: address,
    options: vector<u8>,
): GetFeeParam {
    GetFeeParam { dst_eid, packet_header, payload_hash, confirmations, sender, options }
}

// === Getters ===

/// Returns the destination endpoint ID.
public fun dst_eid(self: &GetFeeParam): u32 {
    self.dst_eid
}

/// Returns a reference to the packet header.
public fun packet_header(self: &GetFeeParam): &vector<u8> {
    &self.packet_header
}

/// Returns the payload hash.
public fun payload_hash(self: &GetFeeParam): Bytes32 {
    self.payload_hash
}

/// Returns the number of confirmations required.
public fun confirmations(self: &GetFeeParam): u64 {
    self.confirmations
}

/// Returns the sender address.
public fun sender(self: &GetFeeParam): address {
    self.sender
}

/// Returns a reference to the DVN options.
public fun options(self: &GetFeeParam): &vector<u8> {
    &self.options
}
