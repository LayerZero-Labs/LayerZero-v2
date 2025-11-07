// This module is only used to help with the testing of OFT contracts.
#[test_only]
module oft::scenario_utils;

use iota::test_scenario::{Self, Scenario};

// === Public Functions ===

/// Take a shared object by its address from the test scenario
public fun take_shared_by_address<T: key>(scenario: &mut Scenario, address: address): T {
    test_scenario::take_shared_by_id<T>(scenario, object::id_from_address(address))
}

/// Take an object from sender by its address from the test scenario
public fun take_from_sender_by_address<T: key + store>(scenario: &mut Scenario, address: address): T {
    test_scenario::take_from_address_by_id<T>(scenario, scenario.sender(), object::id_from_address(address))
}
