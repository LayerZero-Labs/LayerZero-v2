/// OApp Registry
///
/// This module manages the registration and metadata of OApps (Omnichain Applications)
/// within the LayerZero V2 Endpoint. It maintains mappings between OApp package addresses
/// and their associated metadata including messaging channels and lz_receive execution information.
///
/// The registry ensures that only properly registered OApps can participate in cross-chain
/// messaging and provides the endpoint with the necessary information to route messages
/// and validate OApp operations.
module endpoint_v2::oapp_registry;

use sui::{event, table::{Self, Table}};
use utils::table_ext;

// === Error ===

const EOAppNotRegistered: u64 = 1;
const EOAppRegistered: u64 = 2;

// === Structs ===

/// Registry that manages OApp registrations and their associated metadata.
/// Maintains mappings between OApp package addresses and their complete information.
public struct OAppRegistry has store {
    // Maps OApp package address to its complete information
    oapps: Table<address, OAppRegistration>,
}

/// Stores the complete registration information for an OApp.
/// This information is used throughout the system to:
/// - Route messages to the correct messaging channel
/// - Validate that operations come from legitimate OApps
/// - Track the oapp information for the OApp, including the lz_receive execution information
/// - Track the delegate address for the OApp
public struct OAppRegistration has store {
    // The address of the messaging channel object that the OApp uses to send and receive messages
    messaging_channel: address,
    // The oapp information for the OApp
    oapp_info: vector<u8>,
    // The delegate address for the OApp
    delegate: address,
}

// === Events ===

public struct OAppRegisteredEvent has copy, drop {
    oapp: address,
    messaging_channel: address,
    oapp_info: vector<u8>,
}

public struct OAppInfoSetEvent has copy, drop {
    oapp: address,
    oapp_info: vector<u8>,
}

public struct DelegateSetEvent has copy, drop {
    oapp: address,
    delegate: address,
}

// === Constructor ===

/// Creates a new empty OAppRegistry.
public(package) fun new(ctx: &mut TxContext): OAppRegistry {
    OAppRegistry {
        oapps: table::new(ctx),
    }
}

// === Package Functions ===

/// Registers a new OApp with its messaging channel and metadata.
/// This establishes the OApp's identity within the LayerZero system and enables
/// it to send and receive cross-chain messages.
public(package) fun register_oapp(
    self: &mut OAppRegistry,
    oapp: address,
    messaging_channel: address,
    oapp_info: vector<u8>,
) {
    assert!(!self.is_registered(oapp), EOAppRegistered);
    let registration = OAppRegistration { messaging_channel, oapp_info, delegate: @0x0 };
    self.oapps.add(oapp, registration);
    event::emit(OAppRegisteredEvent { oapp, messaging_channel, oapp_info });
}

/// Updates the oapp information for a registered OApp.
/// This allows OApps to modify their oapp information after registration.
public(package) fun set_oapp_info(self: &mut OAppRegistry, oapp: address, oapp_info: vector<u8>) {
    let registration = table_ext::borrow_mut_or_abort!(&mut self.oapps, oapp, EOAppNotRegistered);
    registration.oapp_info = oapp_info;
    event::emit(OAppInfoSetEvent { oapp, oapp_info });
}

/// Sets the delegate address for a registered OApp.
/// This function allows OApps to set a delegate address that will be used to authorize
public(package) fun set_delegate(self: &mut OAppRegistry, oapp: address, delegate: address) {
    let registration = table_ext::borrow_mut_or_abort!(&mut self.oapps, oapp, EOAppNotRegistered);
    registration.delegate = delegate;
    event::emit(DelegateSetEvent { oapp, delegate });
}

// === View Functions (package) ===

/// Checks if an OApp is fully registered in the system.
/// An OApp is considered registered if it has an entry in the registry.
public(package) fun is_registered(self: &OAppRegistry, oapp: address): bool {
    self.oapps.contains(oapp)
}

/// Asserts that an OApp is fully registered in the system.
/// An OApp is considered registered if it has an entry in the registry.
/// Reverts if the OApp is not registered.
public(package) fun assert_registered(self: &OAppRegistry, oapp: address) {
    assert!(self.is_registered(oapp), EOAppNotRegistered);
}

/// Gets the messaging channel address for a registered OApp.
/// The messaging channel is used for managing message state and parallel execution.
public(package) fun get_messaging_channel(self: &OAppRegistry, oapp: address): address {
    let registration = table_ext::borrow_or_abort!(&self.oapps, oapp, EOAppNotRegistered);
    registration.messaging_channel
}

/// Gets the oapp information for a registered OApp.
/// This contains version and payload data needed for lz_receive and extra oapp information.
public(package) fun get_oapp_info(self: &OAppRegistry, oapp: address): &vector<u8> {
    let registration = table_ext::borrow_or_abort!(&self.oapps, oapp, EOAppNotRegistered);
    &registration.oapp_info
}

/// Gets the delegate address for a registered OApp.
/// The delegate is the address that will be used to authorize certain
/// operations for the OApp.
public(package) fun get_delegate(self: &OAppRegistry, oapp: address): address {
    let registration = table_ext::borrow_or_abort!(&self.oapps, oapp, EOAppNotRegistered);
    registration.delegate
}

// === Test Functions ===

#[test_only]
public(package) fun create_oapp_info_set_event(oapp: address, oapp_info: vector<u8>): OAppInfoSetEvent {
    OAppInfoSetEvent { oapp, oapp_info }
}

#[test_only]
public(package) fun create_oapp_registered_event(
    oapp: address,
    messaging_channel: address,
    oapp_info: vector<u8>,
): OAppRegisteredEvent {
    OAppRegisteredEvent { oapp, messaging_channel, oapp_info }
}

#[test_only]
public(package) fun create_delegate_set_event(oapp: address, delegate: address): DelegateSetEvent {
    DelegateSetEvent { oapp, delegate }
}
