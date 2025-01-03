module layerzero_views::endpoint_views {
    use endpoint_v2::endpoint;
    use endpoint_v2_common::bytes32;

    // EXECUTABLE STATES
    const STATE_NOT_EXECUTABLE: u8 = 0;
    const STATE_VERIFIED_BUT_NOT_EXECUTABLE: u8 = 1;
    const STATE_EXECUTABLE: u8 = 2;
    const STATE_EXECUTED: u8 = 3;

    #[view]
    public fun initializable(
        src_eid: u32,
        sender: vector<u8>,
        receiver: address,
    ): bool {
        endpoint::initializable(src_eid, sender, receiver)
    }

    #[view]
    /// View function to check if a message is verifiable (can commit_verification on the uln via endpoint.verify())
    public fun verifiable(
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        receiver: address,
        receive_lib: address,
    ): bool {
        if (
            !endpoint::is_valid_receive_library_for_oapp(receiver, src_eid, receive_lib) ||
                !endpoint::verifiable_view(src_eid, sender, nonce, receiver)
        ) {
            return false
        };

        true
    }

    #[view]
    public fun executable(
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        receiver: address,
    ): u8 {
        let sender_bytes32 = bytes32::to_bytes32(sender);
        let has_payload_hash = endpoint::has_payload_hash(
            src_eid,
            sender_bytes32,
            nonce,
            receiver,
        );

        if (!has_payload_hash && nonce <= endpoint::get_lazy_inbound_nonce(receiver, src_eid, sender)) {
            return STATE_EXECUTED
        };

        if (has_payload_hash) {
            let payload_hash = endpoint::payload_hash(
                receiver,
                src_eid,
                sender_bytes32,
                nonce,
            );
            if (
                !bytes32::is_zero(&payload_hash) && nonce <= endpoint::get_inbound_nonce(
                    receiver, src_eid, sender,
                )) {
                return STATE_EXECUTABLE
            };

            if (payload_hash != bytes32::zero_bytes32()) {
                return STATE_VERIFIED_BUT_NOT_EXECUTABLE
            }
        };

        return STATE_NOT_EXECUTABLE
    }
}
