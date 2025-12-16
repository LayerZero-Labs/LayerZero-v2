// This module is only used to help with the testing of OFT contracts.
#[test_only]
module oft::deployments;

use oft::scenario_utils;
use iota::{table::{Self, Table}, test_scenario::Scenario, test_utils};

// === Structs ===

/// Deployment registry for managing test contract addresses across multiple endpoints
public struct Deployments has key, store {
    id: UID,
    deployments: Table<DeploymentKey, address>,
}

/// Key for deployment lookups combining type and endpoint ID
public struct DeploymentKey has copy, drop, store {
    type_name: std::ascii::String,
    eid: u32,
}

// === Constructor ===

/// Create a new deployments registry
public fun new(ctx: &mut TxContext): Deployments {
    Deployments {
        id: object::new(ctx),
        deployments: table::new(ctx),
    }
}

// === Public Functions ===

/// Set deployment address for a specific type and endpoint
public fun set_deployment<T>(self: &mut Deployments, eid: u32, address: address) {
    let key = DeploymentKey {
        type_name: std::type_name::get<T>().into_string(),
        eid,
    };

    if (self.deployments.contains(key)) {
        *self.deployments.borrow_mut(key) = address;
    } else {
        self.deployments.add(key, address);
    };
}

/// Get deployment address for a specific type and endpoint
public fun get_deployment<T>(self: &Deployments, eid: u32): address {
    let key = DeploymentKey {
        type_name: std::type_name::get<T>().into_string(),
        eid,
    };
    *self.deployments.borrow(key)
}

/// Check if deployment exists for a specific type and endpoint
public fun has_deployment<T>(self: &Deployments, eid: u32): bool {
    let key = DeploymentKey {
        type_name: std::type_name::get<T>().into_string(),
        eid,
    };
    self.deployments.contains(key)
}

public fun take_shared_object<T: key>(self: &Deployments, scenario: &mut Scenario, eid: u32): T {
    let object_address = self.get_deployment<T>(eid);
    scenario_utils::take_shared_by_address<T>(scenario, object_address)
}

public fun take_owned_object<T: key + store>(self: &Deployments, scenario: &mut Scenario, eid: u32): T {
    let object_address = self.get_deployment<T>(eid);
    scenario_utils::take_from_sender_by_address<T>(scenario, object_address)
}

// === Destructor ===

/// Destroy the deployments registry (for test cleanup)
public fun destroy(self: Deployments) {
    let Deployments { id, deployments } = self;
    id.delete();
    deployments.destroy_empty();
}

// === Test Utilities ===

#[test_only]
public fun destroy_for_testing(self: Deployments) {
    let Deployments { id, deployments } = self;
    test_utils::destroy(id);
    test_utils::destroy(deployments);
}
