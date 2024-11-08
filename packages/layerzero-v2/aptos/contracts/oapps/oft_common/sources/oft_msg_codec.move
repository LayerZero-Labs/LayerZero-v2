/// This module provides the encoding and decoding of OFT messages
module oft_common::oft_msg_codec {
    use std::vector;

    use endpoint_v2_common::bytes32::Bytes32;
    use endpoint_v2_common::serde;

    const SEND_TO_OFFSET: u64 = 0;
    const SEND_AMOUNT_OFFSET: u64 = 32;
    const COMPOSE_MESSAGE_OFFSET: u64 = 40;

    /// Create a new OFT Message with this codec
    /// @param send_to: The address to send the message to
    /// @param amount_shared: The amount in shared decimals to send
    /// @param sender: The address of the sender (used as the compose_from in the compose message if present)
    /// @param compose_msg: The compose message to send
    /// @return The encoded OFT Message
    public fun encode(send_to: Bytes32, amount_shared: u64, sender: Bytes32, compose_payload: vector<u8>): vector<u8> {
        let encoded = vector[];
        serde::append_bytes32(&mut encoded, send_to);
        serde::append_u64(&mut encoded, amount_shared);
        if (!vector::is_empty(&compose_payload)) {
            serde::append_bytes32(&mut encoded, sender);
            vector::append(&mut encoded, compose_payload);
        };
        encoded
    }

    /// Check whether an encoded OFT Message includes a compose
    public fun has_compose(message: &vector<u8>): bool {
        vector::length(message) > COMPOSE_MESSAGE_OFFSET
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
    /// Make sure to check if the message `has_compose()` before calling this function, which will fail without a clear
    /// error message if it is not present
    public fun sender(message: &vector<u8>): Bytes32 {
        serde::extract_bytes32(message, &mut COMPOSE_MESSAGE_OFFSET)
    }

    /// Read the compose payload, including the sender, from an encoded OFT Message
    public fun compose_payload(message: &vector<u8>): vector<u8> {
        vector::slice(message, COMPOSE_MESSAGE_OFFSET, vector::length(message))
    }
}