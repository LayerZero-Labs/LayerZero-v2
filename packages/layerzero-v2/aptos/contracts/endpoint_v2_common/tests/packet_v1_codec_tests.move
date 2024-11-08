#[test_only]
module endpoint_v2_common::packet_v1_codec_tests {
    use std::vector;

    use endpoint_v2_common::bytes32;
    use endpoint_v2_common::packet_raw;
    use endpoint_v2_common::packet_v1_codec::{assert_receive_header, new_packet_v1_header_only};

    #[test]
    fun test_assert_receive_header() {
        let header = new_packet_v1_header_only(
            1,
            bytes32::from_address(@0x3),
            2,
            bytes32::from_address(@0x4),
            0x1234,
        );
        assert_receive_header(&header, 2);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::packet_v1_codec::EINVALID_PACKET_HEADER)]
    fun test_assert_receive_header_fails_if_invalid_length() {
        let header = packet_raw::bytes_to_raw_packet(b"1234");
        assert_receive_header(&header, 1);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::packet_v1_codec::EINVALID_PACKET_VERSION)]
    fun test_assert_receive_header_fails_if_invalid_version() {
        let header = new_packet_v1_header_only(
            1,
            bytes32::from_address(@0x3),
            2,
            bytes32::from_address(@0x4),
            0x1234,
        );
        let bytes = packet_raw::borrow_packet_bytes_mut(&mut header);
        *vector::borrow_mut(bytes, 0) = 0x02;
        assert_receive_header(&header, 2);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::packet_v1_codec::EINVALID_EID)]
    fun test_assert_receive_header_fails_if_invalid_dst_eid() {
        let header = new_packet_v1_header_only(
            1,
            bytes32::from_address(@0x3),
            2,
            bytes32::from_address(@0x4),
            0x1234,
        );
        // dst_eid (not src_eid) should match local_eid
        assert_receive_header(&header, 1);
    }
}
