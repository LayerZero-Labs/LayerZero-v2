/// MsglibPtbBuilderInfo Module
///
/// This module defines the information structure for message library PTB builders.
/// Each PTB builder provides pre-built MoveCall templates for the three core operations:
/// quote, send, and set_config. These templates are used by the EndpointPtbBuilder
/// to construct complete PTBs for LayerZero operations.
module endpoint_ptb_builder::msglib_ptb_builder_info;

use ptb_move_call::move_call::MoveCall;

/// Information about a message library PTB builder including its address and PTB templates
///
/// This struct contains all necessary information to use a PTB builder:
/// - Addresses for validation and identification
/// - Pre-built PTB templates for each operation type
///
/// The PTB templates are designed to be inserted into larger PTBs constructed
/// by the EndpointPtbBuilder, creating seamless composition of endpoint and
/// message library operations.
public struct MsglibPtbBuilderInfo has copy, drop, store {
    // Address of the message library this builder supports
    message_lib: address,
    // Address of the PTB builder's call capability
    ptb_builder: address,
    // PTB template for quote operations - calculates messaging fees
    quote_ptb: vector<MoveCall>,
    // PTB template for send operations - processes outbound messages
    send_ptb: vector<MoveCall>,
    // PTB template for set_config operations - configures library settings
    set_config_ptb: vector<MoveCall>,
}

// === Create Functions ===

/// Create a new MsglibPtbBuilderInfo with the provided addresses and PTB templates
public fun create(
    message_lib: address,
    ptb_builder: address,
    quote_ptb: vector<MoveCall>,
    send_ptb: vector<MoveCall>,
    set_config_ptb: vector<MoveCall>,
): MsglibPtbBuilderInfo {
    MsglibPtbBuilderInfo { message_lib, ptb_builder, quote_ptb, send_ptb, set_config_ptb }
}

// === View Functions ===

/// Get the address of the message library
public fun message_lib(self: &MsglibPtbBuilderInfo): address {
    self.message_lib
}

/// Get the address of the PTB builder
public fun ptb_builder(self: &MsglibPtbBuilderInfo): address {
    self.ptb_builder
}

/// Get the reference to the PTB template for quote operations
public fun quote_ptb(self: &MsglibPtbBuilderInfo): &vector<MoveCall> {
    &self.quote_ptb
}

/// Get the reference to the PTB template for send operations
public fun send_ptb(self: &MsglibPtbBuilderInfo): &vector<MoveCall> {
    &self.send_ptb
}

/// Get the reference to the PTB template for set_config operations
public fun set_config_ptb(self: &MsglibPtbBuilderInfo): &vector<MoveCall> {
    &self.set_config_ptb
}
