/// This module provides the encoding and decoding of legacy OFT v1 (OFT on LayerZero V1 Endpoint) messages
module oft_common::oft_v1_msg_codec {
    use std::vector;

    use endpoint_v2_common::bytes32::{Bytes32, from_bytes32};
    use endpoint_v2_common::serde;
    use endpoint_v2_common::serde::flatten;

    const TYPE_OFFSET: u64 = 0;
    const SEND_TO_OFFSET: u64 = 1;
    const SEND_AMOUNT_OFFSET: u64 = 33;
    const COMPOSE_MESSAGE_OFFSET_SENDER: u64 = 41;
    const COMPOSE_MESSAGE_OFFSET_COMPOSE_GAS: u64 = 73;
    const COMPOSE_MESSAGE_CONTENT_OFFSET: u64 = 81;

    public inline fun PT_SEND(): u8 { 0 }

    public inline fun PT_SEND_AND_CALL(): u8 { 1 }

    /// Create a new OFT (Endpoint V1) Message with this codec
    /// @param message_type: The type of message to send (0 = PT_SEND, 1 = PT_SEND_AND_CALL).  Please note that these
    ///                      enums do not align with the SEND / SEND_AND_CALL consts used in the OFT
    /// @param send_to: The address to send the message to
    /// @param amount_shared: The amount in shared decimals to send
    /// @param sender: The address of the sender (used as the compose_from in the compose message if present)
    /// @param compose_msg: The compose message to send
    /// @return The encoded OFT Message
    public fun encode(
        message_type: u8,
        send_to: Bytes32,
        amount_shared: u64,
        sender: Bytes32,
        compose_gas: u64,
        compose_payload: vector<u8>,
    ): vector<u8> {
        assert!(message_type == PT_SEND() || message_type == PT_SEND_AND_CALL(), EUNKNOWN_MESSAGE_TYPE);
        let encoded = vector[];
        serde::append_u8(&mut encoded, message_type);
        serde::append_bytes32(&mut encoded, send_to);
        serde::append_u64(&mut encoded, amount_shared);
        if (message_type == PT_SEND_AND_CALL()) {
            serde::append_bytes32(&mut encoded, sender);
            serde::append_u64(&mut encoded, compose_gas);
            vector::append(&mut encoded, compose_payload);
        };
        encoded
    }

    /// Check the message type in an encoded OFT Message
    public fun message_type(message: &vector<u8>): u8 {
        serde::extract_u8(message, &mut TYPE_OFFSET)
    }

    /// Check whether an encoded OFT Message includes a compose
    public fun has_compose(message: &vector<u8>): bool {
        vector::length(message) > COMPOSE_MESSAGE_OFFSET_SENDER
    }

    /// Check the send to address in an encoded OFT Message
    public fun send_to(message: &vector<u8>): Bytes32 {
        serde::extract_bytes32(message, &mut SEND_TO_OFFSET)
    }

    /// Check the amount in shared decimals in an encoded OFT Message
    public fun amount_sd(message: &vector<u8>): u64 {
        serde::extract_u64(message, &mut SEND_AMOUNT_OFFSET)
    }

    /// Check the sender in an encoded OFT Message
    /// This function should only be called after verifying that the message has a compose message
    public fun sender(message: &vector<u8>): Bytes32 {
        serde::extract_bytes32(message, &mut COMPOSE_MESSAGE_OFFSET_SENDER)
    }

    /// Check the compose gas in an encoded OFT Message
    /// This function should only be called after verifying that the message has a compose message
    public fun compose_gas(message: &vector<u8>): u64 {
        serde::extract_u64(message, &mut COMPOSE_MESSAGE_OFFSET_COMPOSE_GAS)
    }

    public fun compose_message_content(message: &vector<u8>): vector<u8> {
        serde::extract_bytes_until_end(message, &mut COMPOSE_MESSAGE_CONTENT_OFFSET)
    }

    /// Return the compose "payload", including the sender, from an encoded OFT Message
    /// This will return an empty string if the message does not have a compose message
    public fun v2_compatible_compose_payload(message: &vector<u8>): vector<u8> {
        flatten(vector[
            from_bytes32(sender(message)),
            compose_message_content(message),
        ])
    }

    // ================================================== Error Codes =================================================

    const EUNKNOWN_MESSAGE_TYPE: u64 = 1;
}