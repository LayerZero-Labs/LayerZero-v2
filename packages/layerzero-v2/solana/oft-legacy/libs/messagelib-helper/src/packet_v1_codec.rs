use anchor_lang::prelude::Pubkey;
use messagelib_interface::Packet;
use utils::bytes_lib::BytesUtils;

pub const PACKET_VERSION: u8 = 1;
pub const PACKET_HEADER_SIZE: usize = 81;

// header (version + nonce + path)
// version
const PACKET_VERSION_OFFSET: usize = 0;
// nonce
const NONCE_OFFSET: usize = 1;
// path
const SRC_EID_OFFSET: usize = 9;
const SENDER_OFFSET: usize = 13;
const DST_EID_OFFSET: usize = 45;
const RECEIVER_OFFSET: usize = 49;
// payload (guid + message)
const GUID_OFFSET: usize = 81;
const MESSAGE_OFFSET: usize = 113;

pub fn encode(packet: &Packet) -> Vec<u8> {
    [
        &PACKET_VERSION.to_be_bytes()[..],
        &packet.nonce.to_be_bytes()[..],
        &packet.src_eid.to_be_bytes()[..],
        &packet.sender.to_bytes()[..],
        &packet.dst_eid.to_be_bytes()[..],
        &packet.receiver[..],
        &packet.guid[..],
        &packet.message,
    ]
    .concat()
}

pub fn encode_packet_header(packet: &Packet) -> Vec<u8> {
    [
        &PACKET_VERSION.to_be_bytes()[..],
        &packet.nonce.to_be_bytes()[..],
        &packet.src_eid.to_be_bytes()[..],
        &packet.sender.to_bytes()[..],
        &packet.dst_eid.to_be_bytes()[..],
        &packet.receiver[..],
    ]
    .concat()
}

pub fn header(packet: &[u8]) -> &[u8] {
    &packet[0..GUID_OFFSET]
}

pub fn version(packet: &[u8]) -> u8 {
    packet.to_u8(PACKET_VERSION_OFFSET)
}

pub fn nonce(packet: &[u8]) -> u64 {
    packet.to_u64(NONCE_OFFSET)
}

pub fn src_eid(packet: &[u8]) -> u32 {
    packet.to_u32(SRC_EID_OFFSET)
}

pub fn sender(packet: &[u8]) -> [u8; 32] {
    packet.to_byte_array(SENDER_OFFSET)
}

pub fn sender_pubkey(packet: &[u8]) -> Pubkey {
    packet.to_pubkey(SENDER_OFFSET)
}

pub fn dst_eid(packet: &[u8]) -> u32 {
    packet.to_u32(DST_EID_OFFSET)
}

pub fn receiver(packet: &[u8]) -> [u8; 32] {
    packet.to_byte_array(RECEIVER_OFFSET)
}

pub fn receiver_pubkey(packet: &[u8]) -> Pubkey {
    packet.to_pubkey(RECEIVER_OFFSET)
}

pub fn guid(packet: &[u8]) -> [u8; 32] {
    packet.to_byte_array(GUID_OFFSET)
}

pub fn message(packet: &[u8]) -> &[u8] {
    &packet[MESSAGE_OFFSET..]
}

pub fn payload(packet: &[u8]) -> &[u8] {
    &packet[GUID_OFFSET..]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encode() {
        let packet = Packet {
            nonce: 1,
            src_eid: 101,
            sender: Pubkey::new_unique(),
            dst_eid: 102,
            receiver: Pubkey::new_unique().to_bytes(),
            guid: [2; 32],
            message: vec![1, 2, 3],
        };

        let encoded = encode(&packet);
        assert_eq!(version(&encoded), PACKET_VERSION);
        assert_eq!(nonce(&encoded), packet.nonce);
        assert_eq!(src_eid(&encoded), packet.src_eid);
        assert_eq!(sender(&encoded), packet.sender.to_bytes());
        assert_eq!(dst_eid(&encoded), packet.dst_eid);
        assert_eq!(receiver(&encoded), packet.receiver);
        assert_eq!(guid(&encoded), packet.guid);
        assert_eq!(message(&encoded), packet.message);

        // assert payload, should equal to guid + message
        let payload_bytes = [&packet.guid[..], packet.message.as_slice()].concat();
        assert_eq!(payload(&encoded), payload_bytes.as_slice());

        // assert header, should equal to version + nonce + path
        let header_bytes = [
            // version
            &PACKET_VERSION.to_be_bytes()[..],
            // nonce
            &packet.nonce.to_be_bytes()[..],
            // path
            &packet.src_eid.to_be_bytes()[..],
            &packet.sender.to_bytes()[..],
            &packet.dst_eid.to_be_bytes()[..],
            &packet.receiver[..],
        ]
        .concat();
        assert_eq!(header(&encoded), header_bytes.as_slice());

        // assert sender_pubkey
        assert_eq!(sender_pubkey(&encoded), packet.sender);

        // assert receiver_pubkey
        assert_eq!(receiver_pubkey(&encoded), Pubkey::new_from_array(packet.receiver));
    }

    #[test]
    fn test_encode_packet_header() {
        let packet = Packet {
            nonce: 1,
            src_eid: 101,
            sender: Pubkey::new_unique(),
            dst_eid: 102,
            receiver: Pubkey::new_unique().to_bytes(),
            guid: [2; 32],
            message: vec![1, 2, 3],
        };

        let encoded = encode_packet_header(&packet);
        assert_eq!(version(&encoded), PACKET_VERSION);
        assert_eq!(nonce(&encoded), packet.nonce);
        assert_eq!(src_eid(&encoded), packet.src_eid);
        assert_eq!(sender(&encoded), packet.sender.to_bytes());
        assert_eq!(dst_eid(&encoded), packet.dst_eid);
        assert_eq!(receiver(&encoded), packet.receiver);

        // assert header, should equal to version + nonce + path
        let header_bytes = [
            // version
            &PACKET_VERSION.to_be_bytes()[..],
            // nonce
            &packet.nonce.to_be_bytes()[..],
            // path
            &packet.src_eid.to_be_bytes()[..],
            &packet.sender.to_bytes()[..],
            &packet.dst_eid.to_be_bytes()[..],
            &packet.receiver[..],
        ]
        .concat();
        assert_eq!(header(&encoded), header_bytes.as_slice());
    }
}
