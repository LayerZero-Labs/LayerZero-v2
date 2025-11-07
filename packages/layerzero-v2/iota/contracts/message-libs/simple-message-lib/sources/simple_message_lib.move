/// # Simple Message Library Module
///
/// A reference implementation of LayerZero V2's MessageLib interface providing basic
/// cross-chain messaging capabilities with configurable fee structures. This library
/// serves as both a functional message transport layer and a template for building
/// custom message libraries with enhanced features.
///
module simple_message_lib::simple_message_lib;

use call::{call::{Call, Void}, call_cap::{Self, CallCap}};
use endpoint_v2::{
    endpoint_send::SendParam as EndpointSendParam,
    endpoint_v2::EndpointV2,
    message_lib_quote::QuoteParam as MessageLibQuoteParam,
    message_lib_send::{Self, SendParam as MessageLibSendParam, SendResult as MessageLibSendResult},
    message_lib_set_config::SetConfigParam as MessageLibSetConfigParam,
    messaging_channel::MessagingChannel,
    messaging_fee::{Self, MessagingFee},
    messaging_receipt::MessagingReceipt,
    utils
};
use message_lib_common::packet_v1_codec;
use iota::clock::Clock;
use utils::{bytes32::Bytes32, package};

// === Error Codes ===

const ENotImplemented: u64 = 1;
const EZROFeeNotEnabled: u64 = 2;
const EInvalidEid: u64 = 3;

// === Structs ==

/// One-time witness for the simple message library.
public struct SIMPLE_MESSAGE_LIB has drop {}

public struct SimpleMessageLib has key {
    id: UID,
    call_cap: CallCap,
    endpoint: address,
    native_fee: u64,
    zro_fee: u64,
    fee_recipient: address,
}

public struct AdminCap has key, store {
    id: UID,
}

/// Initializes the SimpleMessageLib with default configuration values.
fun init(otw: SIMPLE_MESSAGE_LIB, ctx: &mut TxContext) {
    transfer::share_object(SimpleMessageLib {
        id: object::new(ctx),
        call_cap: call_cap::new_package_cap(&otw, ctx),
        endpoint: package::original_package_of_type<EndpointV2>(),
        native_fee: 100, // default native fee
        zro_fee: 99, // default zro fee
        fee_recipient: tx_context::sender(ctx),
    });
    transfer::transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
}

// === Call From Endpoint(by ptb) ===

/// Processes fee quote requests from LayerZero V2 endpoints.
///
/// This function implements step 2-3 of the LayerZero V2 quote flow:
/// 1. Validates ZRO fee payment eligibility based on current configuration
/// 2. Calculates appropriate fee (native + optional ZRO) based on payment method
/// 3. Completes the message lib quote call with calculated fees
///
/// # Flow Integration
/// Called by endpoints during cross-chain message fee estimation.
public fun quote(self: &SimpleMessageLib, call: &mut Call<MessageLibQuoteParam, MessagingFee>) {
    call.assert_caller(self.endpoint);

    // Step 2/3 of quote flow: Complete the quote call with fee information
    let pay_in_zro = call.param().pay_in_zro();
    self.validate_zro_fee_payment(pay_in_zro);
    let zro_fee = if (pay_in_zro) self.zro_fee else 0;
    call.complete(&self.call_cap, messaging_fee::create(self.native_fee, zro_fee));
}

/// Processes cross-chain message send requests from LayerZero V2 endpoints.
///
/// This function implements step 2-3 of the LayerZero V2 send flow:
/// 1. Validates ZRO fee payment and calculates total fees
/// 2. Encodes the outbound packet using V1 packet codec
/// 3. Completes the message lib send call with encoded packet and fee info
/// 4. Confirms the send with endpoint and receives fee payments
/// 5. Transfers collected fees to the designated fee recipient
///
/// # Flow Integration
/// Called by endpoints during actual cross-chain message transmission.
public fun send(
    self: &SimpleMessageLib,
    endpoint: &EndpointV2,
    messaging_channel: &mut MessagingChannel,
    endpoint_call: &mut Call<EndpointSendParam, MessagingReceipt>,
    mut message_lib_call: Call<MessageLibSendParam, MessageLibSendResult>,
    ctx: &mut TxContext,
) {
    message_lib_call.assert_caller(self.endpoint);

    // Step 2/4 of send flow: Complete the send call with fee information
    let pay_in_zro = message_lib_call.param().base().pay_in_zro();
    self.validate_zro_fee_payment(pay_in_zro);
    let zro_fee = if (pay_in_zro) self.zro_fee else 0;

    // Complete the call with fee information
    let fee = messaging_fee::create(self.native_fee, zro_fee);
    let encoded_packet = packet_v1_codec::encode_packet(message_lib_call.param().base().packet());
    message_lib_call.complete(&self.call_cap, message_lib_send::create_result(encoded_packet, fee));

    // Step 3/4 of send flow: Confirm the send call with the endpoint. This can be done by directly call or via ptb.
    let (paid_native_token, paid_zro_token) = endpoint.confirm_send(
        &self.call_cap,
        messaging_channel,
        endpoint_call,
        message_lib_call,
        ctx,
    );

    // Pay fees to fee recipient
    utils::transfer_coin(paid_native_token, self.fee_recipient);
    utils::transfer_coin(paid_zro_token, self.fee_recipient);
}

/// Handles configuration update requests from LayerZero V2 endpoints.
///
/// **Note**: This function is intentionally not implemented in SimpleMessageLib
/// as it focuses on basic messaging without advanced configuration options.
/// Custom message libraries can override this to support dynamic configuration.
///
/// # Error
/// Always aborts with `ENotImplemented` error code.
public fun set_config(_self: &SimpleMessageLib, _call: Call<MessageLibSetConfigParam, Void>) {
    abort ENotImplemented
}

// === Admin Functions ===

/// Updates the messaging fee configuration for both native and ZRO token payments.
///
/// This administrative function allows fee adjustments to respond to network
/// conditions, token price changes, or operational requirements.
///
/// # Parameters
/// - `_admin`: Admin capability proving authorization (consumed for access control)
/// - `zro_fee`: New ZRO token fee amount (set to 0 to disable ZRO payments)
/// - `native_fee`: New native IOTA token fee amount
///
/// # Access Control
/// Requires valid AdminCap - only callable by authorized administrators.
public fun set_messaging_fee(self: &mut SimpleMessageLib, _admin: &AdminCap, zro_fee: u64, native_fee: u64) {
    self.zro_fee = zro_fee;
    self.native_fee = native_fee;
}

/// Updates the address that receives collected messaging fees.
///
/// # Parameters
/// - `_admin`: Admin capability proving authorization (consumed for access control)
/// - `fee_recipient`: New address to receive all collected messaging fees
///
/// # Access Control
/// Requires valid AdminCap - only callable by authorized administrators.
public fun set_fee_recipient(self: &mut SimpleMessageLib, _admin: &AdminCap, fee_recipient: address) {
    self.fee_recipient = fee_recipient;
}

// === Endpoint Validation ===

/// Validates and commits inbound cross-chain packets to the messaging channel.
///
/// # Parameters
/// - `_admin`: Admin capability proving authorization (consumed for access control)
/// - `messaging_channel`: Mutable reference to commit verified packets
/// - `packet_header`: Raw bytes of the packet header to validate
/// - `payload_hash`: Hash of the packet payload for integrity verification
/// - `clock`: Clock reference for timestamp-based validations
///
/// # Access Control
/// Requires valid AdminCap - typically called by authorized relayer infrastructure.
public fun validate_packet(
    self: &SimpleMessageLib,
    endpoint: &EndpointV2,
    _admin: &AdminCap,
    messaging_channel: &mut MessagingChannel,
    packet_header: vector<u8>,
    payload_hash: Bytes32,
    clock: &Clock,
) {
    let header = packet_v1_codec::decode_header(packet_header);
    assert!(header.dst_eid() == endpoint.eid(), EInvalidEid);
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

// === View Functions ===

/// Returns the current native IOTA token fee for cross-chain messaging.
public fun get_native_fee(self: &SimpleMessageLib): u64 {
    self.native_fee
}

/// Returns the current ZRO token fee for cross-chain messaging.
public fun get_zro_fee(self: &SimpleMessageLib): u64 {
    self.zro_fee
}

/// Returns the address that receives all collected messaging fees.
public fun get_fee_recipient(self: &SimpleMessageLib): address {
    self.fee_recipient
}

/// Returns version information for LayerZero V2 compatibility checking.
public fun version(): (u64, u8, u8) {
    (0, 0, 2) // major, minor, endpoint_version
}

// === Internal Helpers ===

/// Internal helper to validate ZRO token payment requests.
///
/// Ensures that ZRO payments are only accepted when a non-zero ZRO fee is configured.
/// This prevents users from attempting ZRO payments when the feature is disabled.
///
/// # Parameters
/// - `pay_in_zro`: Whether the user requested to pay in ZRO tokens
///
/// # Errors
/// Aborts with `EZROFeeNotEnabled` if ZRO payment is requested but ZRO fee is 0.
fun validate_zro_fee_payment(self: &SimpleMessageLib, pay_in_zro: bool) {
    assert!(!pay_in_zro || self.zro_fee > 0, EZROFeeNotEnabled);
}

// === Test Functions ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    transfer::share_object(SimpleMessageLib {
        id: object::new(ctx),
        call_cap: call_cap::new_package_cap_for_test(ctx),
        endpoint: package::original_package_of_type<EndpointV2>(),
        native_fee: 100, // default native fee
        zro_fee: 99, // default zro fee
        fee_recipient: tx_context::sender(ctx),
    });
    transfer::transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
}

#[test_only]
public fun borrow_call_cap(self: &SimpleMessageLib): &CallCap {
    &self.call_cap
}
