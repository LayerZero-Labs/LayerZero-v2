/// Module for handling lz_compose parameters from Endpoint calling Composer.
///
/// This module defines the LzComposeParam struct which encapsulates all necessary
/// information required for composing cross-chain messages. Compose operations
/// allow complex multi-step workflows where a received message can trigger
/// additional actions.
module endpoint_v2::lz_compose;

use sui::{coin::Coin, sui::SUI};
use utils::bytes32::Bytes32;

// === Structs ===

/// Parameters required for composing cross-chain messages.
///
/// This struct contains all information needed to execute a compose operation.
/// Like SendParam, it uses the hot-potato pattern due to containing coins
/// that must be properly handled.
#[allow(lint(coin_field))]
public struct LzComposeParam {
    // Address of the message sender that initiated the compose operation
    from: address,
    // Global unique identifier for the cross-chain message
    guid: Bytes32,
    // The compose message payload to be processed
    message: vector<u8>,
    // Address of the executor executing the compose operation
    executor: address,
    // Additional data for compose execution
    extra_data: vector<u8>,
    // Optional SUI tokens provided by the executor to the composer
    value: Option<Coin<SUI>>,
}

// === Creation ===

/// Creates a new LzComposeParam instance with the specified compose parameters.
public(package) fun create_param(
    from: address,
    guid: Bytes32,
    message: vector<u8>,
    executor: address,
    extra_data: vector<u8>,
    value: Option<Coin<SUI>>,
): LzComposeParam {
    LzComposeParam { from, guid, message, executor, extra_data, value }
}

// === Destruction ===

/// Destroys the LzComposeParam and returns all contained data and coins.
public fun destroy(self: LzComposeParam): (address, Bytes32, vector<u8>, address, vector<u8>, Option<Coin<SUI>>) {
    let LzComposeParam { from, guid, message, executor, extra_data, value } = self;
    (from, guid, message, executor, extra_data, value)
}

// === Getters ===

/// Returns the address of the message sender that initiated the compose.
public fun from(self: &LzComposeParam): address {
    self.from
}

/// Returns the global unique identifier for the cross-chain message.
public fun guid(self: &LzComposeParam): Bytes32 {
    self.guid
}

/// Returns a reference to the compose message payload.
public fun message(self: &LzComposeParam): &vector<u8> {
    &self.message
}

/// Returns the address of the executor executing the compose operation.
public fun executor(self: &LzComposeParam): address {
    self.executor
}

/// Returns a reference to the additional execution data.
public fun extra_data(self: &LzComposeParam): &vector<u8> {
    &self.extra_data
}

/// Returns a reference to the optional SUI tokens for execution.
public fun value(self: &LzComposeParam): &Option<Coin<SUI>> {
    &self.value
}

// === Test Only ===

#[test_only]
public fun create_param_for_test(
    from: address,
    guid: Bytes32,
    message: vector<u8>,
    executor: address,
    extra_data: vector<u8>,
    value: Option<Coin<SUI>>,
): LzComposeParam {
    create_param(from, guid, message, executor, extra_data, value)
}
