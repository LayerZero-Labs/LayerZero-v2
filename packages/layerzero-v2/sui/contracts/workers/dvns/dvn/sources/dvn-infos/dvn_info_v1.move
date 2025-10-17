/// DVN Information Module
///
/// This module provides data structures and functionality for managing DVN (Decentralized Verifier Network)
/// metadata.
module dvn::dvn_info_v1;

use sui::bcs;
use utils::{buffer_reader, buffer_writer};

// === Constants ===

/// Version identifier for DVN info encoding format.
const DVN_INFO_VERSION: u16 = 1;

// === Errors ===

const EInvalidData: u64 = 1;
const EInvalidVersion: u64 = 2;

// === Structs ===

/// DVN configuration container that stores essential DVN metadata.
public struct DVNInfoV1 has copy, drop, store {
    /// Object ID address of the DVN instance
    dvn_object: address,
}

// === Creation Functions ===

/// Creates a new DVNInfoV1 instance with the provided DVN object ID.
///
/// **Parameters**:
/// - `dvn_object`: Object ID address of the DVN instance
///
/// **Returns**: Configured DVNInfoV1 instance
public fun create(dvn_object: address): DVNInfoV1 {
    DVNInfoV1 { dvn_object }
}

// === View Functions ===

/// Returns the DVN object ID address.
public fun dvn_object(self: &DVNInfoV1): address {
    self.dvn_object
}

// === Serialization Functions ===

/// Encodes DVNInfoV1 into a versioned byte vector for storage or transmission.
/// The encoding format is: [version: u16][BCS serialized DVNInfoV1 data]
///
/// **Parameters**:
/// - `self`: DVNInfoV1 instance to encode
///
/// **Returns**: Byte vector containing version header and BCS-encoded data
public fun encode(self: &DVNInfoV1): vector<u8> {
    let mut writer = buffer_writer::new();
    writer.write_u16(DVN_INFO_VERSION).write_bytes(bcs::to_bytes(self));
    writer.to_bytes()
}

/// Decodes a versioned byte vector back into a DVNInfoV1 struct.
/// Validates the version header and deserializes the BCS data.
///
/// **Parameters**:
/// - `dvn_info`: Byte vector containing version header and BCS-encoded data
///
/// **Returns**: Decoded DVNInfoV1 instance
public fun decode(dvn_info: vector<u8>): DVNInfoV1 {
    let mut reader = buffer_reader::create(dvn_info);

    // Extract and validate version header
    let version = reader.read_u16();
    assert!(version == DVN_INFO_VERSION, EInvalidVersion);

    // Extract BCS payload and initialize BCS reader
    let dvn_info_bytes = reader.read_bytes_until_end();
    let mut bcs_reader = bcs::new(dvn_info_bytes);

    // Deserialize struct fields in declaration order
    let dvn_object = bcs_reader.peel_address();

    // Verify complete deserialization (no trailing bytes)
    assert!(bcs_reader.into_remainder_bytes().is_empty(), EInvalidData);

    DVNInfoV1 { dvn_object }
}
