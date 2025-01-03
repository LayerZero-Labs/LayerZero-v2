/// This is a wrapper for vector<u8> that enforces a length of 32 bytes
module endpoint_v2_common::bytes32 {
    use std::bcs;
    use std::from_bcs;
    use std::vector;

    public inline fun ZEROS_32_BYTES(): vector<u8> {
        x"0000000000000000000000000000000000000000000000000000000000000000"
    }

    struct Bytes32 has store, drop, copy {
        bytes: vector<u8>
    }

    /// Returns a Bytes32 with all bytes set to zero
    public fun zero_bytes32(): Bytes32 {
        Bytes32 { bytes: ZEROS_32_BYTES() }
    }

    /// Returns a Bytes32 with all bytes set to 0xff
    public fun ff_bytes32(): Bytes32 {
        Bytes32 { bytes: x"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" }
    }

    /// Returns true if the given Bytes32 is all zeros
    public fun is_zero(bytes32: &Bytes32): bool {
        bytes32.bytes == ZEROS_32_BYTES()
    }

    /// Converts a vector of bytes to a Bytes32
    /// The vector must be exactly 32 bytes long
    public fun to_bytes32(bytes: vector<u8>): Bytes32 {
        assert!(vector::length(&bytes) == 32, EINVALID_LENGTH);
        Bytes32 { bytes }
    }

    /// Converts a Bytes32 to a vector of bytes
    public fun from_bytes32(bytes32: Bytes32): vector<u8> {
        bytes32.bytes
    }

    /// Converts an address to a Bytes32
    public fun from_address(addr: address): Bytes32 {
        let bytes = bcs::to_bytes(&addr);
        to_bytes32(bytes)
    }

    /// Converts a Bytes32 to an address
    public fun to_address(bytes32: Bytes32): address {
        from_bcs::to_address(bytes32.bytes)
    }

    /// Get the keccak256 hash of the given bytes
    public fun keccak256(bytes: vector<u8>): Bytes32 {
        let hash = std::aptos_hash::keccak256(bytes);
        to_bytes32(hash)
    }

    // ================================================== Error Codes =================================================

    const EINVALID_LENGTH: u64 = 1;
}
