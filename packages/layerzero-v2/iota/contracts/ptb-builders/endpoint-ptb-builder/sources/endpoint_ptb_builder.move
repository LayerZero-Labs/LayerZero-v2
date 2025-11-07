/// EndpointPtbBuilder Module
///
/// This module provides a Programmable Transaction Block (PTB) builder for LayerZero Endpoint V2 operations.
/// It serves as a registry and coordinator for message library PTB builders, allowing OApps to configure
/// and use different message library PTB builders for cross-chain communication.
///
/// Key Functionality:
/// - Registry management for message library PTB builders
/// - Configuration of default and per-OApp message library builders
/// - PTB construction for endpoint operations (quote, send, set_config)
///
/// Usage Flow:
/// 1. Admin registers message library PTB builders with their capabilities
/// 2. OApps configure which PTB builder to use (or fallback to defaults)
/// 3. SDK or on-chain composition calls build_*_ptb functions to get executable PTBs
module endpoint_ptb_builder::endpoint_ptb_builder;

use call::{call::{Call, Void}, call_cap::CallCap};
use endpoint_ptb_builder::msglib_ptb_builder_info::MsglibPtbBuilderInfo;
use endpoint_v2::{
    endpoint_quote::QuoteParam as EndpointQuoteParam,
    endpoint_send::SendParam as EndpointSendParam,
    endpoint_v2::EndpointV2,
    message_lib_quote::QuoteParam as MessageLibQuoteParam,
    message_lib_send::{SendParam as MessageLibSendParam, SendResult as MessageLibSendResult},
    message_lib_set_config::SetConfigParam as MessageLibSetConfigParam,
    messaging_fee::MessagingFee,
    messaging_receipt::MessagingReceipt
};
use ptb_move_call::{argument, move_call::{Self, MoveCall}, move_calls_builder};
use std::{type_name, u64};
use iota::{event, table::{Self, Table}, table_vec::{Self, TableVec}};
use utils::{bytes32::Bytes32, hash, package, table_ext};

// === Constants ===

const DEFAULT_BUILDER: address = @0x0;

// === Error Codes ===

const EBuilderNotFound: u64 = 1;
const EBuilderRegistered: u64 = 2;
const EBuilderUnsupported: u64 = 3;
const EInvalidBounds: u64 = 4;
const EInvalidBuilderAddress: u64 = 5;
const EInvalidLibrary: u64 = 6;
const EUnauthorized: u64 = 7;

// === Structs ===

/// Administrative capability for managing the EndpointPtbBuilder
/// Allows registration of new message library PTB builders and setting default configurations
public struct AdminCap has key, store {
    id: UID,
}

/// Main registry and coordinator for message library PTB builders
/// Manages both default configurations and per-OApp overrides
public struct EndpointPtbBuilder has key {
    id: UID,
    // Registry of all supported message library PTB builders
    registry: MsglibPtbBuilderRegistry,
    // Default PTB builder for each message library: lib -> lib_ptb_builder
    default_configs: Table<address, address>,
    // Per-OApp PTB builder overrides: (oapp, lib) -> lib_ptb_builder
    oapp_configs: Table<OAppConfigKey, address>,
}

/// Composite key for OApp-specific message library PTB builder configurations
public struct OAppConfigKey has copy, drop, store {
    oapp: address,
    lib: address,
}

/// Registry containing all registered message library PTB builders
/// Maintains both an ordered list and detailed information for each builder
public struct MsglibPtbBuilderRegistry has store {
    // Ordered list of registered PTB builder addresses
    builders: TableVec<address>,
    // Detailed information for each registered PTB builder: builder -> MsglibPtbBuilderInfo
    builder_infos: Table<address, MsglibPtbBuilderInfo>,
}

// === Events ===

public struct MsglibPtbBuilderRegisteredEvent has copy, drop {
    message_lib: address,
    ptb_builder: address,
}

public struct DefaultMsglibPtbBuilderSetEvent has copy, drop {
    message_lib: address,
    ptb_builder: address,
}

public struct MsglibPtbBuilderSetEvent has copy, drop {
    oapp: address,
    message_lib: address,
    ptb_builder: address,
}

// === Initialization ===

/// Initialize the EndpointPtbBuilder with empty registries and transfer AdminCap to deployer
fun init(ctx: &mut TxContext) {
    transfer::share_object(EndpointPtbBuilder {
        id: object::new(ctx),
        registry: MsglibPtbBuilderRegistry {
            builders: table_vec::empty(ctx),
            builder_infos: table::new(ctx),
        },
        default_configs: table::new(ctx),
        oapp_configs: table::new(ctx),
    });
    transfer::transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
}

// === Configuration ===

/// Register a new message library PTB builder in the registry
public fun register_msglib_ptb_builder(
    self: &mut EndpointPtbBuilder,
    _admin: &AdminCap,
    endpoint: &EndpointV2,
    builder_info: MsglibPtbBuilderInfo,
) {
    // Validate the builder address
    let builder_address = builder_info.ptb_builder();
    assert!(builder_address != @0x0, EInvalidBuilderAddress);

    // Validate the builder is not already registered
    assert!(!self.is_msglib_ptb_builder_registered(builder_address), EBuilderRegistered);
    assert!(endpoint.is_registered_library(builder_info.message_lib()), EInvalidLibrary);

    // Add the builder to the registry
    self.registry.builders.push_back(builder_address);
    self.registry.builder_infos.add(builder_address, builder_info);

    // Emit event
    event::emit(MsglibPtbBuilderRegisteredEvent {
        message_lib: builder_info.message_lib(),
        ptb_builder: builder_address,
    });
}

/// Set the default PTB builder for a message library
/// This builder will be used by OApps that haven't configured a specific override
public fun set_default_msglib_ptb_builder(
    self: &mut EndpointPtbBuilder,
    _admin: &AdminCap,
    message_lib: address,
    ptb_builder: address,
) {
    self.registry.assert_msglib_ptb_builder_supported(message_lib, ptb_builder);
    table_ext::upsert!(&mut self.default_configs, message_lib, ptb_builder);
    event::emit(DefaultMsglibPtbBuilderSetEvent { message_lib, ptb_builder });
}

/// Allow an OApp to configure which PTB builder to use for a specific message library
/// OApps can set this to DEFAULT_BUILDER to use the system default
public fun set_msglib_ptb_builder(
    self: &mut EndpointPtbBuilder,
    caller: &CallCap,
    endpoint: &EndpointV2,
    oapp: address,
    message_lib: address,
    ptb_builder: address,
) {
    assert!(caller.id() == oapp || caller.id() == endpoint.get_delegate(oapp), EUnauthorized);
    // If not DEFAULT_BUILDER, validate the builder exists and matches the lib
    if (ptb_builder != DEFAULT_BUILDER) {
        self.registry.assert_msglib_ptb_builder_supported(message_lib, ptb_builder);
    };
    table_ext::upsert!(&mut self.oapp_configs, OAppConfigKey { oapp, lib: message_lib }, ptb_builder);
    event::emit(MsglibPtbBuilderSetEvent { oapp, message_lib, ptb_builder });
}

// === PTB Build Functions For SDK ===

/// Build a complete PTB for quoting messaging fees based on an endpoint quote call
/// Extracts parameters from the call object and delegates to build_quote_ptb
public fun build_quote_ptb_by_call(
    self: &EndpointPtbBuilder,
    endpoint: &EndpointV2,
    call: &Call<EndpointQuoteParam, MessagingFee>,
): vector<MoveCall> {
    self.build_quote_ptb(endpoint, call.caller(), call.param().dst_eid())
}

/// Build a complete PTB for sending messages based on an endpoint send call
/// Extracts parameters from the call object and delegates to build_send_ptb
public fun build_send_ptb_by_call(
    self: &EndpointPtbBuilder,
    endpoint: &EndpointV2,
    call: &Call<EndpointSendParam, MessagingReceipt>,
): vector<MoveCall> {
    self.build_send_ptb(endpoint, call.caller(), call.param().dst_eid(), call.one_way())
}

/// Build a complete PTB for setting message library configuration based on an endpoint config call
/// Extracts parameters from the call object and delegates to build_set_config_ptb
public fun build_set_config_ptb_by_call(
    self: &EndpointPtbBuilder,
    call: &Call<MessageLibSetConfigParam, Void>,
): vector<MoveCall> {
    self.build_set_config_ptb(call.param().oapp(), call.callee())
}

// === PTB Build Functions For Onchain Composition ===

/// Build a complete PTB for quoting messaging fees for on-chain composition
///
/// Creates a 3-step PTB:
/// 1. endpoint_v2::quote() - initiate quote process
/// 2. message_lib specific quote calls - library-specific fee calculation
/// 3. endpoint_v2::confirm_quote() - finalize and return MessagingFee
public fun build_quote_ptb(
    self: &EndpointPtbBuilder,
    endpoint: &EndpointV2,
    sender: address,
    dst_eid: u32,
): vector<MoveCall> {
    let endpoint_package = package::original_package_of_type<EndpointV2>();
    let endpoint_object = object::id_address(endpoint);
    let messaging_channel_object = endpoint.get_messaging_channel(sender);

    let (quote_lib, _) = endpoint.get_send_library(sender, dst_eid);
    let mut move_calls_builder = move_calls_builder::new();

    // 1. endpoint_v2::quote(endpoint, messaging_channel, endpoint_quote_call): Call<MessageLibQuoteParam, MessagingFee>
    let message_lib_quote_call = move_calls_builder
        .add(
            move_call::create(
                endpoint_package,
                b"endpoint_v2".to_ascii_string(),
                b"quote".to_ascii_string(),
                vector[
                    argument::create_object(endpoint_object),
                    argument::create_object(messaging_channel_object),
                    argument::create_id(endpoint_quote_call_id()),
                ],
                vector[],
                false,
                vector[message_lib_quote_call_id()],
            ),
        )
        .to_nested_result_arg(0);

    // 2. append the message_lib's quote move_calls
    let msglib_ptb_builder_address = self.get_effective_msglib_ptb_builder(sender, quote_lib);
    let msglib_ptb_builder_info = self.get_msglib_ptb_builder_info(msglib_ptb_builder_address);
    move_calls_builder.append(*msglib_ptb_builder_info.quote_ptb());

    // 3. endpoint_v2::confirm_quote(endpoint, endpoint_quote_call, message_lib_quote_call)
    move_calls_builder.add(
        move_call::create(
            endpoint_package,
            b"endpoint_v2".to_ascii_string(),
            b"confirm_quote".to_ascii_string(),
            vector[
                argument::create_object(endpoint_object),
                argument::create_id(endpoint_quote_call_id()),
                message_lib_quote_call,
            ],
            vector[],
            false,
            vector[],
        ),
    );

    move_calls_builder.build()
}

/// Build a complete PTB for sending messages for on-chain composition
///
/// Creates a 2-3 step PTB:
/// 1. endpoint_v2::send() - initiate send process
/// 2. message_lib specific send calls - library-specific message processing
/// 3. endpoint_v2::refund() - optional refund of remaining fees
public fun build_send_ptb(
    self: &EndpointPtbBuilder,
    endpoint: &EndpointV2,
    sender: address,
    dst_eid: u32,
    refund: bool,
): vector<MoveCall> {
    let endpoint_package = package::original_package_of_type<EndpointV2>();
    let endpoint_object = object::id_address(endpoint);
    let messaging_channel_object = endpoint.get_messaging_channel(sender);

    let (send_lib, _) = endpoint.get_send_library(sender, dst_eid);
    let mut move_calls_builder = move_calls_builder::new();

    // 1. endpoint_v2::send(endpoint, messaging_channel, endpoint_send_call) -> Call<MessageLibSendParam,
    // MessageLibSendResult>
    move_calls_builder.add(
        move_call::create(
            endpoint_package,
            b"endpoint_v2".to_ascii_string(),
            b"send".to_ascii_string(),
            vector[
                argument::create_object(endpoint_object),
                argument::create_object(messaging_channel_object),
                argument::create_id(endpoint_send_call_id()),
            ],
            vector[],
            false,
            vector[message_lib_send_call_id()],
        ),
    );

    // 2. append the message_lib's send move_calls
    let msglib_ptb_builder_address = self.get_effective_msglib_ptb_builder(sender, send_lib);
    let msglib_ptb_builder_info = self.get_msglib_ptb_builder_info(msglib_ptb_builder_address);
    move_calls_builder.append(*msglib_ptb_builder_info.send_ptb());

    // 3. endpoint_v2::refund(endpoint, endpoint_send_call) if refund is true
    if (refund) {
        move_calls_builder.add(
            move_call::create(
                endpoint_package,
                b"endpoint_v2".to_ascii_string(),
                b"refund".to_ascii_string(),
                vector[argument::create_object(endpoint_object), argument::create_id(endpoint_send_call_id())],
                vector[],
                false,
                vector[],
            ),
        );
    };

    move_calls_builder.build()
}

/// Build a complete PTB for setting message library configuration for on-chain composition
///
/// Creates a 1-step PTB:
/// 1. message_lib specific config calls - library-specific configuration
public fun build_set_config_ptb(self: &EndpointPtbBuilder, oapp: address, lib: address): vector<MoveCall> {
    let ptb_builder = self.get_effective_msglib_ptb_builder(oapp, lib);
    let builder_info = self.get_msglib_ptb_builder_info(ptb_builder);
    *builder_info.set_config_ptb()
}

// === Call Object IDs ===

/// Generate deterministic call ID for endpoint quote calls
/// Used to create consistent call object references across PTBs
public fun endpoint_quote_call_id(): Bytes32 {
    hash::keccak256!(
        type_name::get_with_original_ids<Call<EndpointQuoteParam, MessagingFee>>().into_string().as_bytes(),
    )
}

/// Generate deterministic call ID for endpoint send calls
/// Used to create consistent call object references across PTBs
public fun endpoint_send_call_id(): Bytes32 {
    hash::keccak256!(
        type_name::get_with_original_ids<Call<EndpointSendParam, MessagingReceipt>>().into_string().as_bytes(),
    )
}

/// Generate deterministic call ID for message library quote calls
/// Used to create consistent call object references across PTBs
public fun message_lib_quote_call_id(): Bytes32 {
    hash::keccak256!(
        type_name::get_with_original_ids<Call<MessageLibQuoteParam, MessagingFee>>().into_string().as_bytes(),
    )
}

/// Generate deterministic call ID for message library send calls
/// Used to create consistent call object references across PTBs
public fun message_lib_send_call_id(): Bytes32 {
    hash::keccak256!(
        type_name::get_with_original_ids<Call<MessageLibSendParam, MessageLibSendResult>>().into_string().as_bytes(),
    )
}

/// Generate deterministic call ID for message library set_config calls
/// Used to create consistent call object references across PTBs
public fun message_lib_set_config_call_id(): Bytes32 {
    hash::keccak256!(type_name::get_with_original_ids<Call<MessageLibSetConfigParam, Void>>().into_string().as_bytes())
}

// === View Functions ===

/// Get the default PTB builder for a message library
public fun get_default_msglib_ptb_builder(self: &EndpointPtbBuilder, lib: address): address {
    *table_ext::borrow_or_abort!(&self.default_configs, lib, EBuilderNotFound)
}

/// Get the OApp-specific PTB builder for a message library
public fun get_oapp_msglib_ptb_builder(self: &EndpointPtbBuilder, oapp: address, lib: address): address {
    *table_ext::borrow_or_abort!(&self.oapp_configs, OAppConfigKey { oapp, lib }, EBuilderNotFound)
}

/// Get the effective PTB builder for an OApp and message library combination
/// Returns OApp-specific builder if configured, otherwise falls back to default
#[allow(implicit_const_copy)]
public fun get_effective_msglib_ptb_builder(self: &EndpointPtbBuilder, oapp: address, lib: address): address {
    let builder = *table_ext::borrow_with_default!(&self.oapp_configs, OAppConfigKey { oapp, lib }, &DEFAULT_BUILDER);
    if (builder != DEFAULT_BUILDER) {
        builder
    } else {
        self.get_default_msglib_ptb_builder(lib)
    }
}

/// Get detailed information about a registered PTB builder
public fun get_msglib_ptb_builder_info(self: &EndpointPtbBuilder, builder: address): &MsglibPtbBuilderInfo {
    assert!(self.is_msglib_ptb_builder_registered(builder), EBuilderNotFound);
    &self.registry.builder_infos[builder]
}

/// Check if a PTB builder is registered in the registry
public fun is_msglib_ptb_builder_registered(self: &EndpointPtbBuilder, builder: address): bool {
    self.registry.builder_infos.contains(builder)
}

/// Get the total number of registered PTB builders
public fun registered_msglib_ptb_builders_count(self: &EndpointPtbBuilder): u64 {
    self.registry.builders.length()
}

/// Get a paginated list of registered PTB builder addresses
public fun registered_msglib_ptb_builders(self: &EndpointPtbBuilder, start: u64, max_count: u64): vector<address> {
    let end = u64::min(start + max_count, self.registered_msglib_ptb_builders_count());
    assert!(start <= end, EInvalidBounds);
    vector::tabulate!(end - start, |i| self.registry.builders[start + i])
}

// === Helper Functions ===

/// Validates that a PTB builder is registered and supports the specified message library
/// If the PTB builder is not registered
/// If the PTB builder doesn't support the specified message library
fun assert_msglib_ptb_builder_supported(self: &MsglibPtbBuilderRegistry, lib: address, ptb_builder: address) {
    let builder_info = table_ext::borrow_or_abort!(&self.builder_infos, ptb_builder, EBuilderNotFound);
    assert!(builder_info.message_lib() == lib, EBuilderUnsupported);
}

// === Test Functions ===

#[test_only]
/// Initialize the EndpointPtbBuilder for testing
public fun init_for_test(ctx: &mut TxContext) {
    init(ctx);
}
