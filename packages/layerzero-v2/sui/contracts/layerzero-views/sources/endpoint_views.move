/// Endpoint Views Module
///
/// This module provides view functions for checking the state of LayerZero messages
/// and their executability status. These functions are used to query the endpoint
/// without modifying state.
module layerzero_views::endpoint_views;

use endpoint_v2::{endpoint_v2, messaging_channel::MessagingChannel};
use utils::bytes32;

// === Constants ===

/// Message execution states
const STATE_NOT_EXECUTABLE: u8 = 0;
const STATE_VERIFIED_BUT_NOT_EXECUTABLE: u8 = 1;
const STATE_EXECUTABLE: u8 = 2;
const STATE_EXECUTED: u8 = 3;

// === Public View Functions ===

/// Checks if a message path is initializable (channel exists).
/// This corresponds to the Aptos version's initializable function.
public fun initializable(messaging_channel: &MessagingChannel, src_eid: u32, sender: vector<u8>): bool {
    let sender_bytes32 = bytes32::from_bytes(sender);
    endpoint_v2::initializable(messaging_channel, src_eid, sender_bytes32)
}

/// Checks if a message is verifiable by the endpoint.
/// This function verifies that the receive library is valid and the message can be verified.
public fun verifiable(messaging_channel: &MessagingChannel, src_eid: u32, sender: vector<u8>, nonce: u64): bool {
    let sender_bytes32 = bytes32::from_bytes(sender);
    endpoint_v2::verifiable(messaging_channel, src_eid, sender_bytes32, nonce)
}

/// Determines the execution state of a message.
/// Returns one of the STATE_* constants indicating the current state.
public fun executable(messaging_channel: &MessagingChannel, src_eid: u32, sender: vector<u8>, nonce: u64): u8 {
    let sender_bytes32 = bytes32::from_bytes(sender);

    // Check if payload hash exists
    let has_payload_hash = endpoint_v2::has_inbound_payload_hash(messaging_channel, src_eid, sender_bytes32, nonce);

    // Check if already executed (nonce <= lazy_inbound_nonce and no payload hash)
    if (!has_payload_hash && nonce <= endpoint_v2::get_lazy_inbound_nonce(messaging_channel, src_eid, sender_bytes32)) {
        return STATE_EXECUTED
    };

    if (has_payload_hash) {
        let payload_hash = endpoint_v2::get_inbound_payload_hash(messaging_channel, src_eid, sender_bytes32, nonce);

        // Check if executable (verified and ready for execution)
        if (
            !bytes32::is_zero(&payload_hash) && nonce <= endpoint_v2::get_inbound_nonce(messaging_channel, src_eid, sender_bytes32)
        ) {
            return STATE_EXECUTABLE
        };

        // Check if verified but not yet executable
        if (!bytes32::is_zero(&payload_hash)) {
            return STATE_VERIFIED_BUT_NOT_EXECUTABLE
        }
    };

    STATE_NOT_EXECUTABLE
}
