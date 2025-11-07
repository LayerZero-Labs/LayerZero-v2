/// Package Whitelist Validator
///
/// This module provides a security mechanism for validating packages that can be called
/// through Programmable Transaction Blocks (PTBs). It maintains a whitelist of trusted
/// package addresses and validates witness types to ensure only authorized packages
/// can be added to the whitelist.
module package_whitelist_validator::package_whitelist_validator;

use blocked_message_lib::blocked_message_lib::BlockedMessageLib;
use endpoint_v2::endpoint_v2::EndpointV2;
use simple_message_lib::simple_message_lib::SimpleMessageLib;
use std::type_name;
use iota::{event, table};
use treasury::treasury::Treasury;
use uln_302::uln_302::Uln302;
use utils::{buffer_reader, package, table_ext};

// === Error Codes ===

const EInvalidWitness: u64 = 1;

// === Constants ===

/// The required suffix pattern for valid witness types
/// Witnesses must be named `LayerZeroWitness` and be in a module ending with `_witness`
const EXPECTED_WITNESS_SUFFIX: vector<u8> = b"_witness::LayerZeroWitness";

// === Structs ===

public struct Validator has key {
    id: UID,
    /// Table mapping package addresses to their whitelist status (always true if present)
    whitelist: table::Table<address, bool>,
}

// === Events ===

public struct WhitelistAddedEvent has copy, drop {
    package: address,
}

// === Initialization ===

/// Initializes the package whitelist with default trusted packages
/// This function is called once when the module is published
fun init(ctx: &mut TxContext) {
    let mut validator = Validator {
        id: object::new(ctx),
        whitelist: table::new(ctx),
    };

    // Initialize the default whitelist with core LayerZero packages
    let default_packages = vector[
        package::package_of_type<EndpointV2>(),
        package::package_of_type<BlockedMessageLib>(),
        package::package_of_type<SimpleMessageLib>(),
        package::package_of_type<Uln302>(),
        package::package_of_type<Treasury>(),
    ];
    default_packages.do!(|package_addr| {
        table_ext::upsert!(&mut validator.whitelist, package_addr, true);
    });

    transfer::share_object(validator);
}

// === Whitelist Functions ===

/// Adds a package to the whitelist using witness-based authorization
///
/// This function allows a package to add itself to the whitelist by providing
/// a valid witness. The witness must be a struct named `LayerZeroWitness`
/// located in a module ending with `_witness`.
///
/// **Type Parameters**
/// * `T` - The witness type that must match the expected pattern
///
/// **Parameters**
/// * `_witness` - The witness struct used for authorization (consumed)
public fun add_whitelist<T: drop>(self: &mut Validator, _witness: T) {
    assert_witness_pattern<T>();
    let package = package::package_of_type<T>();
    self.whitelist.add(package, true);
    event::emit(WhitelistAddedEvent { package });
}

// === View Functions ===

/// Validates that all packages in the provided list are whitelisted
public fun validate(self: &Validator, packages: vector<address>): bool {
    packages.all!(|package| self.is_whitelisted(*package))
}

/// Checks if a specific package address is whitelisted
public fun is_whitelisted(self: &Validator, package: address): bool {
    // Since we only store `true` values, contains() is sufficient
    self.whitelist.contains(package)
}

// === Internal Functions ===

/// Validates that a witness type matches the expected pattern
fun assert_witness_pattern<T>() {
    let witness_type = type_name::get<T>();

    // Reject primitive types (u8, u64, bool, address, etc.)
    assert!(!witness_type.is_primitive(), EInvalidWitness);

    // Convert type name to bytes for pattern matching
    let type_str = witness_type.into_string().into_bytes();

    let suffix = EXPECTED_WITNESS_SUFFIX;
    let suffix_len = suffix.length();
    let type_len = type_str.length();

    // Ensure the type name is at least as long as the required suffix
    assert!(type_len >= suffix_len, EInvalidWitness);

    // Use buffer_reader for efficient suffix comparison
    let mut type_reader = buffer_reader::create(type_str);
    let type_suffix = type_reader.skip(type_len - suffix_len).read_bytes_until_end();

    // Verify the suffix matches exactly
    assert!(type_suffix == suffix, EInvalidWitness);
}

// === Test Helper Functions ===

#[test_only]
public(package) fun create_for_testing(ctx: &mut TxContext): Validator {
    Validator {
        id: object::new(ctx),
        whitelist: table::new(ctx),
    }
}

#[test_only]
public(package) fun add_package_for_testing(self: &mut Validator, package: address) {
    self.whitelist.add(package, true);
}

#[test_only]
public(package) fun assert_witness_pattern_for_testing<T>() {
    assert_witness_pattern<T>()
}
