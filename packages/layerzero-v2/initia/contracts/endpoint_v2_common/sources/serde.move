/// Serialization and deserialization utilities
module endpoint_v2_common::serde {
    use std::bcs::to_bytes;
    use std::from_bcs::to_address;
    use std::vector;

    use endpoint_v2_common::bytes32::{Self, Bytes32};

    /// Extract a uint from a vector of bytes starting at `position`, up to 8 bytes (u64).
    /// Position will be incremented to the position after the end of the read
    /// This decodes in big-endian format, with the most significant byte first
    public fun extract_uint(input: &vector<u8>, position: &mut u64, bytes: u8): u64 {
        let result: u64 = 0;
        for (i in 0..bytes) {
            let byte: u8 = *vector::borrow(input, *position);
            result = result + ((byte as u64) << ((bytes - i - 1) * 8));
            *position = *position + 1;
        };
        result
    }

    /// Extract a u8 from a vector of bytes starting at `position` (position will be updated to the end of read)
    public inline fun extract_u8(input: &vector<u8>, position: &mut u64): u8 {
        (extract_uint(input, position, 1) as u8)
    }

    /// Extract a u16 from a vector of bytes starting at `position` (position will be updated to the end of read)
    public inline fun extract_u16(input: &vector<u8>, position: &mut u64): u16 {
        (extract_uint(input, position, 2) as u16)
    }

    /// Extract a u32 from a vector of bytes starting at `position` (position will be updated to the end of read)
    public inline fun extract_u32(input: &vector<u8>, position: &mut u64): u32 {
        (extract_uint(input, position, 4) as u32)
    }

    /// Extract a u64 from a vector of bytes starting at `position` (position will be updated to the end of read)
    public inline fun extract_u64(input: &vector<u8>, position: &mut u64): u64 {
        extract_uint(input, position, 8)
    }

    /// Extract a u128 from a vector of bytes starting at `position` (position will be updated to the end of read)
    /// This function does not use extract_uint because it is more efficient to handle u128 as a special case
    public fun extract_u128(input: &vector<u8>, position: &mut u64): u128 {
        let result: u128 = 0;
        for (i in 0..16) {
            let byte: u8 = *vector::borrow(input, *position);
            result = result + ((byte as u128) << ((16 - i - 1) * 8));
            *position = *position + 1;
        };
        result
    }

    /// Extract a u256 from a vector of bytes starting at `position` (position will be updated to the end of read)
    /// This function does not use extract_uint because it is more efficient to handle u256 as a special case
    public fun extract_u256(input: &vector<u8>, position: &mut u64): u256 {
        let result: u256 = 0;
        for (i in 0..32) {
            let byte: u8 = *vector::borrow(input, *position);
            result = result + ((byte as u256) << ((32 - i - 1) * 8));
            *position = *position + 1;
        };
        result
    }

    /// Extract a vector of bytes from a vector<u8> starting at `position` and ending at `position + len`
    /// This will update the position to `position + len`
    public fun extract_fixed_len_bytes(input: &vector<u8>, position: &mut u64, len: u64): vector<u8> {
        let result = vector::slice(input, *position, *position + len);
        *position = *position + len;
        result
    }

    /// Extract a vector of bytes from a vector<u8> starting at `position` and ending at the end of the vector
    public fun extract_bytes_until_end(input: &vector<u8>, position: &mut u64): vector<u8> {
        let len = vector::length(input);
        let result = vector::slice(input, *position, len);
        *position = len;
        result
    }

    /// Extract an address from a vector of bytes
    public fun extract_address(input: &vector<u8>, position: &mut u64): address {
        let bytes = vector::slice(input, *position, *position + 32);
        *position = *position + 32;
        to_address(bytes)
    }

    /// Append a uint to a vector of bytes, up to 8 bytes (u64)
    public fun append_uint(target: &mut vector<u8>, value: u64, bytes: u8) {
        for (i in 0..bytes) {
            let byte: u8 = (((value >> (8 * (bytes - i - 1))) & 0xFF) as u8);
            vector::push_back(target, byte);
        };
    }

    /// Append a u8 to a vector of bytes
    public inline fun append_u8(target: &mut vector<u8>, value: u8) { append_uint(target, (value as u64), 1); }

    /// Append a u16 to a vector of bytes
    public inline fun append_u16(target: &mut vector<u8>, value: u16) { append_uint(target, (value as u64), 2); }

    /// Append a u32 to a vector of bytes
    public inline fun append_u32(target: &mut vector<u8>, value: u32) { append_uint(target, (value as u64), 4); }

    /// Append a u64 to a vector of bytes
    public inline fun append_u64(target: &mut vector<u8>, value: u64) { append_uint(target, value, 8); }


    /// Append a u128 to a vector of bytes
    /// This function does not use append_uint because it is more efficient to handle u128 as a special case
    public fun append_u128(target: &mut vector<u8>, value: u128) {
        for (i in 0..16) {
            let byte: u8 = (((value >> (8 * (16 - i - 1))) & 0xFF) as u8);
            vector::push_back(target, byte);
        }
    }

    /// Append a u256 to a vector of bytes
    /// This function does not use append_uint because it is more efficient to handle u256 as a special case
    public fun append_u256(target: &mut vector<u8>, value: u256) {
        for (i in 0..32) {
            let byte: u8 = (((value >> (8 * (32 - i - 1))) & 0xFF) as u8);
            vector::push_back(target, byte);
        }
    }

    /// Get the remaining length of the byte-vector starting at `position`
    public fun get_remaining_length(input: &vector<u8>, position: u64): u64 {
        vector::length(input) - position
    }

    /// Pad the bytes provided with zeros to the left make it the target size
    /// This will throw if the length of the provided vector surpasses the target size
    public fun pad_zero_left(bytes: vector<u8>, target_size: u64): vector<u8> {
        let bytes_size = vector::length(&bytes);
        assert!(target_size >= bytes_size, EINVALID_LENGTH);
        let output = vector[];
        let padding_needed = target_size - bytes_size;
        for (i in 0..padding_needed) {
            vector::push_back(&mut output, 0);
        };
        vector::append(&mut output, bytes);
        output
    }

    /// Append a byte vector to the of a buffer
    public inline fun append_bytes(buf: &mut vector<u8>, bytes: vector<u8>) {
        vector::append(buf, bytes);
    }

    /// Append an address to a vector of bytes
    public fun append_address(buf: &mut vector<u8>, addr: address) {
        let bytes = to_bytes(&addr);
        vector::append(buf, bytes);
    }

    /// Append a bytes32 to a vector of bytes
    public fun append_bytes32(buf: &mut vector<u8>, bytes32: Bytes32) {
        vector::append(buf, bytes32::from_bytes32(bytes32));
    }

    /// Extract a bytes32 from a vector of bytes
    public fun extract_bytes32(input: &vector<u8>, position: &mut u64): Bytes32 {
        let bytes = vector::slice(input, *position, *position + 32);
        *position = *position + 32;
        bytes32::to_bytes32(bytes)
    }

    /// This function flattens a vector of byte-vectors into a single byte-vector
    public inline fun flatten(input: vector<vector<u8>>): vector<u8> {
        let result = vector[];
        vector::for_each(input, |element| {
            vector::append(&mut result, element);
        });
        result
    }

    /// This function creates a vector of `Element` by applying the function `f` to each element in the range [0, count)
    public inline fun map_count<Element>(count: u64, f: |u64|Element): vector<Element> {
        let vec = vector[];
        for (i in 0..count) {
            vector::push_back(&mut vec, f(i));
        };
        vec
    }

    /// This function create a bytes vector by applying the function `f` to a &mut buffer empty vector<u8>
    /// this is useful for directly creating a bytes vector from an append_*() function in a single line
    /// for example: let eighteen = bytes_of(|buf| append_u8(buf, 0x12))
    public inline fun bytes_of(f: |&mut vector<u8>|()): vector<u8> {
        let buf = vector[];
        f(&mut buf);
        buf
    }

    // ================================================== Error Codes =================================================

    const EINVALID_LENGTH: u64 = 1;
}