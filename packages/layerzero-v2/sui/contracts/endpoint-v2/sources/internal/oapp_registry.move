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

const EInvalidLZReceiveInfo: u64 = 1;
const EOAppNotRegistered: u64 = 2;
const EOAppRegistered: u64 = 3;

// === Structs ===

/// Registry that manages OApp registrations and their associated metadata.
/// Maintains mappings between OApp package addresses and their complete information.
public struct OAppRegistry has store {
    // Maps OApp package address to its complete information
    oapps: Table<address, OAppInfo>,
}

/// Stores the complete registration information for an OApp.
/// This information is used throughout the system to:
/// - Route messages to the correct messaging channel
/// - Validate that operations come from legitimate OApps
/// - Execute lz_receive with the correct parameters
/// - Track the delegate address for the OApp
public struct OAppInfo has store {
    // The address of the messaging channel object that the OApp uses to send and receive messages
    messaging_channel: address,
    // The lz_receive execution information for the OApp
    lz_receive_info: vector<u8>,
    // The delegate address for the OApp
    delegate: address,
}

// === Events ===

public struct OAppRegisteredEvent has copy, drop {
    oapp: address,
    messaging_channel: address,
    lz_receive_info: vector<u8>,
}

public struct LzReceiveInfoSetEvent has copy, drop {
    oapp: address,
    lz_receive_info: vector<u8>,
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
    lz_receive_info: vector<u8>,
) {
    assert!(!self.is_registered(oapp), EOAppRegistered);
    assert!(lz_receive_info.length() > 0, EInvalidLZReceiveInfo);
    let info = OAppInfo { messaging_channel, lz_receive_info, delegate: @0x0 };
    self.oapps.add(oapp, info);
    event::emit(OAppRegisteredEvent { oapp, messaging_channel, lz_receive_info });
}

/// Updates the lz_receive execution information for a registered OApp.
/// This allows OApps to modify their message execution parameters after registration.
public(package) fun set_lz_receive_info(self: &mut OAppRegistry, oapp: address, lz_receive_info: vector<u8>) {
    assert!(lz_receive_info.length() > 0, EInvalidLZReceiveInfo);
    let oapp_info = table_ext::borrow_mut_or_abort!(&mut self.oapps, oapp, EOAppNotRegistered);
    oapp_info.lz_receive_info = lz_receive_info;
    event::emit(LzReceiveInfoSetEvent { oapp, lz_receive_info });
}

/// Sets the delegate address for a registered OApp.
/// This function allows OApps to set a delegate address that will be used to authorize
public(package) fun set_delegate(self: &mut OAppRegistry, oapp: address, delegate: address) {
    let oapp_info = table_ext::borrow_mut_or_abort!(&mut self.oapps, oapp, EOAppNotRegistered);
    oapp_info.delegate = delegate;
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
    let oapp_info = table_ext::borrow_or_abort!(&self.oapps, oapp, EOAppNotRegistered);
    oapp_info.messaging_channel
}

/// Gets the lz_receive execution information for a registered OApp.
/// This contains version and payload data needed for message execution.
public(package) fun get_lz_receive_info(self: &OAppRegistry, oapp: address): &vector<u8> {
    let oapp_info = table_ext::borrow_or_abort!(&self.oapps, oapp, EOAppNotRegistered);
    &oapp_info.lz_receive_info
}

/// Gets the delegate address for a registered OApp.
/// The delegate is the address that will be used to authorize certain
/// operations for the OApp.
public(package) fun get_delegate(self: &OAppRegistry, oapp: address): address {
    let oapp_info = table_ext::borrow_or_abort!(&self.oapps, oapp, EOAppNotRegistered);
    oapp_info.delegate
}

// === Test Functions ===

#[test_only]
public(package) fun create_lz_receive_info_set_event(
    oapp: address,
    lz_receive_info: vector<u8>,
): LzReceiveInfoSetEvent {
    LzReceiveInfoSetEvent { oapp, lz_receive_info }
}

#[test_only]
public(package) fun create_oapp_registered_event(
    oapp: address,
    messaging_channel: address,
    lz_receive_info: vector<u8>,
): OAppRegisteredEvent {
    OAppRegisteredEvent { oapp, messaging_channel, lz_receive_info }
}

#[test_only]
public(package) fun create_delegate_set_event(oapp: address, delegate: address): DelegateSetEvent {
    DelegateSetEvent { oapp, delegate }
}
