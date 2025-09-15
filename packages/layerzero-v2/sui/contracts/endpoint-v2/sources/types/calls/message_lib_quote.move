/// Module for handling message library quote parameters from Endpoint calling MessageLib.
///
/// This module defines the QuoteParam struct which encapsulates all necessary
/// information required for message libraries to quote messaging fees. Unlike
/// the endpoint quote module, this operates at the message library level and
/// works with outbound packets rather than raw message parameters.
module endpoint_v2::message_lib_quote;

use endpoint_v2::outbound_packet::OutboundPacket;

// === Structs ===

/// Parameters required for message libraries to quote messaging fees.
///
/// This struct contains all information needed for a message library to calculate
/// the cost of processing and transmitting an outbound packet. The quote process
/// helps determine fees at the message library level for specific message library
/// configurations.
public struct QuoteParam has copy, drop, store {
    // The outbound packet containing message details
    packet: OutboundPacket,
    // Additional options for message delivery (e.g., gas limits, native drop)
    options: vector<u8>,
    // Whether to pay fees using ZRO tokens
    pay_in_zro: bool,
}

// === Creation ===

/// Creates a new QuoteParam instance with the specified message library quote parameters.
public(package) fun create_param(packet: OutboundPacket, options: vector<u8>, pay_in_zro: bool): QuoteParam {
    QuoteParam { packet, options, pay_in_zro }
}

// === Param Getters ===

/// Returns a reference to the outbound packet containing message details.
public fun packet(self: &QuoteParam): &OutboundPacket {
    &self.packet
}

/// Returns a reference to the options for message delivery.
public fun options(self: &QuoteParam): &vector<u8> {
    &self.options
}

/// Returns whether fees will be paid using ZRO tokens.
public fun pay_in_zro(self: &QuoteParam): bool {
    self.pay_in_zro
}

// === Test Only ===

#[test_only]
public fun create_param_for_test(packet: OutboundPacket, options: vector<u8>, pay_in_zro: bool): QuoteParam {
    create_param(packet, options, pay_in_zro)
}
