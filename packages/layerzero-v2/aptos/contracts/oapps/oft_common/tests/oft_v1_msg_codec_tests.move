#[test_only]
module oft_common::oft_1_msg_codec_tests {
    use endpoint_v2_common::bytes32;
    use oft_common::oft_v1_msg_codec;
    use oft_common::oft_v1_msg_codec::{PT_SEND, PT_SEND_AND_CALL};

    #[test]
    fun test_encode_should_encode_and_decode_without_compose() {
        let send_to = bytes32::to_bytes32(b"12345678901234567890123456789012");
        let amount = 1000;

        let encoded = oft_v1_msg_codec::encode(
            PT_SEND(),
            send_to,
            amount,
            bytes32::from_address(@0x1234567890123456789012345678901234567890123456789012345678901234),
            0,
            vector[],
        );

        assert!(oft_v1_msg_codec::message_type(&encoded) == PT_SEND(), 1);
        assert!(!oft_v1_msg_codec::has_compose(&encoded), 0);
        assert!(oft_v1_msg_codec::send_to(&encoded) == send_to, 1);
        assert!(oft_v1_msg_codec::amount_sd(&encoded) == amount, 2);
    }

    #[test]
    fun test_encode_should_encode_and_decode_with_compose() {
        let sender = @0x1234567890123456789012345678901234567890123456789012345678901234;
        let send_to = bytes32::to_bytes32(b"12345678901234567890123456789012");
        let amount = 1000;
        let compose_msg = x"9999888855";

        let encoded = oft_v1_msg_codec::encode(
            PT_SEND_AND_CALL(),
            send_to,
            amount,
            bytes32::from_address(sender),
            0x101,
            compose_msg,
        );

        assert!(oft_v1_msg_codec::message_type(&encoded) == PT_SEND_AND_CALL(), 1);
        assert!(oft_v1_msg_codec::has_compose(&encoded), 0);
        assert!(oft_v1_msg_codec::send_to(&encoded) == send_to, 1);
        assert!(oft_v1_msg_codec::amount_sd(&encoded) == amount, 2);
        assert!(oft_v1_msg_codec::compose_gas(&encoded) == 0x101, 3);

        let v2_style_compose_packet = x"12345678901234567890123456789012345678901234567890123456789012349999888855";
        assert!(oft_v1_msg_codec::v2_compatible_compose_payload(&encoded) == v2_style_compose_packet, 3);
    }
}
