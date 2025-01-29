module bridge_remote::bridge_codecs {
    use std::vector;

    use endpoint_v2_common::bytes32::{Self, Bytes32};
    use endpoint_v2_common::serde;

    /// Encode a message for adding a token to the factory contract
    /// This is used on the "local" (adapter) side
    ///
    /// @param token: The token address on the Local side
    /// @param shared_decimals: The shared decimals of the token
    /// @param name: The name of the token
    /// @param symbol: The symbol of the token
    ///
    /// @return The encoded message
    public fun encode_factory_add_token_message(
        token: Bytes32,
        shared_decimals: u8,
        name: vector<u8>,
        symbol: vector<u8>,
    ): vector<u8> {
        let message = vector[];
        serde::append_bytes32(&mut message, token);
        serde::append_u8(&mut message, shared_decimals);
        serde::append_u64(&mut message, vector::length(&name));
        serde::append_bytes(&mut message, name);
        serde::append_bytes(&mut message, symbol);

        message
    }

    /// Decode a message for adding a token to the factory contract
    /// This is used on the "remote" (factory) side
    ///
    /// @param message: The encoded message
    ///
    /// @return (token, shared_decimals, name, symbol)
    public fun decode_factory_add_token_message(message: &vector<u8>): (Bytes32, u8, vector<u8>, vector<u8>) {
        let cursor = 0;
        let token = serde::extract_bytes32(message, &mut cursor);
        let sharedDecimals = serde::extract_u8(message, &mut cursor);
        let name_length = serde::extract_u64(message, &mut cursor);
        let name = serde::extract_fixed_len_bytes(message, &mut cursor, name_length);
        let symbol = serde::extract_bytes_until_end(message, &mut cursor);

        (token, sharedDecimals, name, symbol)
    }

    /// Encode a message for transferring tokens
    /// This is used on the "local" (adapter) side
    /// A token transfer message with 0 value is also used to ACK the creation of the bridge
    ///
    /// @param token: The token address on the Local side
    /// @param to: The recipient of the tokens
    /// @param amount_sd: The amount of tokens to transfer (in shared decimals)
    /// @param sender: The sender of the tokens
    /// @param compose_payload: The compose message to include in the transfer (empty indicates no compose message)
    ///
    /// @return The encoded message
    public fun encode_tokens_transfer_message(
        token: Bytes32,
        to: Bytes32,
        amount_sd: u64,
        sender: Bytes32,
        compose_payload: vector<u8>,
    ): vector<u8> {
        let message = vector[];
        serde::append_bytes32(&mut message, token);
        serde::append_bytes32(&mut message, to);
        serde::append_u64(&mut message, amount_sd);

        // Append sender and composeMsg if composeMsg is not empty
        if (vector::length(&compose_payload) > 0) {
            serde::append_bytes32(&mut message, sender);
            serde::append_bytes(&mut message, compose_payload)
        };

        message
    }

    /// Decode a message for transferring tokens
    /// This is used on the "remote" (factory) side
    /// A token transfer message with 0 value is also used to ACK the creation of the bridge
    /// If the message has a compose message, the sender and compose message are returned
    /// Otherwise, the sender is zeroed and the compose message is empty
    ///
    /// @param message: The encoded message
    ///
    /// @return (token, to, amount_sd, has_compose, sender, compose_payload)
    public fun decode_tokens_transfer_message(
        message: &vector<u8>,
    ): (Bytes32, Bytes32, u64, bool, Bytes32, vector<u8>) {
        let cursor = 0;
        let token = serde::extract_bytes32(message, &mut cursor);
        let to = serde::extract_bytes32(message, &mut cursor);
        let amount_sd = serde::extract_u64(message, &mut cursor);

        if (cursor < vector::length(message)) {
            // Has a compose message
            let sender = serde::extract_bytes32(message, &mut cursor);
            let compose_payload = serde::extract_bytes_until_end(message, &mut cursor);
            (token, to, amount_sd, true, sender, compose_payload)
        } else {
            // No compose message
            (token, to, amount_sd, false, bytes32::zero_bytes32(), vector[])
        }
    }


    /// Encode a compose message into a byte vector
    /// @param nonce: The nonce of the LayerZero message that contains the compose message
    /// @param src_eid: The source endpoint ID of the compose message
    /// @param token: The token address of the compose message
    /// @param amount_ld: The amount in local decimals of the compose message
    /// @param sender: The sender of the compose message
    /// @param compose_payload: The compose message to encode
    public fun encode_compose(
        nonce: u64,
        src_eid: u32,
        token: Bytes32,
        amount_ld: u64,
        sender: Bytes32,
        compose_payload: vector<u8>,
    ): vector<u8> {
        let encoded = vector[];

        serde::append_u64(&mut encoded, nonce);
        serde::append_u32(&mut encoded, src_eid);
        serde::append_bytes32(&mut encoded, token);
        serde::append_u64(&mut encoded, amount_ld);
        serde::append_bytes32(&mut encoded, sender);
        serde::append_bytes(&mut encoded, compose_payload);

        encoded
    }

    /// Decode a compose message
    /// @param encoded: The encoded compose message
    /// @return (nonce, src_eid, token, amount_ld, sender, compose_payload)
    public fun decode_compose(encoded: &vector<u8>): (u64, u32, Bytes32, u64, Bytes32, vector<u8>) {
        let cursor = 0;

        let nonce = serde::extract_u64(encoded, &mut cursor);
        let src_eid = serde::extract_u32(encoded, &mut cursor);
        let token = serde::extract_bytes32(encoded, &mut cursor);
        let amount_ld = serde::extract_u64(encoded, &mut cursor);
        let sender = serde::extract_bytes32(encoded, &mut cursor);
        let compose_payload = serde::extract_bytes_until_end(encoded, &mut cursor);

        (nonce, src_eid, token, amount_ld, sender, compose_payload)
    }
}