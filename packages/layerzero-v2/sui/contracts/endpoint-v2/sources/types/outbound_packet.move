/// Outbound packet structure for endpoint v2.
/// Represents a message packet being sent from the endpoint to the message library for processing and encoding.
/// Contains all necessary payload information that the message library needs to encode and transmit the message
/// cross-chain.
module endpoint_v2::outbound_packet;

use endpoint_v2::utils;
use utils::bytes32::{Self, Bytes32};

// === Structs ===

/// Packet structure passed from the endpoint to message libraries for processing.
/// Contains all payload data that message libraries need to encode and transmit messages cross-chain.
public struct OutboundPacket has copy, drop, store {
    // Sequential number for message ordering and tracking
    nonce: u64,
    // Source endpoint ID
    src_eid: u32,
    // Address of the sender on the source chain
    sender: address,
    // Destination endpoint ID
    dst_eid: u32,
    // Receiver address on the destination chain (encoded as Bytes32)
    receiver: Bytes32,
    // Globally unique identifier computed from packet parameters
    guid: Bytes32,
    // The actual message payload to be delivered
    message: vector<u8>,
}

// === Creation ===

/// Creates a new OutboundPacket with the specified parameters for message library processing.
/// The GUID is automatically computed based on the packet parameters for unique identification across the LayerZero
/// network.
public(package) fun create(
    nonce: u64,
    src_eid: u32,
    sender: address,
    dst_eid: u32,
    receiver: Bytes32,
    message: vector<u8>,
): OutboundPacket {
    let guid = utils::compute_guid(nonce, src_eid, bytes32::from_address(sender), dst_eid, receiver);
    OutboundPacket { nonce, src_eid, sender, dst_eid, receiver, guid, message }
}

// === Unpacking ===

/// Unpacks the OutboundPacket into its constituent components.
/// Returns: (nonce, src_eid, sender, dst_eid, receiver, guid, message)
public fun unpack(self: OutboundPacket): (u64, u32, address, u32, Bytes32, Bytes32, vector<u8>) {
    let OutboundPacket { nonce, src_eid, sender, dst_eid, receiver, guid, message } = self;
    (nonce, src_eid, sender, dst_eid, receiver, guid, message)
}

// === Getters ===

/// Returns the nonce (sequential number) of the packet.
public fun nonce(self: &OutboundPacket): u64 {
    self.nonce
}

/// Returns the source endpoint ID.
public fun src_eid(self: &OutboundPacket): u32 {
    self.src_eid
}

/// Returns the sender address on the source chain.
public fun sender(self: &OutboundPacket): address {
    self.sender
}

/// Returns the destination endpoint ID.
public fun dst_eid(self: &OutboundPacket): u32 {
    self.dst_eid
}

/// Returns the receiver address on the destination chain.
public fun receiver(self: &OutboundPacket): Bytes32 {
    self.receiver
}

/// Returns the globally unique identifier of the packet.
public fun guid(self: &OutboundPacket): Bytes32 {
    self.guid
}

/// Returns a reference to the message payload.
public fun message(self: &OutboundPacket): &vector<u8> {
    &self.message
}

/// Returns the length of the message payload in bytes.
public fun message_length(self: &OutboundPacket): u64 {
    self.message.length()
}

// === Test Only ===

#[test_only]
public fun create_for_test(
    nonce: u64,
    src_eid: u32,
    sender: address,
    dst_eid: u32,
    receiver: Bytes32,
    message: vector<u8>,
): OutboundPacket {
    create(nonce, src_eid, sender, dst_eid, receiver, message)
}
