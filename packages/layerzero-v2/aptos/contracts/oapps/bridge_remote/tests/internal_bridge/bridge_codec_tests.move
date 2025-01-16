#[test_only]
module bridge_remote::bridge_codec_tests {
    use bridge_remote::bridge_codecs;
    use endpoint_v2_common::bytes32::{Self, Bytes32, from_address};

    #[test]
    fun test_encode_decode_factory_add_token_message() {
        let token: Bytes32 = from_address(@0x2000);
        let shared_decimals: u8 = 6;
        let name: vector<u8> = b"My Test Token";
        let symbol: vector<u8> = b"MYT";

        let message = bridge_codecs::encode_factory_add_token_message(
            token,
            shared_decimals,
            name,
            symbol,
        );

        let (decoded_token, decoded_shared_decimals, decoded_name, decoded_symbol) =
            bridge_codecs::decode_factory_add_token_message(&message);

        assert!(decoded_token == token, 1);
        assert!(decoded_shared_decimals == shared_decimals, 1);
        assert!(decoded_name == name, 1);
        assert!(decoded_symbol == symbol, 1);
    }

    #[test]
    fun test_encode_decode_tokens_transfer_message() {
        let token: Bytes32 = from_address(@0x2000);
        let to: Bytes32 = from_address(@0x2000);
        let amount_sd: u64 = 123;
        let sender: Bytes32 = from_address(@0x3000);
        let compose_payload: vector<u8> = b"";

        let message = bridge_codecs::encode_tokens_transfer_message(
            token,
            to,
            amount_sd,
            sender,
            compose_payload,
        );

        let (decoded_token, decoded_to, decoded_amount_sd, decoded_has_compose, decoded_sender, decoded_compose_payload) =
            bridge_codecs::decode_tokens_transfer_message(&message);

        assert!(decoded_token == token, 1);
        assert!(decoded_to == to, 1);
        assert!(decoded_amount_sd == amount_sd, 1);
        assert!(decoded_has_compose == false, 1);
        assert!(decoded_sender == bytes32::zero_bytes32(), 1);
        assert!(decoded_compose_payload == compose_payload, 1);
    }

    #[test]
    fun test_encode_decode_tokens_transfer_message_with_compose() {
        let token: Bytes32 = from_address(@0x2000);
        let to: Bytes32 = from_address(@0x2000);
        let amount_sd: u64 = 123;
        let sender: Bytes32 = from_address(@0x3000);
        let compose_payload: vector<u8> = b"Hi there!";

        let message = bridge_codecs::encode_tokens_transfer_message(
            token,
            to,
            amount_sd,
            sender,
            compose_payload,
        );

        let (decoded_token, decoded_to, decoded_amount_sd, decoded_has_compose, decoded_sender, decoded_compose_payload) =
            bridge_codecs::decode_tokens_transfer_message(&message);

        assert!(decoded_token == token, 1);
        assert!(decoded_to == to, 1);
        assert!(decoded_amount_sd == amount_sd, 1);
        assert!(decoded_has_compose == true, 1);
        assert!(decoded_sender == sender, 1);
        assert!(decoded_compose_payload == compose_payload, 1);
    }

    #[test]
    fun test_encode_decode_compose() {
        let nonce: u64 = 1;
        let src_eid: u32 = 2;
        let token: Bytes32 = from_address(@0x2000);
        let amount_ld: u64 = 123;
        let sender: Bytes32 = from_address(@0x3000);
        let compose_payload: vector<u8> = b"Hi there!";

        let encoded = bridge_codecs::encode_compose(
            nonce,
            src_eid,
            token,
            amount_ld,
            sender,
            compose_payload,
        );

        let (decoded_nonce, decoded_src_eid, decoded_token, decoded_amount_ld, decoded_sender, decoded_compose_payload) =
            bridge_codecs::decode_compose(&encoded);

        assert!(decoded_nonce == nonce, 1);
        assert!(decoded_src_eid == src_eid, 1);
        assert!(decoded_token == token, 1);
        assert!(decoded_amount_ld == amount_ld, 1);
        assert!(decoded_sender == sender, 1);
        assert!(decoded_compose_payload == compose_payload, 1);
    }
}
