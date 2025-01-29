module layerzero_views::uln_302 {
    use endpoint_v2::endpoint;
    use endpoint_v2_common::bytes32::{Self, Bytes32};
    use endpoint_v2_common::packet_raw;
    use endpoint_v2_common::packet_v1_codec;
    use endpoint_v2_common::universal_config;
    use layerzero_views::endpoint_views;

    // VERIFICATION STATES
    const STATE_VERIFYING: u8 = 0;
    const STATE_VERIFIABLE: u8 = 1;
    const STATE_VERIFIED: u8 = 2;
    const STATE_NOT_INITIALIZABLE: u8 = 3;

    #[view]
    /// View function to check if a message is verifiable (can commit_verification on the uln via endpoint.verify())
    public fun verifiable(
        packet_header_bytes: vector<u8>,
        payload_hash: vector<u8>,
    ): u8 {
        // extract data from packet
        let packet_header = packet_raw::bytes_to_raw_packet(packet_header_bytes);
        let src_eid = packet_v1_codec::get_src_eid(&packet_header);
        let sender = packet_v1_codec::get_sender(&packet_header);
        let nonce = packet_v1_codec::get_nonce(&packet_header);
        let receiver = bytes32::to_address(
            packet_v1_codec::get_receiver(&packet_header)
        );

        packet_v1_codec::assert_receive_header(
            &packet_header,
            universal_config::eid()
        );

        // check endpoint initializable
        if (!endpoint_views::initializable(
            src_eid,
            bytes32::from_bytes32(sender),
            receiver,
        )) {
            return STATE_NOT_INITIALIZABLE
        };

        // check endpoint verifiable
        if (!endpoint_verifiable(
            src_eid,
            sender,
            nonce,
            receiver,
            payload_hash,
        )) {
            return STATE_VERIFIED
        };

        // check uln verifiable
        if (uln_302::msglib::verifiable(packet_header_bytes, payload_hash)) {
            return STATE_VERIFIABLE
        };
        STATE_VERIFYING
    }

    fun endpoint_verifiable(
        src_eid: u32,
        sender: Bytes32,
        nonce: u64,
        receiver: address,
        payload_hash: vector<u8>,
    ): bool {
        let (receive_lib, _) = endpoint_v2::endpoint::get_effective_receive_library(receiver, src_eid);
        let sender_vec = bytes32::from_bytes32(sender);
        // check if commit_verification is possible via endpoint::verify()
        if (!endpoint_views::verifiable(
            src_eid,
            sender_vec,
            nonce,
            receiver,
            receive_lib,
        )) {
            return false
        };

        if (
            endpoint::has_payload_hash_view(
                src_eid,
                bytes32::from_bytes32(sender),
                nonce,
                receiver,
            ) && endpoint_v2::endpoint::get_payload_hash(receiver, src_eid, sender_vec, nonce) ==
                payload_hash) {
            return false
        };
        true
    }
}
