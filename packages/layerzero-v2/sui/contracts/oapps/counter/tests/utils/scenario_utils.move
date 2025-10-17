// Utility functions for test scenarios
#[test_only]
module counter::scenario_utils;

use sui::test_scenario::Scenario;

/// Take an object from sender by address (convenience wrapper)
public fun take_from_sender_by_address<T: key>(scenario: &mut Scenario, address: address): T {
    scenario.take_from_sender_by_id<T>(object::id_from_address(address))
}

/// Take a shared object by address (convenience wrapper)
public fun take_shared_by_address<T: key>(scenario: &mut Scenario, address: address): T {
    scenario.take_shared_by_id<T>(object::id_from_address(address))
}
