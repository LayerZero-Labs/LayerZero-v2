/// Package Address Utilities
///
/// This module provides utilities for extracting package addresses from Move types.
/// The module supports both original package addresses (from type definition) and
/// current package addresses (after potential upgrades).
module utils::package;

use std::{ascii, type_name};
use sui::{address, hex};

/// Gets the original package address where a type was first defined.
/// This returns the package address from the original type definition,
/// which remains constant even after package upgrades.
public fun original_package_of_type<T>(): address {
    extract_package_address(type_name::get_with_original_ids<T>())
}

/// Gets the current package address where a type is defined.
/// This returns the current package address, which may change after upgrades.
public fun package_of_type<T>(): address {
    extract_package_address(type_name::get<T>())
}

/// Extracts the package address from a type name.
/// Converts the hex-encoded address string to an address type.
fun extract_package_address(type_name: type_name::TypeName): address {
    address::from_bytes(
        hex::decode(*ascii::as_bytes(&type_name.get_address())),
    )
}
