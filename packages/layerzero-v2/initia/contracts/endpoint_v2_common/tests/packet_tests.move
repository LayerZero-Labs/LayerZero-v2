#[test_only]
module endpoint_v2_common::packet_tests {
    use std::vector;

    use endpoint_v2_common::bytes32;
    use endpoint_v2_common::guid::compute_guid;
    use endpoint_v2_common::packet_raw::get_packet_bytes;
    use endpoint_v2_common::packet_v1_codec;
    use endpoint_v2_common::packet_v1_codec::{
        compute_payload,
        extract_header,
        get_dst_eid,
        get_guid,
        get_message,
        get_nonce,
        get_receiver,
        get_sender, get_src_eid, new_packet_v1,
    };

    #[test]
    fun test_encode_and_extract_packet() {
        let src_eid = 1;
        let sender = bytes32::from_address(@0x3);
        let dst_eid = 2;
        let receiver = bytes32::from_address(@0x4);
        let nonce = 0x1234;
        let message = vector<u8>[9, 8, 7, 6, 5, 4];
        let guid = compute_guid(nonce, src_eid, sender, dst_eid, receiver);

        let packet = new_packet_v1(src_eid, sender, dst_eid, receiver, nonce, guid, message);

        // test header extraction and assertion
        let packet_header = extract_header(&packet);
        packet_v1_codec::assert_receive_header(&packet_header, 2);

        // test textual decoders
        assert!(get_src_eid(&packet) == 1, 2);

        assert!(get_sender(&packet) == sender, 3);
        assert!(get_dst_eid(&packet) == 2, 4);
        assert!(get_receiver(&packet) == receiver, 5);
        assert!(get_nonce(&packet) == 0x1234, 6);
        assert!(get_message(&packet) == message, 7);
        assert!(get_guid(&packet) == guid, 8);

        // construct expected serialized packet
        let expected = vector<u8>[
            1, // version
            0, 0, 0, 0, 0, 0, 18, 52, // nonce
            0, 0, 0, 1, // src_eid
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, // sender
            0, 0, 0, 2, // dst_eid
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, // receiver
        ];
        vector::append(&mut expected, bytes32::from_bytes32(guid));
        vector::append(&mut expected, vector[9, 8, 7, 6, 5, 4]);

        let serialized = get_packet_bytes(packet);
        // test whole
        assert!(serialized == expected, 1);
    }

    #[test]
    fun test_compute_payload() {
        let guid = bytes32::to_bytes32(b"................................");
        let message = vector<u8>[18, 19, 20];
        let payload = compute_payload(guid, message);

        let expected = vector<u8>[
            46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46,
            46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, // 32 periods
            18, 19, 20, // message
        ];
        assert!(payload == expected, 1);
    }
}
