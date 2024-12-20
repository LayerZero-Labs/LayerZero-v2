/// This module contains the serialization and deserialization logic for handling Executor configurations
///
/// The serialized format is as follows:
/// [max_message_size: u32]
/// [executor_address: bytes32]
module msglib_types::configs_executor {
    use endpoint_v2_common::serde::{append_address, append_u32, extract_address, extract_u32};

    struct ExecutorConfig has drop, copy, store {
        max_message_size: u32,
        executor_address: address,
    }

    public fun new_executor_config(max_message_size: u32, executor_address: address): ExecutorConfig {
        ExecutorConfig { max_message_size, executor_address }
    }

    // =================================================== Accessors ==================================================

    public fun get_max_message_size(self: &ExecutorConfig): u32 { self.max_message_size }

    public fun get_executor_address(self: &ExecutorConfig): address { self.executor_address }

    // ======================================== Serialization / Deserialization =======================================

    public fun append_executor_config(bytes: &mut vector<u8>, config: ExecutorConfig) {
        append_u32(bytes, config.max_message_size);
        append_address(bytes, config.executor_address);
    }

    public fun extract_executor_config(bytes: &vector<u8>, position: &mut u64): ExecutorConfig {
        let max_message_size = extract_u32(bytes, position);
        let executor_address = extract_address(bytes, position);
        ExecutorConfig { max_message_size, executor_address }
    }
}