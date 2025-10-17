module oft_common::oft_compose_msg_codec;

use utils::{buffer_reader, buffer_writer, bytes32::Bytes32};

// === Structs ===

/// Decoded compose message containing transfer context and payload execution
public struct OFTComposeMsg has copy, drop {
    /// Unique sequence number for the cross-chain message packet
    nonce: u64,
    /// Source chain endpoint ID where the transfer originated
    src_eid: u32,
    /// Amount received in local decimals
    amount_ld: u64,
    /// Address that initiated the compose call on the source chain
    compose_from: Bytes32,
    /// Custom payload for compose logic execution
    compose_msg: vector<u8>,
}

// === Codec Functions ===

/// Encodes compose message data into a byte vector for cross-chain execution
/// Format: [nonce(8)] [src_eid(4)] [amount_ld(8)] [compose_from(32)] [compose_msg(variable)]
public fun encode(
    nonce: u64,
    src_eid: u32,
    amount_ld: u64,
    compose_from: Bytes32,
    compose_msg: vector<u8>,
): vector<u8> {
    let mut writer = buffer_writer::new();
    writer
        .write_u64(nonce)
        .write_u32(src_eid)
        .write_u64(amount_ld)
        .write_bytes32(compose_from)
        .write_bytes(compose_msg);
    writer.to_bytes()
}

/// Decodes byte vector into OFTComposeMsg struct for destination chain processing
public fun decode(msg: &vector<u8>): OFTComposeMsg {
    let mut reader = buffer_reader::create(*msg);
    let nonce = reader.read_u64();
    let src_eid = reader.read_u32();
    let amount_ld = reader.read_u64();
    let compose_from = reader.read_bytes32();
    let compose_msg = reader.read_bytes_until_end();

    OFTComposeMsg { nonce, src_eid, amount_ld, compose_from, compose_msg }
}

// === Getters ===

/// Returns the unique sequence number for the cross-chain message packet
public fun nonce(self: &OFTComposeMsg): u64 {
    self.nonce
}

/// Returns the source chain endpoint ID where the transfer originated
public fun src_eid(self: &OFTComposeMsg): u32 {
    self.src_eid
}

/// Returns the amount received in local decimals
public fun amount_ld(self: &OFTComposeMsg): u64 {
    self.amount_ld
}

/// Returns the address that initiated the compose call on the source chain
public fun compose_from(self: &OFTComposeMsg): Bytes32 {
    self.compose_from
}

/// Returns the custom payload for compose logic execution
public fun compose_msg(self: &OFTComposeMsg): &vector<u8> {
    &self.compose_msg
}
