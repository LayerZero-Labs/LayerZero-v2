module oft::oft_msg_codec;

use utils::{buffer_reader, buffer_writer, bytes32::Bytes32};

// === Structs ===

/// Decoded OFT message containing transfer details and optional compose data
public struct OFTMessage has copy, drop {
    /// Recipient address on the destination chain
    send_to: address,
    /// Amount to transfer in shared decimals (normalized cross-chain format)
    amount_sd: u64,
    /// Address that initiated the compose call (optional)
    compose_from: Option<Bytes32>,
    /// Compose message payload for additional logic (optional)
    compose_msg: Option<vector<u8>>,
}

// === Codec Functions ===

/// Encodes OFT message data into a byte vector for cross-chain transmission
/// Format: [send_to(32)] [amount_sd(8)] [compose_from(32)] [compose_msg(variable)]
/// Compose fields are only included if both are provided
public fun encode(
    send_to: Bytes32,
    amount_sd: u64,
    compose_from: Option<Bytes32>,
    compose_msg: Option<vector<u8>>,
): vector<u8> {
    let mut writer = buffer_writer::new();
    writer.write_bytes32(send_to).write_u64(amount_sd);
    if (compose_from.is_some() && compose_msg.is_some()) {
        writer.write_bytes32(compose_from.destroy_some());
        writer.write_bytes(compose_msg.destroy_some());
    };
    writer.to_bytes()
}

/// Decodes byte vector into OFTMessage struct
/// Automatically detects presence of compose data based on remaining length
public fun decode(msg: vector<u8>): OFTMessage {
    let mut reader = buffer_reader::create(msg);
    let send_to = reader.read_address();
    let amount_sd = reader.read_u64();
    if (reader.remaining_length() > 0) {
        let compose_from = reader.read_bytes32();
        let compose_msg = reader.read_bytes_until_end();
        OFTMessage {
            send_to,
            amount_sd,
            compose_from: option::some(compose_from),
            compose_msg: option::some(compose_msg),
        }
    } else {
        OFTMessage { send_to, amount_sd, compose_from: option::none(), compose_msg: option::none() }
    }
}

// === Getters ===

/// Returns the recipient address on the destination chain
public fun send_to(self: &OFTMessage): address {
    self.send_to
}

/// Returns the transfer amount in shared decimals (normalized format)
public fun amount_sd(self: &OFTMessage): u64 {
    self.amount_sd
}

/// Returns the compose initiator address (if compose is enabled)
public fun compose_from(self: &OFTMessage): Option<Bytes32> {
    self.compose_from
}

/// Returns the compose message payload (if compose is enabled)
public fun compose_msg(self: &OFTMessage): &Option<vector<u8>> {
    &self.compose_msg
}

/// Returns true if this message includes compose functionality
public fun is_composed(self: &OFTMessage): bool {
    self.compose_from.is_some() && self.compose_msg.is_some()
}
