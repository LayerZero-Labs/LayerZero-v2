#[test_only]
module uln_302::uln_config_tests;

use iota::bcs;
use uln_302::uln_config;

// Helper function to generate test DVN vectors of specified size
fun generate_dvn_vector(count: u64): vector<address> {
    let mut dvns = vector[];
    let mut i = 1;
    while (i <= count) {
        // Generate addresses from 0x1 to 0x{count}
        if (i <= 255) {
            let mut addr_bytes = vector[];
            let mut j = 0;
            while (j < 31) {
                addr_bytes.push_back(0);
                j = j + 1;
            };
            addr_bytes.push_back((i as u8)); // Last byte is the counter
            dvns.push_back(iota::address::from_bytes(addr_bytes));
        };
        i = i + 1;
    };
    dvns
}

#[test]
fun test_new_creates_empty_config() {
    let config = uln_config::new();

    assert!(config.confirmations() == 0, 1);
    assert!(config.required_dvns().is_empty(), 2);
    assert!(config.optional_dvns().is_empty(), 3);
    assert!(config.optional_dvn_threshold() == 0, 4);
}

#[test]
fun test_create_with_custom_values() {
    let confirmations = 64;
    let required_dvns = vector[@0x123, @0x456];
    let optional_dvns = vector[@0x789, @0xabc];
    let optional_dvn_threshold = 2;

    let config = uln_config::create(
        confirmations,
        required_dvns,
        optional_dvns,
        optional_dvn_threshold,
    );

    assert!(config.confirmations() == confirmations, 1);
    assert!(config.required_dvns() == &required_dvns, 2);
    assert!(config.optional_dvns() == &optional_dvns, 3);
    assert!(config.optional_dvn_threshold() == optional_dvn_threshold, 4);
}

#[test]
fun test_deserialize_valid_config() {
    let expected_confirmations = 1000;
    let expected_required_dvns = vector[@0x123];
    let expected_optional_dvns = vector[@0x456, @0x789];
    let expected_threshold = 2;

    let original_config = uln_config::create(
        expected_confirmations,
        expected_required_dvns,
        expected_optional_dvns,
        expected_threshold,
    );

    let config_bytes = bcs::to_bytes(&original_config);

    let deserialized_config = uln_config::deserialize(config_bytes);

    assert!(deserialized_config.confirmations() == expected_confirmations, 1);
    assert!(deserialized_config.required_dvns() == &expected_required_dvns, 2);
    assert!(deserialized_config.optional_dvns() == &expected_optional_dvns, 3);
    assert!(deserialized_config.optional_dvn_threshold() == expected_threshold, 4);
}

#[test, expected_failure(abort_code = uln_config::EInvalidUlnConfigBytes)]
fun test_deserialize_with_extra_bytes_should_fail() {
    let config = uln_config::create(1000, vector[@0x123], vector[@0x456], 1);
    let mut config_bytes = bcs::to_bytes(&config);

    // Add extra bytes that shouldn't be there
    config_bytes.push_back(0xFF);
    config_bytes.push_back(0xEE);

    uln_config::deserialize(config_bytes);
}

#[test, expected_failure(abort_code = iota::bcs::EOutOfRange)]
fun test_deserialize_empty_bytes_should_fail() {
    let empty_bytes = vector[];
    uln_config::deserialize(empty_bytes);
}

#[test, expected_failure]
fun test_deserialize_incomplete_bytes_should_fail() {
    // Generic expected_failure: incomplete BCS causes internal vector error with no public abort code
    // missing required_dvns, optional_dvns, threshold configs
    let mut incomplete_bytes = vector[];
    let confirmations = 1000_u64;
    let confirmations_bytes = bcs::to_bytes(&confirmations);
    incomplete_bytes.append(confirmations_bytes);

    uln_config::deserialize(incomplete_bytes);
}

#[test]
fun test_assert_default_config_valid() {
    let config = uln_config::create(
        64,
        vector[@0x123, @0x456], // required DVNs (no duplicates)
        vector[@0x789, @0xabc], // optional DVNs (no duplicates)
        2, // threshold <= optional DVN count
    );

    config.assert_default_config(); // Should not abort
}

#[test, expected_failure(abort_code = uln_config::EAtLeastOneDVN)]
fun test_assert_default_config_should_fail_when_no_dvns() {
    let config = uln_config::create(
        64,
        vector[], // No required DVNs
        vector[], // No optional DVNs
        0, // No threshold
    );

    config.assert_default_config(); // Should fail - no DVNs at all
}

#[test, expected_failure(abort_code = uln_config::EDuplicateRequiredDVNs)]
fun test_assert_required_dvns_should_fail_when_duplicates() {
    let config = uln_config::create(
        64,
        vector[@0x123, @0x456, @0x123], // Duplicate @0x123
        vector[@0x789],
        1,
    );

    config.assert_required_dvns();
}

#[test, expected_failure(abort_code = uln_config::EDuplicateOptionalDVNs)]
fun test_assert_optional_dvns_should_fail_when_duplicates() {
    let config = uln_config::create(
        64,
        vector[@0x123],
        vector[@0x456, @0x789, @0x456],
        2,
    );

    config.assert_optional_dvns();
}

#[test, expected_failure(abort_code = uln_config::EInvalidOptionalDVNThreshold)]
fun test_assert_optional_dvns_should_fail_when_threshold_too_high() {
    let config = uln_config::create(
        64,
        vector[@0x123],
        vector[@0x456], // Only 1 optional DVN
        3, // But threshold is 3
    );

    config.assert_optional_dvns();
}

#[test, expected_failure(abort_code = uln_config::EInvalidOptionalDVNThreshold)]
fun test_assert_optional_dvns_should_fail_when_threshold_without_dvns() {
    let config = uln_config::create(
        64,
        vector[@0x123],
        vector[], // No optional DVNs
        1, // But threshold > 0
    );

    config.assert_optional_dvns();
}

#[test, expected_failure(abort_code = uln_config::EInvalidOptionalDVNThreshold)]
fun test_assert_optional_dvns_should_fail_when_threshold_is_zero_and_non_empty_dvns() {
    let config = uln_config::create(
        64,
        vector[@0x123],
        vector[@0x456], // 1 optional DVN
        0, // But threshold = 0
    );

    config.assert_optional_dvns();
}

#[test]
fun test_assert_optional_dvns_valid_scenarios() {
    // Scenario 1: threshold = 0, no optional DVNs (valid)
    let config1 = uln_config::create(64, vector[@0x123], vector[], 0);
    config1.assert_optional_dvns();

    // Scenario 2: threshold > 0 and threshold <= DVN count (valid)
    let config2 = uln_config::create(64, vector[@0x123], vector[@0x456, @0x789], 1);
    config2.assert_optional_dvns();

    // Scenario 3: threshold = DVN count (edge case, valid)
    let config3 = uln_config::create(64, vector[@0x123], vector[@0x456], 1);
    config3.assert_optional_dvns();
}

#[test]
fun test_assert_at_least_one_dvn_valid_scenarios() {
    // Scenario 1: Has required DVNs
    let config1 = uln_config::create(64, vector[@0x123], vector[], 0);
    config1.assert_at_least_one_dvn();

    // Scenario 2: Has optional DVN threshold > 0
    let config2 = uln_config::create(64, vector[], vector[@0x456], 1);
    config2.assert_at_least_one_dvn();

    // Scenario 3: Has both
    let config3 = uln_config::create(64, vector[@0x123], vector[@0x456], 1);
    config3.assert_at_least_one_dvn();
}

#[test, expected_failure(abort_code = uln_config::EInvalidRequiredDVNCount)]
fun test_too_many_dvns_should_fail() {
    // Test with 128 DVNs (exceeds MAX_DVNS of 127)
    let required_dvns = generate_dvn_vector(128);

    let config = uln_config::create(64, required_dvns, vector[], 0);
    config.assert_required_dvns();
}

#[test]
fun test_getters_return_correct_values() {
    let confirmations = 9999_u64;
    let required_dvns = vector[@0x111, @0x222, @0x333];
    let optional_dvns = vector[@0x444, @0x555];
    let threshold = 1_u8;

    let config = uln_config::create(confirmations, required_dvns, optional_dvns, threshold);

    assert!(config.confirmations() == confirmations, 1);
    assert!(config.required_dvns() == &required_dvns, 2);
    assert!(config.optional_dvns() == &optional_dvns, 3);
    assert!(config.optional_dvn_threshold() == threshold, 4);
}

#[test, expected_failure(abort_code = uln_config::EInvalidOptionalDVNCount)]
fun test_too_many_optional_dvns_should_fail() {
    // Test with 128 optional DVNs (exceeds MAX_DVNS of 127)
    let optional_dvns = generate_dvn_vector(128);

    let config = uln_config::create(
        64,
        vector[@0x123], // Just one required DVN
        optional_dvns, // 128 optional DVNs - should fail
        64, // threshold (valid, but won't be reached due to count limit)
    );

    config.assert_optional_dvns();
}

#[test]
fun test_exactly_127_required_dvns_should_pass() {
    // Test with exactly 127 required DVNs (boundary test - should pass)
    let required_dvns = generate_dvn_vector(127);

    let config = uln_config::create(
        64,
        required_dvns, // Exactly 127 required DVNs - should pass
        vector[], // No optional DVNs
        0, // No threshold needed
    );

    // This should NOT abort - exactly 127 is allowed
    config.assert_required_dvns();
    config.assert_default_config();
}

#[test]
fun test_exactly_127_optional_dvns_should_pass() {
    // Test with exactly 127 optional DVNs (boundary test - should pass)
    let optional_dvns = generate_dvn_vector(127);

    let config = uln_config::create(
        64,
        vector[@0x123], // One required DVN to satisfy "at least one DVN" requirement
        optional_dvns, // Exactly 127 optional DVNs - should pass
        64, // Valid threshold (less than or equal to optional DVN count)
    );

    // This should NOT abort - exactly 127 is allowed
    config.assert_optional_dvns();
    config.assert_default_config();
}
