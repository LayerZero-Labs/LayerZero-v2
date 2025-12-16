#[test_only]
module call::call_cap_tests;

use call::call_cap;
use iota::{test_scenario as ts, test_utils};
use utils::package;

// === Test Constants ===

const ADMIN: address = @0x1;

// === Test Structs for Package Capabilities ===

/// One-time witness for this test module (follows IOTA naming convention)
public struct CALL_CAP_TESTS has drop {}

/// Non-one-time witness struct for negative testing
/// This struct has drop ability but is not a proper one-time witness
public struct NotAOneTimeWitness has drop {}

// === Helper Functions ===

fun setup(): ts::Scenario {
    ts::begin(ADMIN)
}

fun clean(scenario: ts::Scenario) {
    ts::end(scenario);
}

// === Individual CallCap Tests ===

#[test]
fun test_new_individual_cap() {
    let mut scenario = setup();

    let individual_cap = call_cap::new_individual_cap(scenario.ctx());

    // Verify it's an individual cap
    assert!(individual_cap.is_individual(), 1);
    assert!(!individual_cap.is_package(), 2);

    // Verify ID matches UID address for individual caps
    assert!(individual_cap.id() == object::id_address(&individual_cap), 3);

    // Verify package_address returns None for individual caps
    assert!(individual_cap.package_address().is_none(), 4);

    test_utils::destroy(individual_cap);
    clean(scenario);
}

#[test]
fun test_multiple_individual_caps_have_different_ids() {
    let mut scenario = setup();

    let individual_cap1 = call_cap::new_individual_cap(scenario.ctx());
    let individual_cap2 = call_cap::new_individual_cap(scenario.ctx());

    // Verify different individual caps have different IDs
    assert!(individual_cap1.id() != individual_cap2.id(), 0);
    assert!(object::id_address(&individual_cap1) != object::id_address(&individual_cap2), 1);

    test_utils::destroy(individual_cap1);
    test_utils::destroy(individual_cap2);
    clean(scenario);
}

// === Package CallCap Tests ===

#[test]
fun test_new_package_cap() {
    let mut scenario = setup();

    let witness = test_utils::create_one_time_witness<CALL_CAP_TESTS>();
    let package_cap = call_cap::new_package_cap(&witness, scenario.ctx());

    // Verify cap was created successfully
    assert!(object::id_address(&package_cap) != @0x0, 0);

    // Verify it's a package cap
    assert!(!package_cap.is_individual(), 1);
    assert!(package_cap.is_package(), 2);

    // Verify package_address returns Some for package caps
    assert!(package_cap.package_address().is_some(), 3);

    // Verify ID matches package address, not UID address
    let package_addr = package_cap.package_address().destroy_some();
    assert!(package_cap.id() == package_addr, 4);
    assert!(package_cap.id() != object::id_address(&package_cap), 5);
    assert!(package_cap.id() == package::package_of_type<CALL_CAP_TESTS>(), 6);

    test_utils::destroy(package_cap);
    clean(scenario);
}

#[test]
fun test_same_package_caps_have_same_logical_id() {
    let mut scenario = setup();

    let witness1 = test_utils::create_one_time_witness<CALL_CAP_TESTS>();
    let witness2 = test_utils::create_one_time_witness<CALL_CAP_TESTS>();
    let package_cap1 = call_cap::new_package_cap(&witness1, scenario.ctx());
    let package_cap2 = call_cap::new_package_cap(&witness2, scenario.ctx());

    // Verify same package caps have same logical ID (package address)
    assert!(package_cap1.id() == package_cap2.id(), 0);

    // But different UID addresses (different objects)
    assert!(object::id_address(&package_cap1) != object::id_address(&package_cap2), 1);

    // Both should have the same package address
    assert!(package_cap1.package_address() == package_cap2.package_address(), 2);

    test_utils::destroy(package_cap1);
    test_utils::destroy(package_cap2);
    clean(scenario);
}

// === Negative Tests ===

#[test]
#[expected_failure(abort_code = call_cap::EBadWitness)]
fun test_new_package_cap_with_non_one_time_witness() {
    let mut scenario = setup();

    // Try to create a package cap with a non-one-time witness
    // This should fail because NotAOneTimeWitness is not a proper one-time witness
    let fake_witness = NotAOneTimeWitness {};
    let package_cap = call_cap::new_package_cap(&fake_witness, scenario.ctx());

    // These lines should never be reached due to the expected failure
    test_utils::destroy(package_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call_cap::EBadWitness)]
fun test_new_package_cap_with_regular_type() {
    let mut scenario = setup();

    // Try to create a package cap with a regular type (u64)
    // This should fail because u64 is not a one-time witness
    let fake_witness = 42u64;
    let package_cap = call_cap::new_package_cap(&fake_witness, scenario.ctx());

    // These lines should never be reached due to the expected failure
    test_utils::destroy(package_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = call_cap::EBadWitness)]
fun test_new_package_cap_with_string() {
    let mut scenario = setup();

    // Try to create a package cap with a string
    // This should fail because string is not a one-time witness
    let fake_witness = b"not_a_witness";
    let package_cap = call_cap::new_package_cap(&fake_witness, scenario.ctx());

    // These lines should never be reached due to the expected failure
    test_utils::destroy(package_cap);
    clean(scenario);
}
