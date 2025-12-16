#[test_only]
module utils::buffer_tests;

use utils::{buffer_reader, buffer_writer, bytes32};

#[test]
fun test_write_bytes() {
    let data: vector<u8> = x"4444";
    let mut writer = buffer_writer::create(data);
    writer.write_bytes(x"1234567890");
    assert!(writer.to_bytes() == x"44441234567890", 0);
}

#[test]
fun test_read_bytes_until_end() {
    let data: vector<u8> = x"444400000000001234567890";

    let mut reader = buffer_reader::create(data);
    let result: vector<u8> = reader.skip(2).read_bytes_until_end();
    assert!(result == x"00000000001234567890", 0);
    assert!(reader.position() == 12, 0);
}

#[test]
fun test_write_address() {
    let data: vector<u8> = x"4444";
    let mut writer = buffer_writer::create(data);
    writer.write_address(@0x12345678);
    assert!(writer.to_bytes() == x"44440000000000000000000000000000000000000000000000000000000012345678", 0);
}

#[test]
fun test_read_address() {
    let data: vector<u8> = x"44440000000000000000000000000000000000000000000000000000000087654321";
    let mut reader = buffer_reader::create(data);
    let result: address = reader.skip(2).read_address();
    assert!(result == @0x87654321, 0);
    assert!(reader.position() == 34, 0);
}

#[test]
fun test_various() {
    let buf: vector<u8> = x"4444";
    let mut writer = buffer_writer::create(buf);
    writer
        .write_u8(0x12) // 1 byte
        .write_u16(0x1234) // 2 bytes
        .write_u32(0x12345678) // 4 bytes
        .write_u64(0x1234567890) // 8 bytes
        .write_u128(0x12345678901234567890123456789012) // 16 bytes
        .write_u256(0x1234567890123456789012345678901234567890123456789012345678901234); // 32 bytes
    assert!(writer.length() == 65, 0);

    let mut reader = buffer_reader::create(writer.to_bytes());
    reader.skip(2); // start after the initial junk data

    assert!(reader.read_u8() == 0x12, 0);
    assert!(reader.read_u16() == 0x1234, 0);
    assert!(reader.read_u32() == 0x12345678, 0);
    assert!(reader.read_u64() == 0x1234567890, 0);
    assert!(reader.read_u128() == 0x12345678901234567890123456789012, 0);
    assert!(reader.read_u256() == 0x1234567890123456789012345678901234567890123456789012345678901234, 0);
    // 2 initial bytes + 63 bytes in closure = 65
    assert!(reader.position() == 65, 0);
    assert!(reader.remaining_length() == 0, 0);
}

#[test]
fun test_write_bytes32() {
    let data: vector<u8> = x"4444";
    let b32 = bytes32::from_bytes(
        x"5555555555555555555555555555555555555555555555555555555555555555",
    );
    let mut writer = buffer_writer::create(data);
    writer.write_bytes32(b32);
    assert!(writer.to_bytes() == x"44445555555555555555555555555555555555555555555555555555555555555555", 0);
}

#[test]
fun test_read_bytes32() {
    let data = x"444455555555555555555555555555555555555555555555555555555555555555551234";
    let mut reader = buffer_reader::create(data);
    let result = reader.skip(2).read_bytes32();
    assert!(result == bytes32::from_bytes(x"5555555555555555555555555555555555555555555555555555555555555555"), 0);
}

#[test, expected_failure(abort_code = buffer_reader::EInvalidLength)]
fun test_skip() {
    let data: vector<u8> = x"1234567890abcdef";
    let mut reader = buffer_reader::create(data);

    // Initial position should be 0
    assert!(reader.position() == 0, 0);
    assert!(reader.remaining_length() == 8, 0);

    // Skip 0 bytes should not change position
    reader.skip(0);
    assert!(reader.position() == 0, 0);
    assert!(reader.remaining_length() == 8, 0);

    // Skip 3 bytes
    reader.skip(3);
    assert!(reader.position() == 3, 0);
    assert!(reader.remaining_length() == 5, 0);

    // Skip beyond remaining_length
    let remaining_length = reader.remaining_length();
    reader.skip(remaining_length + 1);
}

#[test, expected_failure(abort_code = buffer_reader::EInvalidLength)]
fun test_rewind_and_position() {
    let data: vector<u8> = x"1234567890abcdef";
    let mut reader = buffer_reader::create(data);

    // Move to end first
    reader.skip(8);
    assert!(reader.position() == 8, 0);
    assert!(reader.remaining_length() == 0, 0);

    // Rewind 0 bytes should not change position
    reader.rewind(0);
    assert!(reader.position() == 8, 0);
    assert!(reader.remaining_length() == 0, 0);

    // Rewind 3 bytes
    reader.rewind(3);
    assert!(reader.position() == 5, 0);
    assert!(reader.remaining_length() == 3, 0);

    // Try to rewind more than current position
    let position = reader.position();
    reader.rewind(position + 1);
}

#[test]
fun test_read_fixed_len_bytes() {
    let data: vector<u8> = x"1234567890";
    let mut reader = buffer_reader::create(data);

    // Initial state - 5 bytes total
    assert!(reader.position() == 0, 0);
    assert!(reader.remaining_length() == 5, 0);

    // Read first 4 bytes
    let result1 = reader.read_fixed_len_bytes(4);
    assert!(result1 == x"12345678", 0);
    assert!(reader.position() == 4, 0);
    assert!(reader.remaining_length() == 1, 0);

    // Read 0 bytes (should return empty vector and not change position)
    let result3 = reader.read_fixed_len_bytes(0);
    assert!(result3 == x"", 0);
    assert!(reader.position() == 4, 0);
    assert!(reader.remaining_length() == 1, 0);
}

#[test]
fun test_write_read_bool() {
    let mut writer = buffer_writer::new();

    // Write true and false values
    writer.write_bool(true).write_bool(false).write_bool(true);

    let mut reader = buffer_reader::create(writer.to_bytes());

    // Read back the boolean values
    assert!(reader.read_bool() == true, 0);
    assert!(reader.read_bool() == false, 0);
    assert!(reader.read_bool() == true, 0);

    assert!(reader.position() == 3, 0);
    assert!(reader.remaining_length() == 0, 0);
}

#[test]
fun test_bool_edge_cases() {
    // Test that only 0 is interpreted as false, everything else as true
    let data: vector<u8> = x"0001025500";
    let mut reader = buffer_reader::create(data);

    assert!(reader.read_bool() == false, 0); // 0x00
    assert!(reader.read_bool() == true, 0); // 0x01
    assert!(reader.read_bool() == true, 0); // 0x02
    assert!(reader.read_bool() == true, 0); // 0x55
    assert!(reader.read_bool() == false, 0); // 0x00
}
