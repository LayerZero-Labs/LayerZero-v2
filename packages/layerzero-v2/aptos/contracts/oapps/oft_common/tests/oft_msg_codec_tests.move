#[test_only]
module oft_common::oft_msg_codec_tests {
    use endpoint_v2_common::bytes32;
    use oft_common::oft_msg_codec;

    #[test]
    fun test_encode_should_encode_and_decode_without_compose() {
        let send_to = bytes32::to_bytes32(b"12345678901234567890123456789012");
        let amount = 1000;

        let encoded = oft_msg_codec::encode(
            send_to,
            amount,
            bytes32::from_address(@0x1234567890123456789012345678901234567890123456789012345678901234),
            // empty compose message signifies no compose message
            vector[],
        );

        assert!(!oft_msg_codec::has_compose(&encoded), 0);
        assert!(oft_msg_codec::send_to(&encoded) == send_to, 1);
        assert!(oft_msg_codec::amount_sd(&encoded) == amount, 2);
    }

    #[test]
    fun test_encode_should_encode_and_decode_with_compose() {
        let sender = @0x1234567890123456789012345678901234567890123456789012345678901234;
        let send_to = bytes32::to_bytes32(b"12345678901234567890123456789012");
        let amount = 1000;
        let compose_msg = x"9999888855";

        let encoded = oft_msg_codec::encode(send_to, amount, bytes32::from_address(sender), compose_msg);

        assert!(oft_msg_codec::has_compose(&encoded), 0);
        assert!(oft_msg_codec::send_to(&encoded) == send_to, 1);
        assert!(oft_msg_codec::amount_sd(&encoded) == amount, 2);

        let compose_packet = x"12345678901234567890123456789012345678901234567890123456789012349999888855";
        assert!(oft_msg_codec::compose_payload(&encoded) == compose_packet, 3);
    }
}
