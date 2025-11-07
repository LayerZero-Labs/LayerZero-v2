#[test_only]
module uln_302::oapp_uln_config_tests;

use uln_302::{oapp_uln_config, uln_config};

#[test]
fun test_deserialize_happy_flow() {
    let mut oapp_config_bytes = vector[];

    // === Boolean flags ===
    oapp_config_bytes.push_back(0); // use_default_confirmations: false
    oapp_config_bytes.push_back(1); // use_default_required_dvns: true
    oapp_config_bytes.push_back(0); // use_default_optional_dvns: false

    // === Embedded UlnConfig ===
    // confirmations: u64 = 15
    oapp_config_bytes.append(x"0F00000000000000");

    // required_dvns: vector length = 1 (since use_default_required_dvns = true, this might be ignored)
    oapp_config_bytes.push_back(1);
    oapp_config_bytes.append(x"0000000000000000000000000000000000000000000000000000000000000AAA");

    // optional_dvns: vector length = 2
    oapp_config_bytes.push_back(2);
    oapp_config_bytes.append(x"0000000000000000000000000000000000000000000000000000000000000BBB");
    oapp_config_bytes.append(x"0000000000000000000000000000000000000000000000000000000000000CCC");

    // optional_dvn_threshold: u8 = 1
    oapp_config_bytes.push_back(1);

    let config = oapp_uln_config::deserialize(oapp_config_bytes);

    // Assertions
    assert!(config.uln_config().confirmations() == 15, 1);
    assert!(config.use_default_confirmations() == false, 2);
    assert!(config.use_default_required_dvns() == true, 3);
    assert!(config.use_default_optional_dvns() == false, 4);
}

#[test]
fun test_deserialize_empty_vectors_success() {
    let mut config_bytes = vector[];

    // All defaults: false flags, 0 confirmations, empty vectors
    config_bytes.push_back(0); // use_default_confirmations: false
    config_bytes.push_back(0); // use_default_required_dvns: false
    config_bytes.push_back(0); // use_default_optional_dvns: false

    config_bytes.append(x"0000000000000000"); // confirmations: 0
    config_bytes.push_back(0); // required_dvns length: 0
    config_bytes.push_back(0); // optional_dvns length: 0
    config_bytes.push_back(0); // optional_dvn_threshold: 0

    let config = oapp_uln_config::deserialize(config_bytes);

    assert!(config.uln_config().confirmations() == 0, 0);
    assert!(config.uln_config().required_dvns().length() == 0, 1);
    assert!(config.uln_config().optional_dvns().length() == 0, 2);
}

#[test, expected_failure(abort_code = iota::bcs::EOutOfRange)]
fun test_deserialize_empty_bytes() {
    let config_bytes = vector[];
    oapp_uln_config::deserialize(config_bytes); // Should fail - not enough bytes
}

#[test, expected_failure(abort_code = iota::bcs::EOutOfRange)]
fun test_deserialize_invalid_vector_length_failure() {
    let mut config_bytes = vector[];
    config_bytes.push_back(0);
    config_bytes.push_back(0);
    config_bytes.push_back(0);
    config_bytes.append(x"0F00000000000000");

    config_bytes.push_back(3); // Claims 5 addresses
    // But only provide 2 addresses
    config_bytes.append(x"0000000000000000000000000000000000000000000000000000000000000111");
    config_bytes.append(x"0000000000000000000000000000000000000000000000000000000000000222");
    // Missing 1 more address!

    config_bytes.push_back(1);
    config_bytes.append(x"0000000000000000000000000000000000000000000000000000000000000222");
    config_bytes.push_back(0);

    oapp_uln_config::deserialize(config_bytes); // Should fail
}

#[test]
fun test_assert_oapp_config_happy_flow() {
    let confirmations = 0; // Must be 0 when use_default_confirmations is true
    let required_dvns = vector[]; // Must be empty when use_default_required_dvns is true
    let optional_dvns = vector[]; // Must be empty when use_default_optional_dvns is true
    let optional_dvn_threshold = 0; // Must be 0 when optional_dvns is empty

    let uln_config = uln_config::create(
        confirmations,
        required_dvns,
        optional_dvns,
        optional_dvn_threshold,
    );

    let use_default_confirmations = true;
    let use_default_required_dvns = true;
    let use_default_optional_dvns = true;

    let oapp_uln_config = oapp_uln_config::create(
        use_default_confirmations,
        use_default_required_dvns,
        use_default_optional_dvns,
        uln_config,
    );

    oapp_uln_config.assert_oapp_config();
}

#[test]
fun test_assert_oapp_config_allows_empty_when_not_using_defaults() {
    // Test: Custom config can have empty values
    let confirmations = 0;
    let required_dvns = vector[];
    let optional_dvns = vector[];
    let optional_dvn_threshold = 0;

    let uln_config = uln_config::create(
        confirmations,
        required_dvns,
        optional_dvns,
        optional_dvn_threshold,
    );

    let use_default_confirmations = false; // Using custom (empty is OK)
    let use_default_required_dvns = false; // Using custom (empty is OK)
    let use_default_optional_dvns = false; // Using custom (empty is OK)

    let oapp_uln_config = oapp_uln_config::create(
        use_default_confirmations,
        use_default_required_dvns,
        use_default_optional_dvns,
        uln_config,
    );

    oapp_uln_config.assert_oapp_config();
}

#[test]
fun test_assert_oapp_config_allows_custom_confirmations() {
    // Test: Custom confirmations with default DVNs
    let confirmations = 64; // Custom confirmation count
    let required_dvns = vector[]; // Empty because using defaults
    let optional_dvns = vector[]; // Empty because using defaults
    let optional_dvn_threshold = 0;

    let uln_config = uln_config::create(
        confirmations,
        required_dvns,
        optional_dvns,
        optional_dvn_threshold,
    );

    let use_default_confirmations = false; // Using custom confirmations
    let use_default_required_dvns = true; // Using default DVNs (so must be empty)
    let use_default_optional_dvns = true; // Using default DVNs (so must be empty)

    let oapp_uln_config = oapp_uln_config::create(
        use_default_confirmations,
        use_default_required_dvns,
        use_default_optional_dvns,
        uln_config,
    );

    oapp_uln_config.assert_oapp_config();
}

#[test]
fun test_assert_oapp_config_allows_custom_required_dvns() {
    // Test: Custom required DVNs with default others
    let confirmations = 0; // Must be 0 because using defaults
    let required_dvns = vector[@0x123, @0x456]; // Custom required DVNs
    let optional_dvns = vector[]; // Empty because using defaults
    let optional_dvn_threshold = 0;

    let uln_config = uln_config::create(
        confirmations,
        required_dvns,
        optional_dvns,
        optional_dvn_threshold,
    );

    let use_default_confirmations = true; // Using defaults (so confirmations = 0)
    let use_default_required_dvns = false; // Using custom required DVNs
    let use_default_optional_dvns = true; // Using default optional DVNs

    let oapp_uln_config = oapp_uln_config::create(
        use_default_confirmations,
        use_default_required_dvns,
        use_default_optional_dvns,
        uln_config,
    );

    oapp_uln_config.assert_oapp_config();
}

#[test]
fun test_assert_oapp_config_allows_custom_optional_dvns() {
    // Test: Custom optional DVNs with valid threshold
    let confirmations = 0; // Must be 0 because using defaults
    let required_dvns = vector[]; // Empty because using defaults
    let optional_dvns = vector[@0x123, @0x456, @0x789]; // Custom optional DVNs
    let optional_dvn_threshold = 2; // Valid threshold (2 <= 3)

    let uln_config = uln_config::create(
        confirmations,
        required_dvns,
        optional_dvns,
        optional_dvn_threshold,
    );

    let use_default_confirmations = true; // Using defaults
    let use_default_required_dvns = true; // Using defaults
    let use_default_optional_dvns = false; // Using custom optional DVNs

    let oapp_uln_config = oapp_uln_config::create(
        use_default_confirmations,
        use_default_required_dvns,
        use_default_optional_dvns,
        uln_config,
    );

    oapp_uln_config.assert_oapp_config();
}

// === Expected Failure Tests ===

#[test, expected_failure(abort_code = oapp_uln_config::EInvalidConfirmations)]
fun test_assert_oapp_config_should_fail_when_use_defaults_but_pass_params_confirmations() {
    let confirmations = 64; // ❌ Should be empty when using defaults
    let required_dvns = vector[@0x123, @0x456];
    let optional_dvns = vector[@0x789, @0xabc];
    let optional_dvn_threshold = 0;

    let uln_config = uln_config::create(
        confirmations,
        required_dvns,
        optional_dvns,
        optional_dvn_threshold,
    );

    let use_default_confirmations = true;
    let use_default_required_dvns = false;
    let use_default_optional_dvns = false;

    let oapp_uln_config = oapp_uln_config::create(
        use_default_confirmations,
        use_default_required_dvns,
        use_default_optional_dvns,
        uln_config,
    );

    oapp_uln_config.assert_oapp_config();
}

#[test, expected_failure(abort_code = oapp_uln_config::EInvalidRequiredDVNs)]
fun test_assert_oapp_config_should_fail_when_use_defaults_but_pass_params_required_dvns() {
    let confirmations = 64;
    let required_dvns = vector[@0x123, @0x456]; // ❌ Should be empty when using defaults
    let optional_dvns = vector[@0x789, @0xabc];
    let optional_dvn_threshold = 0;

    let uln_config = uln_config::create(
        confirmations,
        required_dvns,
        optional_dvns,
        optional_dvn_threshold,
    );

    let use_default_confirmations = false;
    let use_default_required_dvns = true;
    let use_default_optional_dvns = false;

    let oapp_uln_config = oapp_uln_config::create(
        use_default_confirmations,
        use_default_required_dvns,
        use_default_optional_dvns,
        uln_config,
    );

    oapp_uln_config.assert_oapp_config();
}

#[test, expected_failure(abort_code = oapp_uln_config::EInvalidOptionalDVNs)]
fun test_assert_oapp_config_should_fail_when_use_defaults_but_pass_params_optional_dvns() {
    let confirmations = 64;
    let required_dvns = vector[@0x123, @0x456];
    let optional_dvns = vector[@0x789, @0xabc]; // ❌ Should be empty when using defaults
    let optional_dvn_threshold = 0;

    let uln_config = uln_config::create(
        confirmations,
        required_dvns,
        optional_dvns,
        optional_dvn_threshold,
    );

    let use_default_confirmations = false;
    let use_default_required_dvns = false;
    let use_default_optional_dvns = true;

    let oapp_uln_config = oapp_uln_config::create(
        use_default_confirmations,
        use_default_required_dvns,
        use_default_optional_dvns,
        uln_config,
    );

    oapp_uln_config.assert_oapp_config();
}

#[test, expected_failure(abort_code = oapp_uln_config::EInvalidOptionalDVNs)]
fun test_threshold_while_using_default_optional_dvns_should_fail() {
    // Test: Should fail when optional_dvn_threshold > 0 while use_default_optional_dvns = true
    let confirmations = 0;
    let required_dvns = vector[];
    let optional_dvns = vector[]; // Must be empty when using defaults
    let optional_dvn_threshold = 2; // ❌ Should be 0 when optional_dvns is empty

    let uln_config = uln_config::create(
        confirmations,
        required_dvns,
        optional_dvns,
        optional_dvn_threshold,
    );

    let oapp_uln_config = oapp_uln_config::create(
        true, // use_default_confirmations
        true, // use_default_required_dvns
        true, // use_default_optional_dvns = true (optional_dvns must be empty)
        uln_config,
    );

    // This should trigger EInvalidOptionalDVNThreshold during assert_oapp_config
    // because threshold > 0 but optional_dvns is empty
    oapp_uln_config.assert_oapp_config();
}

#[test, expected_failure(abort_code = uln_config::EInvalidOptionalDVNThreshold)]
fun test_assert_oapp_config_should_fail_when_invalid_optional_dvn_threshold() {
    // Test: Should fail when optional_dvn_threshold > optional_dvns.length()
    let confirmations = 0;
    let required_dvns = vector[];
    let optional_dvns = vector[@0x123]; // Only 1 DVN
    let optional_dvn_threshold = 3; // ❌ Threshold > DVN count

    let uln_config = uln_config::create(
        confirmations,
        required_dvns,
        optional_dvns,
        optional_dvn_threshold,
    );

    let use_default_confirmations = true;
    let use_default_required_dvns = true;
    let use_default_optional_dvns = false; // Using custom optional DVNs

    let oapp_uln_config = oapp_uln_config::create(
        use_default_confirmations,
        use_default_required_dvns,
        use_default_optional_dvns,
        uln_config,
    );

    oapp_uln_config.assert_oapp_config(); // Should abort here
}

#[test, expected_failure(abort_code = uln_config::EDuplicateRequiredDVNs)]
fun test_assert_oapp_config_should_fail_when_duplicate_required_dvns() {
    // Test: Should fail when required_dvns has duplicates
    let confirmations = 0;
    let required_dvns = vector[@0x123, @0x456, @0x123]; // ❌ Duplicate @0x123
    let optional_dvns = vector[];
    let optional_dvn_threshold = 0;

    let uln_config = uln_config::create(
        confirmations,
        required_dvns,
        optional_dvns,
        optional_dvn_threshold,
    );

    let use_default_confirmations = true;
    let use_default_required_dvns = false; // Using custom required DVNs
    let use_default_optional_dvns = true;

    let oapp_uln_config = oapp_uln_config::create(
        use_default_confirmations,
        use_default_required_dvns,
        use_default_optional_dvns,
        uln_config,
    );

    oapp_uln_config.assert_oapp_config(); // Should abort here
}

#[test, expected_failure(abort_code = uln_config::EDuplicateOptionalDVNs)]
fun test_assert_oapp_config_should_fail_when_duplicate_optional_dvns() {
    // Test: Should fail when optional_dvns has duplicates
    let confirmations = 0;
    let required_dvns = vector[];
    let optional_dvns = vector[@0x123, @0x456, @0x123]; // ❌ Duplicate @0x123
    let optional_dvn_threshold = 2;

    let uln_config = uln_config::create(
        confirmations,
        required_dvns,
        optional_dvns,
        optional_dvn_threshold,
    );

    let use_default_confirmations = true;
    let use_default_required_dvns = true;
    let use_default_optional_dvns = false; // Using custom optional DVNs

    let oapp_uln_config = oapp_uln_config::create(
        use_default_confirmations,
        use_default_required_dvns,
        use_default_optional_dvns,
        uln_config,
    );

    oapp_uln_config.assert_oapp_config(); // Should abort here
}

#[test]
fun test_get_effective_config_happy_flow() {
    // Create default config with some values
    let default_config = uln_config::create(
        64, // default confirmations
        vector[@0xaaa], // default required DVNs
        vector[@0xbbb, @0xccc], // default optional DVNs
        2, // default threshold
    );

    // Create OApp config that uses custom values (not defaults)
    let custom_uln_config = uln_config::create(
        10, // custom confirmations
        vector[@0x123], // custom required DVNs
        vector[@0x456], // custom optional DVNs
        1, // custom threshold
    );

    let oapp_config = oapp_uln_config::create(
        false, // use_default_confirmations = false (use custom)
        false, // use_default_required_dvns = false (use custom)
        false, // use_default_optional_dvns = false (use custom)
        custom_uln_config,
    );

    let effective_config = oapp_config.get_effective_config(&default_config);

    assert!(effective_config.confirmations() == 10, 1);
    assert!(effective_config.required_dvns() == vector[@0x123], 2);
    assert!(effective_config.optional_dvns() == vector[@0x456], 3);
    assert!(effective_config.optional_dvn_threshold() == 1, 4);
}

#[test, expected_failure(abort_code = uln_config::EAtLeastOneDVN)]
fun test_get_effective_config_should_fail_when_no_dvns() {
    // Create default config with some values
    let default_config = uln_config::create(
        64, // default confirmations
        vector[@0xaaa], // default required DVNs
        vector[@0xbbb, @0xccc], // default optional DVNs
        2, // default threshold
    );

    // Create OApp config that uses custom values (not defaults)
    let custom_uln_config = uln_config::create(
        0, // custom confirmations
        vector[], // custom required DVNs
        vector[], // custom optional DVNs
        0, // custom threshold
    );

    let oapp_config = oapp_uln_config::create(
        false, // use_default_confirmations = false (use custom)
        false, // use_default_required_dvns = false (use custom)
        false, // use_default_optional_dvns = false (use custom)
        custom_uln_config,
    );

    oapp_config.get_effective_config(&default_config);
}

#[test]
fun test_oapp_uln_config_integration() {
    let uln_config = uln_config::create(1000, vector[@0x123], vector[@0x456], 1);
    let oapp_config = oapp_uln_config::create(false, true, false, uln_config);

    assert!(oapp_config.uln_config().confirmations() == 1000, 1);
    assert!(oapp_config.uln_config().optional_dvn_threshold() == 1, 2);
    assert!(oapp_config.uln_config().required_dvns() == &vector[@0x123], 3);
    assert!(oapp_config.uln_config().optional_dvns() == &vector[@0x456], 4);

    assert!(oapp_config.use_default_confirmations() == false, 5);
    assert!(oapp_config.use_default_required_dvns() == true, 6);
    assert!(oapp_config.use_default_optional_dvns() == false, 7);
}
