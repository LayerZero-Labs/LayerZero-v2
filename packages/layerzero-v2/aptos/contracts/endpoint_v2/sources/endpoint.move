/// Primary entrypoint for all OApps to interact with the LayerZero protocol
module endpoint_v2::endpoint {
    use std::fungible_asset::FungibleAsset;
    use std::option::Option;
    use std::signer::address_of;
    use std::string::String;

    use endpoint_v2::channels;
    use endpoint_v2::messaging_composer;
    use endpoint_v2::messaging_receipt::MessagingReceipt;
    use endpoint_v2::msglib_manager;
    use endpoint_v2::registration;
    use endpoint_v2::store;
    use endpoint_v2::timeout::Timeout;
    use endpoint_v2_common::bytes32::{Self, Bytes32, from_bytes32};
    use endpoint_v2_common::contract_identity::{CallRef, get_call_ref_caller};
    use endpoint_v2_common::packet_raw;
    use endpoint_v2_common::packet_v1_codec::compute_payload;

    #[test_only]
    friend endpoint_v2::endpoint_tests;

    // ============================================== OApp Administration =============================================

    struct EndpointOAppConfigTarget {}

    /// Initialize the OApp while registering the lz_receive module name
    ///
    /// The lz_receive module selection is permanent and cannot be changed
    /// When delivering a message, the offchain entity will call `<oapp_address>::<lz_receive_module>::lz_receive()`
    public fun register_oapp(oapp: &signer, lz_receive_module: String) {
        let oapp_address = address_of(move oapp);
        registration::register_oapp(oapp_address, lz_receive_module);
    }

    /// Registers the Composer with the lz_compose function
    ///
    /// This function must be called before the Composer can start to receive composer messages
    /// The lz_compose module selection is permanent and cannot be changed
    public fun register_composer(composer: &signer, lz_compose_module: String) {
        let composer_address = address_of(move composer);
        registration::register_composer(composer_address, lz_compose_module);
    }

    /// Register a Receive pathway for the given remote EID
    ///
    /// This function must be called before any message can be verified
    /// After a message is verified, the lz_receive() function call is permissionless; therefore, this provides
    /// important protection against the verification of messages from an EID, whose security configuration has not been
    /// accepted by the OApp.
    ///
    /// Once a pathway is registered, receives can happen under either the default configuration or the configuration
    /// provided by the OApp.
    public fun register_receive_pathway(call_ref: &CallRef<EndpointOAppConfigTarget>, src_eid: u32, sender: Bytes32) {
        let oapp = get_oapp_caller(call_ref);
        channels::register_receive_pathway(oapp, src_eid, sender)
    }

    /// Set the send library for a given EID
    ///
    /// Setting to a @0x0 msglib address will unset the send library and cause the OApp to use the default instead
    public fun set_send_library(call_ref: &CallRef<EndpointOAppConfigTarget>, remote_eid: u32, msglib: address) {
        let oapp = get_oapp_caller(call_ref);
        msglib_manager::set_send_library(oapp, remote_eid, msglib);
    }

    /// Set the receiving message library for the given remote EID
    ///
    /// Setting to a @0x0 msglib address will unset the receive library and cause the OApp to use the default instead
    /// The `grace_period` is the maximum number of blocks that the OApp will continue to accept a message from the
    /// prior receive library.
    ///
    /// A grace period cannot be set when switching to or from the unset / default setting.
    ///
    /// To emulate a grace period when switching from default, first set the receive library explicitly to the default
    /// with no grace period, then set to the desired new library with a grace period.
    /// To emulate a grace period when switching to default, first set the receive library explicitly to the default
    /// library address with a grace period, then when the grace period expires, unset the receive library (set to @0x0)
    /// without a grace period
    public fun set_receive_library(
        call_ref: &CallRef<EndpointOAppConfigTarget>,
        remote_eid: u32,
        msglib: address,
        grace_period: u64,
    ) {
        let oapp = get_oapp_caller(call_ref);
        msglib_manager::set_receive_library(oapp, remote_eid, msglib, grace_period);
    }

    /// Update the timeout settings for the receive library
    ///
    /// The `expiry` is the block number at which the OApp will no longer confirm message using the provided
    /// fallback receive library.
    ///
    /// The timeout cannot be set to fall back to the default receive library (@0x0) or when the current receive library
    /// is unset (uses the default). This will also revert if the expiry is not set to a future block number.
    public fun set_receive_library_timeout(
        call_ref: &CallRef<EndpointOAppConfigTarget>,
        remote_eid: u32,
        msglib: address,
        expiry: u64,
    ) {
        let oapp = get_oapp_caller(call_ref);
        msglib_manager::set_receive_library_timeout(oapp, remote_eid, msglib, expiry);
    }

    /// Set the serialized message Library configuration using the serialized format for a specific message library
    public fun set_config(
        call_ref: &CallRef<EndpointOAppConfigTarget>,
        msglib: address,
        config_type: u32,
        config: vector<u8>,
    ) {
        let oapp = get_oapp_caller(call_ref);
        msglib_manager::set_config(oapp, msglib, config_type, config);
    }

    // ==================================================== Sending ===================================================

    struct EndpointV2SendingTarget {}

    /// Gets a quote for a message given all the send parameters
    ///
    /// The response is the (Native fee, ZRO fee). If `pay_in_zro` is true, than whatever portion of the fee that
    /// can be paid in ZRO wil be returned as the ZRO fee, and the remaining portion will be returned as the Native fee.
    /// If `pay_in_zro` is false, the entire fee will be returned as the Native fee, and 0 will be returned as the ZRO
    /// fee.
    public fun quote(
        sender: address,
        dst_eid: u32,
        receiver: Bytes32,
        message: vector<u8>,
        options: vector<u8>,
        pay_in_zro: bool,
    ): (u64, u64) {
        channels::quote(sender, dst_eid, receiver, message, options, pay_in_zro)
    }

    #[view]
    /// View function to get a quote for a message given all the send parameters
    public fun quote_view(
        sender: address,
        dst_eid: u32,
        receiver: vector<u8>,
        message: vector<u8>,
        options: vector<u8>,
        pay_in_zro: bool,
    ): (u64, u64) {
        channels::quote(sender, dst_eid, bytes32::to_bytes32(receiver), message, options, pay_in_zro)
    }

    /// Send a message through the LayerZero protocol
    ///
    /// This will be passed to the Message Library to calculate the fee of the message and emit messages that trigger
    /// offchain entities to deliver and verify the message. If `zro_token` is not option::none, whatever component of
    /// the fee that can be paid in ZRO will be paid in ZRO.
    /// If the amounts provided are insuffient, the transaction will revert
    public fun send(
        call_ref: &CallRef<EndpointV2SendingTarget>,
        dst_eid: u32,
        receiver: Bytes32,
        message: vector<u8>,
        options: vector<u8>,
        native_token: &mut FungibleAsset,
        zro_token: &mut Option<FungibleAsset>,
    ): MessagingReceipt {
        let sender = get_oapp_caller(call_ref);
        channels::send(
            sender,
            dst_eid,
            receiver,
            message,
            options,
            native_token,
            zro_token,
        )
    }

    // ============================================= Clearing "Hot Potato" ============================================

    /// Non-droppable guid that requires a call to `clear()` or `clear_compose()` to delete
    struct WrappedGuid { guid: Bytes32 }

    struct WrappedGuidAndIndex { guid: Bytes32, index: u16 }

    /// Wrap a guid (lz_receive), so that it can only be unwrapped (and disposed of) by the endpoint
    public fun wrap_guid(guid: Bytes32): WrappedGuid { WrappedGuid { guid } }

    /// Wrap a guid and index (lz_compose), so that it can only be unwrapped (and disposed of) by the endpoint
    public fun wrap_guid_and_index(guid: Bytes32, index: u16): WrappedGuidAndIndex {
        WrappedGuidAndIndex { guid, index }
    }

    /// Get the guid from a WrappedGuid without destorying the WrappedGuid
    public fun get_guid_from_wrapped(wrapped: &WrappedGuid): Bytes32 { wrapped.guid }

    /// Get the guid and index from a WrappedGuidAndIndex without destorying the WrappedGuidAndIndex
    public fun get_guid_and_index_from_wrapped(wrapped: &WrappedGuidAndIndex): (Bytes32, u16) {
        (wrapped.guid, wrapped.index)
    }

    /// Endpoint-only call to destroy a WrappedGuid and provide its value; only called by `clear()`
    fun unwrap_guid(wrapped_guid: WrappedGuid): Bytes32 {
        let WrappedGuid { guid } = wrapped_guid;
        guid
    }

    /// Endpoint-only call to destroy a WrappedGuidAndIndex and provide its values; only called by `clear_compose()`
    fun unwrap_guid_and_index(wrapped_guid_and_index: WrappedGuidAndIndex): (Bytes32, u16) {
        let WrappedGuidAndIndex { guid, index } = wrapped_guid_and_index;
        (guid, index)
    }

    // ==================================================== Receiving =================================================

    struct EndpointV2ReceivingTarget {}

    /// Validate and Clear a message received through the LZ Receive protocol
    ///
    /// This should be called by the lz_receive function on the OApp.
    /// In this "pull model", the off-chain entity will call the OApp's lz_receive function. The lz_receive function
    /// must call `clear()` to validate and clear the message. If `clear()` is not called, lz_receive may receive
    /// messages but will not be able to ensure the validity of the messages.
    public fun clear(
        call_ref: &CallRef<EndpointV2ReceivingTarget>,
        src_eid: u32,
        sender: Bytes32,
        nonce: u64,
        guid: WrappedGuid,
        message: vector<u8>,
    ) {
        let oapp = get_oapp_caller(call_ref);
        channels::clear_payload(
            oapp,
            src_eid,
            sender,
            nonce,
            compute_payload(unwrap_guid(guid), message)
        );
    }

    /// Function to alert that the lz_receive function has reverted
    ///
    /// This may be used to create a record that the offchain entity has made an unsuccessful attempt to deliver a
    /// message.
    public entry fun lz_receive_alert(
        executor: &signer,
        receiver: address,
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        guid: vector<u8>,
        gas: u64,
        value: u64,
        message: vector<u8>,
        extra_data: vector<u8>,
        reason: String,
    ) {
        channels::lz_receive_alert(
            receiver,
            address_of(executor),
            src_eid,
            bytes32::to_bytes32(sender),
            nonce,
            bytes32::to_bytes32(guid),
            gas,
            value,
            message,
            extra_data,
            reason,
        );
    }

    /// This prevents verification of the next message in the sequence. An example use case is to skip
    /// a message when precrime throws an alert. The nonce must be provided to avoid the possibility of skipping the
    /// unintended nonce.
    public fun skip(
        call_ref: &CallRef<EndpointV2ReceivingTarget>,
        src_eid: u32,
        sender: Bytes32,
        nonce: u64,
    ) {
        let oapp = get_oapp_caller(call_ref);
        channels::skip(oapp, src_eid, sender, nonce);
    }

    /// This prevents delivery and any possible reverification of an already verified message
    public fun burn(
        call_ref: &CallRef<EndpointV2ReceivingTarget>,
        src_eid: u32,
        sender: Bytes32,
        nonce: u64,
        payload_hash: Bytes32,
    ) {
        let oapp = get_oapp_caller(call_ref);
        channels::burn(oapp, src_eid, sender, nonce, payload_hash);
    }

    // This maintains a packet's status as verified but prevents delivery until the packet is verified again
    public fun nilify(
        call_ref: &CallRef<EndpointV2ReceivingTarget>,
        src_eid: u32,
        sender: Bytes32,
        nonce: u64,
        payload_hash: Bytes32,
    ) {
        let oapp = get_oapp_caller(call_ref);
        channels::nilify(oapp, src_eid, sender, nonce, payload_hash);
    }


    // ==================================================== Compose ===================================================

    struct EndpointV2SendComposeTarget {}

    struct EndpointV2ComposerTarget {}

    /// Initiates a compose message
    ///
    /// This should be called by the lz_receive function on the OApp when it receives a message that indicates that
    /// a compose is required. The composer will then call the target Composer's lz_compose with the message function to
    /// complete the compose
    public fun send_compose(
        call_ref: &CallRef<EndpointV2SendComposeTarget>,
        to: address,
        index: u16,
        guid: Bytes32,
        message: vector<u8>,
    ) {
        let oapp = get_oapp_caller(call_ref);
        messaging_composer::send_compose(oapp, to, index, guid, message);
    }

    /// Internal function to get the address of the OApp caller, and assert that the caller is a registered OApp and
    /// the endpoint is the intended recipient
    public(friend) fun get_oapp_caller<Target>(call_ref: &CallRef<Target>): address {
        let caller = get_call_ref_caller(call_ref);
        assert!(registration::is_registered_oapp(caller), EUNREGISTERED);
        caller
    }

    // =================================================== Composer ===================================================

    /// Function to clear the compose message
    /// This should be called from the Composer's lz_compose function. This will both check the validity of the message
    /// and clear the message from the Composer's compose queue. If this is not called, the Composer will not be able to
    /// ensure the validity of received messages
    public fun clear_compose(
        call_ref: &CallRef<EndpointV2ComposerTarget>,
        from: address,
        guid_and_index: WrappedGuidAndIndex,
        message: vector<u8>,
    ) {
        let composer = get_compose_caller(call_ref);
        let (guid, index) = unwrap_guid_and_index(guid_and_index);
        messaging_composer::clear_compose(from, composer, guid, index, message);
    }

    /// Function to alert that the lz_compose function has reverted
    ///
    /// This may be used to create a record that the offchain composer has made an unsuccessful attempt to deliver a
    /// compose message
    public entry fun lz_compose_alert(
        executor: &signer,
        from: address,
        to: address,
        guid: vector<u8>,
        index: u16,
        gas: u64,
        value: u64,
        message: vector<u8>,
        extra_data: vector<u8>,
        reason: String,
    ) {
        messaging_composer::lz_compose_alert(
            address_of(move executor),
            from,
            to,
            bytes32::to_bytes32(guid),
            index,
            gas,
            value,
            message,
            extra_data,
            reason,
        );
    }

    /// Internal function to get the address of the Composer caller, and assert that the caller is a registered Composer
    /// and that the endpoint is the intended recipient
    public(friend) fun get_compose_caller<Target>(call_ref: &CallRef<Target>): address {
        let caller = get_call_ref_caller(call_ref);
        assert!(registration::is_registered_composer(caller), EUNREGISTERED);
        caller
    }

    // ================================================= Verification =================================================


    /// This verifies a message by storing the payload hash on the receive channel
    ///
    /// Once a message has been verified, it can be permissionlessly delivered. This will revert if the message library
    /// has not committed the verification.
    public entry fun verify(
        receive_lib: address,
        packet_header: vector<u8>,
        payload_hash: vector<u8>,
    ) {
        let packet_header = packet_raw::bytes_to_raw_packet(packet_header);
        channels::verify(receive_lib, packet_header, bytes32::to_bytes32(payload_hash));
    }

    /// Confirms that a message has been verified by the message library, and is ready to be verified (confirmed) on the
    /// endpoint.
    ///
    /// This can be called prior to calling `verify` to ensure that the message is ready to be verified.
    /// This is also exposed as a view function below called `verifiable_view()`
    public fun verifiable(
        src_eid: u32,
        sender: Bytes32,
        nonce: u64,
        receiver: address,
    ): bool {
        channels::verifiable(receiver, src_eid, sender, nonce)
    }

    /// Confirms that a message has a payload hash (has been verified).
    ///
    /// This generally suggests that the message can be delievered, with the exeption of the case where the message has
    /// been nilified
    public fun has_payload_hash(
        src_eid: u32,
        sender: Bytes32,
        nonce: u64,
        receiver: address,
    ): bool {
        channels::has_payload_hash(receiver, src_eid, sender, nonce)
    }

    /// Gets the payload hash for a given message
    public fun payload_hash(receiver: address, src_eid: u32, sender: Bytes32, nonce: u64): Bytes32 {
        channels::get_payload_hash(receiver, src_eid, sender, nonce)
    }

    // ===================================================== View =====================================================

    // Get the serialized message Library configuration using the serialized format for a specific message library
    #[view]
    public fun get_config(oapp: address, msglib: address, eid: u32, config_type: u32): vector<u8> {
        msglib_manager::get_config(oapp, msglib, eid, config_type)
    }

    #[view]
    public fun get_quote(
        sender: address,
        dst_eid: u32,
        receiver: vector<u8>,
        message: vector<u8>,
        options: vector<u8>,
        pay_in_zro: bool,
    ): (u64, u64) {
        quote(sender, dst_eid, bytes32::to_bytes32(receiver), message, options, pay_in_zro)
    }

    #[view]
    public fun get_payload_hash(receiver: address, src_eid: u32, sender: vector<u8>, nonce: u64): vector<u8> {
        from_bytes32(payload_hash(receiver, src_eid, bytes32::to_bytes32(sender), nonce))
    }

    #[view]
    /// This is called by offchain entities to know what function to call on the OApp for lz_receive
    public fun get_lz_receive_module(oapp: address): String {
        registration::lz_receive_module(oapp)
    }

    #[view]
    /// This is called by offchain entities to know what function to call on the Composer for lz_compose
    public fun get_lz_compose_module(composer: address): String {
        registration::lz_compose_module(composer)
    }

    #[view]
    /// Gets the effective receive library for the given source EID, returns both the library and a flag indicating if
    /// this is a fallback to the default (meaning the library is not configured for the oapp)
    public fun get_effective_receive_library(oapp_address: address, src_eid: u32): (address, bool) {
        msglib_manager::get_effective_receive_library(oapp_address, src_eid)
    }

    #[view]
    public fun get_effective_send_library(oapp_address: address, dst_eid: u32): (address, bool) {
        msglib_manager::get_effective_send_library(oapp_address, dst_eid)
    }

    #[view]
    public fun get_outbound_nonce(sender: address, dst_eid: u32, receiver: vector<u8>): u64 {
        channels::outbound_nonce(sender, dst_eid, bytes32::to_bytes32(receiver))
    }

    #[view]
    public fun get_lazy_inbound_nonce(receiver: address, src_eid: u32, sender: vector<u8>): u64 {
        channels::lazy_inbound_nonce(receiver, src_eid, bytes32::to_bytes32(sender))
    }

    #[view]
    public fun get_inbound_nonce(receiver: address, src_eid: u32, sender: vector<u8>): u64 {
        channels::inbound_nonce(receiver, src_eid, bytes32::to_bytes32(sender))
    }

    #[view]
    public fun is_registered_msglib(msglib: address): bool {
        msglib_manager::is_registered_library(msglib)
    }

    #[view]
    public fun is_valid_receive_library_for_oapp(oapp: address, src_eid: u32, msglib: address): bool {
        msglib_manager::is_valid_receive_library_for_oapp(oapp, src_eid, msglib)
    }

    #[view]
    public fun has_payload_hash_view(src_eid: u32, sender: vector<u8>, nonce: u64, receiver: address): bool {
        has_payload_hash(src_eid, bytes32::to_bytes32(sender), nonce, receiver)
    }

    #[view]
    /// Get the hash of the composed message with the given parameters with the following special case values:
    /// NOT SENT: 0x00(*32)
    /// SENT: hash value
    /// RECEIVED / CLEARED: 0xff(*32)
    public fun get_compose_message_hash(from: address, to: address, guid: vector<u8>, index: u16): vector<u8> {
        from_bytes32(
            messaging_composer::get_compose_message_hash(from, to, bytes32::to_bytes32(guid), index)
        )
    }

    #[view]
    public fun get_next_guid(oapp: address, dst_eid: u32, receiver: vector<u8>): vector<u8> {
        from_bytes32(channels::next_guid(oapp, dst_eid, bytes32::to_bytes32(receiver)))
    }

    #[view]
    public fun initializable(src_eid: u32, sender: vector<u8>, receiver: address): bool {
        channels::receive_pathway_registered(receiver, src_eid, bytes32::to_bytes32(sender))
    }

    #[view]
    public fun verifiable_view(
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
        receiver: address,
    ): bool {
        verifiable(src_eid, bytes32::to_bytes32(sender), nonce, receiver)
    }

    #[view]
    /// Get the default send library for the given destination EID
    public fun get_default_send_lib(remote_eid: u32): address {
        msglib_manager::get_default_send_library(remote_eid)
    }

    #[view]
    /// Get the default receive library for the given source EID
    public fun get_default_receive_lib(remote_eid: u32): address {
        msglib_manager::get_default_receive_library(remote_eid)
    }

    #[view]
    public fun get_registered_libraries(start_index: u64, max_entries: u64): vector<address> {
        msglib_manager::get_registered_libraries(start_index, max_entries)
    }

    #[view]
    public fun get_receive_library_timeout(oapp: address, remote_eid: u32): Timeout {
        store::get_receive_library_timeout(oapp, remote_eid)
    }

    #[view]
    public fun get_default_receive_library_timeout(remote_eid: u32): Timeout {
        store::get_default_receive_library_timeout(remote_eid)
    }

    // ================================================== Error Codes =================================================

    const EUNREGISTERED: u64 = 1;
}
