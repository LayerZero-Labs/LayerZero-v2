/// OFT Info Module
///
/// This module defines the OFTInfo struct and related functions for encoding and decoding
/// OFT (Omnichain Fungible Token) metadata. The OFTInfo is used to carry essential
/// information about an OFT instance during cross-chain operations and endpoint registration.
///
/// The primary use case is to provide the LayerZero endpoint with information about
/// the OFT object address for proper message routing and execution context.
module oft::oft_info_v1;

use sui::bcs;
use utils::{buffer_reader, buffer_writer};

// === Constants ===

/// Version identifier for OFT info encoding format stored in oapp_info_v1.extra_info.
/// - **Version 1**: Extended `oapp_info_v1.extra_info` to store complete OFTInfo structure
///   containing oft_object.
const INFO_VERSION: u16 = 1;

// === Errors ===

const EInvalidData: u64 = 1;
const EInvalidVersion: u64 = 2;

// === Structs ===

/// Container for OFT metadata used in cross-chain operations.
public struct OFTInfoV1 has copy, drop, store {
    /// Address of the latest OFT package.
    /// This may differ from the original package address if the OFT has been
    /// migrated or upgraded to a new package version.
    oft_package: address,
    /// Address of the OFT object instance
    oft_object: address,
}

// === Creation Functions ===

/// Creates a new OFTInfoV1 instance with the specified OFT object address.
public fun create(oft_package: address, oft_object: address): OFTInfoV1 {
    OFTInfoV1 { oft_package, oft_object }
}

// === View Functions ===

/// Returns the OFT latest package address
public fun oft_package(self: &OFTInfoV1): address {
    self.oft_package
}

/// Returns the OFT object address
public fun oft_object(self: &OFTInfoV1): address {
    self.oft_object
}

// === Serialization Functions ===

/// Encodes OFTInfoV1 into a byte vector for cross-chain transmission.
public fun encode(self: &OFTInfoV1): vector<u8> {
    let mut writer = buffer_writer::new();
    writer.write_u16(INFO_VERSION).write_bytes(bcs::to_bytes(self));
    writer.to_bytes()
}

/// Decodes a byte vector back into an OFTInfoV1 struct.
public fun decode(bytes: vector<u8>): OFTInfoV1 {
    let mut reader = buffer_reader::create(bytes);

    let version = reader.read_u16();
    assert!(version == INFO_VERSION, EInvalidVersion);

    let oft_info_bytes = reader.read_bytes_until_end();
    let mut bcs_reader = bcs::new(oft_info_bytes);
    let oft_package = bcs_reader.peel_address();
    let oft_object = bcs_reader.peel_address();

    assert!(bcs_reader.into_remainder_bytes().is_empty(), EInvalidData);

    OFTInfoV1 { oft_package, oft_object }
}
