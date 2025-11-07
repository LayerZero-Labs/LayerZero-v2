/// Module for handling lz_receive parameters from Endpoint calling OApp.
///
/// This module defines the LzReceiveParam struct which encapsulates all necessary
/// information required for receiving cross-chain messages. Receive operations
/// are triggered when messages arrive from other chains and need to be processed
/// by the destination OApp.
module endpoint_v2::lz_receive;

use iota::{coin::Coin, iota::IOTA};
use utils::bytes32::Bytes32;

// === Structs ===

/// Parameters required for receiving cross-chain messages.
///
/// This struct contains all information needed to process an incoming cross-chain
/// message. Like SendParam, it uses the hot-potato pattern due to containing coins
/// that must be properly handled.
#[allow(lint(coin_field))]
public struct LzReceiveParam {
    // Source endpoint ID - identifies the origin blockchain
    src_eid: u32,
    // Address of the message sender on the source chain
    sender: Bytes32,
    // Nonce for message ordering and replay protection
    nonce: u64,
    // Global unique identifier for the cross-chain message
    guid: Bytes32,
    // The received message payload to be processed
    message: vector<u8>,
    // Address of the executor delivering the message
    executor: address,
    // Additional data for message execution
    extra_data: vector<u8>,
    // Optional IOTA tokens provided by the executor to the receiver
    value: Option<Coin<IOTA>>,
}

// === Creation ===

/// Creates a new LzReceiveParam instance with the specified receive parameters.
public(package) fun create_param(
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    guid: Bytes32,
    message: vector<u8>,
    executor: address,
    extra_data: vector<u8>,
    value: Option<Coin<IOTA>>,
): LzReceiveParam {
    LzReceiveParam { src_eid, sender, nonce, guid, message, executor, extra_data, value }
}

// === Destruction ===

/// Destroys the LzReceiveParam and returns all contained data and coins.
public fun destroy(
    self: LzReceiveParam,
): (u32, Bytes32, u64, Bytes32, vector<u8>, address, vector<u8>, Option<Coin<IOTA>>) {
    let LzReceiveParam { src_eid, sender, nonce, guid, message, executor, extra_data, value } = self;
    (src_eid, sender, nonce, guid, message, executor, extra_data, value)
}

// === Getters ===

/// Returns the source endpoint ID where the message originated.
public fun src_eid(self: &LzReceiveParam): u32 {
    self.src_eid
}

/// Returns the address of the message sender on the source chain.
public fun sender(self: &LzReceiveParam): Bytes32 {
    self.sender
}

/// Returns the nonce for message ordering and replay protection.
public fun nonce(self: &LzReceiveParam): u64 {
    self.nonce
}

/// Returns the global unique identifier for the cross-chain message.
public fun guid(self: &LzReceiveParam): Bytes32 {
    self.guid
}

/// Returns a reference to the received message payload.
public fun message(self: &LzReceiveParam): &vector<u8> {
    &self.message
}

/// Returns the address of the executor delivering the message.
public fun executor(self: &LzReceiveParam): address {
    self.executor
}

/// Returns a reference to the additional execution data.
public fun extra_data(self: &LzReceiveParam): &vector<u8> {
    &self.extra_data
}

/// Returns a reference to the optional IOTA tokens provided by executor.
public fun value(self: &LzReceiveParam): &Option<Coin<IOTA>> {
    &self.value
}

// === Test Only ===

#[test_only]
public fun create_param_for_test(
    src_eid: u32,
    sender: Bytes32,
    nonce: u64,
    guid: Bytes32,
    message: vector<u8>,
    executor: address,
    extra_data: vector<u8>,
    value: Option<Coin<IOTA>>,
): LzReceiveParam {
    create_param(src_eid, sender, nonce, guid, message, executor, extra_data, value)
}
