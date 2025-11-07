/// Messaging Channel
///
/// This module manages message channels for OApps within the LayerZero V2 Endpoint.
/// Each OApp gets its own MessagingChannel shared object to enable parallel transaction
/// execution and maintain message state for cross-chain communication.
module endpoint_v2::messaging_channel;

use endpoint_v2::{
    endpoint_quote::QuoteParam as EndpointQuoteParam,
    endpoint_send::SendParam as EndpointSendParam,
    message_lib_quote::{Self, QuoteParam as MessageLibQuoteParam},
    message_lib_send::{Self, SendParam as MessageLibSendParam, SendResult as MessageLibSendResult},
    messaging_fee::MessagingFee,
    messaging_receipt::{Self, MessagingReceipt},
    outbound_packet,
    utils
};
use std::ascii::String;
use iota::{coin::{Self, Coin}, event, iota::IOTA, table::{Self, Table}};
use utils::{bytes32::{Self, Bytes32}, hash, table_ext};
use zro::zro::ZRO;

// === Errors ===

const EAlreadyInitialized: u64 = 1;
const EInsufficientNativeFee: u64 = 2;
const EInsufficientZroFee: u64 = 3;
const EInvalidNonce: u64 = 4;
const EInvalidOApp: u64 = 5;
const EInvalidPayloadHash: u64 = 6;
const ENotSending: u64 = 7;
const EPathNotVerifiable: u64 = 8;
const EPayloadHashNotFound: u64 = 9;
const ESendReentrancy: u64 = 10;
const EUninitializedChannel: u64 = 11;

// === Structs ===

/// Shared object that manages message channels for a specific OApp.
/// Each OApp gets its own MessagingChannel to enable parallel transaction execution.
public struct MessagingChannel has key {
    id: UID,
    // The OApp that owns this messaging channel
    oapp: address,
    // Maps (remote_eid, remote_oapp) -> Channel for each communication path
    channels: Table<ChannelKey, Channel>,
    // Prevents reentrancy when sending messages
    is_sending: bool,
}

/// Composite key identifying a specific channel path to a remote OApp.
public struct ChannelKey has copy, drop, store {
    remote_eid: u32,
    remote_oapp: Bytes32,
}

/// State for a specific channel path between local and remote OApps.
public struct Channel has store {
    // Nonce to use for outbound messages
    outbound_nonce: u64,
    // Highest nonce that has been cleared (executed)
    lazy_inbound_nonce: u64,
    // Maps nonce -> payload_hash for verified but unexecuted messages
    inbound_payload_hashes: Table<u64, Bytes32>,
}

// === Events ===

public struct ChannelInitializedEvent has copy, drop {
    local_oapp: address,
    remote_eid: u32,
    remote_oapp: Bytes32,
}

public struct PacketSentEvent has copy, drop {
    encoded_packet: vector<u8>,
    options: vector<u8>,
    send_library: address,
}

public struct PacketVerifiedEvent has copy, drop {
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    receiver: address,
    payload_hash: Bytes32,
}

public struct PacketDeliveredEvent has copy, drop {
    src_eid: u32,
    sender: Bytes32,
    receiver: address,
    nonce: u64,
}

public struct InboundNonceSkippedEvent has copy, drop {
    src_eid: u32,
    sender: Bytes32,
    receiver: address,
    nonce: u64,
}

public struct PacketNilifiedEvent has copy, drop {
    src_eid: u32,
    sender: Bytes32,
    receiver: address,
    nonce: u64,
    payload_hash: Bytes32,
}

public struct PacketBurntEvent has copy, drop {
    src_eid: u32,
    sender: Bytes32,
    receiver: address,
    nonce: u64,
    payload_hash: Bytes32,
}

public struct LzReceiveAlertEvent has copy, drop {
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
}

// === Creation ===

/// Creates a new MessagingChannel for an OApp and returns the channel's address.
/// Each OApp can create its own messaging channel once. The channel becomes
/// a public shared object to enable parallel transaction execution.
public(package) fun create(oapp: address, ctx: &mut TxContext): address {
    let messaging_channel = MessagingChannel {
        id: object::new(ctx),
        oapp,
        channels: table::new(ctx),
        is_sending: false,
    };
    let channel_address = object::id_address(&messaging_channel);
    transfer::share_object(messaging_channel);
    channel_address
}

// === Core Functions ===

/// Initializes a new channel for a remote OApp.
/// This must be called before sending/receiving messages on this path.
public(package) fun init_channel(
    self: &mut MessagingChannel,
    remote_eid: u32,
    remote_oapp: Bytes32,
    ctx: &mut TxContext,
) {
    assert!(!self.is_channel_inited(remote_eid, remote_oapp), EAlreadyInitialized);
    self
        .channels
        .add(
            ChannelKey { remote_eid, remote_oapp },
            Channel {
                outbound_nonce: 0,
                lazy_inbound_nonce: 0,
                inbound_payload_hashes: table::new(ctx),
            },
        );
    event::emit(ChannelInitializedEvent { local_oapp: self.oapp, remote_eid, remote_oapp });
}

/// Prepares quote parameters for message library fee estimation.
/// Uses the next outbound nonce to create a packet for quoting.
public(package) fun quote(self: &MessagingChannel, src_eid: u32, param: &EndpointQuoteParam): MessageLibQuoteParam {
    let dst_eid = param.dst_eid();
    let receiver = param.receiver();
    let outbound_nonce = self.channel(dst_eid, receiver).outbound_nonce + 1;
    let packet = outbound_packet::create(outbound_nonce, src_eid, self.oapp, dst_eid, receiver, *param.message());
    message_lib_quote::create_param(packet, *param.options(), param.pay_in_zro())
}

/// Prepares send parameters for sending a message.
/// Uses the next outbound nonce to create a packet for sending.
public(package) fun send(self: &mut MessagingChannel, src_eid: u32, param: &EndpointSendParam): MessageLibSendParam {
    // Prevents reentrancy when sending messages
    assert!(!self.is_sending, ESendReentrancy);
    self.is_sending = true;

    // Create packet and send parameters
    let dst_eid = param.dst_eid();
    let receiver = param.receiver();
    let outbound_nonce = self.channel(dst_eid, receiver).outbound_nonce + 1;
    let packet = outbound_packet::create(outbound_nonce, src_eid, self.oapp, dst_eid, receiver, *param.message());
    let quote_param = message_lib_quote::create_param(packet, *param.options(), param.pay_in_zro());
    message_lib_send::create_param(quote_param)
}

/// Confirms message send after the send library finished handling the message.
/// Increments outbound nonce, splits fees, and emits PacketSentEvent.
public(package) fun confirm_send(
    self: &mut MessagingChannel,
    send_library: address,
    endpoint_param: &mut EndpointSendParam,
    send_library_param: MessageLibSendParam,
    send_library_result: MessageLibSendResult,
    ctx: &mut TxContext,
): (MessagingReceipt, Coin<IOTA>, Coin<ZRO>) {
    // Reset sending flag
    assert!(self.is_sending, ENotSending);
    self.is_sending = false;

    // Increment outbound nonce and verify sequential ordering
    let packet = send_library_param.base().packet();
    let channel = self.channel_mut(packet.dst_eid(), packet.receiver());
    channel.outbound_nonce = channel.outbound_nonce + 1;
    assert!(channel.outbound_nonce == packet.nonce(), EInvalidNonce);

    // Split fees from the endpoint parameters
    let fee = send_library_result.fee();
    let (paid_native_token, paid_zro_token) = split_fee(endpoint_param, fee, ctx);

    event::emit(PacketSentEvent {
        encoded_packet: *send_library_result.encoded_packet(),
        options: *send_library_param.base().options(),
        send_library,
    });

    let receipt = messaging_receipt::create(packet.guid(), packet.nonce(), *fee);
    (receipt, paid_native_token, paid_zro_token)
}

/// Verifies an inbound packet by storing its payload hash.
/// Called by message libraries after successful packet verification.
public(package) fun verify(
    self: &mut MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    payload_hash: Bytes32,
) {
    // Check if the packet is new or re-verifiable
    assert!(self.verifiable(src_eid, sender, nonce), EPathNotVerifiable);
    assert!(!payload_hash.is_zero(), EInvalidPayloadHash);
    table_ext::upsert!(&mut self.channel_mut(src_eid, sender).inbound_payload_hashes, nonce, payload_hash);
    event::emit(PacketVerifiedEvent { src_eid, sender, nonce, receiver: self.oapp, payload_hash });
}

/// Skips the next expected inbound nonce without verifying.
/// Used to handle messages that should be bypassed (e.g., due to precrime alerts).
public(package) fun skip(self: &mut MessagingChannel, src_eid: u32, sender: Bytes32, nonce_to_skip: u64) {
    assert!(nonce_to_skip == self.inbound_nonce(src_eid, sender) + 1, EInvalidNonce);
    self.channel_mut(src_eid, sender).lazy_inbound_nonce = nonce_to_skip;
    event::emit(InboundNonceSkippedEvent { src_eid, sender, receiver: self.oapp, nonce: nonce_to_skip });
}

/// Marks a verified packet as undeliverable by setting its hash to 0xff.
/// This prevents the packet from being executed until the packet is re-verified.
public(package) fun nilify(
    self: &mut MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    payload_hash: Bytes32,
) {
    let channel = self.channel_mut(src_eid, sender);
    // Verify the provided hash matches what was stored during verification
    let stored_hash = table_ext::borrow_with_default!(&channel.inbound_payload_hashes, nonce, &bytes32::zero_bytes32());
    assert!(payload_hash == *stored_hash, EPayloadHashNotFound);
    assert!(nonce > channel.lazy_inbound_nonce || !stored_hash.is_zero(), EInvalidNonce);

    // Mark as nilified with 0xff hash to prevent execution
    table_ext::upsert!(&mut channel.inbound_payload_hashes, nonce, bytes32::ff_bytes32());
    event::emit(PacketNilifiedEvent { src_eid, sender, receiver: self.oapp, nonce, payload_hash });
}

/// Permanently removes a packet, making it unexecutable.
/// Can only be called on packets that have been verified and not executed yet.
public(package) fun burn(
    self: &mut MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    payload_hash: Bytes32,
) {
    let channel = self.channel_mut(src_eid, sender);
    assert!(nonce <= channel.lazy_inbound_nonce && channel.inbound_payload_hashes.contains(nonce), EInvalidNonce);

    // Verify hash matches and remove from storage
    let stored_hash = channel.inbound_payload_hashes.remove(nonce);
    assert!(payload_hash == stored_hash, EPayloadHashNotFound);
    event::emit(PacketBurntEvent { src_eid, sender, receiver: self.oapp, nonce, payload_hash });
}

/// Clears a payload and updates the lazy inbound nonce.
/// This function requires all packets up to this nonce to be verified before clearing.
public(package) fun clear_payload(
    self: &mut MessagingChannel,
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    payload: vector<u8>,
) {
    let channel = self.channel_mut(src_eid, sender);
    let current_nonce = channel.lazy_inbound_nonce;

    // Ensure all packets up to this nonce are verified before clearing
    if (nonce > current_nonce) {
        let mut i = current_nonce + 1;
        while (i <= nonce) {
            assert!(channel.inbound_payload_hashes.contains(i), EInvalidNonce);
            i = i + 1
        };
        // Update lazy nonce to mark messages as consecutively executed
        channel.lazy_inbound_nonce = nonce;
    };

    // Verify payload hash matches and remove from storage
    let expected_hash = table_ext::try_remove!(&mut channel.inbound_payload_hashes, nonce);
    let actual_hash = hash::keccak256!(&payload);
    assert!(option::some(actual_hash) == expected_hash, EPayloadHashNotFound);
    event::emit(PacketDeliveredEvent { src_eid, sender, nonce, receiver: self.oapp });
}

/// Emits an alert event when lz_receive execution fails.
/// Called by executors to log failed message execution attempts.
public(package) fun lz_receive_alert(
    executor: address,
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
    event::emit(LzReceiveAlertEvent {
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
    });
}

// === View Functions ===

/// Checks if a channel has been initialized for the given remote path.
public(package) fun is_channel_inited(self: &MessagingChannel, remote_eid: u32, remote_oapp: Bytes32): bool {
    self.channels.contains(ChannelKey { remote_eid, remote_oapp })
}

/// Returns the address of the OApp that owns this messaging channel.
public(package) fun oapp(self: &MessagingChannel): address {
    self.oapp
}

/// Returns whether the oapp is sending a message.
public(package) fun is_sending(self: &MessagingChannel): bool {
    self.is_sending
}

/// Computes the GUID for the next outbound message to the specified destination.
public(package) fun next_guid(self: &MessagingChannel, src_eid: u32, dst_eid: u32, receiver: Bytes32): Bytes32 {
    let next_nonce = self.outbound_nonce(dst_eid, receiver) + 1;
    utils::compute_guid(next_nonce, src_eid, bytes32::from_address(self.oapp), dst_eid, receiver)
}

/// Returns the current outbound nonce (last sent message nonce).
public(package) fun outbound_nonce(self: &MessagingChannel, dst_eid: u32, receiver: Bytes32): u64 {
    self.channel(dst_eid, receiver).outbound_nonce
}

/// Returns the lazy inbound nonce (highest consecutively executed nonce).
public(package) fun lazy_inbound_nonce(self: &MessagingChannel, src_eid: u32, sender: Bytes32): u64 {
    self.channel(src_eid, sender).lazy_inbound_nonce
}

/// Returns the actual inbound nonce (highest consecutive verified nonce).
/// This may be higher than lazy_inbound_nonce if messages are verified but not executed.
public(package) fun inbound_nonce(self: &MessagingChannel, src_eid: u32, sender: Bytes32): u64 {
    let channel = self.channel(src_eid, sender);
    let mut i = channel.lazy_inbound_nonce;
    loop {
        if (channel.inbound_payload_hashes.contains(i + 1)) {
            i = i + 1;
        } else {
            return i
        }
    }
}

/// Checks if a payload hash exists for the given nonce.
public(package) fun has_payload_hash(self: &MessagingChannel, src_eid: u32, sender: Bytes32, nonce: u64): bool {
    self.channel(src_eid, sender).inbound_payload_hashes.contains(nonce)
}

/// Gets the stored payload hash for a specific nonce.
public(package) fun get_payload_hash(self: &MessagingChannel, src_eid: u32, sender: Bytes32, nonce: u64): Bytes32 {
    *table_ext::borrow_or_abort!(&self.channel(src_eid, sender).inbound_payload_hashes, nonce, EPayloadHashNotFound)
}

/// Checks if a nonce can be verified:
/// 1. It's a new message (nonce > lazy_inbound_nonce) that can be verified for the first time
/// 2. It's an existing unexecuted message (has stored payload hash) that can be re-verified
public(package) fun verifiable(self: &MessagingChannel, src_eid: u32, sender: Bytes32, nonce: u64): bool {
    nonce > self.lazy_inbound_nonce(src_eid, sender) || self.has_payload_hash(src_eid, sender, nonce)
}

/// Asserts that the given OApp address owns this messaging channel.
/// Reverts if the OApp is not the owner.
public(package) fun assert_ownership(self: &MessagingChannel, oapp: address) {
    assert!(self.oapp == oapp, EInvalidOApp);
}

// === Internal Functions ===

/// Gets an immutable reference to a specific channel.
fun channel(self: &MessagingChannel, remote_eid: u32, remote_oapp: Bytes32): &Channel {
    let channel_key = ChannelKey { remote_eid, remote_oapp };
    table_ext::borrow_or_abort!(&self.channels, channel_key, EUninitializedChannel)
}

/// Gets a mutable reference to a specific channel.
fun channel_mut(self: &mut MessagingChannel, remote_eid: u32, remote_oapp: Bytes32): &mut Channel {
    let channel_key = ChannelKey { remote_eid, remote_oapp };
    table_ext::borrow_mut_or_abort!(&mut self.channels, channel_key, EUninitializedChannel)
}

/// Splits the required fees from the endpoint parameters and returns them as coins.
fun split_fee(endpoint_param: &mut EndpointSendParam, fee: &MessagingFee, ctx: &mut TxContext): (Coin<IOTA>, Coin<ZRO>) {
    // Extract native token fee
    let native_token = endpoint_param.native_token_mut();
    assert!(native_token.value() >= fee.native_fee(), EInsufficientNativeFee);
    let paid_native_token = native_token.split(fee.native_fee(), ctx);

    // Extract ZRO token fee (if required)
    let zro_token = endpoint_param.zro_token_mut();
    let paid_zro_token = if (fee.zro_fee() > 0) {
        assert!(zro_token.is_some() && zro_token.borrow().value() >= fee.zro_fee(), EInsufficientZroFee);
        zro_token.borrow_mut().split(fee.zro_fee(), ctx)
    } else {
        coin::zero<ZRO>(ctx)
    };
    (paid_native_token, paid_zro_token)
}

// === Test Only Functions ===

#[test_only]
public(package) fun create_channel_initialized_event(
    local_oapp: address,
    remote_eid: u32,
    remote_oapp: Bytes32,
): ChannelInitializedEvent {
    ChannelInitializedEvent { local_oapp, remote_eid, remote_oapp }
}

#[test_only]
public(package) fun create_packet_sent_event(
    encoded_packet: vector<u8>,
    send_library: address,
    options: vector<u8>,
): PacketSentEvent {
    PacketSentEvent { encoded_packet, send_library, options }
}

#[test_only]
public(package) fun create_packet_verified_event(
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    receiver: address,
    payload_hash: Bytes32,
): PacketVerifiedEvent {
    PacketVerifiedEvent { src_eid, sender, nonce, receiver, payload_hash }
}

#[test_only]
public(package) fun create_packet_delivered_event(
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    receiver: address,
): PacketDeliveredEvent {
    PacketDeliveredEvent { src_eid, sender, nonce, receiver }
}

#[test_only]
public(package) fun create_inbound_nonce_skipped_event(
    src_eid: u32,
    sender: Bytes32,
    receiver: address,
    nonce: u64,
): InboundNonceSkippedEvent {
    InboundNonceSkippedEvent { src_eid, sender, receiver, nonce }
}

#[test_only]
public(package) fun create_packet_nilified_event(
    src_eid: u32,
    sender: Bytes32,
    receiver: address,
    nonce: u64,
    payload_hash: Bytes32,
): PacketNilifiedEvent {
    PacketNilifiedEvent { src_eid, sender, receiver, nonce, payload_hash }
}

#[test_only]
public(package) fun create_packet_burnt_event(
    src_eid: u32,
    sender: Bytes32,
    receiver: address,
    nonce: u64,
    payload_hash: Bytes32,
): PacketBurntEvent {
    PacketBurntEvent { src_eid, sender, receiver, nonce, payload_hash }
}

#[test_only]
public(package) fun create_lz_receive_alert_event(
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
): LzReceiveAlertEvent {
    LzReceiveAlertEvent { receiver, executor, src_eid, sender, nonce, guid, gas, value, message, extra_data, reason }
}

#[test_only]
public(package) fun test_split_fee(
    endpoint_param: &mut EndpointSendParam,
    fee: &MessagingFee,
    ctx: &mut TxContext,
): (Coin<IOTA>, Coin<ZRO>) {
    split_fee(endpoint_param, fee, ctx)
}

#[test_only]
public fun get_encoded_packet_from_packet_sent_event(packet_sent_event: &PacketSentEvent): vector<u8> {
    packet_sent_event.encoded_packet
}

#[test_only]
public fun create_for_testing(oapp: address, ctx: &mut TxContext): address {
    create(oapp, ctx)
}
