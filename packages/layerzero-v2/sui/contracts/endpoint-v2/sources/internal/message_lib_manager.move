/// Message Library Manager
///
/// This module manages the registration, configuration, and validation of message libraries
/// within the LayerZero V2 Endpoint. Message libraries are responsible for handling the
/// actual sending and receiving of cross-chain messages.
///
/// **Library Types**:
/// - Send libraries: Handle outbound message transmission
/// - Receive libraries: Handle inbound message verification and processing
/// - Send and receive libraries: Handle both directions
///
/// **Configuration Hierarchy**:
/// 1. **Default configurations**: Global settings per endpoint ID (EID)
/// 2. **OApp-specific configurations**: Per-OApp overrides for specific EIDs
/// 3. **Timeout mechanisms**: Grace periods for library transitions
///
/// **Timeout Mechanism**: When switching receive libraries, a timeout period allows the old
/// library to continue processing messages that were already in flight.
module endpoint_v2::message_lib_manager;

use endpoint_v2::{
    message_lib_set_config::{Self, SetConfigParam as MessageLibSetConfigParam},
    message_lib_type::{Self, MessageLibType},
    timeout::{Self, Timeout}
};
use std::u64;
use sui::{clock::Clock, event, table::{Self, Table}, table_vec::{Self, TableVec}};
use utils::table_ext;

// === Error Codes ===

const EAlreadyRegistered: u64 = 1;
const EDefaultReceiveLibUnavailable: u64 = 2;
const EDefaultSendLibUnavailable: u64 = 3;
const EInvalidAddress: u64 = 4;
const EInvalidBounds: u64 = 5;
const EInvalidExpiry: u64 = 6;
const EInvalidReceiveLib: u64 = 7;
const EOnlyNonDefaultLib: u64 = 8;
const EOnlyReceiveLib: u64 = 9;
const EOnlyRegisteredLib: u64 = 10;
const EOnlySendLib: u64 = 11;
const ESameValue: u64 = 12;

// === Constants ===

/// Represents the default library (no specific library configured)
/// When set to this value, the system falls back to default configurations
const DEFAULT_LIB: address = @0x0;

// === Structs ===

/// Central manager for all message library operations within an endpoint.
/// Manages both the registry of available libraries and their configurations
/// at both the default (per-EID) and application-specific levels.
public struct MessageLibManager has store {
    // Registry of all available message libraries
    registry: MessageLibRegistry,
    // Default library configurations per endpoint ID (EID -> config)
    // These serve as fallbacks when OApps don't have specific configurations
    default_configs: Table<u32, MessageLibConfig>,
    // OApp-specific library configurations ((oapp, eid) -> config)
    // These override default configurations for specific applications
    oapp_configs: Table<OAppConfigKey, MessageLibConfig>,
}

/// Registry for managing message library registrations and metadata.
///
/// The registry uses the message library package address as the unique identifier
/// for each library. This address serves as the primary key for all message
/// library configurations and operations throughout the system.
public struct MessageLibRegistry has store {
    // Sequential list of all registered library addresses
    libs: TableVec<address>,
    // Maps library address to its type
    lib_to_type: Table<address, MessageLibType>,
}

/// Configuration for send and receive libraries for a specific EID.
public struct MessageLibConfig has copy, drop, store {
    // Library used for sending messages (DEFAULT_LIB = use default)
    send_lib: address,
    // Library used for receiving messages (DEFAULT_LIB = use default)
    receive_lib: address,
    // Optional timeout for the previous receive library during transitions
    // Allows the old library to continue processing messages for a grace period
    receive_lib_timeout: Option<Timeout>,
}

/// Composite key for OApp-specific library configurations.
public struct OAppConfigKey has copy, drop, store {
    oapp: address,
    eid: u32,
}

// === Events ===

public struct LibraryRegisteredEvent has copy, drop {
    new_lib: address,
    lib_type: MessageLibType,
}

public struct DefaultSendLibrarySetEvent has copy, drop {
    dst_eid: u32,
    new_lib: address,
}

public struct DefaultReceiveLibrarySetEvent has copy, drop {
    src_eid: u32,
    new_lib: address,
}

public struct DefaultReceiveLibraryTimeoutSetEvent has copy, drop {
    src_eid: u32,
    old_lib: address,
    expiry: u64,
}

public struct SendLibrarySetEvent has copy, drop {
    sender: address,
    dst_eid: u32,
    new_lib: address,
}

public struct ReceiveLibrarySetEvent has copy, drop {
    receiver: address,
    src_eid: u32,
    new_lib: address,
}

public struct ReceiveLibraryTimeoutSetEvent has copy, drop {
    receiver: address,
    src_eid: u32,
    old_lib: address,
    expiry: u64,
}

// === Creation ===

/// Creates a new MessageLibManager instance with empty registry and configurations.
/// This is typically called once during endpoint initialization.
public(package) fun new(ctx: &mut TxContext): MessageLibManager {
    MessageLibManager {
        registry: MessageLibRegistry {
            libs: table_vec::empty(ctx),
            lib_to_type: table::new(ctx),
        },
        default_configs: table::new(ctx),
        oapp_configs: table::new(ctx),
    }
}

// === Library Registration ===

/// Registers a new message library in Endpoint.
/// Each library must have a unique package address.
public(package) fun register_library(self: &mut MessageLibManager, new_lib: address, lib_type: MessageLibType) {
    // Ensure the library is not already registered and is not the default library
    assert!(!self.registry.lib_to_type.contains(new_lib), EAlreadyRegistered);
    assert!(new_lib != DEFAULT_LIB, EInvalidAddress);

    // Add the library to all registry data structures
    self.registry.libs.push_back(new_lib);
    self.registry.lib_to_type.add(new_lib, lib_type);
    event::emit(LibraryRegisteredEvent { new_lib, lib_type });
}

// === Default Library Configuration ===

/// Sets the default send library for a destination endpoint.
/// This library will be used by all OApps that don't have a specific send library configured.
public(package) fun set_default_send_library(self: &mut MessageLibManager, dst_eid: u32, new_lib: address) {
    // Validate that the library supports send operations
    self.assert_send_library_type(new_lib);

    // Get or create the default configuration for this EID
    let config = table_ext::borrow_mut_with_default!(&mut self.default_configs, dst_eid, new_config!());
    assert!(config.send_lib != new_lib, ESameValue);

    // Update the configuration and emit event
    config.send_lib = new_lib;
    event::emit(DefaultSendLibrarySetEvent { dst_eid, new_lib });
}

/// Sets the default receive library for a source endpoint with optional timeout.
/// When changing libraries, a grace period allows the old library to continue processing in-flight messages.
public(package) fun set_default_receive_library(
    self: &mut MessageLibManager,
    src_eid: u32,
    new_lib: address,
    grace_period: u64,
    clock: &Clock,
) {
    // Validate that the library supports receive operations
    self.assert_receive_library_type(new_lib);

    // Get or create the default configuration for this endpoint
    let config = table_ext::borrow_mut_with_default!(&mut self.default_configs, src_eid, new_config!());
    let old_lib = config.receive_lib;
    assert!(old_lib != new_lib, ESameValue);

    // Update the receive library configuration
    config.receive_lib = new_lib;
    event::emit(DefaultReceiveLibrarySetEvent { src_eid, new_lib });

    // Configure timeout for the previous library if grace period is specified
    let expiry = if (grace_period > 0) {
        let timeout = timeout::create_with_grace_period(grace_period, old_lib, clock);
        config.receive_lib_timeout = option::some(timeout);
        timeout.expiry()
    } else {
        config.receive_lib_timeout = option::none();
        0
    };
    event::emit(DefaultReceiveLibraryTimeoutSetEvent { src_eid, old_lib, expiry });
}

/// Sets or updates the timeout for the previous default receive library.
public(package) fun set_default_receive_library_timeout(
    self: &mut MessageLibManager,
    src_eid: u32,
    lib: address,
    expiry: u64,
    clock: &Clock,
) {
    // Validate that the library supports receive operations
    self.assert_receive_library_type(lib);

    // Update the timeout configuration for the existing default library config
    let config = &mut self.default_configs[src_eid];
    if (expiry > 0) {
        let timeout = timeout::create(expiry, lib);
        assert!(!timeout.is_expired(clock), EInvalidExpiry);
        config.receive_lib_timeout = option::some(timeout);
    } else {
        // Remove the timeout by setting to none
        config.receive_lib_timeout = option::none();
    };
    event::emit(DefaultReceiveLibraryTimeoutSetEvent { src_eid, old_lib: lib, expiry });
}

// === OApp Library Configuration ===

/// Sets the send library for a specific OApp and destination endpoint.
/// This overrides the default send library. Setting to DEFAULT_LIB reverts to using the default.
public(package) fun set_send_library(self: &mut MessageLibManager, sender: address, dst_eid: u32, new_lib: address) {
    // Validate library type only if not using default
    if (new_lib != DEFAULT_LIB) self.assert_send_library_type(new_lib);
    // Ensure a default send library exists to fall back to
    self.assert_default_send_library_configured(dst_eid);

    // Get or create the OApp-specific configuration
    let config = table_ext::borrow_mut_with_default!(
        &mut self.oapp_configs,
        OAppConfigKey { oapp: sender, eid: dst_eid },
        new_config!(),
    );
    assert!(config.send_lib != new_lib, ESameValue);

    // Update the configuration and emit notification
    config.send_lib = new_lib;
    event::emit(SendLibrarySetEvent { sender, dst_eid, new_lib });
}

/// Sets the receive library for a specific OApp and source endpoint with optional timeout.
/// This overrides the default receive library. When changing libraries, a grace period
/// allows the old library to continue processing in-flight messages.
public(package) fun set_receive_library(
    self: &mut MessageLibManager,
    receiver: address,
    src_eid: u32,
    new_lib: address,
    grace_period: u64,
    clock: &Clock,
) {
    // Validate library type only if not using default
    if (new_lib != DEFAULT_LIB) self.assert_receive_library_type(new_lib);
    // Ensure a default receive library exists to fall back to
    self.assert_default_receive_library_configured(src_eid);

    // Get or create the OApp-specific configuration
    let config = table_ext::borrow_mut_with_default!(
        &mut self.oapp_configs,
        OAppConfigKey { oapp: receiver, eid: src_eid },
        new_config!(),
    );
    let old_lib = config.receive_lib;
    assert!(old_lib != new_lib, ESameValue);

    // Update the receive library configuration
    config.receive_lib = new_lib;
    event::emit(ReceiveLibrarySetEvent { receiver, src_eid, new_lib });

    // Handle timeout configuration for library transition
    let expiry = if (grace_period > 0) {
        // Timeout logic is only supported for non-default libraries to simplify implementation
        // For transitions involving DEFAULT_LIB:
        // (1) To revert to default: set new_lib to DEFAULT_LIB with grace_period == 0
        // (2) From default to specific: set new_lib to specific with grace_period == 0,
        //     then use set_receive_library_timeout() if needed
        assert!(old_lib != DEFAULT_LIB && new_lib != DEFAULT_LIB, EOnlyNonDefaultLib);

        let timeout = timeout::create_with_grace_period(grace_period, old_lib, clock);
        config.receive_lib_timeout = option::some(timeout);
        timeout.expiry()
    } else {
        config.receive_lib_timeout = option::none();
        0
    };
    event::emit(ReceiveLibraryTimeoutSetEvent { receiver, src_eid, old_lib, expiry });
}

/// Sets or updates the timeout for an OApp's previous receive library.
/// Only works when the OApp has a non-default library configured.
public(package) fun set_receive_library_timeout(
    self: &mut MessageLibManager,
    receiver: address,
    src_eid: u32,
    lib: address,
    expiry: u64,
    clock: &Clock,
) {
    // Validate library type and default configuration existence
    self.assert_receive_library_type(lib);
    self.assert_default_receive_library_configured(src_eid);

    // Check that the OApp has a non-default library configured
    let (_, is_default) = self.get_receive_library(receiver, src_eid);
    assert!(!is_default, EOnlyNonDefaultLib);

    // Update the timeout configuration
    let config = &mut self.oapp_configs[OAppConfigKey { oapp: receiver, eid: src_eid }];
    if (expiry > 0) {
        let timeout = timeout::create(expiry, lib);
        assert!(!timeout.is_expired(clock), EInvalidExpiry);
        config.receive_lib_timeout = option::some(timeout);
    } else {
        // Remove the timeout by setting to none
        config.receive_lib_timeout = option::none();
    };
    event::emit(ReceiveLibraryTimeoutSetEvent { receiver, src_eid, old_lib: lib, expiry });
}

/// Prepares the parameters for the message library to set the config.
public(package) fun set_config(
    self: &MessageLibManager,
    oapp: address,
    lib: address,
    eid: u32,
    config_type: u32,
    config: vector<u8>,
): MessageLibSetConfigParam {
    self.assert_registered_library(lib);
    message_lib_set_config::create_param(oapp, eid, config_type, config)
}

// === View Functions ===

/// Returns the number of registered libraries.
public(package) fun registered_libraries_count(self: &MessageLibManager): u64 {
    self.registry.libs.length()
}

/// Returns a list of registered library addresses within the specified range.
public(package) fun registered_libraries(self: &MessageLibManager, start: u64, max_count: u64): vector<address> {
    let end = u64::min(start + max_count, self.registered_libraries_count());
    assert!(start <= end, EInvalidBounds);
    vector::tabulate!(end - start, |i| self.registry.libs[start + i])
}

/// Checks if a library is registered in the system.
public(package) fun is_registered_library(self: &MessageLibManager, lib: address): bool {
    self.registry.lib_to_type.contains(lib)
}

/// Gets the type of operations a registered library supports.
public(package) fun get_library_type(self: &MessageLibManager, lib: address): MessageLibType {
    *table_ext::borrow_or_abort!(&self.registry.lib_to_type, lib, EOnlyRegisteredLib)
}

/// Gets the default send library for a destination endpoint.
public(package) fun get_default_send_library(self: &MessageLibManager, dst_eid: u32): address {
    self.assert_default_send_library_configured(dst_eid);
    self.default_configs[dst_eid].send_lib
}

/// Gets the default receive library for a source endpoint.
public(package) fun get_default_receive_library(self: &MessageLibManager, src_eid: u32): address {
    self.assert_default_receive_library_configured(src_eid);
    self.default_configs[src_eid].receive_lib
}

/// Gets the timeout configuration for a default receive library.
public(package) fun get_default_receive_library_timeout(self: &MessageLibManager, src_eid: u32): Option<Timeout> {
    self.assert_default_receive_library_configured(src_eid);
    self.default_configs[src_eid].receive_lib_timeout
}

/// Checks if a destination endpoint ID is supported by the message library manager.
public(package) fun is_supported_eid(self: &MessageLibManager, eid: u32): bool {
    self.default_configs.contains(eid) && 
        self.default_configs[eid].send_lib != DEFAULT_LIB && 
        self.default_configs[eid].receive_lib != DEFAULT_LIB
}

/// Gets the effective send library for an OApp and destination endpoint.
/// Returns either the OApp-specific configuration or falls back to the default.
/// Returns (library_address, is_default_config).
public(package) fun get_send_library(self: &MessageLibManager, sender: address, dst_eid: u32): (address, bool) {
    let config = table_ext::borrow_with_default!(
        &self.oapp_configs,
        OAppConfigKey { oapp: sender, eid: dst_eid },
        &new_config!(),
    );
    if (config.send_lib != DEFAULT_LIB) {
        (config.send_lib, false)
    } else {
        (self.get_default_send_library(dst_eid), true)
    }
}

/// Gets the effective receive library for an OApp and source endpoint.
/// Returns either the OApp-specific configuration or falls back to the default.
/// Returns (library_address, is_default_config).
public(package) fun get_receive_library(self: &MessageLibManager, receiver: address, src_eid: u32): (address, bool) {
    let config = table_ext::borrow_with_default!(
        &self.oapp_configs,
        OAppConfigKey { oapp: receiver, eid: src_eid },
        &new_config!(),
    );
    if (config.receive_lib != DEFAULT_LIB) {
        (config.receive_lib, false)
    } else {
        (self.get_default_receive_library(src_eid), true)
    }
}

/// Gets the timeout configuration for an OApp's receive library.
public(package) fun get_receive_library_timeout(
    self: &MessageLibManager,
    receiver: address,
    src_eid: u32,
): Option<Timeout> {
    table_ext::borrow_with_default!(
        &self.oapp_configs,
        OAppConfigKey { oapp: receiver, eid: src_eid },
        &new_config!(),
    ).receive_lib_timeout
}

/// Validates if a receive library is valid for processing messages.
/// A library is valid if it's either the currently configured receive library,
/// or a previous library that's still within its timeout grace period.
public(package) fun is_valid_receive_library(
    self: &MessageLibManager,
    receiver: address,
    src_eid: u32,
    actual_receive_lib: address,
    clock: &Clock,
): bool {
    // Get the current receive library configuration
    let (expected_receive_lib, is_default) = self.get_receive_library(receiver, src_eid);

    // If it matches the current configuration, it's valid
    if (actual_receive_lib == expected_receive_lib) return true;

    // Check if it's a previous library still within timeout grace period
    let timeout = if (is_default) {
        // Use default timeout configuration
        self.default_configs[src_eid].receive_lib_timeout
    } else {
        // Use OApp-specific timeout configuration
        self.oapp_configs[OAppConfigKey { oapp: receiver, eid: src_eid }].receive_lib_timeout
    };

    if (timeout.is_none()) {
        // No timeout configured, so only current library is valid
        false
    } else {
        let timeout = timeout.destroy_some();
        // Valid if timeout hasn't expired and this is the fallback library
        !timeout.is_expired(clock) && timeout.fallback_lib() == actual_receive_lib
    }
}

/// Validates if a receive library is valid for processing messages.
/// A library is valid if it's either the currently configured receive library,
/// or a previous library that's still within its timeout grace period.
/// Aborts if the library is not valid.
public(package) fun assert_receive_library(
    self: &MessageLibManager,
    receiver: address,
    src_eid: u32,
    actual_receive_lib: address,
    clock: &Clock,
) {
    let valid = self.is_valid_receive_library(receiver, src_eid, actual_receive_lib, clock);
    assert!(valid, EInvalidReceiveLib);
}

// === Internal Functions ===

/// Validates that a library is registered in the system. Aborts if not.
fun assert_registered_library(self: &MessageLibManager, lib: address) {
    assert!(self.registry.lib_to_type.contains(lib), EOnlyRegisteredLib);
}

/// Internal helper to validate that a library supports send operations.
fun assert_send_library_type(self: &MessageLibManager, lib: address) {
    let t = self.get_library_type(lib);
    assert!(t == message_lib_type::send() || t == message_lib_type::send_and_receive(), EOnlySendLib);
}

/// Internal helper to validate that a library supports receive operations.
fun assert_receive_library_type(self: &MessageLibManager, lib: address) {
    let t = self.get_library_type(lib);
    assert!(t == message_lib_type::receive() || t == message_lib_type::send_and_receive(), EOnlyReceiveLib);
}

/// Validates that a default send library is configured for the given destination endpoint ID.
/// This validation is necessary because send_lib.supports_send_eid() is not yet implemented,
/// so we rely on the presence of a configured default send library to guarantee that
/// the destination endpoint ID is valid and supported.
fun assert_default_send_library_configured(self: &MessageLibManager, dst_eid: u32) {
    let config = table_ext::borrow_with_default!(&self.default_configs, dst_eid, &new_config!());
    assert!(config.send_lib != DEFAULT_LIB, EDefaultSendLibUnavailable);
}

/// Validates that a default receive library is configured for the given source endpoint ID.
/// This validation is necessary because receive_lib.supports_receive_eid() is not yet implemented,
/// so we rely on the presence of a configured default receive library to guarantee that
/// the source endpoint ID is valid and supported.
fun assert_default_receive_library_configured(self: &MessageLibManager, src_eid: u32) {
    let config = table_ext::borrow_with_default!(&self.default_configs, src_eid, &new_config!());
    assert!(config.receive_lib != DEFAULT_LIB, EDefaultReceiveLibUnavailable);
}

/// Macro to create a new MessageLibConfig with default values.
/// All libraries are initially set to DEFAULT_LIB (use default configuration)
/// and no timeout is configured.
macro fun new_config(): MessageLibConfig {
    MessageLibConfig {
        send_lib: DEFAULT_LIB,
        receive_lib: DEFAULT_LIB,
        receive_lib_timeout: option::none(),
    }
}

// === Test Helper Functions ===

#[test_only]
public(package) fun create_library_registered_event(
    new_lib: address,
    lib_type: MessageLibType,
): LibraryRegisteredEvent {
    LibraryRegisteredEvent { new_lib, lib_type }
}

#[test_only]
public(package) fun create_default_send_library_set_event(dst_eid: u32, new_lib: address): DefaultSendLibrarySetEvent {
    DefaultSendLibrarySetEvent { dst_eid, new_lib }
}

#[test_only]
public(package) fun create_default_receive_library_set_event(
    src_eid: u32,
    new_lib: address,
): DefaultReceiveLibrarySetEvent {
    DefaultReceiveLibrarySetEvent { src_eid, new_lib }
}

#[test_only]
public(package) fun create_default_receive_library_timeout_set_event(
    src_eid: u32,
    old_lib: address,
    expiry: u64,
): DefaultReceiveLibraryTimeoutSetEvent {
    DefaultReceiveLibraryTimeoutSetEvent { src_eid, old_lib, expiry }
}

#[test_only]
public(package) fun create_send_library_set_event(
    sender: address,
    dst_eid: u32,
    new_lib: address,
): SendLibrarySetEvent {
    SendLibrarySetEvent { sender, dst_eid, new_lib }
}

#[test_only]
public(package) fun create_receive_library_set_event(
    receiver: address,
    src_eid: u32,
    new_lib: address,
): ReceiveLibrarySetEvent {
    ReceiveLibrarySetEvent { receiver, src_eid, new_lib }
}

#[test_only]
public(package) fun create_receive_library_timeout_set_event(
    receiver: address,
    src_eid: u32,
    old_lib: address,
    expiry: u64,
): ReceiveLibraryTimeoutSetEvent {
    ReceiveLibraryTimeoutSetEvent { receiver, src_eid, old_lib, expiry }
}
