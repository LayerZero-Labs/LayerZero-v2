/// Hash Module
///
/// This module provides convenient wrapper functions for common cryptographic hash functions.
/// All hash functions return a `Bytes32` struct for consistent handling of 32-byte hash values.
module utils::hash;

use sui::hash;
use utils::bytes32::{Self, Bytes32};

/// Compute BLAKE2b-256 hash.
public macro fun blake2b256($bytes: &vector<u8>): Bytes32 {
    bytes32::from_bytes(hash::blake2b256($bytes))
}

/// Compute Keccak-256 hash.
public macro fun keccak256($bytes: &vector<u8>): Bytes32 {
    bytes32::from_bytes(hash::keccak256($bytes))
}
