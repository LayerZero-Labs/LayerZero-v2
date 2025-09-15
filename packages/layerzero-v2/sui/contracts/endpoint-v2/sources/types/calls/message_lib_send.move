/// Module for handling message library send parameters from Endpoint calling MessageLib.
///
/// This module defines the SendParam and SendResult structs which encapsulate all
/// necessary information for message libraries to send messages and return results.
/// Unlike the endpoint send module, this operates at the message library level
/// and works with outbound packets rather than raw message parameters.
module endpoint_v2::message_lib_send;

use endpoint_v2::{message_lib_quote::QuoteParam, messaging_fee::MessagingFee};

// === Structs ===

/// Parameters required for message libraries to send messages.
///
/// This struct contains all information needed for a message library to send an outbound packet.
/// It wraps QuoteParam to reuse the same parameter structure for both quoting and sending operations,
/// ensuring consistency and type safety between the quote and send flows.
public struct SendParam has copy, drop, store {
    base: QuoteParam,
}

/// Result returned by message libraries after processing a send operation.
///
/// This struct contains the outputs from a successful message library send,
/// including the encoded packet for transmission and the actual fees charged.
public struct SendResult has copy, drop, store {
    // The encoded packet ready for transmission
    encoded_packet: vector<u8>,
    // The messaging fee charged for the send operation
    fee: MessagingFee,
}

// === Creation ===

/// Creates a new SendParam instance with the specified base quote param.
public(package) fun create_param(base: QuoteParam): SendParam {
    SendParam { base }
}

/// Creates a new SendResult instance with the encoded packet and fee information.
public fun create_result(encoded_packet: vector<u8>, fee: MessagingFee): SendResult {
    SendResult { encoded_packet, fee }
}

// === Param Getters ===

/// Returns a reference to the base quote param.
public fun base(self: &SendParam): &QuoteParam {
    &self.base
}

// === Result Getters ===

/// Returns a reference to the encoded packet ready for sending.
public fun encoded_packet(self: &SendResult): &vector<u8> {
    &self.encoded_packet
}

/// Returns a reference to the messaging fee charged for the operation.
public fun fee(self: &SendResult): &MessagingFee {
    &self.fee
}

// === Test Only ===

#[test_only]
public fun create_param_for_test(base: QuoteParam): SendParam {
    create_param(base)
}
