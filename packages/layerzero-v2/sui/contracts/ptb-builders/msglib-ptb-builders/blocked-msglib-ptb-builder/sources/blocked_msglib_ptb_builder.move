module blocked_msglib_ptb_builder::blocked_msglib_ptb_builder;

use blocked_message_lib::blocked_message_lib::BlockedMessageLib;
use call::call_cap::{Self, CallCap};
use endpoint_ptb_builder::{endpoint_ptb_builder, msglib_ptb_builder_info::{Self, MsglibPtbBuilderInfo}};
use ptb_move_call::{argument, move_call::{Self, MoveCall}, move_calls_builder};
use utils::package;

// === structs ===

/// One time witness for the blocked message library PTB builder
public struct BLOCKED_MSGLIB_PTB_BUILDER has drop {}

public struct BlockedMsglibPtbBuilder has key {
    id: UID,
    call_cap: CallCap,
}

// === Init Functions ===

fun init(witness: BLOCKED_MSGLIB_PTB_BUILDER, ctx: &mut TxContext) {
    transfer::share_object(BlockedMsglibPtbBuilder {
        id: object::new(ctx),
        call_cap: call_cap::new_package_cap(&witness, ctx),
    });
}

public fun get_ptb_builder_info(
    self: &BlockedMsglibPtbBuilder,
    blocked_msglib: &BlockedMessageLib,
): MsglibPtbBuilderInfo {
    msglib_ptb_builder_info::create(
        package::original_package_of_type<BlockedMessageLib>(),
        self.call_cap.id(),
        build_quote_ptb(blocked_msglib),
        build_send_ptb(blocked_msglib),
        build_set_config_ptb(blocked_msglib),
    )
}

// === Build Functions ===

public fun build_quote_ptb(blocked_msglib: &BlockedMessageLib): vector<MoveCall> {
    let blocked_msglib_package = package::original_package_of_type<BlockedMessageLib>();
    let mut move_calls_builder = move_calls_builder::new();

    // blocked_msglib::quote(blocked_msglib, message_lib_quote_call)
    move_calls_builder.add(
        move_call::create(
            blocked_msglib_package,
            b"blocked_message_lib".to_ascii_string(),
            b"quote".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(blocked_msglib)),
                argument::create_id(endpoint_ptb_builder::message_lib_quote_call_id()),
            ],
            vector[],
            false,
            vector[],
        ),
    );
    move_calls_builder.build()
}

public fun build_send_ptb(blocked_msglib: &BlockedMessageLib): vector<MoveCall> {
    let blocked_msglib_package = package::original_package_of_type<BlockedMessageLib>();
    let mut move_calls_builder = move_calls_builder::new();

    // blocked_msglib::send(blocked_msglib, message_lib_send_call)
    move_calls_builder.add(
        move_call::create(
            blocked_msglib_package,
            b"blocked_message_lib".to_ascii_string(),
            b"send".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(blocked_msglib)),
                argument::create_id(endpoint_ptb_builder::message_lib_send_call_id()),
            ],
            vector[],
            false,
            vector[],
        ),
    );
    move_calls_builder.build()
}

public fun build_set_config_ptb(blocked_msglib: &BlockedMessageLib): vector<MoveCall> {
    let blocked_msglib_package = package::original_package_of_type<BlockedMessageLib>();
    let mut move_calls_builder = move_calls_builder::new();

    // blocked_msglib::set_config(blocked_msglib, message_lib_set_config_call)
    move_calls_builder.add(
        move_call::create(
            blocked_msglib_package,
            b"blocked_message_lib".to_ascii_string(),
            b"set_config".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(blocked_msglib)),
                argument::create_id(endpoint_ptb_builder::message_lib_set_config_call_id()),
            ],
            vector[],
            false,
            vector[],
        ),
    );
    move_calls_builder.build()
}
