/// Buffer Writer Module
///
/// This module provides a `Writer` struct for efficiently serializing various data types
/// into a byte buffer. The writer supports writing primitive types (u8, u16, u32, u64, u128, u256),
/// booleans, addresses, bytes32, and raw byte vectors in big-endian format.
///
/// Usage:
/// ```move
/// let mut writer = buffer_writer::new();
/// writer.write_u32(0x12345678)
///       .write_bool(true)
///       .write_address(@0x123);
/// let bytes = writer.to_bytes();
/// ```
///
/// Features:
/// - Chain-able API for fluent writing
/// - Big-endian encoding for cross-platform compatibility
/// - Support for all Move primitive types
/// - Efficient byte buffer management
module utils::buffer_writer;

use utils::bytes32::Bytes32;

// === Structs ===

/// A writer for serializing data to a byte buffer.
///
/// The writer maintains an internal byte buffer and provides methods to write
/// various data types in big-endian format. All write operations return a
/// mutable reference to the writer, enabling method chaining.
public struct Writer has copy {
    buffer: vector<u8>,
}

// === Public API ===

/// Create a new empty writer.
public fun new(): Writer {
    Writer { buffer: vector[] }
}

/// Create a new writer initialized with existing data.
public fun create(buffer: vector<u8>): Writer {
    Writer { buffer }
}

/// Get the current length of the buffer.
public fun length(self: &Writer): u64 {
    self.buffer.length()
}

/// Write a boolean value to the buffer (true as 1, false as 0).
public fun write_bool(self: &mut Writer, value: bool): &mut Writer {
    self.write_u8(if (value) 1 else 0)
}

/// Write an unsigned 8-bit integer to the buffer.
public fun write_u8(self: &mut Writer, value: u8): &mut Writer {
    write_uint_internal!(self, value, 1)
}

/// Write an unsigned 16-bit integer in big-endian format.
public fun write_u16(self: &mut Writer, value: u16): &mut Writer {
    write_uint_internal!(self, value, 2)
}

/// Write an unsigned 32-bit integer in big-endian format.
public fun write_u32(self: &mut Writer, value: u32): &mut Writer {
    write_uint_internal!(self, value, 4)
}

/// Write an unsigned 64-bit integer in big-endian format.
public fun write_u64(self: &mut Writer, value: u64): &mut Writer {
    write_uint_internal!(self, value, 8)
}

/// Write an unsigned 128-bit integer in big-endian format.
public fun write_u128(self: &mut Writer, value: u128): &mut Writer {
    write_uint_internal!(self, value, 16)
}

/// Write an unsigned 256-bit integer in big-endian format.
public fun write_u256(self: &mut Writer, value: u256): &mut Writer {
    write_uint_internal!(self, value, 32)
}

/// Write a byte vector to the buffer (appends without length prefix).
public fun write_bytes(self: &mut Writer, bytes: vector<u8>): &mut Writer {
    self.buffer.append(bytes);
    self
}

/// Write an address to the buffer (32 bytes).
public fun write_address(self: &mut Writer, addr: address): &mut Writer {
    self.buffer.append(addr.to_bytes());
    self
}

/// Write a bytes32 value to the buffer.
public fun write_bytes32(self: &mut Writer, bytes32: Bytes32): &mut Writer {
    self.buffer.append(bytes32.to_bytes());
    self
}

/// Get the complete buffer as a byte vector.
public fun to_bytes(self: Writer): vector<u8> {
    let Writer { buffer } = self;
    buffer
}

// === Internal Implementation ===

/// Internal macro for writing unsigned integers in big-endian format.
macro fun write_uint_internal<$T>($self: &mut Writer, $value: $T, $len: u8): &mut Writer {
    let self = $self;
    let mut i = 0;
    while (i < $len) {
        let byte = ((($value >> (8 * ($len - i - 1))) & 0xFF) as u8);
        self.buffer.push_back(byte);
        i = i + 1;
    };
    self
}
