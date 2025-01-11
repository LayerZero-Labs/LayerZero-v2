#[test_only]
module msglib_types::test_dvn_verify_params {
    use endpoint_v2_common::bytes32;
    use endpoint_v2_common::packet_raw;

    #[test]
    fun test_dvn_verify_params_pack_and_unpack() {
        let original_header = packet_raw::bytes_to_raw_packet(b"1234");
        let packed = msglib_types::dvn_verify_params::pack_dvn_verify_params(
            original_header,
            bytes32::to_bytes32(b"12345678901234567890123456789012"),
            42,
        );
        let (packet_header, payload_hash, confirmations) = msglib_types::dvn_verify_params::unpack_dvn_verify_params(
            packed,
        );
        assert!(packet_header == original_header, 0);
        assert!(payload_hash == bytes32::to_bytes32(b"12345678901234567890123456789012"), 1);
        assert!(confirmations == 42, 2);
    }
}
