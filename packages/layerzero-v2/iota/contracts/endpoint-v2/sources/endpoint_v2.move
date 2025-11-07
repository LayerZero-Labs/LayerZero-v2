/// The LayerZero V2 Endpoint is the core infrastructure that enables omnichain applications (OApps)
/// to send and receive messages across different blockchains. This endpoint acts as the entry point
/// for cross-chain communication within the LayerZero ecosystem.
module endpoint_v2::endpoint_v2;

use call::{call::{Self, Call, Void}, call_cap::{Self, CallCap}};
use endpoint_v2::{
    endpoint_quote::QuoteParam as EndpointQuoteParam,
    endpoint_send::SendParam as EndpointSendParam,
    lz_compose::{Self, LzComposeParam},
    lz_receive::{Self, LzReceiveParam},
    message_lib_manager::{Self, MessageLibManager},
    message_lib_quote::QuoteParam as MessageLibQuoteParam,
    message_lib_send::{SendParam as MessageLibSendParam, SendResult as MessageLibSendResult},
    message_lib_set_config::SetConfigParam as MessageLibSetConfigParam,
    message_lib_type::MessageLibType,
    messaging_channel::{Self, MessagingChannel},
    messaging_composer::{Self, ComposeQueue, ComposerRegistry},
    messaging_fee::MessagingFee,
    messaging_receipt::MessagingReceipt,
    oapp_registry::{Self, OAppRegistry},
    timeout::Timeout,
    utils
};
use std::ascii::String;
use iota::{clock::Clock, coin::Coin, iota::IOTA};
use utils::bytes32::Bytes32;
use zro::zro::ZRO;

// === Error ===

const EAlreadyInitialized: u64 = 1;
const EInvalidEid: u64 = 2;
const ENotInitialized: u64 = 3;
const ERefundAddressNotFound: u64 = 4;
const EUnauthorizedOApp: u64 = 5;
const EUnauthorizedSendLibrary: u64 = 6;

// === Structs ===

/// One-time witness for the endpoint contract.
public struct ENDPOINT_V2 has drop {}

/// Administrative capability for endpoint management operations.
/// Only the admin can register libraries, set default configurations, and perform
/// other system-level operations that affect all OApps on this endpoint.
public struct AdminCap has key, store {
    id: UID,
}

/// The main endpoint object that coordinates all cross-chain messaging operations.
/// Contains the core registries and managers that enable secure, efficient omnichain communication.
///
/// **Components**:
/// - `eid`: This endpoint's unique identifier in the LayerZero network
/// - `call_cap`: Capability for creating cross-contract calls to OApps and libraries
/// - `oapp_registry`: Registry of all registered OApps and their messaging channels
/// - `composer_registry`: Registry of compose message handlers and their queues
/// - `message_lib_manager`: Manager for all message libraries and their configurations
public struct EndpointV2 has key {
    id: UID,
    eid: u32,
    call_cap: CallCap,
    oapp_registry: OAppRegistry,
    composer_registry: ComposerRegistry,
    message_lib_manager: MessageLibManager,
}

// === Initialization ===

/// Initializes the LayerZero V2 Endpoint with `ZERO` values.
///
/// **Note**: The endpoint EID must be set separately via `init_eid` after deployment
/// to complete the initialization process.
fun init(otw: ENDPOINT_V2, ctx: &mut TxContext) {
    let endpoint = EndpointV2 {
        id: object::new(ctx),
        eid: 0,
        call_cap: call_cap::new_package_cap(&otw, ctx),
        oapp_registry: oapp_registry::new(ctx),
        composer_registry: messaging_composer::new_composer_registry(ctx),
        message_lib_manager: message_lib_manager::new(ctx),
    };
    transfer::share_object(endpoint);
    transfer::transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
}

/// Initializes the endpoint's unique identifier (EID) in the LayerZero network.
///
/// This function completes the endpoint initialization by setting the EID that identifies
/// this specific chain/endpoint within the LayerZero ecosystem. The EID is used
/// in all cross-chain communications to identify the source and destination endpoints.
public fun init_eid(self: &mut EndpointV2, _admin: &AdminCap, eid: u32) {
    assert!(self.eid == 0, EAlreadyInitialized);
    assert!(eid != 0, EInvalidEid);
    self.eid = eid;
}

// === OApp Messaging Functions ===

/// Registers a new OApp with the endpoint, creating its own messaging channel.
///
/// This function creates the essential infrastructure for an OApp to participate in cross-chain
/// messaging by:
/// 1. Creating a spefiic MessagingChannel shared object for isolated message state
/// 2. Registering the OApp in the registry with its metadata
/// 3. Establishing the mapping between OApp address and its messaging channel
///
/// **Parameters**:
/// - `oapp`: The OApp's address proving ownership and authorization
/// - `oapp_info`: OApp information for the OApp, including lz_receive_info for lz_receive calls and extra oapp
/// information. Can be empty and updated later via set_oapp_info() after registration.
///
/// **Returns**: The address of the created messaging channel
public fun register_oapp(self: &mut EndpointV2, oapp: &CallCap, oapp_info: vector<u8>, ctx: &mut TxContext): address {
    // Safe to create messaging channel - oapp_registry has already checked if the oapp is already registered.
    let oapp_address = oapp.id();
    let messaging_channel_address = messaging_channel::create(oapp_address, ctx);
    self.oapp_registry.register_oapp(oapp_address, messaging_channel_address, oapp_info);
    messaging_channel_address
}

/// Sets the delegate address for a registered OApp.
///
/// This function allows OApps to set a delegate address that will be used to authorize
/// certain operations on the OApp.
///
/// **Parameters**:
/// - `oapp`: The OApp's address
/// - `new_delegate`: The delegate address to set
public fun set_delegate(self: &mut EndpointV2, oapp: &CallCap, new_delegate: address) {
    self.oapp_registry.set_delegate(oapp.id(), new_delegate);
}

/// Updates the oapp information for a registered OApp.
///
/// This function allows OApps to update their execution metadata that
/// the executor uses for message delivery.
///
/// **Parameters**:
/// - `caller`: The caller's capability, which must be the OApp or its delegate
/// - `oapp`: The OApp's address
/// - `oapp_info`: New OApp information for the OApp, including lz_receive_info for lz_receive calls and extra oapp
/// information.
public fun set_oapp_info(self: &mut EndpointV2, caller: &CallCap, oapp: address, oapp_info: vector<u8>) {
    self.assert_authorized(caller.id(), oapp);
    self.oapp_registry.set_oapp_info(oapp, oapp_info);
}

/// Initializes a new channel path for communication between this OApp and a remote OApp.
///
/// Channel initialization establishes the communication pathway and initializes nonce tracking
/// for message sequencing. This must be called before any messages can be sent or received
/// on this specific path. Typically called by the OApp during peer configuration.
///
/// **Parameters**:
/// - `caller`: The caller's capability, which must be the OApp or its delegate
/// - `messaging_channel`: The OApp's messaging channel
/// - `remote_eid`: The endpoint ID of the remote chain
/// - `remote_oapp`: The bytes32 address of the remote OApp to communicate with
public fun init_channel(
    self: &EndpointV2,
    caller: &CallCap,
    messaging_channel: &mut MessagingChannel,
    remote_eid: u32,
    remote_oapp: Bytes32,
    ctx: &mut TxContext,
) {
    self.assert_authorized(caller.id(), messaging_channel.oapp());
    messaging_channel.init_channel(remote_eid, remote_oapp, ctx);
}

/// Initiates the quote flow (Step 1 of 3) for calculating cross-chain message fees.
///
/// **Quote Flow Process**:
/// 1. **quote()** - OApp requests a fee quote from the endpoint (this function)
/// 2. **send library processes** - Endpoint delegates to the configured send library
/// 3. **confirm_quote()** - Endpoint receives and returns the calculated fees
///
/// This function begins the quote process by validating the OApp's ownership of the
/// messaging channel, retrieving the appropriate send library for the destination,
/// and creating a child call to the send library for fee calculation.
///
/// **Parameters**:
/// - `messaging_channel`: The OApp's messaging channel
/// - `call`: The quote request call containing destination and message details
///
/// **Returns**: A child call to the send library for quote processing
public fun quote(
    self: &EndpointV2,
    messaging_channel: &MessagingChannel,
    call: &mut Call<EndpointQuoteParam, MessagingFee>,
    ctx: &mut TxContext,
): Call<MessageLibQuoteParam, MessagingFee> {
    call.assert_caller(messaging_channel.oapp());
    let (send_lib, _) = self.message_lib_manager.get_send_library(call.caller(), call.param().dst_eid());
    // Create a outbound call to the message-lib to process the quote.
    // Using self.eid() here is to ensure the Endpoint is initialized.
    let quote_param = messaging_channel.quote(self.eid(), call.param());
    call.create_single_child(&self.call_cap, send_lib, quote_param, ctx)
}

/// Completes the quote flow (Step 3 of 3) by receiving the calculated fees from the send library.
///
/// This function processes the quote result from the send library and completes
/// the original quote call with the calculated messaging fees. The fees include
/// both native token costs and optional ZRO token payments that the OApp will
/// need to pay when actually sending the message.
///
/// **Parameters**:
/// - `endpoint_call`: The original quote call from the OApp
/// - `send_library_call`: The completed quote call from the send library
public fun confirm_quote(
    self: &EndpointV2,
    endpoint_call: &mut Call<EndpointQuoteParam, MessagingFee>,
    send_library_call: Call<MessageLibQuoteParam, MessagingFee>,
) {
    let (_, _, result) = endpoint_call.destroy_child(&self.call_cap, send_library_call);
    endpoint_call.complete(&self.call_cap, result)
}

/// Initiates the send flow (Step 1 of 4) for sending a cross-chain message.
///
/// **Send Flow Process**:
/// 1. **send()** - OApp initiates message sending (this function)
/// 2. **send library processes** - Library handles sending logic
/// 3. **confirm_send()** - Endpoint completes the send and processes fee payment
/// 4. **refund()** - Endpoint refunds unspent tokens to the refund address (optional)
///
/// This function begins the send process by validating the OApp's ownership,
/// determining the appropriate send library for the destination chain, preparing
/// the outbound packet with the next nonce, and delegating to the send library.
///
/// **Parameters**:
/// - `messaging_channel`: The OApp's messaging channel for state management
/// - `call`: The send request call containing message payload, destination, and options
///
/// **Returns**: A child call to the send library for message processing
public fun send(
    self: &EndpointV2,
    messaging_channel: &mut MessagingChannel,
    call: &mut Call<EndpointSendParam, MessagingReceipt>,
    ctx: &mut TxContext,
): Call<MessageLibSendParam, MessageLibSendResult> {
    call.assert_caller(messaging_channel.oapp());
    let (send_lib, _) = self.message_lib_manager.get_send_library(call.caller(), call.param().dst_eid());
    // Create outbound packet and delegate to send library for sending.
    let send_param = messaging_channel.send(self.eid(), call.param());
    call.create_single_child(&self.call_cap, send_lib, send_param, ctx)
}

/// Confirms the send flow (Step 3 of 4) by processing send results and handling fee payment.
///
/// This function is called after the send library has successfully processed the message
/// to finalize the operation. It validates the library's authorization,
/// updates the messaging channel state (increments nonce, emits events), processes
/// fee payments, and returns any unused tokens to the caller.
///
/// **Parameters**:
/// - `send_library`: The send library's capability (ensures this function is called by the send library
///   via static dispatch instead of PTB to receive the returned fees)
/// - `messaging_channel`: The OApp's messaging channel for state updates
/// - `endpoint_call`: The original send call from the OApp
/// - `send_library_call`: The completed send call from the library
///
/// **Returns**: Tuple of (paid IOTA tokens, paid ZRO tokens) for fee collection
public fun confirm_send(
    self: &EndpointV2,
    send_library: &CallCap,
    messaging_channel: &mut MessagingChannel,
    endpoint_call: &mut Call<EndpointSendParam, MessagingReceipt>,
    send_library_call: Call<MessageLibSendParam, MessageLibSendResult>,
    ctx: &mut TxContext,
): (Coin<IOTA>, Coin<ZRO>) {
    messaging_channel.assert_ownership(endpoint_call.caller());
    let (send_lib, param, result) = endpoint_call.destroy_child(&self.call_cap, send_library_call);
    assert!(send_lib == send_library.id(), EUnauthorizedSendLibrary);

    let (receipt, paid_native_token, paid_zro_token) = messaging_channel.confirm_send(
        send_lib,
        endpoint_call.param_mut(&self.call_cap),
        param,
        result,
        ctx,
    );
    endpoint_call.complete(&self.call_cap, receipt);
    (paid_native_token, paid_zro_token)
}

/// Completes the send flow (Step 4 of 4) by refunding unspent native and ZRO tokens to the refund address.
///
/// This is an optional function for OApps that want to simply refund tokens to the refund address.
/// Alternatively, OApps can implement their own refund logic by destroying the send call in their contracts.
///
/// **Parameters**:
/// - `call`: The send call containing tokens and refund address to be processed
public fun refund(self: &EndpointV2, call: Call<EndpointSendParam, MessagingReceipt>) {
    // Get the tokens and refund address from the call.
    let (_, param, _) = call.destroy(&self.call_cap);
    let refund_address = param.refund_address().destroy_or!(abort ERefundAddressNotFound);
    let (native_token, zro_token) = param.destroy();

    // Transfer the tokens to the refund address.
    utils::transfer_coin(native_token, refund_address);
    utils::transfer_coin_option(zro_token, refund_address);
}

/// Verifies an inbound packet from a receive library.
///
/// This is the critical security checkpoint where receive libraries confirm that an inbound
/// message has been properly verified according to their security model.
/// Once verified, the message becomes available for execution via lz_receive.
///
/// **Parameters**:
/// - `receive_library`: The library capability that verified the message
/// - `messaging_channel`: The destination OApp's messaging channel
/// - `src_eid`: Source endpoint ID where the message originated
/// - `sender`: The remote OApp that sent the message
/// - `nonce`: Message sequence number for ordering
/// - `payload_hash`: Hash of the message payload
/// - `clock`: System clock for timeout validation
public fun verify(
    self: &EndpointV2,
    receive_library: &CallCap,
    messaging_channel: &mut MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    payload_hash: Bytes32,
    clock: &Clock,
) {
    self.message_lib_manager.assert_receive_library(messaging_channel.oapp(), src_eid, receive_library.id(), clock);
    messaging_channel.verify(src_eid, sender, nonce, payload_hash);
}

/// Clears a verified message payload from the messaging channel.
///
/// The OApp can remove the verified payload hash from storage in PULL mode.
///
/// **Parameters**:
/// - `caller`: The caller's capability, which must be the OApp or its delegate
/// - `messaging_channel`: The OApp's messaging channel
/// - `src_eid`: Source endpoint ID
/// - `sender`: Remote OApp address that sent the message
/// - `nonce`: Message sequence number
/// - `guid`: Global unique identifier for the message
/// - `message`: The actual message payload
public fun clear(
    self: &EndpointV2,
    caller: &CallCap,
    messaging_channel: &mut MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    guid: Bytes32,
    message: vector<u8>,
) {
    self.assert_authorized(caller.id(), messaging_channel.oapp());
    messaging_channel.clear_payload(src_eid, sender, nonce, utils::build_payload(guid, message));
}

/// Skips verification of the message at the next inbound nonce.
///
/// This function allows OApps to skip problematic messages that may be causing
/// delivery issues.
///
/// **Security**:
/// - Only the receiving OApp can skip its own messages
/// - Requires exact nonce to prevent skipping the unintended nonce
///
/// **Parameters**:
/// - `caller`: The caller's capability, which must be the OApp or its delegate
/// - `messaging_channel`: The OApp's messaging channel
/// - `src_eid`: Source endpoint ID
/// - `sender`: Remote OApp address
/// - `nonce`: Exact nonce to skip (prevents unintended skips)
public fun skip(
    self: &EndpointV2,
    caller: &CallCap,
    messaging_channel: &mut MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
) {
    self.assert_authorized(caller.id(), messaging_channel.oapp());
    messaging_channel.skip(src_eid, sender, nonce);
}

/// Nilifies a message, maintaining verification status but preventing delivery.
///
/// This function keeps a message's verification status but prevents its execution
/// until it's verified again. Used for messages that may have security concerns
/// but shouldn't be permanently skipped.
///
/// **Parameters**:
/// - `caller`: The caller's capability, which must be the OApp or its delegate
/// - `messaging_channel`: The OApp's messaging channel
/// - `src_eid`: Source endpoint ID
/// - `sender`: Remote OApp address
/// - `nonce`: Message sequence number
/// - `payload_hash`: Hash of the message payload
public fun nilify(
    self: &EndpointV2,
    caller: &CallCap,
    messaging_channel: &mut MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    payload_hash: Bytes32,
) {
    self.assert_authorized(caller.id(), messaging_channel.oapp());
    messaging_channel.nilify(src_eid, sender, nonce, payload_hash);
}

/// Permanently marks a nonce as unexecutable and un-verifiable.
///
/// This function provides the most extreme form of message handling by permanently
/// blocking a specific nonce from any future verification or execution. Used only
/// in severe security situations where a message must never be processed.
///
/// **Warning**: This action is irreversible and blocks the nonce permanently
///
/// **Parameters**:
/// - `caller`: The caller's capability, which must be the OApp or its delegate
/// - `messaging_channel`: The OApp's messaging channel
/// - `src_eid`: Source endpoint ID
/// - `sender`: Remote OApp address
/// - `nonce`: Message sequence number to permanently block
/// - `payload_hash`: Hash of the message payload
public fun burn(
    self: &EndpointV2,
    caller: &CallCap,
    messaging_channel: &mut MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    payload_hash: Bytes32,
) {
    self.assert_authorized(caller.id(), messaging_channel.oapp());
    messaging_channel.burn(src_eid, sender, nonce, payload_hash);
}

/// Executes a verified cross-chain message by calling the receiving OApp's lz_receive function.
///
/// This function handles the final delivery of cross-chain messages by:
/// 1. Clearing the verified payload from the channel
/// 2. Creating the lz_receive execution parameters
/// 3. Initiating the call to the receiving OApp
///
/// **Parameters**:
/// - `executor`: The executor's capability
/// - `messaging_channel`: The receiving OApp's messaging channel
/// - `src_eid`: Source endpoint ID
/// - `sender`: Remote OApp that sent the message
/// - `nonce`: Message sequence number
/// - `guid`: Global unique identifier
/// - `message`: The message payload to deliver
/// - `extra_data`: Additional execution data from the executor
/// - `value`: Optional native token transfer with the message
///
/// **Returns**: A call to the OApp's lz_receive function
public fun lz_receive(
    self: &EndpointV2,
    executor: &CallCap,
    messaging_channel: &mut MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    guid: Bytes32,
    message: vector<u8>,
    extra_data: vector<u8>,
    value: Option<Coin<IOTA>>,
    ctx: &mut TxContext,
): Call<LzReceiveParam, Void> {
    messaging_channel.clear_payload(src_eid, sender, nonce, utils::build_payload(guid, message));
    let param = lz_receive::create_param(
        src_eid,
        sender,
        nonce,
        guid,
        message,
        executor.id(),
        extra_data,
        value,
    );
    call::create(&self.call_cap, messaging_channel.oapp(), true, param, ctx)
}

/// Records a failed lz_receive execution for off-chain processing.
///
/// When an lz_receive call fails during execution, this function captures the failure
/// details for analysis and potential retry mechanisms. This provides visibility into
/// delivery failures.
///
/// **Parameters**:
/// - `executor`: The executor that attempted the delivery
/// - `src_eid`: Source endpoint ID
/// - `sender`: Remote OApp that sent the message
/// - `nonce`: Message sequence number
/// - `receiver`: The intended receiving OApp address
/// - `guid`: Global unique identifier
/// - `gas`: Gas limit used for the execution attempt
/// - `value`: Native token value included with the message
/// - `message`: The message payload
/// - `extra_data`: Additional execution data
/// - `reason`: Error message or failure reason
public fun lz_receive_alert(
    executor: &CallCap,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    receiver: address,
    guid: Bytes32,
    gas: u64,
    value: u64,
    message: vector<u8>,
    extra_data: vector<u8>,
    reason: String,
) {
    messaging_channel::lz_receive_alert(
        executor.id(),
        src_eid,
        sender,
        nonce,
        receiver,
        guid,
        gas,
        value,
        message,
        extra_data,
        reason,
    );
}

// === Compose Functions ===

/// Registers a new composer with the endpoint for handling compose messages.
///
/// Composers are specialized contracts that handle sequential execution of operations
/// after a cross-chain message is received. This registration creates the infrastructure
/// needed for the compose messaging system.
///
/// **Parameters**:
/// - `composer`: The composer's capability proving ownership and authorization
/// - `composer_info`: Composer information for the composer, including the lz_compose execution information
/// Can be empty and updated later via set_composer_info() after registration.
///
/// **Returns**: The address of the created compose queue
public fun register_composer(
    self: &mut EndpointV2,
    composer: &CallCap,
    composer_info: vector<u8>,
    ctx: &mut TxContext,
): address {
    self.composer_registry.register_composer(composer.id(), composer_info, ctx)
}

/// Updates the lz_compose execution information for a registered composer.
///
/// This function allows composers to update their execution metadata
/// that the executor system uses for compose message execution.
/// Useful when composers upgrade their lz_compose implementations.
///
/// **Parameters**:
/// - `composer`: The composer's capability
/// - `composer_info`: Composer information for the composer, including the lz_compose execution information
public fun set_composer_info(self: &mut EndpointV2, composer: &CallCap, composer_info: vector<u8>) {
    self.composer_registry.set_composer_info(composer.id(), composer_info);
}

/// Queues a compose message for sequential execution after lz_receive completes.
///
/// Compose messaging enables complex multi-step workflows by allowing OApps to schedule
/// additional operations that execute after the initial message processing. This is essential
/// for scenarios requiring multiple contract interactions or when operations must be split
/// across transactions due to gas limits.
///
/// **Parameters**:
/// - `from`: The OApp that is queuing the compose message
/// - `compose_queue`: The composer's message queue
/// - `guid`: Global unique identifier linking this compose to the original lz_receive
/// - `index`: Sequence number for multiple compose messages from the same lz_receive
/// - `message`: The payload data to be processed by the composer
public fun send_compose(
    from: &CallCap,
    compose_queue: &mut ComposeQueue,
    guid: Bytes32,
    index: u16,
    message: vector<u8>,
) {
    compose_queue.send_compose(from.id(), guid, index, message);
}

/// Executes a queued compose message by calling the composer's lz_compose function.
///
/// This function handles the execution of compose messages by:
/// 1. Validating the compose message exists in the queue
/// 2. Clearing the message from the queue to prevent replay
/// 3. Creating the lz_compose execution parameters
/// 4. Initiating the call to the composer
///
/// **Parameters**:
/// - `executor`: The executor's capability
/// - `compose_queue`: The composer's message queue
/// - `from`: The OApp that originally queued the compose message
/// - `guid`: Global unique identifier
/// - `index`: Sequence number of the compose message
/// - `message`: The compose message payload
/// - `extra_data`: Additional execution data from the executor
/// - `value`: Optional native token transfer with the compose
///
/// **Returns**: A call to the composer's lz_compose function
public fun lz_compose(
    self: &EndpointV2,
    executor: &CallCap,
    compose_queue: &mut ComposeQueue,
    from: address,
    guid: Bytes32,
    index: u16,
    message: vector<u8>,
    extra_data: vector<u8>,
    value: Option<Coin<IOTA>>,
    ctx: &mut TxContext,
): Call<LzComposeParam, Void> {
    compose_queue.clear_compose(from, guid, index, message);
    let param = lz_compose::create_param(from, guid, message, executor.id(), extra_data, value);
    call::create(&self.call_cap, compose_queue.composer(), true, param, ctx)
}

/// Records a failed lz_compose execution for off-chain processing.
///
/// When an lz_compose call fails during execution, this function captures the failure
/// details for analysis and potential retry mechanisms. This provides visibility into
/// delivery failures.
///
/// **Parameters**:
/// - `executor`: The executor that attempted the compose execution
/// - `from`: The OApp that originally queued the compose message
/// - `to`: The composer that was supposed to handle the message
/// - `guid`: Global unique identifier
/// - `index`: Sequence number of the failed compose message
/// - `gas`: Gas limit used for the execution attempt
/// - `value`: Native token value included with the compose
/// - `message`: The compose message payload
/// - `extra_data`: Additional execution data
/// - `reason`: Error message or failure reason
public fun lz_compose_alert(
    executor: &CallCap,
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
    messaging_composer::lz_compose_alert(
        executor.id(),
        from,
        to,
        guid,
        index,
        gas,
        value,
        message,
        extra_data,
        reason,
    );
}

// === OApp Library Configuration Functions ===

/// OApp sets the send library for a specific destination endpoint.
///
/// Allows OApps to choose their preferred send library for different destination chains.
/// This enables OApps to optimize for different trade-offs based on the destination and
/// use case requirements.
///
/// If the OApp has not set a send library for a specific destination endpoint,
/// the endpoint will use the default send library for that destination.
///
/// **Parameters**:
/// - `caller`: The caller's capability, which must be the OApp or its delegate
/// - `sender`: The OApp's address
/// - `dst_eid`: The destination endpoint ID to configure the library for
/// - `new_lib`: The send library address to use
public fun set_send_library(self: &mut EndpointV2, caller: &CallCap, sender: address, dst_eid: u32, new_lib: address) {
    self.assert_authorized(caller.id(), sender);
    self.message_lib_manager.set_send_library(sender, dst_eid, new_lib);
}

/// OApp sets the receive library for a specific source endpoint with a grace period.
///
/// Configures which library will verify inbound messages from a specific source chain.
/// The grace period allows for safe library transitions without disrupting in-flight messages.
///
/// If the OApp has not set a receive library for a specific source endpoint,
/// the endpoint will use the default receive library for that source.
///
/// **Note**: Using seconds instead of block numbers for timeout calculations because
/// IOTA does not have block numbers.
///
/// **Parameters**:
/// - `caller`: The caller's capability, which must be the OApp or its delegate
/// - `receiver`: The OApp's address
/// - `src_eid`: The source endpoint ID to configure the library for
/// - `new_lib`: The receive library address to use
/// - `grace_period`: Transition period in seconds for previous library to verify messages
/// - `clock`: System clock for timeout calculations
public fun set_receive_library(
    self: &mut EndpointV2,
    caller: &CallCap,
    receiver: address,
    src_eid: u32,
    new_lib: address,
    grace_period: u64,
    clock: &Clock,
) {
    self.assert_authorized(caller.id(), receiver);
    self.message_lib_manager.set_receive_library(receiver, src_eid, new_lib, grace_period, clock);
}

/// OApp sets a custom timeout for a specific receive library configuration.
///
/// Allows OApps to override the grace period for a specific library transition.
/// This provides fine-grained control over library switching timelines.
///
/// **Parameters**:
/// - `caller`: The caller's capability, which must be the OApp or its delegate
/// - `receiver`: The OApp's address
/// - `src_eid`: The source endpoint ID
/// - `lib`: The receive library address
/// - `expiry`: Custom expiry timestamp in seconds for the library timeout
/// - `clock`: System clock for timeout validation
public fun set_receive_library_timeout(
    self: &mut EndpointV2,
    caller: &CallCap,
    receiver: address,
    src_eid: u32,
    lib: address,
    expiry: u64,
    clock: &Clock,
) {
    self.assert_authorized(caller.id(), receiver);
    self.message_lib_manager.set_receive_library_timeout(receiver, src_eid, lib, expiry, clock);
}

/// Initiates the configuration flow (Step 1 of 2) for updating message library settings.
///
/// **Configuration Flow Process**:
/// 1. **set_config()** - OApp requests a configuration update from the endpoint (this function)
/// 2. **message library processes** - Message library processes the configuration and destroys the call
///
/// This function begins the configuration process by validating the target message library
/// is registered, then creating a call to the library for configuration processing.
///
/// **Parameters**:
/// - `caller`: The caller's capability, which must be the OApp or its delegate
/// - `oapp`: The OApp's address
/// - `lib`: The target message library address to configure
/// - `eid`: The endpoint ID
/// - `config_type`: The type of configuration
/// - `config`: The configuration data
///
/// **Returns**: A call to the message library for config processing
public fun set_config(
    self: &EndpointV2,
    caller: &CallCap,
    oapp: address,
    lib: address,
    eid: u32,
    config_type: u32,
    config: vector<u8>,
    ctx: &mut TxContext,
): Call<MessageLibSetConfigParam, Void> {
    self.assert_authorized(caller.id(), oapp);
    let param = self.message_lib_manager.set_config(oapp, lib, eid, config_type, config);
    call::create(&self.call_cap, lib, true, param, ctx)
}

// === Admin Functions ===

/// Registers a new message library with the endpoint (admin-only).
///
/// **Parameters**:
/// - `_admin`: Admin capability for authorization
/// - `new_lib`: The address of the new message library
/// - `lib_type`: Specifies whether the library handles send, receive, or both operations
public fun register_library(self: &mut EndpointV2, _admin: &AdminCap, new_lib: address, lib_type: MessageLibType) {
    self.message_lib_manager.register_library(new_lib, lib_type)
}

/// Sets the default send library for a specific destination endpoint (admin-only).
///
/// Establishes the fallback send library that OApps will use if they haven't
/// configured a specific send library for the destination.
///
/// **Parameters**:
/// - `_admin`: Admin capability for authorization
/// - `dst_eid`: The destination endpoint ID
/// - `new_lib`: The default send library address for this destination
public fun set_default_send_library(self: &mut EndpointV2, _admin: &AdminCap, dst_eid: u32, new_lib: address) {
    self.message_lib_manager.set_default_send_library(dst_eid, new_lib);
}

/// Sets the default receive library for a specific source endpoint (admin-only).
///
/// Establishes the fallback receive library for message verification from a specific
/// source chain. The grace period allows for safe transitions when updating the
/// default library without disrupting in-flight messages.
///
/// **Note**: Using seconds instead of block numbers for timeout calculations because
/// IOTA does not have block numbers.
///
/// **Parameters**:
/// - `_admin`: Admin capability for authorization
/// - `src_eid`: The source endpoint ID
/// - `new_lib`: The default receive library address for this source
/// - `grace_period`: Transition period in seconds for safe library switching
/// - `clock`: System clock for timeout calculations
public fun set_default_receive_library(
    self: &mut EndpointV2,
    _admin: &AdminCap,
    src_eid: u32,
    new_lib: address,
    grace_period: u64,
    clock: &Clock,
) {
    self.message_lib_manager.set_default_receive_library(src_eid, new_lib, grace_period, clock);
}

/// Sets a custom timeout for the default receive library configuration (admin-only).
///
/// Allows administrators to override the default grace period for specific library.
///
/// **Parameters**:
/// - `_admin`: Admin capability for authorization
/// - `src_eid`: The source endpoint ID
/// - `lib`: The receive library address
/// - `expiry`: Custom expiry timestamp in seconds for the library timeout
/// - `clock`: System clock for timeout validation
public fun set_default_receive_library_timeout(
    self: &mut EndpointV2,
    _admin: &AdminCap,
    src_eid: u32,
    lib: address,
    expiry: u64,
    clock: &Clock,
) {
    self.message_lib_manager.set_default_receive_library_timeout(src_eid, lib, expiry, clock);
}

// === Public View Functions ===

/// Returns the endpoint's unique identifier in the LayerZero network.
/// Aborts if the endpoint is not initialized.
public fun eid(self: &EndpointV2): u32 {
    assert!(self.eid != 0, ENotInitialized);
    self.eid
}

// === OApp Registration Public View Functions ===

/// Checks if an OApp is registered with the endpoint.
public fun is_oapp_registered(self: &EndpointV2, oapp: address): bool {
    self.oapp_registry.is_registered(oapp)
}

/// Retrieves the messaging channel address for a registered OApp.
public fun get_messaging_channel(self: &EndpointV2, oapp: address): address {
    self.oapp_registry.get_messaging_channel(oapp)
}

/// Retrieves the oapp information for a registered OApp.
public fun get_oapp_info(self: &EndpointV2, oapp: address): vector<u8> {
    *self.oapp_registry.get_oapp_info(oapp)
}

/// Retrieves the delegate address for a registered OApp.
public fun get_delegate(self: &EndpointV2, oapp: address): address {
    self.oapp_registry.get_delegate(oapp)
}

// === Composer Registration Public View Functions ===

/// Checks if a composer is registered with the endpoint.
public fun is_composer_registered(self: &EndpointV2, composer: address): bool {
    self.composer_registry.is_registered(composer)
}

/// Retrieves the compose queue address for a registered composer.
public fun get_compose_queue(self: &EndpointV2, composer: address): address {
    self.composer_registry.get_compose_queue(composer)
}

/// Retrieves the composer information for a registered composer.
public fun get_composer_info(self: &EndpointV2, composer: address): vector<u8> {
    *self.composer_registry.get_composer_info(composer)
}

// === Compose Queue Public View Functions ===

/// Retrieves the composer address that owns the compose queue.
public fun get_composer(compose_queue: &ComposeQueue): address {
    compose_queue.composer()
}

/// Checks if a compose message hash exists in the queue.
public fun has_compose_message_hash(compose_queue: &ComposeQueue, from: address, guid: Bytes32, index: u16): bool {
    compose_queue.has_compose_message_hash(from, guid, index)
}

/// Retrieves the hash of a queued compose message.
public fun get_compose_message_hash(compose_queue: &ComposeQueue, from: address, guid: Bytes32, index: u16): Bytes32 {
    compose_queue.get_compose_message_hash(from, guid, index)
}

// === Message Lib Manager Public View Functions ===

/// Returns the total number of registered message libraries.
public fun registered_libraries_count(self: &EndpointV2): u64 {
    self.message_lib_manager.registered_libraries_count()
}

/// Retrieves a paginated list of registered message library addresses.
public fun registered_libraries(self: &EndpointV2, start: u64, max_count: u64): vector<address> {
    self.message_lib_manager.registered_libraries(start, max_count)
}

/// Checks if a specific address corresponds to a registered message library.
public fun is_registered_library(self: &EndpointV2, lib: address): bool {
    self.message_lib_manager.is_registered_library(lib)
}

/// Retrieves the type classification for a registered message library.
public fun get_library_type(self: &EndpointV2, lib: address): MessageLibType {
    self.message_lib_manager.get_library_type(lib)
}

/// Retrieves the default send library for a specific destination endpoint.
public fun get_default_send_library(self: &EndpointV2, dst_eid: u32): address {
    self.message_lib_manager.get_default_send_library(dst_eid)
}

/// Retrieves the default receive library for a specific source endpoint.
public fun get_default_receive_library(self: &EndpointV2, src_eid: u32): address {
    self.message_lib_manager.get_default_receive_library(src_eid)
}

/// Retrieves the timeout configuration for the default receive library.
public fun get_default_receive_library_timeout(self: &EndpointV2, src_eid: u32): Option<Timeout> {
    self.message_lib_manager.get_default_receive_library_timeout(src_eid)
}

/// Checks if a destination endpoint ID is supported by the endpoint.
public fun is_supported_eid(self: &EndpointV2, eid: u32): bool {
    self.message_lib_manager.is_supported_eid(eid)
}

/// Retrieves the effective send library for a specific OApp and destination.
public fun get_send_library(self: &EndpointV2, sender: address, dst_eid: u32): (address, bool) {
    self.message_lib_manager.get_send_library(sender, dst_eid)
}

/// Retrieves the effective receive library for a specific OApp and source.
public fun get_receive_library(self: &EndpointV2, receiver: address, src_eid: u32): (address, bool) {
    self.message_lib_manager.get_receive_library(receiver, src_eid)
}

/// Retrieves the timeout configuration for an OApp's receive library.
public fun get_receive_library_timeout(self: &EndpointV2, receiver: address, src_eid: u32): Option<Timeout> {
    self.message_lib_manager.get_receive_library_timeout(receiver, src_eid)
}

/// Validates if a specific receive library is currently valid for an OApp.
public fun is_valid_receive_library(
    self: &EndpointV2,
    receiver: address,
    src_eid: u32,
    actual_receive_lib: address,
    clock: &Clock,
): bool {
    self.message_lib_manager.is_valid_receive_library(receiver, src_eid, actual_receive_lib, clock)
}

// === Messaging Channel Public View Functions ===

/// Checks if a channel has been initialized for a specific communication pathway.
public fun is_channel_inited(messaging_channel: &MessagingChannel, remote_eid: u32, remote_oapp: Bytes32): bool {
    messaging_channel.is_channel_inited(remote_eid, remote_oapp)
}

/// Checks if a channel has been initialized for a specific communication pathway.
/// Same as is_channel_inited, but with consistent name to the spec.
public fun initializable(messaging_channel: &MessagingChannel, src_eid: u32, sender: Bytes32): bool {
    messaging_channel.is_channel_inited(src_eid, sender)
}

/// Retrieves the OApp address that owns the messaging channel.
public fun get_oapp(messaging_channel: &MessagingChannel): address {
    messaging_channel.oapp()
}

/// Checks if the messaging channel is currently in a sending state.
public fun is_sending(messaging_channel: &MessagingChannel): bool {
    messaging_channel.is_sending()
}

/// Generates the next GUID for the next outbound message.
public fun get_next_guid(
    self: &EndpointV2,
    messaging_channel: &MessagingChannel,
    dst_eid: u32,
    receiver: Bytes32,
): Bytes32 {
    messaging_channel.next_guid(self.eid(), dst_eid, receiver)
}

/// Retrieves the current outbound nonce for a specific destination.
public fun get_outbound_nonce(messaging_channel: &MessagingChannel, dst_eid: u32, receiver: Bytes32): u64 {
    messaging_channel.outbound_nonce(dst_eid, receiver)
}

/// Retrieves the lazy inbound nonce for a specific source.
public fun get_lazy_inbound_nonce(messaging_channel: &MessagingChannel, src_eid: u32, sender: Bytes32): u64 {
    messaging_channel.lazy_inbound_nonce(src_eid, sender)
}

/// Retrieves the max nonce of the longest gapless sequence of verified messages.
/// It starts from the lazy inbound nonce and iteratively check if the next nonce has been verified
public fun get_inbound_nonce(messaging_channel: &MessagingChannel, src_eid: u32, sender: Bytes32): u64 {
    messaging_channel.inbound_nonce(src_eid, sender)
}

/// Checks if a payload hash exists for a specific inbound nonce.
public fun has_inbound_payload_hash(
    messaging_channel: &MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
): bool {
    messaging_channel.has_payload_hash(src_eid, sender, nonce)
}

/// Retrieves the stored payload hash for a verified inbound nonce.
public fun get_inbound_payload_hash(
    messaging_channel: &MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
): Bytes32 {
    messaging_channel.get_payload_hash(src_eid, sender, nonce)
}

/// Checks if a specific message nonce is verifiable.
public fun verifiable(messaging_channel: &MessagingChannel, src_eid: u32, sender: Bytes32, nonce: u64): bool {
    messaging_channel.verifiable(src_eid, sender, nonce)
}

// === Internal Functions ===

/// Asserts that the caller is authorized to perform the action for the given OApp.
/// The caller can be the OApp itself or its delegate.
fun assert_authorized(self: &EndpointV2, caller: address, oapp: address) {
    assert!(caller == oapp || caller == self.oapp_registry.get_delegate(oapp), EUnauthorizedOApp);
}

// === Test Functions ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    init(iota::test_utils::create_one_time_witness<ENDPOINT_V2>(), ctx);
}

#[test_only]
public fun get_call_cap_ref(self: &EndpointV2): &CallCap {
    &self.call_cap
}
