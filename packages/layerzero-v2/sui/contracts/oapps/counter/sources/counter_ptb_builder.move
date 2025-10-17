module counter::counter_ptb_builder;

use call::call::{Call, Void};
use counter::{counter::Counter, msg_codec};
use endpoint_ptb_builder::endpoint_ptb_builder::{Self, EndpointPtbBuilder};
use endpoint_v2::{endpoint_v2::EndpointV2, lz_compose::LzComposeParam, lz_receive::LzReceiveParam};
use oapp::{oapp::OApp, ptb_builder_helper};
use ptb_move_call::{
    argument::{Self, Argument},
    move_call::{Self, MoveCall},
    move_calls_builder::{Self, MoveCallsBuilder}
};
use sui::bcs;
use utils::{buffer_writer, package};

// === Constants ===

const ABA_TYPE: u8 = 3;
const COMPOSED_ABA_TYPE: u8 = 4;

const LZ_EXECUTE_INFO_VERSION_1: u16 = 1; // 2 bytes + vector<MoveCall>.to_bytes(), return ptb calls after simulate

public fun lz_receive_info(
    counter: &Counter,
    oapp: &OApp,
    endpoint: &EndpointV2,
    endpoint_ptb_builder: &EndpointPtbBuilder,
): vector<u8> {
    let counter_package = package::package_of_type<Counter>();
    let lz_receive_move_calls = vector[
        move_call::create(
            counter_package,
            b"counter_ptb_builder".to_ascii_string(),
            b"build_ptb_for_lz_receive".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(counter)),
                argument::create_object(object::id_address(oapp)),
                argument::create_object(object::id_address(endpoint)),
                argument::create_object(object::id_address(endpoint_ptb_builder)),
                argument::create_id(ptb_builder_helper::lz_receive_call_id()),
            ],
            vector[],
            true,
            vector[],
        ),
    ];
    let move_calls_bytes = bcs::to_bytes(&lz_receive_move_calls);
    let mut writer = buffer_writer::new();
    writer.write_u16(LZ_EXECUTE_INFO_VERSION_1).write_bytes(move_calls_bytes);
    writer.to_bytes()
}

public fun lz_compose_info(
    counter: &Counter,
    oapp: &OApp,
    endpoint: &EndpointV2,
    endpoint_ptb_builder: &EndpointPtbBuilder,
): vector<u8> {
    let counter_package = package::package_of_type<Counter>();
    let lz_compose_move_calls = vector[
        move_call::create(
            counter_package,
            b"counter_ptb_builder".to_ascii_string(),
            b"build_ptb_for_lz_compose".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(counter)),
                argument::create_object(object::id_address(oapp)),
                argument::create_object(object::id_address(endpoint)),
                argument::create_object(object::id_address(endpoint_ptb_builder)),
                argument::create_id(ptb_builder_helper::lz_compose_call_id()),
            ],
            vector[],
            true,
            vector[],
        ),
    ];
    let move_calls_bytes = bcs::to_bytes(&lz_compose_move_calls);
    let mut writer = buffer_writer::new();
    writer.write_u16(LZ_EXECUTE_INFO_VERSION_1).write_bytes(move_calls_bytes);
    writer.to_bytes()
}

// === PTB Builder Functions ===

public fun build_ptb_for_lz_receive(
    counter: &Counter,
    oapp: &OApp,
    endpoint: &EndpointV2,
    endpoint_ptb_builder: &EndpointPtbBuilder,
    call: &Call<LzReceiveParam, Void>,
): vector<MoveCall> {
    let message = call.param().message();
    let msg_type = msg_codec::get_msg_type(message);
    let mut builder = move_calls_builder::new();

    if (msg_type != ABA_TYPE) {
        add_lz_receive_call(&mut builder, counter, oapp, endpoint);
    } else {
        // ABA Mode:
        // call lz_receive_aba() and get the endpoint_call
        let endpoint_call = add_lz_receive_aba_call(&mut builder, counter, oapp);
        // build the endpoint send ptb
        let endpoint_move_calls = endpoint_ptb_builder::build_send_ptb(
            endpoint_ptb_builder,
            endpoint,
            counter.call_cap_address(),
            call.param().src_eid(),
            false,
        );
        builder.append(endpoint_move_calls);
        // refund fee
        add_refund_fee_call(&mut builder, endpoint, endpoint_call);
    };
    builder.build()
}

public fun build_ptb_for_lz_compose(
    counter: &Counter,
    oapp: &OApp,
    endpoint: &EndpointV2,
    endpoint_ptb_builder: &EndpointPtbBuilder,
    call: &Call<LzComposeParam, Void>,
): vector<MoveCall> {
    let message = call.param().message();
    let msg_type = msg_codec::get_msg_type(message);
    let mut builder = move_calls_builder::new();

    if (msg_type != COMPOSED_ABA_TYPE) {
        add_lz_compose_call(&mut builder, counter);
    } else {
        // ABA Mode:
        // call lz_compose_aba() and get the endpoint_call
        let endpoint_call = add_lz_compose_aba_call(&mut builder, counter, oapp);
        // build the endpoint send ptb
        let src_eid = msg_codec::get_src_eid(message);
        let endpoint_move_calls = endpoint_ptb_builder::build_send_ptb(
            endpoint_ptb_builder,
            endpoint,
            counter.call_cap_address(),
            src_eid,
            false,
        );
        builder.append(endpoint_move_calls);
        // refund fee
        add_refund_fee_call(&mut builder, endpoint, endpoint_call);
    };
    builder.build()
}

// === Helper Functions ===

fun add_lz_receive_call(builder: &mut MoveCallsBuilder, counter: &Counter, oapp: &OApp, endpoint: &EndpointV2) {
    let counter_package = package::package_of_type<Counter>();
    let composer = counter.composer_address();
    let compose_queue = endpoint.get_compose_queue(composer);
    builder.add(
        move_call::create(
            counter_package,
            b"counter".to_ascii_string(),
            b"lz_receive".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(counter)),
                argument::create_object(object::id_address(oapp)),
                argument::create_object(compose_queue),
                argument::create_id(ptb_builder_helper::lz_receive_call_id()),
            ],
            vector[],
            false,
            vector[],
        ),
    );
}

fun add_lz_receive_aba_call(builder: &mut MoveCallsBuilder, counter: &Counter, oapp: &OApp): Argument {
    let counter_package = package::package_of_type<Counter>();
    builder
        .add(
            move_call::create(
                counter_package,
                b"counter".to_ascii_string(),
                b"lz_receive_aba".to_ascii_string(),
                vector[
                    argument::create_object(object::id_address(counter)),
                    argument::create_object(object::id_address(oapp)),
                    argument::create_id(ptb_builder_helper::lz_receive_call_id()),
                ],
                vector[],
                false,
                vector[endpoint_ptb_builder::endpoint_send_call_id()],
            ),
        )
        .to_nested_result_arg(0)
}

fun add_lz_compose_call(builder: &mut MoveCallsBuilder, counter: &Counter) {
    let counter_package = package::package_of_type<Counter>();
    builder.add(
        move_call::create(
            counter_package,
            b"counter".to_ascii_string(),
            b"lz_compose".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(counter)),
                argument::create_id(ptb_builder_helper::lz_compose_call_id()),
            ],
            vector[],
            false,
            vector[],
        ),
    );
}

fun add_lz_compose_aba_call(builder: &mut MoveCallsBuilder, counter: &Counter, oapp: &OApp): Argument {
    let counter_package = package::package_of_type<Counter>();
    builder
        .add(
            move_call::create(
                counter_package,
                b"counter".to_ascii_string(),
                b"lz_compose_aba".to_ascii_string(),
                vector[
                    argument::create_object(object::id_address(counter)),
                    argument::create_object(object::id_address(oapp)),
                    argument::create_id(ptb_builder_helper::lz_compose_call_id()),
                ],
                vector[],
                false,
                vector[endpoint_ptb_builder::endpoint_send_call_id()],
            ),
        )
        .to_nested_result_arg(0)
}

fun add_refund_fee_call(builder: &mut MoveCallsBuilder, endpoint: &EndpointV2, endpoint_call: Argument) {
    let endpoint_package = package::package_of_type<EndpointV2>();
    builder.add(
        move_call::create(
            endpoint_package,
            b"endpoint_v2".to_ascii_string(),
            b"refund".to_ascii_string(),
            vector[argument::create_object(object::id_address(endpoint)), endpoint_call],
            vector[],
            false,
            vector[],
        ),
    );
}
