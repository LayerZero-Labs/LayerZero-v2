/// Executor Config Module
///
/// This module provides configuration management for message executors in the ULN.
/// It handles executor address configuration and maximum message size limits for cross-chain
/// message execution.
module uln_302::executor_config;

use sui::bcs;

// === Errors ===

const EInvalidExecutorAddress: u64 = 1;
const EInvalidExecutorBytes: u64 = 2;
const EZeroMessageSize: u64 = 3;

// === Structs ===

/// Configuration struct for message executors.
public struct ExecutorConfig has copy, drop, store {
    // Maximum size of messages that can be executed (in bytes)
    max_message_size: u64,
    // Address of the executor contract responsible for message execution
    executor: address,
}

// === Creation ===

/// Creates a new ExecutorConfig with default empty values.
public fun new(): ExecutorConfig {
    ExecutorConfig { max_message_size: 0, executor: @0x0 }
}

/// Creates a new ExecutorConfig with the specified parameters.
public fun create(max_message_size: u64, executor: address): ExecutorConfig {
    ExecutorConfig { max_message_size, executor }
}

// === Getters ===

/// Returns the maximum message size allowed for this executor configuration.
public fun max_message_size(config: &ExecutorConfig): u64 {
    config.max_message_size
}

/// Returns the executor address for this configuration.
public fun executor(config: &ExecutorConfig): address {
    config.executor
}

// === Deserialization ===

/// Deserializes an ExecutorConfig from BCS-encoded bytes.
///
/// The expected byte format is:
/// 1. max_message_size (u64) - 8 bytes
/// 2. executor (address) - variable length
public fun deserialize(config_bytes: vector<u8>): ExecutorConfig {
    let mut bcs = bcs::new(config_bytes);
    let max_message_size = bcs.peel_u64();
    let executor = bcs.peel_address();
    assert!(bcs.into_remainder_bytes().length() == 0, EInvalidExecutorBytes);
    create(max_message_size, executor)
}

// === Validation Functions ===

/// Validates an ExecutorConfig for use as a default configuration.
///
/// Checks:
/// - Maximum message size is greater than 0
/// - Executor address is not the zero address
public fun assert_default_config(config: &ExecutorConfig) {
    assert!(config.max_message_size != 0, EZeroMessageSize);
    assert!(config.executor != @0x0, EInvalidExecutorAddress);
}

/// Merges application-specific config with default config to get effective configuration.
///
/// Uses oapp_config values when they are non-zero/non-null, otherwise falls back
/// to default_config values. This allows applications to override specific settings
/// while inheriting defaults for unspecified values.
public fun get_effective_executor_config(
    oapp_config: &ExecutorConfig,
    default_config: &ExecutorConfig,
): ExecutorConfig {
    let max_message_size = if (oapp_config.max_message_size != 0) {
        oapp_config.max_message_size
    } else {
        default_config.max_message_size
    };
    let executor = if (oapp_config.executor != @0x0) oapp_config.executor else default_config.executor;
    create(max_message_size, executor)
}
