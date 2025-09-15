/// Capability management for cross-contract call authorization
///
/// This module provides CallCap objects that serve as authorization tokens to perform
/// specific operations on calls within the LayerZero ecosystem. It supports both
/// individual and package-based capabilities.
///
/// Usage Patterns:
/// 1. **Package Capabilities**: Created by contracts using one-time witness pattern
///    - Identity derived from package address
///    - Shared across all instances from same package
///    - Used for protocol-level operations
///
/// 2. **Individual Capabilities**: Created for individual entities or instances
///    - Identity derived from CallCap's UID
///    - Unique per capability instance
///    - Used for individual-specific operations
module call::call_cap;

use sui::types;
use utils::package;

// === Errors ===

const EBadWitness: u64 = 1;

// === Structs ===

/// Capability object that authorizes call operations
///
/// The CallCap serves dual purposes based on its type:
/// 1. For Individual caps: Uses the UID as the unique identifier
/// 2. For Package caps: Uses the package address as the unique identifier
///
/// This design eliminates the need for layerzero components to maintain a separate mapping
/// between CallCap IDs and package addresses. The identifier directly represents the
/// authorization source.
public struct CallCap has key, store {
    id: UID,
    cap_type: CapType,
}

/// Type that determines how the CallCap identifier is resolved
///
/// - Individual: Individual capability with unique identity, uses the CallCap's UID address as identifier
/// - Package: Contract-based capability, uses the package address as identifier
public enum CapType has copy, drop, store {
    Individual,
    Package(address),
}

// === Constructor ===

/// Create a new CallCap for a contract using one-time witness pattern
///
/// This creates a CallCap that uses the package address as its identifier.
/// Multiple instances deployed from the same package will share the same
/// logical identity.
///
/// Parameters
/// - `witness`: One-time witness proving package ownership
///
/// Returns a CallCap with the package address as its identifier.
public fun new_package_cap<T: drop>(witness: &T, ctx: &mut TxContext): CallCap {
    // Make sure there's only one instance of the type T
    assert!(types::is_one_time_witness(witness), EBadWitness);

    let package = package::original_package_of_type<T>();
    CallCap { id: object::new(ctx), cap_type: CapType::Package(package) }
}

/// Create a new CallCap for an individual entity
///
/// This creates a CallCap that uses its own UID as the identifier,
/// suitable for individual-specific operations.
///
/// Returns a CallCap with its UID address as the identifier
public fun new_individual_cap(ctx: &mut TxContext): CallCap {
    CallCap { id: object::new(ctx), cap_type: CapType::Individual }
}

// === View Functions ===

/// Get the unique identifier for this CallCap
///
/// Returns the appropriate identifier based on the capability type:
/// - For Individual: Returns the UID address of this CallCap object
/// - For Package: Returns the package address
public fun id(self: &CallCap): address {
    match (self.cap_type) {
        CapType::Individual => self.id.to_address(),
        CapType::Package(package) => package,
    }
}

/// Check if this is an Individual CallCap
public fun is_individual(self: &CallCap): bool {
    self.cap_type == CapType::Individual
}

/// Check if this is a Package CallCap
public fun is_package(self: &CallCap): bool {
    self.cap_type != CapType::Individual
}

/// Get the package address for a Package CallCap
///
/// Returns None if this is an Individual CallCap
public fun package_address(self: &CallCap): Option<address> {
    match (self.cap_type) {
        CapType::Package(package) => option::some(package),
        CapType::Individual => option::none(),
    }
}

// === Test Helper Functions ===

#[test_only]
public fun new_package_cap_for_test(ctx: &mut TxContext): CallCap {
    CallCap { id: object::new(ctx), cap_type: CapType::Package(ctx.fresh_object_address()) }
}

#[test_only]
public fun new_package_cap_with_address_for_test(ctx: &mut TxContext, source: address): CallCap {
    CallCap { id: object::new(ctx), cap_type: CapType::Package(source) }
}
