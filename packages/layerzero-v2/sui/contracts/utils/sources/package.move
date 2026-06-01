/// Package Address Utilities
///
/// This module provides utilities for extracting package addresses from Move types.
/// The module supports both original package addresses (from type definition) and
/// current package addresses (after potential upgrades).
module utils::package;

use std::type_name;
use sui::{address, hex};

/// Gets the original package address where a type was first defined.
/// This returns the package address from the original type definition,
/// which remains constant even after package upgrades.
public fun original_package_of_type<T>(): address {
    extract_package_address(type_name::with_original_ids<T>())
}

/// Gets the current package address where a type is defined.
/// This returns the current package address, which may change after upgrades.
public fun package_of_type<T>(): address {
    extract_package_address(type_name::with_defining_ids<T>())
}

/// Extracts the package address from a type name.
/// Converts the hex-encoded address string to an address type.
fun extract_package_address(type_name: type_name::TypeName): address {
    let package_address = type_name.address_string();
    address::from_bytes(hex::decode(*package_address.as_bytes()))
}
