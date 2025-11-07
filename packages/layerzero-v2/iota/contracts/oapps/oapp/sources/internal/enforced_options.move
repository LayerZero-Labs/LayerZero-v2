/// Enforced Options Management Module
module oapp::enforced_options;

use iota::{event, table::{Self, Table}};
use utils::{buffer_reader, buffer_writer, table_ext};

// === Constants ===

const OPTION_TYPE_3: u16 = 3;

// === Errors ===

const EEnforcedOptionsNotFound: u64 = 1;
const EInvalidOptionsLength: u64 = 2;
const EInvalidOptionsType: u64 = 3;

// === Structs ===

/// Manages enforced options for cross-chain message execution.
///
/// This struct maintains a mapping of (endpoint ID, message type) pairs to their
/// corresponding enforced options.
public struct EnforcedOptions has store {
    options: Table<EnforcedOptionsKey, vector<u8>>,
}

/// Key structure for identifying enforced options by endpoint and message type.
public struct EnforcedOptionsKey has copy, drop, store {
    eid: u32,
    msg_type: u16,
}

// === Events ===

/// Event emitted when enforced options are set or updated for a specific endpoint and message type.
public struct EnforcedOptionSetEvent has copy, drop {
    /// Address of the OApp package
    oapp: address,
    /// Endpoint ID of the destination blockchain
    eid: u32,
    /// Message type identifier
    msg_type: u16,
    /// Enforced option bytes
    options: vector<u8>,
}

// === Package Functions ===

/// Creates a new empty EnforcedOptions registry.
public(package) fun new(ctx: &mut TxContext): EnforcedOptions {
    EnforcedOptions { options: table::new(ctx) }
}

/// Sets or updates enforced options for a specific endpoint and message type.
///
/// Parameters:
/// - `self`: Mutable reference to the EnforcedOptions registry
/// - `oapp`: The address of the OApp package
/// - `eid`: The Endpoint ID of the destination blockchain
/// - `msg_type`: The message type identifier
/// - `options`: The enforced option bytes (must be type 3 format)
///
/// Aborts:
/// - `EInvalidOptionsLength`: If options data is too short
/// - `EInvalidOptionsType`: If options are not type 3 format
public(package) fun set_enforced_options(
    self: &mut EnforcedOptions,
    oapp: address,
    eid: u32,
    msg_type: u16,
    options: vector<u8>,
) {
    assert_options_type3(options);
    table_ext::upsert!(&mut self.options, EnforcedOptionsKey { eid, msg_type }, options);
    event::emit(EnforcedOptionSetEvent { oapp, eid, msg_type, options });
}

// === View Functions ===

/// Retrieves the enforced options for a specific endpoint and message type.
///
/// Parameters:
/// - `self`: Reference to the EnforcedOptions registry
/// - `eid`: The Endpoint ID of the destination blockchain
/// - `msg_type`: The message type identifier
///
/// Returns:
/// Reference to the enforced option bytes for the specified endpoint and message type
///
/// Aborts:
/// - `EEnforcedOptionsNotFound`: If no enforced options are set for the given EID and message type
public(package) fun get_enforced_options(self: &EnforcedOptions, eid: u32, msg_type: u16): &vector<u8> {
    table_ext::borrow_or_abort!(&self.options, EnforcedOptionsKey { eid, msg_type }, EEnforcedOptionsNotFound)
}

/// Combines enforced options with additional user-provided options.
///
/// This function merges the mandatory enforced options with optional extra options
/// to create the final options.
///
/// Parameters:
/// - `self`: Reference to the EnforcedOptions registry
/// - `eid`: The Endpoint ID of the destination blockchain
/// - `msg_type`: The message type identifier
/// - `extra_options`: Additional user-provided option bytes to combine
///
/// Returns:
/// The combined option bytes containing both enforced and extra options
///
/// Aborts:
/// - `EInvalidOptionsLength`: If extra_options data is too short
/// - `EInvalidOptionsType`: If extra_options are not type 3 format
public(package) fun combine_options(
    self: &EnforcedOptions,
    eid: u32,
    msg_type: u16,
    extra_options: vector<u8>,
): vector<u8> {
    let enforced_options =
        *table_ext::borrow_with_default!(&self.options, EnforcedOptionsKey { eid, msg_type }, &vector[]);

    // Early return if either options is empty
    if (enforced_options.is_empty()) return extra_options;
    if (extra_options.is_empty()) return enforced_options;

    // Validate extra options before combining
    assert_options_type3(extra_options);

    // Combine options
    let reader = buffer_reader::create(extra_options).skip(2); // skip the type(2 bytes)
    let mut writer = buffer_writer::create(enforced_options);
    writer.write_bytes(reader.read_bytes_until_end());
    writer.to_bytes()
}

// === Internal Functions ===

/// Validates that the provided options are in the required type 3 format.
fun assert_options_type3(options: vector<u8>) {
    assert!(options.length() >= 2, EInvalidOptionsLength);
    assert!(buffer_reader::create(options).read_u16() == OPTION_TYPE_3, EInvalidOptionsType);
}
