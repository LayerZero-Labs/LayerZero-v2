/// Executor Information Module
///
/// This module provides data structures and functionality for managing Executor
/// metadata.
module executor::executor_info_v1;

use iota::bcs;
use utils::{buffer_reader, buffer_writer};

// === Constants ===

/// Version identifier for Executor info encoding format.
const EXECUTOR_INFO_VERSION: u16 = 1;

// === Errors ===

const EInvalidData: u64 = 1;
const EInvalidVersion: u64 = 2;

// === Structs ===

/// Executor configuration container that stores essential Executor metadata.
public struct ExecutorInfoV1 has copy, drop, store {
    /// Object ID address of the Executor instance
    executor_object: address,
}

// === Creation Functions ===

/// Creates a new ExecutorInfoV1 instance with the provided Executor object ID.
///
/// **Parameters**:
/// - `executor_object`: Object ID address of the Executor instance
///
/// **Returns**: Configured ExecutorInfoV1 instance
public fun create(executor_object: address): ExecutorInfoV1 {
    ExecutorInfoV1 { executor_object }
}

// === View Functions ===

/// Returns the Executor object ID address.
public fun executor_object(self: &ExecutorInfoV1): address {
    self.executor_object
}

// === Serialization Functions ===

/// Encodes ExecutorInfoV1 into a versioned byte vector for storage or transmission.
/// The encoding format is: [version: u16][BCS serialized ExecutorInfoV1 data]
///
/// **Parameters**:
/// - `self`: ExecutorInfoV1 instance to encode
///
/// **Returns**: Byte vector containing version header and BCS-encoded data
public fun encode(self: &ExecutorInfoV1): vector<u8> {
    let mut writer = buffer_writer::new();
    writer.write_u16(EXECUTOR_INFO_VERSION).write_bytes(bcs::to_bytes(self));
    writer.to_bytes()
}

/// Decodes a versioned byte vector back into an ExecutorInfoV1 struct.
/// Validates the version header and deserializes the BCS data.
///
/// **Parameters**:
/// - `executor_info`: Byte vector containing version header and BCS-encoded data
///
/// **Returns**: Decoded ExecutorInfoV1 instance
public fun decode(executor_info: vector<u8>): ExecutorInfoV1 {
    let mut reader = buffer_reader::create(executor_info);

    // Extract and validate version header
    let version = reader.read_u16();
    assert!(version == EXECUTOR_INFO_VERSION, EInvalidVersion);

    // Extract BCS payload and initialize BCS reader
    let executor_info_bytes = reader.read_bytes_until_end();
    let mut bcs_reader = bcs::new(executor_info_bytes);

    // Deserialize struct fields in declaration order
    let executor_object = bcs_reader.peel_address();

    // Verify complete deserialization (no trailing bytes)
    assert!(bcs_reader.into_remainder_bytes().is_empty(), EInvalidData);

    ExecutorInfoV1 { executor_object }
}
