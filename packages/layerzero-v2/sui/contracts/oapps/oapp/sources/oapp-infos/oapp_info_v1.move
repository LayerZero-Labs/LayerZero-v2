/// OApp Information Module
///
/// This module provides data structures and functionality for managing OApp (Omnichain Application)
/// configuration information and metadata. It handles the serialization, deserialization, and
/// registration of OApp details with LayerZero v2 endpoints.
module oapp::oapp_info_v1;

use sui::bcs;
use utils::{buffer_reader, buffer_writer};

// === Constants ===

/// Version identifier for OApp info encoding format stored in endpoint.oapp_info.
/// - **Version 1**: Store complete serialized OAppInfo structure containing oapp_object, next_nonce_info,
/// lz_receive_info, extra_info.
const INFO_VERSION: u16 = 1;

// === Errors ===

const EInvalidData: u64 = 1;
const EInvalidVersion: u64 = 2;

/// OApp info struct that stores essential OApp metadata.
public struct OAppInfoV1 has copy, drop, store {
    /// Object ID address of the OApp instance
    oapp_object: address,
    /// Used to populate the MoveCalls to fetch the next nonce that can be executed by executor in order
    next_nonce_info: vector<u8>,
    /// Used to populate the MoveCalls to execute lz_receive by executor
    lz_receive_info: vector<u8>,
    /// Additional configuration data for custom OApp functionality
    extra_info: vector<u8>,
}

// === Creation Functions ===

/// Creates a new OAppInfoV1 instance with the provided configuration.
///
/// **Parameters**:
/// - `oapp_object`: Object ID address of the OApp instance
/// - `next_nonce_info`: Used to populate the MoveCalls to fetch the next nonce that can be executed by executor in
/// order
/// - `lz_receive_info`: Serialized execution data for incoming LayerZero messages
/// - `extra_info`: Additional configuration data for custom functionality
///
/// **Returns**: Configured OAppInfoV1 instance
public fun create(
    oapp_object: address,
    next_nonce_info: vector<u8>,
    lz_receive_info: vector<u8>,
    extra_info: vector<u8>,
): OAppInfoV1 {
    OAppInfoV1 { oapp_object, next_nonce_info, lz_receive_info, extra_info }
}

// === View Functions ===

/// Returns the OApp object ID address.
public fun oapp_object(self: &OAppInfoV1): address {
    self.oapp_object
}

/// Returns the next nonce information data.
public fun next_nonce_info(self: &OAppInfoV1): &vector<u8> {
    &self.next_nonce_info
}

/// Returns the LayerZero receive information data.
public fun lz_receive_info(self: &OAppInfoV1): &vector<u8> {
    &self.lz_receive_info
}

/// Returns the extra configuration information data.
public fun extra_info(self: &OAppInfoV1): &vector<u8> {
    &self.extra_info
}

// === Serialization Functions ===

/// Encodes OAppInfoV1 into a versioned byte vector for storage or transmission.
/// The encoding format is: [version: u16][BCS serialized OAppInfoV1 data]
///
/// **Parameters**:
/// - `oapp_info`: OAppInfoV1 instance to encode
///
/// **Returns**: Byte vector containing version header and BCS-encoded data
public fun encode(self: &OAppInfoV1): vector<u8> {
    let oapp_info_bytes = bcs::to_bytes(self);
    let mut writer = buffer_writer::new();
    writer.write_u16(INFO_VERSION).write_bytes(oapp_info_bytes);
    writer.to_bytes()
}

/// Decodes a versioned byte vector back into an OAppInfoV1 struct.
/// Validates the version header and deserializes the BCS data.
///
/// **Parameters**:
/// - `bytes`: Byte vector containing version header and BCS-encoded data
///
/// **Returns**: Decoded OAppInfoV1 instance
public fun decode(bytes: vector<u8>): OAppInfoV1 {
    let mut reader = buffer_reader::create(bytes);

    // Extract and validate version header
    let version = reader.read_u16();
    assert!(version == INFO_VERSION, EInvalidVersion);

    // Extract BCS payload and initialize BCS reader
    let oapp_info_bytes = reader.read_bytes_until_end();
    let mut bcs_reader = bcs::new(oapp_info_bytes);

    // Deserialize struct fields in declaration order
    let oapp_object = bcs_reader.peel_address();
    let next_nonce_info = bcs_reader.peel_vec_u8();
    let lz_receive_info = bcs_reader.peel_vec_u8();
    let extra_info = bcs_reader.peel_vec_u8();

    // Verify complete deserialization (no trailing bytes)
    assert!(bcs_reader.into_remainder_bytes().is_empty(), EInvalidData);

    OAppInfoV1 { oapp_object, next_nonce_info, lz_receive_info, extra_info }
}

// === Test Helper Functions ===

#[test_only]
/// Creates an OAppInfoV1 instance for testing purposes.
/// Bypasses normal validation and initialization flow.
public(package) fun create_test_oapp_info(
    oapp_object: address,
    lz_receive_info: vector<u8>,
    next_nonce_info: vector<u8>,
    extra_info: vector<u8>,
): OAppInfoV1 {
    OAppInfoV1 { oapp_object, next_nonce_info, lz_receive_info, extra_info }
}

#[test_only]
/// Exposes the encode function for testing codec functionality.
public(package) fun encode_for_test(oapp_info: &OAppInfoV1): vector<u8> {
    encode(oapp_info)
}
