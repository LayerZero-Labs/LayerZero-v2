/// Module for handling message library configuration parameters from Endpoint calling MessageLib.
///
/// This module defines the SetConfigParam struct which encapsulates all necessary
/// information required for message libraries to update OApp's configurations.
/// Unlike the endpoint set config module, this operates at the message library
/// level and includes the OApp address for configuration context.
module endpoint_v2::message_lib_set_config;

// === Structs ===

/// Parameters required for message libraries to set configuration.
///
/// This struct contains all information needed for a message library to update
/// its configuration settings for a specific OApp and endpoint. Configuration
/// changes at the message library level affect how messages are processed for
/// the specified OApp.
public struct SetConfigParam has copy, drop, store {
    // Address of the OApp requesting the configuration change
    oapp: address,
    // Endpoint ID of the target chain where config applies
    eid: u32,
    // Type identifier for the specific configuration being set
    config_type: u32,
    // Encoded configuration data specific to the config type
    config: vector<u8>,
}

// === Creation ===

/// Creates a new SetConfigParam instance with the specified configuration parameters.
public(package) fun create_param(oapp: address, eid: u32, config_type: u32, config: vector<u8>): SetConfigParam {
    SetConfigParam { oapp, eid, config_type, config }
}

// === Param Getters ===

/// Returns the address of the OApp requesting the configuration change.
public fun oapp(self: &SetConfigParam): address {
    self.oapp
}

/// Returns the endpoint ID of the target chain.
public fun eid(self: &SetConfigParam): u32 {
    self.eid
}

/// Returns the configuration type identifier.
public fun config_type(self: &SetConfigParam): u32 {
    self.config_type
}

/// Returns a reference to the encoded configuration data.
public fun config(self: &SetConfigParam): &vector<u8> {
    &self.config
}

// === Test Only ===

#[test_only]
public fun create_param_for_test(oapp: address, eid: u32, config_type: u32, config: vector<u8>): SetConfigParam {
    create_param(oapp, eid, config_type, config)
}
