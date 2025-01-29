#[test_only]
module oft_common::oft_compose_codec_tests {
    use endpoint_v2_common::bytes32;
    use endpoint_v2_common::serde::flatten;
    use oft_common::oft_compose_msg_codec;

    #[test]
    fun test_encode_should_encode_and_decode_with_compose() {
        let nonce = 123;
        let src_eid = 456;
        let amount_ld = 1000;
        let compose_msg = flatten(vector[
            x"1234567890123456789012345678901234567890123456789012345678901234",
            x"9999888855",
        ]);

        let encoded = oft_compose_msg_codec::encode(
            nonce,
            src_eid,
            amount_ld,
            compose_msg,
        );

        assert!(oft_compose_msg_codec::nonce(&encoded) == nonce, 1);
        assert!(oft_compose_msg_codec::src_eid(&encoded) == src_eid, 2);
        assert!(oft_compose_msg_codec::amount_ld(&encoded) == amount_ld, 3);
        assert!(
            oft_compose_msg_codec::compose_payload_from(&encoded) == bytes32::to_bytes32(
                x"1234567890123456789012345678901234567890123456789012345678901234"
            ),
            5,
        );
        assert!(oft_compose_msg_codec::compose_payload_message(&encoded) == x"9999888855", 6);
    }

    #[test]
    #[expected_failure(abort_code = oft_common::oft_compose_msg_codec::ENO_COMPOSE_MSG)]
    fun test_compose_from_should_fail_when_no_compose() {
        let encoded = oft_compose_msg_codec::encode(
            123,
            456,
            1000,
            vector[],
        );

        oft_compose_msg_codec::compose_payload_from(&encoded);
    }

    #[test]
    #[expected_failure(abort_code = oft_common::oft_compose_msg_codec::ENO_COMPOSE_MSG)]
    fun test_compose_msg_from_oft_compose_msg_should_fail_when_no_compose() {
        let encoded = oft_compose_msg_codec::encode(
            123,
            456,
            1000,
            vector[],
        );

        oft_compose_msg_codec::compose_payload_message(&encoded);
    }
}
