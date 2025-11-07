/// Module for handling quote parameters from OApp calling Endpoint.
///
/// This module defines the QuoteParam struct which encapsulates all necessary
/// information required to quote messaging fees for cross-chain transactions.
/// The quote operation estimates the cost of sending a message from the current
/// chain to a destination chain through the LayerZero messaging protocol.
module endpoint_v2::endpoint_quote;

use utils::bytes32::Bytes32;

// === Structs ===

/// Parameters required for quoting cross-chain messaging fees.
///
/// This struct contains all the information needed to calculate the cost
/// of sending a message to another chain. The quote process helps users
/// understand the fees before actually sending a transaction.
public struct QuoteParam has copy, drop, store {
    // Destination endpoint ID - identifies the target blockchain
    dst_eid: u32,
    // Address of the OApp receiver on the destination chain
    receiver: Bytes32,
    // The actual message payload to be sent cross-chain
    message: vector<u8>,
    // Additional options for message delivery (e.g., gas limits, native drop)
    options: vector<u8>,
    // Whether to pay fees using ZRO tokens
    pay_in_zro: bool,
}

// === Creation ===

/// Creates a new QuoteParam instance with the specified parameters for fee quotation.
public fun create_param(
    dst_eid: u32,
    receiver: Bytes32,
    message: vector<u8>,
    options: vector<u8>,
    pay_in_zro: bool,
): QuoteParam {
    QuoteParam { dst_eid, receiver, message, options, pay_in_zro }
}

// === Param Getters ===

/// Returns the destination endpoint ID (chain identifier).
public fun dst_eid(self: &QuoteParam): u32 {
    self.dst_eid
}

/// Returns the receiver address on the destination chain.
public fun receiver(self: &QuoteParam): Bytes32 {
    self.receiver
}

/// Returns a reference to the message payload to be sent cross-chain.
public fun message(self: &QuoteParam): &vector<u8> {
    &self.message
}

/// Returns a reference to the options for message delivery.
public fun options(self: &QuoteParam): &vector<u8> {
    &self.options
}

/// Returns whether fees will be paid using ZRO tokens.
public fun pay_in_zro(self: &QuoteParam): bool {
    self.pay_in_zro
}
