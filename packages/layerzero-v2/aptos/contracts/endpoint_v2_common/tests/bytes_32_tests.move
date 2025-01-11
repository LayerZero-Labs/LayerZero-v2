#[test_only]
module endpoint_v2_common::bytes_32_tests {
    use endpoint_v2_common::bytes32::{from_address, from_bytes32, is_zero, to_address, to_bytes32, zero_bytes32};

    #[test]
    fun test_zero_bytes32() {
        let zero_bytes32 = zero_bytes32();
        assert!(is_zero(&zero_bytes32), 0);

        let zero_manual = to_bytes32(x"0000000000000000000000000000000000000000000000000000000000000000");
        assert!(is_zero(&zero_manual), 0);

        let non_zero = to_bytes32(x"0000000000000000000000000000000000000000000000000000000000000001");
        assert!(!is_zero(&non_zero), 0);
    }

    #[test]
    fun test_from_to_address() {
        let addr = @0x12345;
        let bytes32 = from_address(addr);
        assert!(from_bytes32(bytes32) == x"0000000000000000000000000000000000000000000000000000000000012345", 0);

        let addr2 = to_address(bytes32);
        assert!(addr == addr2, 0);
    }

    #[test]
    fun test_to_from_bytes32() {
        let bytes = x"1234560000000000000000000000000000000000000000000000000000123456";
        let bytes32 = to_bytes32(bytes);
        assert!(from_bytes32(bytes32) == bytes, 0);
    }
}
