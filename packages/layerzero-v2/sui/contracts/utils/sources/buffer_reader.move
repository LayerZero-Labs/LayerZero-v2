/// Buffer Reader Module
///
/// This module provides a `Reader` struct for efficiently deserializing various data types
/// from a byte buffer. The reader supports reading primitive types (u8, u16, u32, u64, u128, u256),
/// booleans, addresses, bytes32, and raw byte vectors in big-endian format.
///
/// Usage:
/// ```move
/// let mut reader = buffer_reader::create(data);
/// let value1 = reader.read_u32();
/// let value2 = reader.read_bool();
/// let addr = reader.read_address();
/// ```
///
/// Features:
/// - Position tracking for sequential reading
/// - Big-endian decoding for cross-platform compatibility
/// - Support for all Move primitive types
/// - Safe bounds checking with descriptive errors
/// - Flexible positioning (skip, rewind, set_position)
module utils::buffer_reader;

use utils::bytes32::{Self, Bytes32};

// === Error Codes ===

const EInvalidLength: u64 = 1;

// === Structs ===

/// A reader for deserializing data from a byte buffer.
///
/// The reader maintains an internal position cursor and provides methods to read
/// various data types in big-endian format. The position automatically advances
/// after each read operation.
public struct Reader has copy, drop {
    buffer: vector<u8>,
    position: u64,
}

// === Public API ===

/// Create a new reader from a byte buffer.
public fun create(buffer: vector<u8>): Reader {
    Reader { buffer, position: 0 }
}

/// Get the current position in the reader.
public fun position(self: &Reader): u64 {
    self.position
}

/// Get the total length of the buffer.
public fun length(self: &Reader): u64 {
    self.buffer.length()
}

/// Get the number of remaining bytes to read.
public fun remaining_length(self: &Reader): u64 {
    self.buffer.length() - self.position
}

/// Set the reader position to a specific byte offset.
public fun set_position(self: &mut Reader, position: u64): &mut Reader {
    assert!(position <= self.buffer.length(), EInvalidLength);
    self.position = position;
    self
}

/// Skip forward a number of bytes in the reader.
public fun skip(self: &mut Reader, len: u64): &mut Reader {
    let pos = self.position + len;
    self.set_position(pos)
}

/// Move the reader position backward by a number of bytes.
public fun rewind(self: &mut Reader, len: u64): &mut Reader {
    assert!(self.position >= len, EInvalidLength);
    let pos = self.position - len;
    self.set_position(pos)
}

/// Read a boolean value (0 = false, anything else = true).
public fun read_bool(self: &mut Reader): bool {
    let value = self.read_u8();
    value != 0
}

/// Read an unsigned 8-bit integer.
public fun read_u8(self: &mut Reader): u8 {
    read_uint_internal!(self, 1)
}

/// Read an unsigned 16-bit integer in big-endian format.
public fun read_u16(self: &mut Reader): u16 {
    read_uint_internal!(self, 2)
}

/// Read an unsigned 32-bit integer in big-endian format.
public fun read_u32(self: &mut Reader): u32 {
    read_uint_internal!(self, 4)
}

/// Read an unsigned 64-bit integer in big-endian format.
public fun read_u64(self: &mut Reader): u64 {
    read_uint_internal!(self, 8)
}

/// Read an unsigned 128-bit integer in big-endian format.
public fun read_u128(self: &mut Reader): u128 {
    read_uint_internal!(self, 16)
}

/// Read an unsigned 256-bit integer in big-endian format.
public fun read_u256(self: &mut Reader): u256 {
    read_uint_internal!(self, 32)
}

/// Read a bytes32 value from the buffer.
public fun read_bytes32(self: &mut Reader): Bytes32 {
    let bytes = self.read_fixed_len_bytes(32);
    bytes32::from_bytes(bytes)
}

/// Read an address from the buffer (32 bytes).
public fun read_address(self: &mut Reader): address {
    self.read_bytes32().to_address()
}

/// Read a fixed number of bytes from the buffer.
public fun read_fixed_len_bytes(self: &mut Reader, len: u64): vector<u8> {
    assert!(self.position + len <= self.buffer.length(), EInvalidLength);
    let result = vector::tabulate!(len, |i| self.buffer[self.position + i]);
    self.position = self.position + len;
    result
}

/// Read all remaining bytes from the buffer.
public fun read_bytes_until_end(self: &mut Reader): vector<u8> {
    let len = self.remaining_length();
    self.read_fixed_len_bytes(len)
}

/// Get the complete buffer as a byte vector.
public fun to_bytes(self: &Reader): vector<u8> {
    self.buffer
}

// === Internal Implementation ===

/// Internal macro for reading unsigned integers in big-endian format.
macro fun read_uint_internal<$T>($self: &mut Reader, $len: u8): $T {
    let self = $self;
    assert!(self.position + ($len as u64) <= self.buffer.length(), EInvalidLength);

    let mut result: $T = 0;
    let mut i = 0;
    let mut pos = self.position;
    while (i < $len) {
        let byte = self.buffer[pos];
        result = result + ((byte as $T) << (($len - i - 1) * 8));
        pos = pos + 1;
        i = i + 1;
    };
    self.position = pos;
    result
}
