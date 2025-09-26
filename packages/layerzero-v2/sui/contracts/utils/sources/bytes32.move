/// Bytes32 Module
///
/// This module provides a `Bytes32` struct for working with 32-byte fixed-length data.
/// It's commonly used for hashes, addresses, and other cryptographic values that require
/// exactly 32 bytes of data.
///
/// Usage:
/// ```move
/// let hash = bytes32::from_bytes(x"1234..."); // 32 bytes
/// let addr = hash.to_address();
/// let is_empty = bytes32::is_zero(&hash);
/// ```
///
/// Features:
/// - Fixed 32-byte length with validation
/// - Conversion to/from addresses and IDs
/// - Padding support for shorter byte vectors
/// - Common utility checks
module utils::bytes32;

use sui::address;

// === Error Codes ===

const EInvalidLength: u64 = 1;

// === Constants ===

const ZEROS_BYTES: vector<u8> = x"0000000000000000000000000000000000000000000000000000000000000000";
const FFS_BYTES: vector<u8> = x"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

// === Structs ===

/// A struct representing exactly 32 bytes of data.
/// Commonly used for hashes, addresses, and cryptographic values.
public struct Bytes32 has copy, drop, store {
    bytes: vector<u8>,
}

// === Functions ===

/// Create a Bytes32 with all bytes set to zero.
public fun zero_bytes32(): Bytes32 {
    Bytes32 { bytes: ZEROS_BYTES }
}

/// Create a Bytes32 with all bytes set to 0xff.
public fun ff_bytes32(): Bytes32 {
    Bytes32 { bytes: FFS_BYTES }
}

/// Check if all bytes are zero.
public fun is_zero(self: &Bytes32): bool {
    self.bytes == ZEROS_BYTES
}

/// Check if all bytes are 0xff.
public fun is_ff(self: &Bytes32): bool {
    self.bytes == FFS_BYTES
}

/// Create a Bytes32 from exactly 32 bytes.
public fun from_bytes(bytes: vector<u8>): Bytes32 {
    assert!(bytes.length() == 32, EInvalidLength);
    Bytes32 { bytes }
}

/// Create a Bytes32 from bytes, padding with zeros on the left if needed.
public fun from_bytes_left_padded(bytes: vector<u8>): Bytes32 {
    let mut bytes32 = create_zero_padding(&bytes);
    bytes32.append(bytes);
    from_bytes(bytes32)
}

/// Create a Bytes32 from bytes, padding with zeros on the right if needed.
public fun from_bytes_right_padded(bytes: vector<u8>): Bytes32 {
    let mut bytes32 = bytes;
    bytes32.append(create_zero_padding(&bytes));
    from_bytes(bytes32)
}

/// Create a Bytes32 from an address.
public fun from_address(addr: address): Bytes32 {
    from_bytes(addr.to_bytes())
}

/// Convert to a vector of bytes (returns a copy).
public fun to_bytes(self: &Bytes32): vector<u8> {
    self.bytes
}

/// Convert to an address.
public fun to_address(self: &Bytes32): address {
    address::from_bytes(self.bytes)
}

/// Create a Bytes32 from an object ID.
public fun from_id(id: ID): Bytes32 {
    from_bytes(id.to_bytes())
}

/// Convert to an object ID.
public fun to_id(self: &Bytes32): ID {
    object::id_from_bytes(self.bytes)
}

// === Internal Helpers ===

/// Create zero padding for bytes to reach 32 bytes total length.
/// Asserts that the original bytes length is <= 32.
fun create_zero_padding(bytes: &vector<u8>): vector<u8> {
    let len = bytes.length();
    assert!(len <= 32, EInvalidLength);
    vector::tabulate!(32 - len, |_| 0)
}
