/// This module provides functions to encode and decode OFT compose messages
module oft_common::oft_compose_msg_codec {
    use std::vector;

    use endpoint_v2_common::bytes32::Bytes32;
    use endpoint_v2_common::serde;

    const NONCE_OFFSET: u64 = 0;
    const SRC_EID_OFFSET: u64 = 8;
    const AMOUNT_LD_OFFSET: u64 = 12;
    const COMPOSE_FROM_OFFSET: u64 = 44;
    const COMPOSE_MSG_OFFSET: u64 = 76;

    /// Encode a compose message into a byte vector
    /// @param nonce: The nonce of the LayerZero message that contains the compose message
    /// @param src_eid: The source endpoint ID of the compose message
    /// @param amount_ld: The amount in local decimals of the compose message
    /// @param compose_payload: The compose message to encode [compose_payload_from][compose_payload_message]
    public fun encode(
        nonce: u64,
        src_eid: u32,
        amount_ld: u64,
        compose_payload: vector<u8>,
    ): vector<u8> {
        let encoded = vector[];
        serde::append_u64(&mut encoded, nonce);
        serde::append_u32(&mut encoded, src_eid);
        serde::append_u256(&mut encoded, (amount_ld as u256));
        serde::append_bytes(&mut encoded, compose_payload);
        encoded
    }

    /// Get the nonce from an encoded compose message
    public fun nonce(encoded: &vector<u8>): u64 {
        serde::extract_u64(encoded, &mut NONCE_OFFSET)
    }

    /// Get the source endpoint ID from an encoded compose message
    public fun src_eid(encoded: &vector<u8>): u32 {
        serde::extract_u32(encoded, &mut SRC_EID_OFFSET)
    }

    /// Get the amount in local decimals from an encoded compose message
    public fun amount_ld(encoded: &vector<u8>): u64 {
        (serde::extract_u256(encoded, &mut AMOUNT_LD_OFFSET) as u64)
    }

    /// Get the compose from address from an encoded compose message
    public fun compose_payload_from(encoded: &vector<u8>): Bytes32 {
        assert!(vector::length(encoded) >= COMPOSE_MSG_OFFSET, ENO_COMPOSE_MSG);
        serde::extract_bytes32(encoded, &mut COMPOSE_FROM_OFFSET)
    }

    /// Get the compose payload from an encoded compose message
    public fun compose_payload_message(encoded: &vector<u8>): vector<u8> {
        assert!(vector::length(encoded) >= COMPOSE_MSG_OFFSET, ENO_COMPOSE_MSG);
        serde::extract_bytes_until_end(encoded, &mut COMPOSE_MSG_OFFSET)
    }

    // ================================================== Error Codes =================================================

    const ENO_COMPOSE_MSG: u64 = 1;
}
