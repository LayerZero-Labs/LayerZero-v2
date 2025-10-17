/// ULN 302 Views Module
///
/// This module provides view functions for checking the verification state of ULN 302 messages.
/// It allows querying whether messages are verifiable, verified, or in other states without
/// modifying the verification storage.
module layerzero_views::uln_302_views;

use endpoint_v2::{endpoint_v2::{Self, EndpointV2}, messaging_channel::MessagingChannel};
use layerzero_views::endpoint_views;
use message_lib_common::packet_v1_codec;
use uln_302::{receive_uln::Verification, uln_302::{Self, Uln302}};
use utils::bytes32::{Self, Bytes32};

// === Constants ===

/// Verification states
const STATE_VERIFYING: u8 = 0;
const STATE_VERIFIABLE: u8 = 1;
const STATE_VERIFIED: u8 = 2;
const STATE_NOT_INITIALIZABLE: u8 = 3;

// === Public View Functions ===

/// Checks the verification state of a message through the ULN 302.
/// This function determines if a message can be verified by checking DVN confirmations
/// and endpoint state.
///
/// Returns:
/// - STATE_NOT_INITIALIZABLE: The endpoint channel is not initializable
/// - STATE_VERIFIED: The message has already been verified in the endpoint
/// - STATE_VERIFIABLE: The message has sufficient DVN confirmations and can be verified
/// - STATE_VERIFYING: The message is still waiting for sufficient DVN confirmations
public fun verifiable(
    uln: &Uln302,
    verification: &Verification,
    endpoint: &EndpointV2,
    messaging_channel: &MessagingChannel,
    packet_header_bytes: vector<u8>,
    payload_hash: vector<u8>,
): u8 {
    // Decode the packet header to extract message details
    let packet_header = packet_v1_codec::decode_header(packet_header_bytes);
    let src_eid = packet_header.src_eid();
    let sender = packet_header.sender();
    let nonce = packet_header.nonce();
    let receiver = packet_header.receiver().to_address();

    // Check if the endpoint channel is initializable
    if (
        !endpoint_views::initializable(
            messaging_channel,
            src_eid,
            sender.to_bytes(),
        )
    ) {
        return STATE_NOT_INITIALIZABLE
    };

    // Check if the message has already been verified by the endpoint
    if (
        !endpoint_verifiable(
            messaging_channel,
            src_eid,
            sender,
            nonce,
            receiver,
            payload_hash,
        )
    ) {
        return STATE_VERIFIED
    };

    // Check if the ULN has sufficient DVN confirmations for verification
    let payload_hash_bytes32 = bytes32::from_bytes(payload_hash);
    if (uln_302::verifiable(uln, verification, endpoint, packet_header_bytes, payload_hash_bytes32)) {
        return STATE_VERIFIABLE
    };

    STATE_VERIFYING
}

// === Helper Functions ===

/// Internal helper to check if a message is verifiable by the endpoint.
/// Returns false if the message has already been verified (payload hash exists and matches).
fun endpoint_verifiable(
    messaging_channel: &MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    _receiver: address,
    payload_hash: vector<u8>,
): bool {
    // Check if the message is verifiable by the endpoint
    if (
        !endpoint_views::verifiable(
            messaging_channel,
            src_eid,
            sender.to_bytes(),
            nonce,
        )
    ) {
        return false
    };

    // If a payload hash already exists for this message and it matches,
    // then the message has already been verified
    if (endpoint_v2::has_inbound_payload_hash(messaging_channel, src_eid, sender, nonce)) {
        let existing_hash = endpoint_v2::get_inbound_payload_hash(messaging_channel, src_eid, sender, nonce);
        if (existing_hash == bytes32::from_bytes(payload_hash)) {
            return false
        }
    };

    true
}
