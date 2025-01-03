/// This module defines a semantic wrapper for raw packet (and packet header) bytes
/// This format is agnostic to the codec used in the Message Library, but it is valuable to provide clarity and type
/// safety for Packets and headers in the codebase
module endpoint_v2_common::packet_raw {
    use std::vector;

    struct RawPacket has drop, copy, store {
        packet: vector<u8>,
    }

    /// Create a vector<u8> from a RawPacket
    public fun bytes_to_raw_packet(packet_bytes: vector<u8>): RawPacket {
        RawPacket { packet: packet_bytes }
    }

    /// Borrow the packet bytes from a RawPacket
    public fun borrow_packet_bytes(raw_packet: &RawPacket): &vector<u8> {
        &raw_packet.packet
    }

    /// Borrow the packet bytes mutably from a RawPacket
    public fun borrow_packet_bytes_mut(raw_packet: &mut RawPacket): &mut vector<u8> {
        &mut raw_packet.packet
    }

    /// Move the packet bytes from a RawPacket
    public fun get_packet_bytes(raw_packet: RawPacket): vector<u8> {
        let RawPacket { packet } = raw_packet;
        packet
    }

    /// Get the packet length of a RawPacket
    public fun length(raw_packet: &RawPacket): u64 {
        vector::length(&raw_packet.packet)
    }
}
