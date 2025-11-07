module oft::send_param;

use utils::bytes32::Bytes32;

// === Struct ===

/// Parameters for cross-chain token transfers in the OFT protocol.
public struct SendParam has drop {
    /// Destination endpoint identifier - specifies which chain to send tokens to
    dst_eid: u32,
    /// Recipient address on the destination chain (32-byte format for cross-chain compatibility)
    to: Bytes32,
    /// Amount to send denominated in local decimals (source chain's token precision)
    amount_ld: u64,
    /// Minimum amount that must be received on destination (prevents slippage/fee issues)
    min_amount_ld: u64,
    /// Additional LayerZero message options (gas limits, delivery guarantees, etc.)
    extra_options: vector<u8>,
    /// (Optional) Compose message payload for triggering actions on the destination chain
    compose_msg: vector<u8>,
    /// (Optional) The OFT command to be executed, unused in default OFT implementations.
    oft_cmd: vector<u8>,
}

// === Creation ===

/// Creates a new SendParam struct for cross-chain token transfers.
public fun create(
    dst_eid: u32,
    to: Bytes32,
    amount_ld: u64,
    min_amount_ld: u64,
    extra_options: vector<u8>,
    compose_msg: vector<u8>,
    oft_cmd: vector<u8>,
): SendParam {
    SendParam { dst_eid, to, amount_ld, min_amount_ld, extra_options, compose_msg, oft_cmd }
}

// === Getters ===

/// Returns the destination endpoint ID
public fun dst_eid(self: &SendParam): u32 {
    self.dst_eid
}

/// Returns the recipient address on the destination chain
public fun to(self: &SendParam): Bytes32 {
    self.to
}

/// Returns the amount to send in local decimals
public fun amount_ld(self: &SendParam): u64 {
    self.amount_ld
}

/// Returns the minimum amount that must be received on destination
public fun min_amount_ld(self: &SendParam): u64 {
    self.min_amount_ld
}

/// Returns additional LayerZero message options
public fun extra_options(self: &SendParam): &vector<u8> {
    &self.extra_options
}

/// Returns the compose message payload
public fun compose_msg(self: &SendParam): &vector<u8> {
    &self.compose_msg
}

/// Returns the OFT command payload
public fun oft_cmd(self: &SendParam): &vector<u8> {
    &self.oft_cmd
}
