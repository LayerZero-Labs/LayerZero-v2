module endpoint_v2::channels {
    use std::event::emit;
    use std::fungible_asset::{Self, FungibleAsset, Metadata};
    use std::object::{address_to_object, Object};
    use std::option::{Self, Option};
    use std::string::String;

    use endpoint_v2::messaging_receipt::{Self, MessagingReceipt};
    use endpoint_v2::msglib_manager;
    use endpoint_v2::store;
    use endpoint_v2_common::bytes32::{Self, Bytes32, from_bytes32, to_bytes32};
    use endpoint_v2_common::guid::compute_guid;
    use endpoint_v2_common::packet_raw::{get_packet_bytes, RawPacket};
    use endpoint_v2_common::send_packet;
    use endpoint_v2_common::send_packet::{new_send_packet, SendPacket};
    use endpoint_v2_common::universal_config;
    use router_node_0::router_node as msglib_router;

    friend endpoint_v2::endpoint;

    #[test_only]
    friend endpoint_v2::channels_tests;

    const NIL_PAYLOAD_HASH: vector<u8> = x"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    const EMPTY_PAYLOAD_HASH: vector<u8> = x"0000000000000000000000000000000000000000000000000000000000000000";

    // ==================================================== Helpers ===================================================

    inline fun is_native_token(native_metadata: Object<Metadata>): bool {
        native_metadata == address_to_object<Metadata>(@native_token_metadata_address)
    }

    // ==================================================== Sending ===================================================

    /// Generate the next GUID for the given destination EID
    public(friend) fun next_guid(sender: address, dst_eid: u32, receiver: Bytes32): Bytes32 {
        let next_nonce = store::outbound_nonce(sender, dst_eid, receiver) + 1;
        compute_guid(next_nonce, universal_config::eid(), bytes32::from_address(sender), dst_eid, receiver)
    }

    public(friend) fun outbound_nonce(sender: address, dst_eid: u32, receiver: Bytes32): u64 {
        store::outbound_nonce(sender, dst_eid, receiver)
    }

    /// Send a message to the given destination EID
    public(friend) fun send(
        sender: address,
        dst_eid: u32,
        receiver: Bytes32,
        message: vector<u8>,
        options: vector<u8>,
        native_token: &mut FungibleAsset,
        zro_token: &mut Option<FungibleAsset>,
    ): MessagingReceipt {
        send_internal(
            sender,
            dst_eid,
            receiver,
            message,
            options,
            native_token,
            zro_token,
            // Message Library Router Send Function
            |send_lib, send_packet| msglib_router::send(
                send_lib,
                &store::make_dynamic_call_ref(send_lib, b"send"),
                send_packet,
                options,
                native_token,
                zro_token,
            ),
        )
    }

    /// This send function receives the send message library call as a lambda function
    ///
    /// @param sender: The address of the sender
    /// @param dst_eid: The destination EID
    /// @param receiver: The receiver's address
    /// @param message: The message to be sent
    /// @param options: The options to be sent with the message
    /// @param native_token: The native token to be sent with the message
    /// @param zro_token: The optional ZRO token to be sent with the message
    /// @param msglib_send: The lambda function that calls the send library
    ///        |send_lib, send_packet| (native_fee, zro_fee, encoded_packet): The lambda function that calls the send
    ///                                                                       library
    public(friend) inline fun send_internal(
        sender: address,
        dst_eid: u32,
        receiver: Bytes32,
        message: vector<u8>,
        options: vector<u8>,
        native_token: &mut FungibleAsset,
        zro_token: &mut Option<FungibleAsset>,
        msglib_send: |address, SendPacket| (u64, u64, RawPacket),
    ): MessagingReceipt {
        let (send_lib, _) = msglib_manager::get_effective_send_library(sender, dst_eid);

        // increment the outbound nonce and get the next nonce
        let nonce = store::increment_outbound_nonce(sender, dst_eid, receiver);

        // check token metadatas
        assert!(is_native_token(fungible_asset::asset_metadata(native_token)), err_EUNSUPPORTED_PAYMENT());
        if (option::is_some(zro_token)) {
            assert!(universal_config::is_zro(option::borrow(zro_token)), err_EUNSUPPORTED_PAYMENT());
        };

        let packet = new_send_packet(
            nonce,
            universal_config::eid(),
            bytes32::from_address(sender),
            dst_eid,
            receiver,
            message,
        );
        let guid = send_packet::get_guid(&packet);

        let (native_fee, zro_fee, encoded_packet) = msglib_send(send_lib, packet);
        emit_packet_sent_event(encoded_packet, options, send_lib);

        messaging_receipt::new_messaging_receipt(
            guid,
            nonce,
            native_fee,
            zro_fee,
        )
    }

    /// This function provides the cost of sending a message in native and ZRO tokens (if pay_in_zro = true) without
    /// sending the message
    public(friend) fun quote(
        sender: address,
        dst_eid: u32,
        receiver: Bytes32,
        message: vector<u8>,
        options: vector<u8>,
        pay_in_zro: bool,
    ): (u64, u64) {
        quote_internal(
            sender,
            dst_eid,
            receiver,
            message,
            // Message Library Router Quote Function
            |send_lib, send_packet| msglib_router::quote(
                send_lib,
                send_packet,
                options,
                pay_in_zro,
            ),
        )
    }

    /// This is the internal portion of the quote function with the message library call provided as a lambda function
    ///
    /// @param sender: The address of the sender
    /// @param dst_eid: The destination EID
    /// @param receiver: The receiver's address
    /// @param message: The message to be sent
    /// @param msglib_quote: The lambda function that calls the send library's quote function
    ///        |send_lib, send_packet| (native_fee, zro_fee)
    public(friend) inline fun quote_internal(
        sender: address,
        dst_eid: u32,
        receiver: Bytes32,
        message: vector<u8>,
        msglib_quote: |address, SendPacket| (u64, u64)
    ): (u64, u64) {
        let nonce = store::outbound_nonce(sender, dst_eid, receiver) + 1;
        let (send_lib, _) = msglib_manager::get_effective_send_library(sender, dst_eid);
        let packet = new_send_packet(
            nonce,
            universal_config::eid(),
            bytes32::from_address(sender),
            dst_eid,
            receiver,
            message,
        );
        msglib_quote(send_lib, packet)
    }

    // =================================================== Receiving ==================================================

    /// Enable verification (committing) of messages from a given src_eid and sender to the receiver OApp
    public(friend) fun register_receive_pathway(receiver: address, src_eid: u32, sender: Bytes32) {
        store::register_receive_pathway(receiver, src_eid, sender);
        emit(ReceivePathwayRegistered { receiver, src_eid, sender: from_bytes32(sender) });
    }

    /// Check if the receive pathway is registered
    public(friend) fun receive_pathway_registered(receiver: address, src_eid: u32, sender: Bytes32): bool {
        store::receive_pathway_registered(receiver, src_eid, sender)
    }

    /// Sets the payload hash for the given nonce
    public(friend) fun inbound(receiver: address, src_eid: u32, sender: Bytes32, nonce: u64, payload_hash: Bytes32) {
        assert!(!bytes32::is_zero(&payload_hash), EEMPTY_PAYLOAD_HASH);
        store::set_payload_hash(receiver, src_eid, sender, nonce, payload_hash);
    }

    // Get the lazy inbound nonce for the given sender
    public(friend) fun lazy_inbound_nonce(receiver: address, src_eid: u32, sender: Bytes32): u64 {
        store::lazy_inbound_nonce(receiver, src_eid, sender)
    }

    /// Returns the max index of the gapless sequence of verfied msg nonces starting at the lazy_inbound_nonce. This is
    /// initially 0, and the first nonce is always 1
    public(friend) fun inbound_nonce(receiver: address, src_eid: u32, sender: Bytes32): u64 {
        let i = store::lazy_inbound_nonce(receiver, src_eid, sender);
        loop {
            i = i + 1;
            if (!store::has_payload_hash(receiver, src_eid, sender, i)) {
                return i - 1
            }
        }
    }

    /// Skip the nonce. The nonce must be the next nonce in the sequence
    public(friend) fun skip(receiver: address, src_eid: u32, sender: Bytes32, nonce_to_skip: u64) {
        assert!(nonce_to_skip == inbound_nonce(receiver, src_eid, sender) + 1, EINVALID_NONCE);
        store::set_lazy_inbound_nonce(receiver, src_eid, sender, nonce_to_skip);
        emit(InboundNonceSkipped { src_eid, sender: from_bytes32(sender), receiver, nonce: nonce_to_skip })
    }

    /// Marks a packet as verified but disables execution until it is re-verified
    /// A non-verified nonce can be nilified by passing EMPTY_PAYLOAD_HASH for payload_hash
    public(friend) fun nilify(receiver: address, src_eid: u32, sender: Bytes32, nonce: u64, payload_hash: Bytes32) {
        let has_payload_hash = store::has_payload_hash(receiver, src_eid, sender, nonce);
        assert!(nonce > store::lazy_inbound_nonce(receiver, src_eid, sender) || has_payload_hash, EINVALID_NONCE);

        let stored_payload_hash = if (has_payload_hash) {
            store::get_payload_hash(receiver, src_eid, sender, nonce)
        } else {
            to_bytes32(EMPTY_PAYLOAD_HASH)
        };

        assert!(payload_hash == stored_payload_hash, EPAYLOAD_HASH_DOES_NOT_MATCH);

        // Set the hash to 0xff*32 to indicate that the packet is nilified
        store::set_payload_hash(receiver, src_eid, sender, nonce, bytes32::to_bytes32(NIL_PAYLOAD_HASH));
        emit(
            PacketNilified {
                src_eid, sender: from_bytes32(sender), receiver, nonce, payload_hash: from_bytes32(payload_hash),
            }
        )
    }

    /// Marks a nonce as unexecutable and unverifiable. The nonce can never be re-verified or executed.
    /// Only packets less than or equal to the current lazy inbound nonce can be burnt.
    public(friend) fun burn(receiver: address, src_eid: u32, sender: Bytes32, nonce: u64, payload_hash: Bytes32) {
        assert!(nonce <= store::lazy_inbound_nonce(receiver, src_eid, sender), EINVALID_NONCE);

        // check that the hash provided matches the stored hash and clear
        let inbound_payload_hash = store::remove_payload_hash(receiver, src_eid, sender, nonce);
        assert!(inbound_payload_hash == payload_hash, EPAYLOAD_HASH_DOES_NOT_MATCH);

        emit(
            PacketBurnt {
                src_eid, sender: from_bytes32(sender), receiver, nonce, payload_hash: from_bytes32(payload_hash),
            }
        )
    }

    /// Clear the stored message and increment the lazy_inbound_nonce to the provided nonce
    /// This is used in the receive pathway as the final step because it validates the hash as well
    /// If a lot of messages are queued, the messages can be cleared with a smaller step size to prevent OOG
    public(friend) fun clear_payload(
        receiver: address,
        src_eid: u32,
        sender: Bytes32,
        nonce: u64,
        payload: vector<u8>,
    ) {
        let current_nonce = store::lazy_inbound_nonce(receiver, src_eid, sender);

        // Make sure that all hashes are present up to the clear-to point, clear them, and update the lazy nonce
        if (nonce > current_nonce) {
            current_nonce = current_nonce + 1;
            while (current_nonce <= nonce) {
                assert!(store::has_payload_hash(receiver, src_eid, sender, current_nonce), ENO_PAYLOAD_HASH);
                current_nonce = current_nonce + 1
            };
            store::set_lazy_inbound_nonce(receiver, src_eid, sender, nonce);
        };

        // Check if the payload hash matches the provided payload
        let actual_hash = bytes32::keccak256(payload);
        assert!(store::has_payload_hash(receiver, src_eid, sender, nonce), ENO_PAYLOAD_HASH);

        // Clear and check the payload hash
        let expected_hash = store::remove_payload_hash(receiver, src_eid, sender, nonce);
        assert!(actual_hash == expected_hash, EPAYLOAD_HASH_DOES_NOT_MATCH);

        emit(PacketDelivered { src_eid, sender: from_bytes32(sender), nonce, receiver });
    }

    /// Checks if the payload hash exists for the given nonce
    public(friend) fun has_payload_hash(receiver: address, src_eid: u32, sender: Bytes32, nonce: u64): bool {
        store::has_payload_hash(receiver, src_eid, sender, nonce)
    }

    /// Get the payload hash for a given nonce
    public(friend) fun get_payload_hash(receiver: address, src_eid: u32, sender: Bytes32, nonce: u64): Bytes32 {
        store::get_payload_hash(receiver, src_eid, sender, nonce)
    }

    /// Check if a message is verifiable (committable)
    public(friend) fun verifiable(receiver: address, src_eid: u32, sender: Bytes32, nonce: u64): bool {
        if (!store::receive_pathway_registered(receiver, src_eid, sender)) {
            return false
        };
        let lazy_inbound_nonce = store::lazy_inbound_nonce(receiver, src_eid, sender);
        nonce > lazy_inbound_nonce || has_payload_hash(receiver, src_eid, sender, nonce)
    }

    /// Verify (commit) a message
    public(friend) fun verify(
        receive_lib: address,
        packet_header: RawPacket,
        payload_hash: Bytes32,
        extra_data: vector<u8>,
    ) {
        let call_ref = &store::make_dynamic_call_ref(receive_lib, b"commit_verification");
        let (receiver, src_eid, sender, nonce) = msglib_router::commit_verification(
            receive_lib,
            call_ref,
            packet_header,
            payload_hash,
            extra_data,
        );

        verify_internal(
            receive_lib,
            payload_hash,
            receiver,
            src_eid,
            sender,
            nonce,
        );
    }

    /// This function is the internal portion of verifying a message. This receives the decoded packet header
    /// information (that verify() gets from the message library) as an input
    ///
    /// @param receive_lib: The address of the receive library
    /// @param packet_header: The packet header
    /// @param payload_hash: The hash of the payload
    /// @params receiver: The address of the receiver
    /// @params src_eid: The source EID
    /// @params sender: The sender's address
    /// @params nonce: The nonce of the message
    public(friend) inline fun verify_internal(
        receive_lib: address,
        payload_hash: Bytes32,
        receiver: address,
        src_eid: u32,
        sender: Bytes32,
        nonce: u64,
    ) {
        // This is the same assertion as initializable() in EVM
        store::assert_receive_pathway_registered(
            receiver,
            src_eid,
            sender,
        );
        assert!(
            msglib_manager::is_valid_receive_library_for_oapp(receiver, src_eid, receive_lib),
            err_EINVALID_MSGLIB()
        );
        assert!(verifiable(receiver, src_eid, sender, nonce), err_ENOT_VERIFIABLE());

        // insert the message into the messaging channel
        inbound(receiver, src_eid, sender, nonce, payload_hash);
        emit_packet_verified_event(src_eid, from_bytes32(sender), nonce, receiver, from_bytes32(payload_hash));
    }


    /// Send an alert if lz_receive reverts
    public(friend) fun lz_receive_alert(
        receiver: address,
        executor: address,
        src_eid: u32,
        sender: Bytes32,
        nonce: u64,
        guid: Bytes32,
        gas: u64,
        value: u64,
        message: vector<u8>,
        extra_data: vector<u8>,
        reason: String,
    ) {
        emit(LzReceiveAlert {
            receiver,
            executor,
            src_eid,
            sender: from_bytes32(sender),
            nonce,
            guid: from_bytes32(guid),
            gas,
            value,
            message,
            extra_data,
            reason,
        });
    }

    // ==================================================== Events ====================================================

    #[event]
    struct ReceivePathwayRegistered has store, drop {
        receiver: address,
        src_eid: u32,
        sender: vector<u8>,
    }

    #[event]
    struct PacketBurnt has store, drop {
        src_eid: u32,
        sender: vector<u8>,
        receiver: address,
        nonce: u64,
        payload_hash: vector<u8>,
    }

    #[event]
    struct PacketNilified has store, drop {
        src_eid: u32,
        sender: vector<u8>,
        receiver: address,
        nonce: u64,
        payload_hash: vector<u8>,
    }

    #[event]
    struct InboundNonceSkipped has store, drop {
        src_eid: u32,
        sender: vector<u8>,
        receiver: address,
        nonce: u64,
    }

    #[event]
    struct PacketDelivered has drop, store {
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        receiver: address,
    }

    #[event]
    struct PacketSent has drop, store {
        encoded_packet: vector<u8>,
        options: vector<u8>,
        send_library: address,
    }

    #[event]
    struct PacketVerified has drop, store {
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        receiver: address,
        payload_hash: vector<u8>,
    }


    #[event]
    struct LzReceiveAlert has drop, store {
        receiver: address,
        executor: address,
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        guid: vector<u8>,
        gas: u64,
        value: u64,
        message: vector<u8>,
        extra_data: vector<u8>,
        reason: String,
    }

    // These 2 emit_ functions are needed so that inline functions can still emit when called from the test module

    public(friend) fun emit_packet_sent_event(encoded_packet: RawPacket, options: vector<u8>, send_library: address) {
        emit(PacketSent { encoded_packet: get_packet_bytes(encoded_packet), options, send_library });
    }

    public(friend) fun emit_packet_verified_event(
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        receiver: address,
        payload_hash: vector<u8>,
    ) {
        emit(PacketVerified { src_eid, sender, nonce, receiver, payload_hash });
    }

    #[test_only]
    public fun receive_pathway_registered_event(
        receiver: address,
        src_eid: u32,
        sender: vector<u8>,
    ): ReceivePathwayRegistered {
        ReceivePathwayRegistered { receiver, src_eid, sender }
    }

    #[test_only]
    public fun packet_burnt_event(
        src_eid: u32,
        sender: vector<u8>,
        receiver: address,
        nonce: u64,
        payload_hash: vector<u8>,
    ): PacketBurnt {
        PacketBurnt { src_eid, sender, receiver, nonce, payload_hash }
    }

    #[test_only]
    public fun packet_nilified_event(
        src_eid: u32,
        sender: vector<u8>,
        receiver: address,
        nonce: u64,
        payload_hash: vector<u8>,
    ): PacketNilified {
        PacketNilified { src_eid, sender, receiver, nonce, payload_hash }
    }

    #[test_only]
    public fun inbound_nonce_skipped_event(
        src_eid: u32,
        sender: vector<u8>,
        receiver: address,
        nonce: u64,
    ): InboundNonceSkipped {
        InboundNonceSkipped { src_eid, sender, receiver, nonce }
    }

    #[test_only]
    public fun packet_delivered_event(
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        receiver: address,
    ): PacketDelivered {
        PacketDelivered { src_eid, sender, nonce, receiver }
    }

    #[test_only]
    public fun packet_sent_event(encoded_packet: RawPacket, options: vector<u8>, send_library: address): PacketSent {
        PacketSent { encoded_packet: get_packet_bytes(encoded_packet), options, send_library }
    }

    #[test_only]
    public fun packet_verified_event(
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        receiver: address,
        payload_hash: vector<u8>,
    ): PacketVerified {
        PacketVerified { src_eid, sender, nonce, receiver, payload_hash }
    }

    #[test_only]
    public fun lz_receive_alert_event(
        receiver: address,
        executor: address,
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        guid: vector<u8>,
        gas: u64,
        value: u64,
        message: vector<u8>,
        extra_data: vector<u8>,
        reason: String,
    ): LzReceiveAlert {
        LzReceiveAlert {
            receiver,
            executor,
            src_eid,
            sender,
            nonce,
            guid,
            gas,
            value,
            message,
            extra_data,
            reason,
        }
    }

    // ================================================== Error Codes =================================================

    const EEMPTY_PAYLOAD_HASH: u64 = 1;
    const EINVALID_MSGLIB: u64 = 2;
    const EINVALID_NONCE: u64 = 3;
    const ENOT_VERIFIABLE: u64 = 4;
    const ENO_PAYLOAD_HASH: u64 = 5;
    const EPAYLOAD_HASH_DOES_NOT_MATCH: u64 = 6;
    const EUNSUPPORTED_PAYMENT: u64 = 7;

    // These wrapper error functions are needed to support testing inline functions in a different testing module
    public(friend) fun err_EUNSUPPORTED_PAYMENT(): u64 { EUNSUPPORTED_PAYMENT }

    public(friend) fun err_EINVALID_MSGLIB(): u64 { EINVALID_MSGLIB }

    public(friend) fun err_ENOT_VERIFIABLE(): u64 { ENOT_VERIFIABLE }
}