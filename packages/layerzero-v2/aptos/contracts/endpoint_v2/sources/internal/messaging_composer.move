/// The messaging composer is responsible for managing composed messages
module endpoint_v2::messaging_composer {
    use std::event::emit;
    use std::string::String;

    use endpoint_v2::store;
    use endpoint_v2_common::bytes32::{Self, Bytes32, from_bytes32};

    friend endpoint_v2::endpoint;

    #[test_only]
    friend endpoint_v2::messaging_composer_tests;

    // ================================================ Core Functions ================================================

    /// Called by the OApp when receiving a message to trigger the sending of a composed message
    /// This preps the message for delivery by lz_compose
    public(friend) fun send_compose(oapp: address, to: address, index: u16, guid: Bytes32, message: vector<u8>) {
        assert!(!store::has_compose_message_hash(oapp, to, guid, index), ECOMPOSE_ALREADY_SENT);
        let message_hash = bytes32::keccak256(message);
        store::set_compose_message_hash(oapp, to, guid, index, message_hash);
        emit(ComposeSent { from: oapp, to, guid: from_bytes32(guid), index, message });
    }

    /// This clears the composed message from the store
    /// This should be triggered by lz_compose on the OApp, and it confirms that the message was delivered
    public(friend) fun clear_compose(from: address, to: address, guid: Bytes32, index: u16, message: vector<u8>) {
        // Make sure the message hash matches the expected hash
        assert!(store::has_compose_message_hash(from, to, guid, index), ECOMPOSE_NOT_FOUND);
        let expected_hash = store::get_compose_message_hash(from, to, guid, index);
        let actual_hash = bytes32::keccak256(message);
        assert!(expected_hash == actual_hash, ECOMPOSE_ALREADY_CLEARED);

        // Set the message 0xff(*32) to prevent sending the message again
        store::set_compose_message_hash(from, to, guid, index, bytes32::ff_bytes32());
        emit(ComposeDelivered { from, to, guid: from_bytes32(guid), index });
    }

    /// Get the hash of the composed message with the given parameters
    /// NOT SENT: 0x00(*32)
    /// SENT: hash value
    /// RECEIVED / CLEARED: 0xff(*32)
    public(friend) fun get_compose_message_hash(from: address, to: address, guid: Bytes32, index: u16): Bytes32 {
        if (store::has_compose_message_hash(from, to, guid, index)) {
            store::get_compose_message_hash(from, to, guid, index)
        } else {
            bytes32::zero_bytes32()
        }
    }

    /// Emit an event that indicates that the off-chain executor failed to deliver the compose message
    public(friend) fun lz_compose_alert(
        executor: address,
        from: address,
        to: address,
        guid: Bytes32,
        index: u16,
        gas: u64,
        value: u64,
        message: vector<u8>,
        extra_data: vector<u8>,
        reason: String,
    ) {
        emit(LzComposeAlert {
            from, to, executor, guid: from_bytes32(guid), index, gas, value, message, extra_data, reason,
        });
    }

    // ==================================================== Events ====================================================

    #[event]
    struct ComposeSent has copy, drop, store {
        from: address,
        to: address,
        guid: vector<u8>,
        index: u16,
        message: vector<u8>,
    }

    #[event]
    struct ComposeDelivered has copy, drop, store {
        from: address,
        to: address,
        guid: vector<u8>,
        index: u16,
    }

    #[event]
    struct LzComposeAlert has copy, drop, store {
        from: address,
        to: address,
        executor: address,
        guid: vector<u8>,
        index: u16,
        gas: u64,
        value: u64,
        message: vector<u8>,
        extra_data: vector<u8>,
        reason: String,
    }

    #[test_only]
    public fun compose_sent_event(
        from: address,
        to: address,
        guid: vector<u8>,
        index: u16,
        message: vector<u8>,
    ): ComposeSent {
        ComposeSent { from, to, guid, index, message }
    }

    #[test_only]
    public fun compose_delivered_event(from: address, to: address, guid: vector<u8>, index: u16): ComposeDelivered {
        ComposeDelivered { from, to, guid, index }
    }

    #[test_only]
    public fun lz_compose_alert_event(
        from: address,
        to: address,
        executor: address,
        guid: vector<u8>,
        index: u16,
        gas: u64,
        value: u64,
        message: vector<u8>,
        extra_data: vector<u8>,
        reason: String,
    ): LzComposeAlert {
        LzComposeAlert { from, to, executor, guid, index, gas, value, message, extra_data, reason }
    }

    // ================================================== Error Codes =================================================

    const ECOMPOSE_ALREADY_CLEARED: u64 = 1;
    const ECOMPOSE_ALREADY_SENT: u64 = 2;
    const ECOMPOSE_NOT_FOUND: u64 = 3;
}

