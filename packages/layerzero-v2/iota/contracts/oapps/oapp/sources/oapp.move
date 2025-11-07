/// OApp (Omnichain Application) Module
///
/// This module provides the core functionality for building omnichain applications on IOTA using LayerZero v2.
/// An OApp is a decentralized application that can send and receive messages across multiple blockchains
/// through LayerZero's messaging protocol.
module oapp::oapp;

use call::{call::{Self, Call, Void}, call_cap::{Self, CallCap}};
use endpoint_v2::{
    endpoint_quote::{Self, QuoteParam},
    endpoint_send::{Self, SendParam},
    endpoint_v2::{Self, EndpointV2},
    lz_receive::LzReceiveParam,
    messaging_channel::MessagingChannel,
    messaging_fee::MessagingFee,
    messaging_receipt::MessagingReceipt
};
use oapp::{enforced_options::{Self, EnforcedOptions}, oapp_peer::{Self, Peer}};
use iota::{coin::Coin, iota::IOTA};
use utils::{bytes32::Bytes32, package};
use zro::zro::ZRO;

// === Errors ===

const EInvalidAdminCap: u64 = 1;
const EInvalidOAppCap: u64 = 2;
const EInvalidRefundAddress: u64 = 3;
const EInvalidSendingCall: u64 = 4;
const EOnlyEndpoint: u64 = 5;
const EOnlyPeer: u64 = 6;
const ESendingInProgress: u64 = 7;

// === Structs ===

/// Admin capability for managing OApp configuration.
/// Provides exclusive access to administrative functions like setting peers and enforced options.
public struct AdminCap has key, store {
    id: UID,
}

/// Core OApp struct containing all configuration and state.
/// Represents an omnichain application that can send and receive cross-chain messages.
public struct OApp has key {
    id: UID,
    /// The internal call capability for the OApp itself for endpoint & OApp related function calls
    oapp_cap: CallCap,
    /// The address of the admin capability
    admin_cap: address,
    /// Peer management for trusted cross-chain counterparts
    peer: Peer,
    /// Enforced execution options for outbound messages
    enforced_options: EnforcedOptions,
    /// The address of the sending call, only used for two-way calls
    sending_call: Option<address>,
}

// === Initialization ===

/// Creates a new OApp instance with admin and call capabilities.
///
/// **Parameters**
/// - `otw`: One-time witness for creating the package capability
///
/// **Returns**
/// A tuple of (CallCap, AdminCap, address):
/// - CallCap: Used for authenticating outbound calls and receiving inbound messages
/// - AdminCap: Used for administrative functions like setting peers, enforced options and endpoint configurations
/// - address: The main OApp object address
public fun new<T: drop>(otw: &T, ctx: &mut TxContext): (CallCap, AdminCap, address) {
    let admin_cap = AdminCap { id: object::new(ctx) };
    let oapp = OApp {
        id: object::new(ctx),
        oapp_cap: call_cap::new_package_cap(otw, ctx),
        admin_cap: object::id_address(&admin_cap),
        peer: oapp_peer::new(ctx),
        enforced_options: enforced_options::new(ctx),
        sending_call: option::none(),
    };
    let oapp_object_address = object::id_address(&oapp);
    transfer::share_object(oapp);
    (call_cap::new_package_cap(otw, ctx), admin_cap, oapp_object_address)
}

// === OApp Core Functions ===

/// Quotes the fee for sending a cross-chain message.
///
/// This function estimates the cost of sending a message to a destination chain
/// without actually sending it. The quote includes both native token fees and
/// optional ZRO token fees based on the LayerZero fee structure.
///
/// **Parameters**
/// - `oapp_cap`: Call capability for authentication
/// - `dst_eid`: Destination endpoint ID (chain identifier)
/// - `message`: The message payload to be sent
/// - `options`: Execution options for the message (e.g., gas limits)
/// - `pay_in_zro`: Whether to pay fees using ZRO tokens
///
/// **Returns**:
/// A Call object that can be executed to get the MessagingFee quote
public fun quote(
    self: &OApp,
    oapp_cap: &CallCap,
    dst_eid: u32,
    message: vector<u8>,
    options: vector<u8>,
    pay_in_zro: bool,
    ctx: &mut TxContext,
): Call<QuoteParam, MessagingFee> {
    self.assert_oapp_cap(oapp_cap);
    let receiver = self.peer.get_peer(dst_eid);
    let quote_param = endpoint_quote::create_param(dst_eid, receiver, message, options, pay_in_zro);
    call::create(oapp_cap, endpoint!(), false, quote_param, ctx)
}

/// Confirms and extracts results from a quote operation.
///
/// This function consumes a Call object returned by `quote()` to extract the
/// quote parameters and messaging fee, providing access to the quote results.
///
/// **Note**: Most users don't need this function. It's only required for advanced
/// use cases where `quote()` and `send()` must be used within the same transaction.
///
/// **Parameters**
/// - `oapp_cap`: Call capability for authentication
/// - `call`: Completed Call object from `quote()` execution
///
/// **Returns**
/// - `QuoteParam`: Original quote parameters used in the message
/// - `MessagingFee`: Fee required for sending the message
public fun confirm_quote(
    self: &OApp,
    oapp_cap: &CallCap,
    call: Call<QuoteParam, MessagingFee>,
): (QuoteParam, MessagingFee) {
    self.assert_oapp_cap(oapp_cap);
    let (endpoint, param, fee) = call.destroy(oapp_cap);
    assert!(endpoint == endpoint!(), EOnlyEndpoint);
    (param, fee)
}

/// Sends a cross-chain message to a destination chain.
///
/// This function creates a call to send a message through the LayerZero protocol.
/// It requires payment of fees in native tokens (IOTA) and optionally ZRO tokens.
/// After the message is sent, use `confirm_lz_send()` to finalize the send operation
/// and retrieve the receipt and parameters.
///
/// **Note**: This function enforces sequential execution by tracking the sending state.
/// Only one send operation can be in progress at a time, and `confirm_lz_send()` must
/// be called to complete the operation before another send can be initiated.
///
/// **Parameters**
/// - `oapp_cap`: Call capability for authentication
/// - `dst_eid`: Destination endpoint ID (chain identifier)
/// - `message`: The message payload to be sent
/// - `options`: Execution options for the message (e.g., gas limits)
/// - `native_token_fee`: IOTA tokens for paying message fees
/// - `zro_token_fee`: Optional ZRO tokens for fee payment
/// - `refund_address`: Optional address to receive any excess fee refunds
///
/// **Returns**: A Call object that can be executed to send the message and get a MessagingReceipt
public fun lz_send(
    self: &mut OApp,
    oapp_cap: &CallCap,
    dst_eid: u32,
    message: vector<u8>,
    options: vector<u8>,
    native_token_fee: Coin<IOTA>,
    zro_token_fee: Option<Coin<ZRO>>,
    refund_address: Option<address>,
    ctx: &mut TxContext,
): Call<SendParam, MessagingReceipt> {
    self.assert_oapp_cap(oapp_cap);
    assert!(self.sending_call.is_none(), ESendingInProgress);
    assert!(refund_address.is_none() || *refund_address.borrow() != @0x0, EInvalidRefundAddress);

    let receiver = self.peer.get_peer(dst_eid);
    let send_param = endpoint_send::create_param(
        dst_eid,
        receiver,
        message,
        options,
        native_token_fee,
        zro_token_fee,
        refund_address,
    );
    let mut call = call::create(oapp_cap, endpoint!(), false, send_param, ctx);
    call.enable_mutable_param(oapp_cap);
    self.sending_call = option::some(call.id());
    call
}

/// Confirms and finalizes a message send operation.
///
/// This function must be called after executing a `Call` returned by `lz_send()`.
/// It performs final validation, resets the sending state, and extracts the send
/// parameters and receipt from the completed call. This two-step process ensures
/// proper state management and allows applications to handle the send result.
///
/// **Parameters**
/// - `oapp_cap`: Call capability for authentication (must belong to this OApp)
/// - `call`: The completed Call object from `lz_send()` execution
///
/// **Returns**:
/// A tuple containing:
/// - `SendParam`: The original send parameters used in the message
/// - `MessagingReceipt`: Receipt containing message details (nonce, hash, etc.)
public fun confirm_lz_send(
    self: &mut OApp,
    oapp_cap: &CallCap,
    call: Call<SendParam, MessagingReceipt>,
): (SendParam, MessagingReceipt) {
    self.assert_oapp_cap(oapp_cap);
    assert!(option::some(call.id()) == self.sending_call, EInvalidSendingCall);
    self.sending_call = option::none();

    let (_, param, receipt) = call.destroy(oapp_cap);
    (param, receipt)
}

/// Sends a cross-chain message with guaranteed refund capability.
///
/// This is similar to `lz_send()` but ensures that any excess fees will be refunded
/// by requiring a refund address and enabling the refund flag in the call.
/// Use this when you want to guarantee that excess fees are returned.
///
/// **Important**: Unlike `lz_send()`, this function does NOT enforce sequential execution.
/// When an OApp calls this function multiple times in one transaction, the returned Call objects
/// can be executed out of order by controlling their execution sequence in the programmable transaction block (PTB).
/// If you need to guarantee sequential execution of messages, use `lz_send()` + `confirm_lz_send()` instead.
///
/// **Parameters**
/// - `oapp_cap`: Call capability for authentication
/// - `dst_eid`: Destination endpoint ID (chain identifier)
/// - `message`: The message payload to be sent
/// - `options`: Execution options for the message (e.g., gas limits)
/// - `native_token_fee`: IOTA tokens for paying message fees
/// - `zro_token_fee`: Optional ZRO tokens for fee payment
/// - `refund_address`: Address to receive any excess fee refunds (required)
///
/// **Returns**:
/// A Call object that can be executed to send the message and get a MessagingReceipt
public fun lz_send_and_refund(
    self: &OApp,
    oapp_cap: &CallCap,
    dst_eid: u32,
    message: vector<u8>,
    options: vector<u8>,
    native_token_fee: Coin<IOTA>,
    zro_token_fee: Option<Coin<ZRO>>,
    refund_address: address,
    ctx: &mut TxContext,
): Call<SendParam, MessagingReceipt> {
    self.assert_oapp_cap(oapp_cap);
    assert!(refund_address != @0x0, EInvalidRefundAddress);
    let receiver = self.peer.get_peer(dst_eid);
    let send_param = endpoint_send::create_param(
        dst_eid,
        receiver,
        message,
        options,
        native_token_fee,
        zro_token_fee,
        option::some(refund_address),
    );
    let mut call = call::create(oapp_cap, endpoint!(), true, send_param, ctx);
    call.enable_mutable_param(oapp_cap);
    call
}

/// Receives and validates an incoming cross-chain message.
///
/// This function processes incoming messages from the LayerZero endpoint.
/// It performs several critical security checks:
/// 1. Validates the call capability belongs to this OApp
/// 2. Ensures the call originated from the LayerZero endpoint
/// 3. Verifies the message sender is a configured peer
///
/// After validation, it extracts and returns the message parameters for
/// the application to process.
///
/// **Parameters**
/// - `oapp_cap`: Call capability for authentication
/// - `call`: The incoming call from the LayerZero endpoint containing the message
///
/// **Returns**:
/// The validated LzReceiveParam containing the cross-chain message data
public fun lz_receive(self: &OApp, oapp_cap: &CallCap, call: Call<LzReceiveParam, Void>): LzReceiveParam {
    self.assert_oapp_cap(oapp_cap);

    // Ensure the call is from the endpoint
    assert!(call.caller() == endpoint!(), EOnlyEndpoint);

    // Ensure the callee is this OApp by completing the call
    let param = call.complete_and_destroy(oapp_cap);

    // Check the message is from a valid peer
    assert!(self.get_peer(param.src_eid()) == param.sender(), EOnlyPeer);
    param
}

// === Admin Config Functions ===

/// Sets enforced execution options for outbound messages to a specific destination.
///
/// Enforced options are mandatory execution parameters (like gas limits) that are
/// automatically applied to all outbound messages of a specific type to a destination chain.
/// These options are combined with any additional options provided during message sending.
///
/// **Parameters**
/// - `admin`: Admin capability for authorization
/// - `eid`: Destination endpoint ID (chain identifier)
/// - `msg_type`: Message type identifier (application-defined)
/// - `options`: Encoded execution options (gas limits, etc.)
public fun set_enforced_options(self: &mut OApp, admin: &AdminCap, eid: u32, msg_type: u16, options: vector<u8>) {
    self.assert_admin(admin);
    self.enforced_options.set_enforced_options(self.oapp_cap.id(), eid, msg_type, options);
}

/// Sets or updates a trusted peer for a destination chain.
///
/// Peers are trusted counterpart OApps on other chains that this OApp can
/// send messages to and receive messages from. This is a critical security
/// configuration - only messages from configured peers are accepted.
///
/// **Parameters**
/// - `admin`: Admin capability for authorization
/// - `eid`: Destination endpoint ID (chain identifier)
/// - `peer`: The address of the trusted peer OApp on the destination chain
public fun set_peer(
    self: &mut OApp,
    admin: &AdminCap,
    endpoint: &EndpointV2,
    messaging_channel: &mut MessagingChannel,
    eid: u32,
    peer: Bytes32,
    ctx: &mut TxContext,
) {
    self.assert_admin(admin);
    if (!endpoint_v2::is_channel_inited(messaging_channel, eid, peer)) {
        endpoint.init_channel(self.oapp_cap(), messaging_channel, eid, peer, ctx);
    };
    self.peer.set_peer(self.oapp_cap.id(), eid, peer);
}

// === View Functions ===

/// Returns the address of the admin capability.
public fun admin_cap(self: &OApp): address {
    self.admin_cap
}

/// Returns the CallCap's identifier for this OApp.
/// This serves as the OApp's unique contract identity in the LayerZero system.
public fun oapp_cap_id(self: &OApp): address {
    self.oapp_cap.id()
}

/// Combines enforced options with additional options for message execution.
public fun combine_options(self: &OApp, eid: u32, msg_type: u16, extra_options: vector<u8>): vector<u8> {
    self.enforced_options.combine_options(eid, msg_type, extra_options)
}

/// Gets the enforced options for a specific destination and message type.
public fun get_enforced_options(self: &OApp, eid: u32, msg_type: u16): &vector<u8> {
    self.enforced_options.get_enforced_options(eid, msg_type)
}

/// Checks if a peer is configured for a specific destination chain.
public fun has_peer(self: &OApp, eid: u32): bool {
    self.peer.has_peer(eid)
}

/// Gets the configured peer address for a specific destination chain.
public fun get_peer(self: &OApp, eid: u32): Bytes32 {
    self.peer.get_peer(eid)
}

/// Validates that an admin capability belongs to this OApp.
public fun assert_admin(self: &OApp, admin: &AdminCap) {
    assert!(object::id_address(admin) == self.admin_cap, EInvalidAdminCap);
}

/// Validates that a call capability belongs to this OApp.
public fun assert_oapp_cap(self: &OApp, oapp_cap: &CallCap) {
    assert!(oapp_cap.id() == self.oapp_cap_id(), EInvalidOAppCap);
}

// === Internal Functions ===

public(package) fun oapp_cap(self: &OApp): &CallCap {
    &self.oapp_cap
}

macro fun endpoint(): address {
    package::original_package_of_type<EndpointV2>()
}

// === Test Helper Functions ===

#[test_only]
public fun create_admin_cap_for_test(ctx: &mut TxContext): AdminCap {
    AdminCap { id: object::new(ctx) }
}

#[test_only]
public fun create_oapp_for_test(call_cap: &CallCap, admin_cap: &AdminCap, ctx: &mut TxContext): OApp {
    let oapp_cap = call_cap::new_package_cap_with_address_for_test(ctx, call_cap.id());
    OApp {
        id: object::new(ctx),
        oapp_cap,
        admin_cap: object::id_address(admin_cap),
        peer: oapp_peer::new(ctx),
        enforced_options: enforced_options::new(ctx),
        sending_call: option::none(),
    }
}

#[test_only]
public fun share_oapp_for_test(oapp: OApp) {
    transfer::share_object(oapp);
}
