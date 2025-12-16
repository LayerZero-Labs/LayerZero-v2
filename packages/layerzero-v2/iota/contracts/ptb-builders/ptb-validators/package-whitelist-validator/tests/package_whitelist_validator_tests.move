#[test_only]
module package_whitelist_validator::package_whitelist_validator_tests;

use package_whitelist_validator::{mock_witness, package_whitelist_validator::{Self, Validator}};
use iota::{test_scenario::{Self as ts, Scenario}, test_utils};

// Test witness structs
public struct ValidWitness has drop {}
public struct InvalidWitness has drop {}

// === Test Constants ===

const ADMIN: address = @0xA;
// const USER: address = @0xB; // Unused for now
const PACKAGE_ADDR: address = @0xC;

// === Helper Functions ===

fun init_test_whitelist(scenario: &mut Scenario): Validator {
    ts::next_tx(scenario, ADMIN);
    let ctx = ts::ctx(scenario);

    let whitelist = package_whitelist_validator::create_for_testing(ctx);
    whitelist
}

// === Whitelist Function Tests ===

#[test]
fun test_add_whitelist_with_valid_witness() {
    let mut scenario = ts::begin(ADMIN);
    let mut whitelist = init_test_whitelist(&mut scenario);

    // Test adding with valid witness
    ts::next_tx(&mut scenario, ADMIN);
    {
        let witness = mock_witness::new();
        whitelist.add_whitelist(witness);

        // Check if the package was added
        let package_addr = @package_whitelist_validator;
        assert!(whitelist.is_whitelisted(package_addr), 0);
    };

    test_utils::destroy(whitelist);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = package_whitelist_validator::EInvalidWitness)]
fun test_add_whitelist_with_invalid_witness_fails() {
    let mut scenario = ts::begin(ADMIN);
    let mut whitelist = init_test_whitelist(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let invalid_witness = InvalidWitness {};
        whitelist.add_whitelist(invalid_witness);
    };

    test_utils::destroy(whitelist);
    ts::end(scenario);
}

// === View Function Tests ===

#[test]
fun test_is_whitelisted() {
    let mut scenario = ts::begin(ADMIN);
    let mut whitelist = init_test_whitelist(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        // Test non-whitelisted package
        assert!(!whitelist.is_whitelisted(PACKAGE_ADDR), 0);

        // Add package to whitelist manually for testing
        whitelist.add_package_for_testing(PACKAGE_ADDR);

        // Test whitelisted package
        assert!(whitelist.is_whitelisted(PACKAGE_ADDR), 1);
    };

    test_utils::destroy(whitelist);
    ts::end(scenario);
}

#[test]
fun test_validate_all_whitelisted() {
    let mut scenario = ts::begin(ADMIN);
    let mut whitelist = init_test_whitelist(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let package1 = @0x1;
        let package2 = @0x2;
        let package3 = @0x3;

        // Add packages to whitelist
        whitelist.add_package_for_testing(package1);
        whitelist.add_package_for_testing(package2);
        whitelist.add_package_for_testing(package3);

        let packages = vector[package1, package2, package3];

        // All packages are whitelisted, should return true
        assert!(whitelist.validate(packages), 0);
    };

    test_utils::destroy(whitelist);
    ts::end(scenario);
}

#[test]
fun test_validate_some_not_whitelisted() {
    let mut scenario = ts::begin(ADMIN);
    let mut whitelist = init_test_whitelist(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let package1 = @0x1;
        let package2 = @0x2;
        let package3 = @0x3;

        // Only add some packages to whitelist
        whitelist.add_package_for_testing(package1);
        whitelist.add_package_for_testing(package3);

        let packages = vector[package1, package2, package3]; // package2 not whitelisted

        // Not all packages are whitelisted, should return false
        assert!(!whitelist.validate(packages), 0);
    };

    test_utils::destroy(whitelist);
    ts::end(scenario);
}

#[test]
fun test_validate_empty_list() {
    let mut scenario = ts::begin(ADMIN);
    let whitelist = init_test_whitelist(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let empty_packages = vector[];

        // Empty list should return true (all zero packages are whitelisted)
        assert!(whitelist.validate(empty_packages), 0);
    };

    test_utils::destroy(whitelist);
    ts::end(scenario);
}

// === Witness Pattern Tests ===

#[test]
fun test_assert_witness_pattern_valid() {
    // This test will pass because mock_witness::LayerZeroWitness ends with "_witness::LayerZeroWitness"
    package_whitelist_validator::assert_witness_pattern_for_testing<mock_witness::LayerZeroWitness>();
}

#[test]
#[expected_failure(abort_code = package_whitelist_validator::EInvalidWitness)]
fun test_assert_witness_pattern_invalid_struct_name() {
    // This should fail because InvalidWitness doesn't end with the expected suffix
    package_whitelist_validator::assert_witness_pattern_for_testing<InvalidWitness>();
}

#[test]
#[expected_failure(abort_code = package_whitelist_validator::EInvalidWitness)]
fun test_assert_witness_pattern_primitive_type() {
    // This should fail because u64 is a primitive type
    package_whitelist_validator::assert_witness_pattern_for_testing<u64>();
}

#[test]
fun test_validate_single_package() {
    let mut scenario = ts::begin(ADMIN);
    let mut whitelist = init_test_whitelist(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let package_addr = @0x123;
        whitelist.add_package_for_testing(package_addr);

        let packages = vector[package_addr];
        assert!(whitelist.validate(packages), 0);

        let non_whitelisted_packages = vector[@0x456];
        assert!(!whitelist.validate(non_whitelisted_packages), 1);
    };

    test_utils::destroy(whitelist);
    ts::end(scenario);
}
