/// ULN Config Module
///
/// This module provides configuration management for the ULN.
/// It handles the validation and management of DVNs configuration, including required
/// DVNs, optional DVNs, and confirmation requirements.
module uln_302::uln_config;

use sui::bcs;

// === Constants ===

/// Maximum number of DVNs allowed in either required or optional lists.
/// Set to 127 to prevent total number of DVNs (127 * 2) from exceeding uint8.max (255).
const MAX_DVNS: u8 = 127;

// === Errors ===

const EAtLeastOneDVN: u64 = 1;
const EDuplicateOptionalDVNs: u64 = 2;
const EDuplicateRequiredDVNs: u64 = 3;
const EInvalidOptionalDVNCount: u64 = 4;
const EInvalidOptionalDVNThreshold: u64 = 5;
const EInvalidRequiredDVNCount: u64 = 6;
const EInvalidUlnConfigBytes: u64 = 7;

// === Structs ===

/// Configuration struct for ULN.
public struct UlnConfig has copy, drop, store {
    // Number of block confirmations required before message verification begins
    confirmations: u64,
    // List of DVN addresses that must ALL verify the message (no threshold)
    required_dvns: vector<address>,
    // List of DVN addresses from which a threshold number must verify
    optional_dvns: vector<address>,
    // Minimum number of optional DVNs required to verify
    optional_dvn_threshold: u8,
}

// === Creation ===

/// Creates a new UlnConfig with default empty values.
public fun new(): UlnConfig {
    UlnConfig {
        confirmations: 0,
        required_dvns: vector::empty(),
        optional_dvns: vector::empty(),
        optional_dvn_threshold: 0,
    }
}

/// Creates a new UlnConfig with the specified parameters.
public fun create(
    confirmations: u64,
    required_dvns: vector<address>,
    optional_dvns: vector<address>,
    optional_dvn_threshold: u8,
): UlnConfig {
    UlnConfig { confirmations, required_dvns, optional_dvns, optional_dvn_threshold }
}

// === Getters ===

/// Returns the number of block confirmations required for this configuration.
public fun confirmations(config: &UlnConfig): u64 {
    config.confirmations
}

/// Returns a reference to the list of required DVN addresses.
public fun required_dvns(config: &UlnConfig): &vector<address> {
    &config.required_dvns
}

/// Returns a reference to the list of optional DVN addresses.
public fun optional_dvns(config: &UlnConfig): &vector<address> {
    &config.optional_dvns
}

/// Returns the minimum number of optional DVNs required to verify a message.
public fun optional_dvn_threshold(config: &UlnConfig): u8 {
    config.optional_dvn_threshold
}

// === Deserialization ===

/// Deserializes a UlnConfig from BCS-encoded bytes.
///
/// The expected byte format is:
/// 1. confirmations (u64) - 8 bytes
/// 2. required_dvns (vector<address>) - variable length
/// 3. optional_dvns (vector<address>) - variable length
/// 4. optional_dvn_threshold (u8) - 1 byte
public fun deserialize(config_bytes: vector<u8>): UlnConfig {
    let mut bcs = bcs::new(config_bytes);
    let confirmations = bcs.peel_u64();
    let required_dvns = bcs.peel_vec_address();
    let optional_dvns = bcs.peel_vec_address();
    let optional_dvn_threshold = bcs.peel_u8();
    assert!(bcs.into_remainder_bytes().length() == 0, EInvalidUlnConfigBytes);
    create(confirmations, required_dvns, optional_dvns, optional_dvn_threshold)
}

// === Validation Functions ===

/// Validates a UlnConfig for use as a default configuration.
///
/// Performs comprehensive validation including:
/// - Required DVNs validation (no duplicates, within limits)
/// - Optional DVNs validation (no duplicates, within limits, valid threshold)
/// - At least one DVN requirement (either required or optional with threshold > 0)
public fun assert_default_config(config: &UlnConfig) {
    config.assert_required_dvns();
    config.assert_optional_dvns();
    config.assert_at_least_one_dvn();
}

/// Validates the required DVNs configuration.
///
/// Checks:
/// - No duplicate addresses in the required DVNs list
/// - Required DVNs count does not exceed MAX_DVNS limit
public fun assert_required_dvns(config: &UlnConfig) {
    assert!(!has_duplicates(config.required_dvns()), EDuplicateRequiredDVNs);
    assert!(config.required_dvns().length() <= MAX_DVNS as u64, EInvalidRequiredDVNCount);
}

/// Validates the optional DVNs configuration and threshold.
///
/// Checks:
/// - No duplicate addresses in the optional DVNs list
/// - Optional DVNs count does not exceed MAX_DVNS limit
/// - Threshold is valid: either (0 threshold with 0 DVNs) or (threshold between 1 and DVN count)
public fun assert_optional_dvns(config: &UlnConfig) {
    let optional_dvn_threshold = config.optional_dvn_threshold() as u64;
    let optional_dvns_length = config.optional_dvns().length();
    assert!(!has_duplicates(config.optional_dvns()), EDuplicateOptionalDVNs);
    assert!(optional_dvns_length <= MAX_DVNS as u64, EInvalidOptionalDVNCount);
    assert!(
        (optional_dvn_threshold == 0 && optional_dvns_length == 0) || (optional_dvn_threshold > 0 && optional_dvn_threshold <= optional_dvns_length),
        EInvalidOptionalDVNThreshold,
    );
}

/// Validates that the configuration has at least one DVN for verification.
///
/// A valid configuration must have either:
/// - At least one required DVN, OR
/// - An optional DVN threshold greater than 0
public fun assert_at_least_one_dvn(config: &UlnConfig) {
    assert!(config.required_dvns().length() > 0 || config.optional_dvn_threshold() > 0, EAtLeastOneDVN);
}

// === Internal Helper Functions ===

/// Checks if a vector of addresses contains any duplicate values.
fun has_duplicates(v: &vector<address>): bool {
    let mut seen = vector[];
    let mut i = 0;
    while (i < v.length()) {
        let addr = v[i];
        if (seen.contains(&addr)) return true;
        seen.push_back(addr);
        i = i + 1;
    };
    false
}
