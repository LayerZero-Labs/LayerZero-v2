/// This module defines the internal send packet structure. This is the packet structure that is used internally by the
/// endpoint_v2 to communicate with the message libraries. Unlike the packet_v1_codec, which is may be upgraded for
/// use with a future message library, the internal packet is a fixed structure and is unchangable even with future
/// message libraries
module endpoint_v2_common::send_packet {
    use std::vector;

    use endpoint_v2_common::bytes32::Bytes32;
    use endpoint_v2_common::guid;

    struct SendPacket has copy, drop, store {
        nonce: u64,
        src_eid: u32,
        sender: Bytes32,
        dst_eid: u32,
        receiver: Bytes32,
        guid: Bytes32,
        message: vector<u8>,
    }

    /// Create a new send packet
    public fun new_send_packet(
        nonce: u64,
        src_eid: u32,
        sender: Bytes32,
        dst_eid: u32,
        receiver: Bytes32,
        message: vector<u8>,
    ): SendPacket {
        let guid = guid::compute_guid(nonce, src_eid, sender, dst_eid, receiver);
        SendPacket {
            nonce,
            src_eid,
            sender,
            dst_eid,
            receiver,
            guid,
            message,
        }
    }

    /// Unpack the send packet into its components
    public fun unpack_send_packet(
        packet: SendPacket,
    ): (u64, u32, Bytes32, u32, Bytes32, Bytes32, vector<u8>) {
        let SendPacket {
            nonce,
            src_eid,
            sender,
            dst_eid,
            receiver,
            guid,
            message,
        } = packet;
        (nonce, src_eid, sender, dst_eid, receiver, guid, message)
    }

    public fun get_nonce(packet: &SendPacket): u64 {
        packet.nonce
    }

    public fun get_src_eid(packet: &SendPacket): u32 {
        packet.src_eid
    }

    public fun get_sender(packet: &SendPacket): Bytes32 {
        packet.sender
    }

    public fun get_dst_eid(packet: &SendPacket): u32 {
        packet.dst_eid
    }

    public fun get_receiver(packet: &SendPacket): Bytes32 {
        packet.receiver
    }

    public fun get_guid(packet: &SendPacket): Bytes32 {
        packet.guid
    }

    public fun borrow_message(packet: &SendPacket): &vector<u8> {
        &packet.message
    }

    public fun get_message_length(packet: &SendPacket): u64 {
        vector::length(&packet.message)
    }
}
