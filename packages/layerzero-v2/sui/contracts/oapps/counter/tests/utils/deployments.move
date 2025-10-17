module counter::deployments;

use counter::scenario_utils;
use std::{ascii::String, type_name};
use sui::{table::{Self, Table}, test_scenario::Scenario};
use utils::table_ext;

public struct Deployments {
    deployments: Table<DeploymentKey, address>,
}

public fun new(ctx: &mut TxContext): Deployments {
    Deployments { deployments: table::new(ctx) }
}

public struct DeploymentKey has copy, drop, store {
    eid: u32,
    type_name: String,
    index: u64, // Index to support multiple deployments of the same type
}

public fun get_deployment_object<T: key>(deployments: &Deployments, scenario: &mut Scenario, eid: u32): T {
    scenario_utils::take_shared_by_address<T>(scenario, deployments.get_deployment<T>(eid))
}

public fun get_deployment_object_indexed<T: key>(
    deployments: &Deployments,
    scenario: &mut Scenario,
    eid: u32,
    index: u64,
): T {
    scenario_utils::take_shared_by_address<T>(scenario, deployments.get_indexed_deployment<T>(eid, index))
}

/// Set a deployment for a specific eid with default index 0
public fun set_deployment<T>(deployments: &mut Deployments, eid: u32, address: address) {
    set_indexed_deployment<T>(deployments, eid, 0, address);
}

/// Set a deployment for a specific eid with a specific index
public fun set_indexed_deployment<T>(deployments: &mut Deployments, eid: u32, index: u64, address: address) {
    let key = DeploymentKey { eid, type_name: type_name::get<T>().into_string(), index };
    table_ext::upsert!(&mut deployments.deployments, key, address);
}

/// Get a deployment for a specific eid with default index 0
public fun get_deployment<T>(deployments: &Deployments, eid: u32): address {
    get_indexed_deployment<T>(deployments, eid, 0)
}

/// Get a deployment for a specific eid with a specific index
public fun get_indexed_deployment<T>(deployments: &Deployments, eid: u32, index: u64): address {
    let key = DeploymentKey { eid, type_name: type_name::get<T>().into_string(), index };
    deployments.deployments[key]
}

/// Check if a deployment exists for a specific eid and index
public fun has_indexed_deployment<T>(deployments: &Deployments, eid: u32, index: u64): bool {
    let key = DeploymentKey { eid, type_name: type_name::get<T>().into_string(), index };
    deployments.deployments.contains(key)
}
