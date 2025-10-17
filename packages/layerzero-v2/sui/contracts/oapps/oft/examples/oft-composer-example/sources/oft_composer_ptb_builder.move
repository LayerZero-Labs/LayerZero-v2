module oft_composer_example::oft_composer_ptb_builder;

use call::call::{Call, Void};
use endpoint_v2::lz_compose::LzComposeParam;
use oapp::ptb_builder_helper;
use oft_common::oft_composer_manager::OFTComposerManager;
use oft_composer_example::oft_composer::OFTComposer;
use ptb_move_call::{argument, move_call::{Self, MoveCall}, move_calls_builder};
use std::{bcs, type_name};
use utils::{buffer_writer, package};

const LZ_EXECUTE_INFO_VERSION_1: u16 = 1; // 2 bytes + vector<MoveCall>.to_bytes(), return ptb calls after simulate

public struct OFT_COMPOSER_PTB_BUILDER has drop {}

public struct OFTComposerPtbBuilder has key {
    id: UID,
}

fun init(_witness: OFT_COMPOSER_PTB_BUILDER, ctx: &mut TxContext) {
    transfer::share_object(OFTComposerPtbBuilder {
        id: object::new(ctx),
    });
}

public fun lz_compose_info<COIN_TYPE>(composer: &OFTComposer, registry: &OFTComposerManager): vector<u8> {
    let ptb_builder_package_id = package::package_of_type<OFTComposerPtbBuilder>();
    let lz_compose_move_calls = vector[
        move_call::create(
            ptb_builder_package_id,
            b"oft_composer_ptb_builder".to_ascii_string(),
            b"build_lz_compose_ptb".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(composer)),
                argument::create_object(object::id_address(registry)),
                argument::create_id(ptb_builder_helper::lz_compose_call_id()),
            ],
            vector[type_name::get<COIN_TYPE>()],
            true,
            vector[],
        ),
    ];
    let move_calls_bytes = bcs::to_bytes(&lz_compose_move_calls);
    let mut writer = buffer_writer::new();
    writer.write_u16(LZ_EXECUTE_INFO_VERSION_1).write_bytes(move_calls_bytes);
    writer.to_bytes()
}

public fun build_lz_compose_ptb<COIN_TYPE>(
    composer: &OFTComposer,
    composer_manager: &OFTComposerManager,
    call: &Call<LzComposeParam, Void>,
): vector<MoveCall> {
    let oft_address = call.param().from(); // oft on target chain that send this compose message
    let guid = call.param().guid();
    let composer_address = composer.composer_address();
    let transfer_address = composer_manager.get_compose_transfer(oft_address, guid, composer_address);

    let mut builder = move_calls_builder::new();
    let ptb_builder_package_id = package::package_of_type<OFTComposerPtbBuilder>();
    builder.add(
        move_call::create(
            ptb_builder_package_id,
            b"oft_composer".to_ascii_string(),
            b"lz_compose".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(composer)),
                argument::create_object(transfer_address),
                argument::create_id(ptb_builder_helper::lz_compose_call_id()),
            ],
            vector[type_name::get<COIN_TYPE>()],
            false,
            vector[],
        ),
    );
    builder.build()
}
