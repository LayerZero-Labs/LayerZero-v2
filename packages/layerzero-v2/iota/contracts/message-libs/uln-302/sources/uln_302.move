/// The ULN 302 (Ultra Light Node) message library provides configurable, decentralized
/// verification for cross-chain messages. This library orchestrates the collaboration
/// between executors and DVNs (Decentralized Verifier Networks) to ensure secure,
/// efficient cross-chain communication.
///
/// **Core Security Model**:
/// The ULN 302 implements a configurable security framework where:
/// - **Executors** handle message delivery and gas payment on destination chains
/// - **DVNs** provide independent verification of cross-chain messages
/// - **Configurations** allow OApps to customize security parameters per destination
///
/// **Key Features**:
/// - Modular architecture supporting different executor and DVN combinations
/// - Per-OApp configuration for customized security and cost trade-offs
/// - Fee estimation and payment processing for cross-chain operations
/// - Verification storage and threshold management for inbound messages
/// - Admin controls for system-wide default configurations
module uln_302::uln_302;

use call::{call::{Call, Void}, call_cap::{Self, CallCap}};
use endpoint_v2::{
    endpoint_send::SendParam as EndpointSendParam,
    endpoint_v2::{Self, EndpointV2},
    message_lib_quote::QuoteParam as MessageLibQuoteParam,
    message_lib_send::{SendParam as MessageLibSendParam, SendResult as MessageLibSendResult},
    message_lib_set_config::SetConfigParam as MessageLibSetConfigParam,
    messaging_channel::MessagingChannel,
    messaging_fee::MessagingFee,
    messaging_receipt::MessagingReceipt
};
use message_lib_common::fee_recipient::FeeRecipient;
use multi_call::multi_call::{Self, MultiCall};
use iota::clock::Clock;
use treasury::treasury::Treasury;
use uln_302::{
    executor_config::{Self, ExecutorConfig},
    oapp_uln_config::{Self, OAppUlnConfig},
    receive_uln::{Self, ReceiveUln, Verification},
    send_uln::{Self, SendUln},
    uln_config::UlnConfig
};
use uln_common::{
    dvn_assign_job::AssignJobParam as DvnAssignJobParam,
    dvn_get_fee::GetFeeParam as DvnGetFeeParam,
    dvn_verify::VerifyParam as DvnVerifyParam,
    executor_assign_job::AssignJobParam as ExecutorAssignJobParam,
    executor_get_fee::GetFeeParam as ExecutorGetFeeParam
};
use utils::{bytes32::Bytes32, package};

// === Constants ===

/// Configuration type identifier for executor settings
const CONFIG_TYPE_EXECUTOR: u32 = 1;
/// Configuration type identifier for send ULN settings
const CONFIG_TYPE_SEND_ULN: u32 = 2;
/// Configuration type identifier for receive ULN settings
const CONFIG_TYPE_RECEIVE_ULN: u32 = 3;

// === Errors ===

const EInvalidConfigType: u64 = 1;
const EInvalidMessagingChannel: u64 = 2;
const EUnsupportedEid: u64 = 3;

// === Structs ===

/// One-time witness for the ULN 302 message library.
public struct ULN_302 has drop {}

/// Admin capability for ULN configuration management.
public struct AdminCap has key, store {
    id: UID,
}

/// Main ULN 302 message library instance that coordinates secure cross-chain messaging.
///
/// **Components**:
/// - `call_cap`: Capability for operating cross-contract calls from Endpoint and creating
///   calls to executors and DVNs
/// - `send_uln`: Manages outbound message processing, fee estimation, and job assignment
/// - `receive_uln`: Handles inbound message verification
///
/// **Note**:
/// The ULN maintains separate send and receive logic to provide bidirectional security.
/// Each direction can be configured independently with different workers.
public struct Uln302 has key {
    id: UID,
    call_cap: CallCap,
    send_uln: SendUln,
    receive_uln: ReceiveUln,
}

// === Initialization ===

/// Initializes the ULN 302 message library.
fun init(otw: ULN_302, ctx: &mut TxContext) {
    let uln_302 = Uln302 {
        id: object::new(ctx),
        call_cap: call_cap::new_package_cap(&otw, ctx),
        send_uln: send_uln::new_send_uln(ctx),
        receive_uln: receive_uln::new_receive_uln(ctx),
    };
    transfer::share_object(uln_302);
    transfer::transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
}

// === Core Message Library Functions ===

/// Initiates the quote flow (Step 1 of 3) for calculating cross-chain message fees.
///
/// **Quote Flow Process**:
/// 1. **quote()** - ULN requests fees from executor and DVNs (this function)
/// 2. **worker processes** - Executor and DVNs calculate fees
/// 3. **confirm_quote()** - ULN aggregates fees and returns total cost
///
/// **Parameters**:
/// - `call`: Quote request from the endpoint containing message details
///
/// **Returns**: Tuple of (executor fee call, DVN fee calls) for processing
public fun quote(
    self: &Uln302,
    call: &mut Call<MessageLibQuoteParam, MessagingFee>,
    ctx: &mut TxContext,
): (Call<ExecutorGetFeeParam, u64>, MultiCall<DvnGetFeeParam, u64>) {
    call.assert_caller(endpoint!());
    let (executor, executor_param, dvns, dvn_params) = self.send_uln.quote(call.param());
    call.new_child_batch(&self.call_cap, 1);
    let dvn_calls = dvns.zip_map!(dvn_params, |dvn, param| call.create_child(&self.call_cap, dvn, param, false, ctx));
    let executor_call = call.create_child(&self.call_cap, executor, executor_param, true, ctx);
    (executor_call, multi_call::create(&self.call_cap, dvn_calls))
}

/// Completes the quote flow (Step 3 of 3) by aggregating fees and calculating total cost.
///
/// This function processes the fee responses from executor and DVNs to provide
/// the final messaging fee quote.
///
/// **Parameters**:
/// - `treasury`: Treasury instance for treasury fee calculation
/// - `send_library_call`: Original quote call to complete
/// - `executor_call`: Completed executor fee call
/// - `dvn_multi_call`: Completed DVN fee calls
public fun confirm_quote(
    self: &Uln302,
    treasury: &Treasury,
    send_library_call: &mut Call<MessageLibQuoteParam, MessagingFee>,
    executor_call: Call<ExecutorGetFeeParam, u64>,
    dvn_multi_call: MultiCall<DvnGetFeeParam, u64>,
) {
    send_library_call.assert_caller(endpoint!());
    let dvn_fees = dvn_multi_call.destroy(&self.call_cap).map!(|dvn_call| {
        let (_, _, dvn_fee) = send_library_call.destroy_child(&self.call_cap, dvn_call);
        dvn_fee
    });
    let (_, _, executor_fee) = send_library_call.destroy_child(&self.call_cap, executor_call);
    let messaging_fee = send_uln::confirm_quote(send_library_call.param(), executor_fee, dvn_fees, treasury);
    send_library_call.complete(&self.call_cap, messaging_fee);
}

/// Initiates the send flow (Step 1 of 3) by assigning jobs to executor and DVNs.
///
/// **Send Flow Process**:
/// 1. **send()** - ULN assigns jobs to executor and DVNs (this function)
/// 2. **worker processes** - Executor and DVNs assign jobs
/// 3. **confirm_send()** - ULN processes job confirmations and handles fee settlement
///
/// **Parameters**:
/// - `call`: Send request from the endpoint containing message and destination details
///
/// **Returns**: Tuple of (executor job call, DVN job calls) for processing
public fun send(
    self: &Uln302,
    call: &mut Call<MessageLibSendParam, MessageLibSendResult>,
    ctx: &mut TxContext,
): (Call<ExecutorAssignJobParam, FeeRecipient>, MultiCall<DvnAssignJobParam, FeeRecipient>) {
    call.assert_caller(endpoint!());
    assert!(self.is_supported_eid(call.param().base().packet().dst_eid()), EUnsupportedEid);

    let (executor, executor_param, dvns, dvn_params) = self.send_uln.send(call.param());
    call.new_child_batch(&self.call_cap, 1);
    let dvn_calls = dvns.zip_map!(dvn_params, |dvn, param| call.create_child(&self.call_cap, dvn, param, false, ctx));
    let executor_call = call.create_child(&self.call_cap, executor, executor_param, true, ctx);
    (executor_call, multi_call::create(&self.call_cap, dvn_calls))
}

/// Completes the send flow (Step 3 of 3) by processing job confirmations and fee settlement.
///
/// This function finalizes the message sending process by destroying the job assignment calls,
/// collecting fee recipient information from each component, confirming the send operation with
/// the SendUln logic, and delegating back to the endpoint for final processing.
///
/// **Parameters**:
/// - `endpoint`: Endpoint for final send confirmation
/// - `treasury`: Treasury for fee calculation and token management
/// - `messaging_channel`: OApp's messaging channel for state updates
/// - `endpoint_call`: Original send call from the Endpoint
/// - `send_library_call`: ULN send call to complete
/// - `executor_call`: Completed executor job assignment call
/// - `dvn_multi_call`: Completed DVN job assignment calls
public fun confirm_send(
    self: &Uln302,
    endpoint: &EndpointV2,
    treasury: &Treasury,
    messaging_channel: &mut MessagingChannel,
    endpoint_call: &mut Call<EndpointSendParam, MessagingReceipt>,
    mut send_library_call: Call<MessageLibSendParam, MessageLibSendResult>,
    executor_call: Call<ExecutorAssignJobParam, FeeRecipient>,
    dvn_multi_call: MultiCall<DvnAssignJobParam, FeeRecipient>,
    ctx: &mut TxContext,
) {
    send_library_call.assert_caller(endpoint!());
    // Destroy DVN calls and extract fee recipient information
    let (mut dvns, mut dvn_recipients) = (vector[], vector[]);
    dvn_multi_call.destroy(&self.call_cap).do!(|dvn_call| {
        let (dvn, _, dvn_recipient) = send_library_call.destroy_child(&self.call_cap, dvn_call);
        dvns.push_back(dvn);
        dvn_recipients.push_back(dvn_recipient);
    });

    // Destroy executor call and extract fee recipient information
    let (executor, _, executor_recipient) = send_library_call.destroy_child(&self.call_cap, executor_call);

    // Confirm send with the SendUln and get the result
    let send_result = send_uln::confirm_send(
        send_library_call.param(),
        executor,
        executor_recipient,
        dvns,
        dvn_recipients,
        treasury,
    );
    send_library_call.complete(&self.call_cap, send_result);

    // Call endpoint for final send confirmation and token collection
    let (native_token, zro_token) = endpoint.confirm_send(
        &self.call_cap,
        messaging_channel,
        endpoint_call,
        send_library_call,
        ctx,
    );

    // Distribute fees to executor and DVNs based on their payment requirements
    send_uln::handle_fees(treasury, executor_recipient, dvn_recipients, native_token, zro_token, ctx);
}

/// Sets OApp-specific configuration.
///
/// Allows OApps to customize their security and execution parameters for specific
/// destination or source endpoints. This enables fine-grained control over:
///
/// **Configuration Types**:
/// - **Executor Config**: Executor and max message size
/// - **Send ULN Config**: DVN sets and thresholds for outbound message verification
/// - **Receive ULN Config**: DVN sets and thresholds for inbound message verification
///
/// **Parameters**:
/// - `call`: Configuration request containing the config type, target endpoint, and settings
public fun set_config(self: &mut Uln302, call: Call<MessageLibSetConfigParam, Void>) {
    call.assert_caller(endpoint!());
    assert!(self.is_supported_eid(call.param().eid()), EUnsupportedEid);

    let param = call.param();
    let config_type = param.config_type();
    if (config_type == CONFIG_TYPE_EXECUTOR) {
        self.send_uln.set_executor_config(param.oapp(), param.eid(), executor_config::deserialize(*param.config()));
    } else if (config_type == CONFIG_TYPE_SEND_ULN) {
        self.send_uln.set_uln_config(param.oapp(), param.eid(), oapp_uln_config::deserialize(*param.config()));
    } else if (config_type == CONFIG_TYPE_RECEIVE_ULN) {
        self.receive_uln.set_uln_config(param.oapp(), param.eid(), oapp_uln_config::deserialize(*param.config()));
    } else {
        abort EInvalidConfigType
    };
    call.complete_and_destroy(&self.call_cap);
}

// === Message Verification Functions ===

/// Records a DVN verification for a specific cross-chain message.
///
/// Called by DVNs to submit their independent verification of a message
/// that was sent from a source chain. Each DVN provides the number of block
/// confirmations they observed for the message, contributing to the overall
/// security threshold required for message delivery.
///
/// **Parameters**:
/// - `verification`: Verification storage tracking all DVN confirmations
/// - `call`: Call containing the DVN verification parameters
public fun verify(self: &Uln302, verification: &mut Verification, call: Call<DvnVerifyParam, Void>) {
    let dvn = call.caller();
    let param = call.complete_and_destroy(&self.call_cap);
    receive_uln::verify(verification, dvn, *param.packet_header(), param.payload_hash(), param.confirmations())
}

/// Commits verification and delivers the message once sufficient DVN confirmations are received.
///
/// This function validates that enough DVNs have verified the message according to
/// the configured security thresholds, then forwards the verification to the endpoint
/// for final message delivery to the receiving OApp.
///
/// **Parameters**:
/// - `verification`: Verification storage containing DVN confirmations
/// - `endpoint`: Endpoint for message delivery
/// - `messaging_channel`: Target OApp's messaging channel
/// - `packet_header`: Message packet header with routing information
/// - `payload_hash`: Hash of the message payload
/// - `clock`: System clock for any time-based validations
public fun commit_verification(
    self: &Uln302,
    verification: &mut Verification,
    endpoint: &EndpointV2,
    messaging_channel: &mut MessagingChannel,
    packet_header: vector<u8>,
    payload_hash: Bytes32,
    clock: &Clock,
) {
    // Verify the message and clean up storage, returning the decoded header
    let header = self.receive_uln.verify_and_reclaim_storage(verification, endpoint.eid(), packet_header, payload_hash);
    assert!(self.is_supported_eid(header.src_eid()), EUnsupportedEid);

    // Assert the header is for the correct messaging channel and verify the message with the endpoint
    assert!(header.receiver().to_address() == endpoint_v2::get_oapp(messaging_channel), EInvalidMessagingChannel);
    endpoint.verify(
        &self.call_cap,
        messaging_channel,
        header.src_eid(),
        header.sender(),
        header.nonce(),
        payload_hash,
        clock,
    );
}

// === Admin Functions ===

/// Sets the default executor configuration for a specific destination endpoint (admin-only).
///
/// Establishes the fallback executor settings that OApps will use if they haven't
/// configured specific executor settings for the destination.
///
/// **Parameters**:
/// - `_admin`: Admin capability for authorization
/// - `dst_eid`: The destination endpoint ID to configure
/// - `config`: Default executor configuration for this destination
public fun set_default_executor_config(self: &mut Uln302, _admin: &AdminCap, dst_eid: u32, config: ExecutorConfig) {
    self.send_uln.set_default_executor_config(dst_eid, config);
}

/// Sets the default send ULN configuration for a specific destination endpoint (admin-only).
///
/// Establishes the fallback security configuration that OApps will use for outbound
/// messages if they haven't configured specific DVN sets and thresholds for the destination.
///
/// **Parameters**:
/// - `_admin`: Admin capability for authorization
/// - `dst_eid`: The destination endpoint ID to configure
/// - `config`: Default ULN configuration with DVN sets and thresholds
public fun set_default_send_uln_config(self: &mut Uln302, _admin: &AdminCap, dst_eid: u32, config: UlnConfig) {
    self.send_uln.set_default_uln_config(dst_eid, config);
}

/// Sets the default receive ULN configuration for a specific source endpoint (admin-only).
///
/// Establishes the fallback security configuration that OApps will use for inbound
/// message verification if they haven't configured specific DVN sets and thresholds
/// for the source.
///
/// **Parameters**:
/// - `_admin`: Admin capability for authorization
/// - `src_eid`: The source endpoint ID to configure
/// - `config`: Default ULN configuration with DVN sets and thresholds
public fun set_default_receive_uln_config(self: &mut Uln302, _admin: &AdminCap, src_eid: u32, config: UlnConfig) {
    self.receive_uln.set_default_uln_config(src_eid, config);
}

// === Public View Functions ===

/// Returns the ULN version (major, minor, endpoint_version).
public fun version(): (u64, u8, u8) {
    (3, 0, 2)
}

/// Checks if an endpoint ID is supported for both sending and receiving operations.
public fun is_supported_eid(self: &Uln302, eid: u32): bool {
    self.send_uln.is_supported_eid(eid) && self.receive_uln.is_supported_eid(eid)
}

// === Send ULN Configuration View Functions ===

/// Returns the default executor configuration for a destination endpoint.
public fun get_default_executor_config(self: &Uln302, dst_eid: u32): &ExecutorConfig {
    self.send_uln.get_default_executor_config(dst_eid)
}

/// Returns the OApp-specific executor configuration for a sender and destination.
public fun get_oapp_executor_config(self: &Uln302, sender: address, dst_eid: u32): &ExecutorConfig {
    self.send_uln.get_oapp_executor_config(sender, dst_eid)
}

/// Returns the effective executor configuration (OApp-specific merged with defaults).
public fun get_effective_executor_config(self: &Uln302, sender: address, dst_eid: u32): ExecutorConfig {
    self.send_uln.get_effective_executor_config(sender, dst_eid)
}

/// Returns the default send ULN configuration for a destination endpoint.
public fun get_default_send_uln_config(self: &Uln302, dst_eid: u32): &UlnConfig {
    self.send_uln.get_default_uln_config(dst_eid)
}

/// Returns the OApp-specific send ULN configuration for a sender and destination.
public fun get_oapp_send_uln_config(self: &Uln302, sender: address, dst_eid: u32): &OAppUlnConfig {
    self.send_uln.get_oapp_uln_config(sender, dst_eid)
}

/// Returns the effective send ULN configuration (OApp-specific merged with defaults).
public fun get_effective_send_uln_config(self: &Uln302, sender: address, dst_eid: u32): UlnConfig {
    self.send_uln.get_effective_uln_config(sender, dst_eid)
}

// === Receive ULN Configuration View Functions ===

/// Returns the default receive ULN configuration for a source endpoint.
public fun get_default_receive_uln_config(self: &Uln302, src_eid: u32): &UlnConfig {
    self.receive_uln.get_default_uln_config(src_eid)
}

/// Returns the OApp-specific receive ULN configuration for a receiver and source.
public fun get_oapp_receive_uln_config(self: &Uln302, receiver: address, src_eid: u32): &OAppUlnConfig {
    self.receive_uln.get_oapp_uln_config(receiver, src_eid)
}

/// Returns the effective receive ULN configuration (OApp-specific merged with defaults).
public fun get_effective_receive_uln_config(self: &Uln302, receiver: address, src_eid: u32): UlnConfig {
    self.receive_uln.get_effective_uln_config(receiver, src_eid)
}

// === Message Verification View Functions ===

/// Returns the address of the verification storage.
public fun get_verification(self: &Uln302): address {
    self.receive_uln.get_verification()
}

/// Checks if a message is verifiable (has sufficient DVN confirmations).
public fun verifiable(
    self: &Uln302,
    verification: &Verification,
    endpoint: &EndpointV2,
    packet_header: vector<u8>,
    payload_hash: Bytes32,
): bool {
    self.receive_uln.verifiable(verification, endpoint.eid(), packet_header, payload_hash)
}

/// Returns the number of confirmations submitted by a specific DVN for a message.
public fun get_confirmations(
    verification: &Verification,
    dvn: address,
    header_hash: Bytes32,
    payload_hash: Bytes32,
): u64 {
    verification.get_confirmations(dvn, header_hash, payload_hash)
}

// === Internal Functions ===

macro fun endpoint(): address {
    package::original_package_of_type<EndpointV2>()
}

// === Test-only Functions ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    let uln_302 = Uln302 {
        id: object::new(ctx),
        call_cap: call_cap::new_package_cap_for_test(ctx),
        send_uln: send_uln::new_send_uln(ctx),
        receive_uln: receive_uln::new_receive_uln(ctx),
    };
    transfer::share_object(uln_302);
    transfer::transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
}

#[test_only]
public fun get_call_cap(self: &Uln302): &CallCap {
    &self.call_cap
}
