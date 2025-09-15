module simple_msglib_ptb_builder::simple_msglib_ptb_builder;

use call::{call::Call, call_cap::{Self, CallCap}};
use endpoint_ptb_builder::{endpoint_ptb_builder, msglib_ptb_builder_info::{Self, MsglibPtbBuilderInfo}};
use endpoint_v2::{endpoint_send::SendParam, endpoint_v2::EndpointV2, messaging_receipt::MessagingReceipt};
use ptb_move_call::{argument, move_call::{Self, MoveCall}, move_calls_builder};
use simple_message_lib::simple_message_lib::SimpleMessageLib;
use utils::package;

// === structs ===

/// One time witness for the simple message library PTB builder
public struct SIMPLE_MSGLIB_PTB_BUILDER has drop {}

public struct SimpleMsglibPtbBuilder has key {
    id: UID,
    call_cap: CallCap,
}

// === Init Functions ===

fun init(witness: SIMPLE_MSGLIB_PTB_BUILDER, ctx: &mut TxContext) {
    transfer::share_object(SimpleMsglibPtbBuilder {
        id: object::new(ctx),
        call_cap: call_cap::new_package_cap(&witness, ctx),
    });
}

public fun get_ptb_builder_info(
    self: &SimpleMsglibPtbBuilder,
    endpoint: &EndpointV2,
    simple_msglib: &SimpleMessageLib,
): MsglibPtbBuilderInfo {
    // This is a builder call to build the send PTB dynamically based on the endpoint and call
    let send_move_calls = vector[
        move_call::create(
            self.call_cap.id(),
            b"simple_msglib_ptb_builder".to_ascii_string(),
            b"build_send_ptb".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(simple_msglib)),
                argument::create_object(object::id_address(endpoint)),
                argument::create_id(endpoint_ptb_builder::endpoint_send_call_id()),
            ],
            vector[],
            true,
            vector[],
        ),
    ];

    msglib_ptb_builder_info::create(
        package::original_package_of_type<SimpleMessageLib>(),
        self.call_cap.id(),
        build_quote_ptb(simple_msglib),
        send_move_calls,
        build_set_config_ptb(simple_msglib),
    )
}

// === Build Functions ===

public fun build_quote_ptb(simple_msglib: &SimpleMessageLib): vector<MoveCall> {
    let simple_msglib_package = package::package_of_type<SimpleMessageLib>();
    let mut move_calls_builder = move_calls_builder::new();

    // simple_msglib::quote(simple_msglib, message_lib_quote_call)
    move_calls_builder.add(
        move_call::create(
            simple_msglib_package,
            b"simple_message_lib".to_ascii_string(),
            b"quote".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(simple_msglib)),
                argument::create_id(endpoint_ptb_builder::message_lib_quote_call_id()),
            ],
            vector[],
            false,
            vector[],
        ),
    );
    move_calls_builder.build()
}

public fun build_send_ptb(
    simple_msglib: &SimpleMessageLib,
    endpoint: &EndpointV2,
    call: &Call<SendParam, MessagingReceipt>,
): vector<MoveCall> {
    let simple_msglib_package = package::package_of_type<SimpleMessageLib>();
    let messaging_channel = endpoint.get_messaging_channel(call.caller());
    let mut move_calls_builder = move_calls_builder::new();

    // simple_msglib::send(simple_msglib, endpoint, messaging_channel, call, message_lib_call)
    move_calls_builder.add(
        move_call::create(
            simple_msglib_package,
            b"simple_message_lib".to_ascii_string(),
            b"send".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(simple_msglib)),
                argument::create_object(object::id_address(endpoint)),
                argument::create_object(messaging_channel),
                argument::create_id(endpoint_ptb_builder::endpoint_send_call_id()),
                argument::create_id(endpoint_ptb_builder::message_lib_send_call_id()),
            ],
            vector[],
            false,
            vector[],
        ),
    );
    move_calls_builder.build()
}

public fun build_set_config_ptb(simple_msglib: &SimpleMessageLib): vector<MoveCall> {
    let simple_msglib_package = package::package_of_type<SimpleMessageLib>();
    let mut move_calls_builder = move_calls_builder::new();

    // simple_msglib::set_config(simple_msglib, message_lib_set_config_call)
    move_calls_builder.add(
        move_call::create(
            simple_msglib_package,
            b"simple_message_lib".to_ascii_string(),
            b"set_config".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(simple_msglib)),
                argument::create_id(endpoint_ptb_builder::message_lib_set_config_call_id()),
            ],
            vector[],
            false,
            vector[],
        ),
    );
    move_calls_builder.build()
}
