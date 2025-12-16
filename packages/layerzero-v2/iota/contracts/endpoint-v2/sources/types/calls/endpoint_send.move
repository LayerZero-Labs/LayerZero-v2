/// Module for handling send parameters from OApp calling Endpoint.
///
/// This module defines the SendParam struct which encapsulates all necessary
/// information and assets required to send cross-chain messages. Unlike QuoteParam,
/// SendParam contains actual coins for payment and is implemented as a hot-potato
/// pattern to ensure proper resource management.
module endpoint_v2::endpoint_send;

use iota::{coin::Coin, iota::IOTA};
use utils::bytes32::Bytes32;
use zro::zro::ZRO;

// === Structs ===

/// Parameters and payment tokens required for sending cross-chain messages.
///
/// This struct is implemented as a hot-potato pattern because it contains coins
/// that must be properly consumed or returned. It encapsulates all information
/// needed to execute a cross-chain message send operation including payment tokens
/// and refund handling.
#[allow(lint(coin_field))]
public struct SendParam {
    // Destination endpoint ID - identifies the target blockchain
    dst_eid: u32,
    // Address of the OApp receiver on the destination chain
    receiver: Bytes32,
    // The actual message payload to be sent cross-chain
    message: vector<u8>,
    // Additional options for message delivery (e.g., gas limits, native drop)
    options: vector<u8>,
    // Native IOTA tokens to pay for messaging fees
    native_token: Coin<IOTA>,
    // Optional ZRO tokens for alternative fee payment
    zro_token: Option<Coin<ZRO>>,
    // Optional refund address - if not provided, refund will be handled by the OApp
    refund_address: Option<address>,
}

// === Creation ===

/// Creates a new SendParam instance with the specified parameters and payment tokens.
public fun create_param(
    dst_eid: u32,
    receiver: Bytes32,
    message: vector<u8>,
    options: vector<u8>,
    native_token: Coin<IOTA>,
    zro_token: Option<Coin<ZRO>>,
    refund_address: Option<address>,
): SendParam {
    SendParam { dst_eid, receiver, message, options, native_token, zro_token, refund_address }
}

/// Destroys the SendParam and returns the remaining coins.
public fun destroy(self: SendParam): (Coin<IOTA>, Option<Coin<ZRO>>) {
    let SendParam { native_token, zro_token, .. } = self;
    (native_token, zro_token)
}

// === Param Getters ===

/// Returns the destination endpoint ID.
public fun dst_eid(self: &SendParam): u32 {
    self.dst_eid
}

/// Returns the receiver address on the destination chain.
public fun receiver(self: &SendParam): Bytes32 {
    self.receiver
}

/// Returns a reference to the message payload to be sent cross-chain.
public fun message(self: &SendParam): &vector<u8> {
    &self.message
}

/// Returns a reference to the options for message delivery.
public fun options(self: &SendParam): &vector<u8> {
    &self.options
}

/// Returns the optional refund address for excess payment tokens.
public fun refund_address(self: &SendParam): Option<address> {
    self.refund_address
}

/// Returns a reference to the native IOTA token.
public fun native_token(self: &SendParam): &Coin<IOTA> {
    &self.native_token
}

/// Returns a reference to the optional ZRO token.
public fun zro_token(self: &SendParam): &Option<Coin<ZRO>> {
    &self.zro_token
}

/// Returns a mutable reference to the native IOTA token for modifications.
public fun native_token_mut(self: &mut SendParam): &mut Coin<IOTA> {
    &mut self.native_token
}

/// Returns a mutable reference to the optional ZRO token for modifications.
public fun zro_token_mut(self: &mut SendParam): &mut Option<Coin<ZRO>> {
    &mut self.zro_token
}

/// Returns whether fees will be paid using ZRO tokens.
public fun pay_in_zro(self: &SendParam): bool {
    self.zro_token.is_some()
}
