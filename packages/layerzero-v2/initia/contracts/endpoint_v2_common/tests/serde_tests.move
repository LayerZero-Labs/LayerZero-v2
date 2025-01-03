#[test_only]
module endpoint_v2_common::serde_tests {
    use endpoint_v2_common::bytes32;
    use endpoint_v2_common::serde::{
        append_address,
        append_bytes,
        append_bytes32,
        append_u128,
        append_u16,
        append_u256,
        append_u32,
        append_u64,
        append_u8,
        append_uint,
        bytes_of,
        extract_address,
        extract_bytes32,
        extract_bytes_until_end,
        extract_u128,
        extract_u16,
        extract_u256,
        extract_u32,
        extract_u64,
        extract_u8,
        extract_uint,
        map_count
    };

    #[test]
    fun test_extract_uint() {
        let data: vector<u8> = x"99999999123456789999999999999999999999";
        let position = 4;
        let result: u32 = (extract_uint(&data, &mut position, 2) as u32);
        assert!(result == 0x1234, (result as u64));  // little endian
        assert!(position == 6, 0);
    }

    #[test]
    fun test_append_uint() {
        let data: vector<u8> = x"99999999";
        append_uint(&mut data, 0x1234, 2);
        assert!(data == x"999999991234", 0);
    }

    #[test]
    fun test_append_then_extract_uint() {
        let data: vector<u8> = x"99999999";
        append_uint(&mut data, 0x1234, 2);
        let position = 4;
        let result: u32 = (extract_uint(&data, &mut position, 2) as u32);
        assert!(result == 0x1234, 0);
        assert!(position == 6, 0);
    }

    #[test]
    fun test_append_bytes() {
        let data: vector<u8> = x"4444";
        append_bytes(&mut data, x"1234567890");
        assert!(data == x"44441234567890", 0);
    }

    #[test]
    fun test_extract_bytes_until_end() {
        let data: vector<u8> = x"444400000000001234567890";
        let position = 2;
        let result: vector<u8> = extract_bytes_until_end(&data, &mut position);
        assert!(result == x"00000000001234567890", 0);
        assert!(position == 12, 0);
    }

    #[test]
    fun test_append_address() {
        let data: vector<u8> = x"4444";
        append_address(&mut data, @0x12345678);
        assert!(data == x"44440000000000000000000000000000000000000000000000000000000012345678", 0);
    }

    #[test]
    fun test_extract_address() {
        let data: vector<u8> = x"44440000000000000000000000000000000000000000000000000000000087654321";
        let position = 2;
        let result: address = extract_address(&data, &mut position);
        assert!(result == @0x87654321, 0);
        assert!(position == 34, 0);
    }

    #[test]
    fun test_various() {
        let buf: vector<u8> = x"4444";
        append_u8(&mut buf, 0x12); // 1 byte
        append_u16(&mut buf, 0x1234); // 2 bytes
        append_u32(&mut buf, 0x12345678); // 4 bytes
        append_u64(&mut buf, 0x1234567890); // 8 bytes
        append_u128(&mut buf, 0x12345678901234567890); // 16 bytes
        append_u256(&mut buf, 0x1234567890123456789012345678901234567890123456789012345678901234); // 32 bytes

        let pos = 2; // start after the initial junk data
        assert!(extract_u8(&buf, &mut pos) == 0x12, 0);
        assert!(extract_u16(&buf, &mut pos) == 0x1234, 0);
        assert!(extract_u32(&buf, &mut pos) == 0x12345678, 0);
        assert!(extract_u64(&buf, &mut pos) == 0x1234567890, 0);
        assert!(extract_u128(&buf, &mut pos) == 0x12345678901234567890, 0);
        assert!(extract_u256(&buf, &mut pos) == 0x1234567890123456789012345678901234567890123456789012345678901234, 0);
        // 2 initial bytes + 63 bytes in closure = 65
        assert!(pos == 65, 0);
    }

    #[test]
    fun test_append_bytes32() {
        let data: vector<u8> = x"4444";
        let b32 = bytes32::to_bytes32(x"5555555555555555555555555555555555555555555555555555555555555555");
        append_bytes32(&mut data, b32);
        assert!(data == x"44445555555555555555555555555555555555555555555555555555555555555555", 0);
    }

    #[test]
    fun test_extract_bytes32() {
        let data = x"444455555555555555555555555555555555555555555555555555555555555555551234";
        let pos = 2;
        let result = extract_bytes32(&data, &mut pos);
        assert!(result == bytes32::to_bytes32(x"5555555555555555555555555555555555555555555555555555555555555555"), 0);
    }

    #[test]
    fun test_map_count() {
        let data = x"00010002000300040005";
        let pos = 0;
        let vec = map_count(4, |_i| extract_u16(&data, &mut pos));
        let expected = vector<u16>[1, 2, 3, 4];
        assert!(vec == expected, 0);
    }

    #[test]
    fun test_map_count_using_i() {
        let vec = map_count(5, |i| (i as u8));
        let expected = vector<u8>[0, 1, 2, 3, 4];
        assert!(vec == expected, 0);
    }

    #[test]
    fun test_bytes_of() {
        let data = bytes_of(|buf| append_address(buf, @0x12345678));
        let expected = x"0000000000000000000000000000000000000000000000000000000012345678";
        assert!(data == expected, 0);
    }
}
