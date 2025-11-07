/// OFT Programmable Transaction Block (PTB) Builder
///
/// This module provides utilities for building programmable transaction blocks (PTBs)
/// that handle OFT cross-chain message reception and compose operations.
module oft::oft_ptb_builder;

use call::call::{Call, Void};
use endpoint_v2::{endpoint_v2::EndpointV2, lz_receive::LzReceiveParam};
use oapp::ptb_builder_helper;
use oft::{oft::OFT, oft_msg_codec};
use oft_common::oft_composer_manager::OFTComposerManager;
use ptb_move_call::{argument, move_call::{Self, MoveCall}, move_calls_builder::{Self, MoveCallsBuilder}};
use std::type_name;
use iota::{bcs, clock::Clock};
use utils::{buffer_writer, package};

/// Version identifier for lz_receive_info format - version 1 includes 2-byte version header plus serialized MoveCall
/// vector
const LZ_RECEIVE_INFO_VERSION_1: u16 = 1;

public struct OFTPtbBuilder {}

/// Generates execution metadata for OFT registration with LayerZero endpoint.
///
/// **Parameters**:
/// - `oft`: OFT instance that will be registered with the endpoint
/// - `endpoint`: LayerZero V2 endpoint for message processing infrastructure
/// - `composer_manager`: Manager for routing compose transfers to composers
///
/// **Returns**: Serialized execution metadata for endpoint registration
public fun lz_receive_info<T>(
    oft: &OFT<T>,
    endpoint: &EndpointV2,
    composer_manager: &OFTComposerManager,
    clock: &Clock,
): vector<u8> {
    let lz_receive_move_calls = vector[
        move_call::create(
            oft_package(),
            b"oft_ptb_builder".to_ascii_string(),
            b"build_lz_receive_ptb".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(oft)),
                argument::create_object(object::id_address(endpoint)),
                argument::create_object(object::id_address(composer_manager)),
                argument::create_id(ptb_builder_helper::lz_receive_call_id()),
                argument::create_object(object::id_address(clock)),
            ],
            vector[type_name::get<T>()],
            true,
            vector[],
        ),
    ];
    let move_calls_bytes = bcs::to_bytes(&lz_receive_move_calls);
    let mut writer = buffer_writer::new();
    writer.write_u16(LZ_RECEIVE_INFO_VERSION_1).write_bytes(move_calls_bytes);
    writer.to_bytes()
}

/// Dynamically builds a PTB for processing incoming LayerZero messages based on message content.
///
/// **Parameters**:
/// - `oft`: Target OFT instance that will process the message
/// - `endpoint`: LayerZero endpoint managing message processing
/// - `composer_manager`: Manager for routing compose transfers (used if compose detected)
/// - `call`: LayerZero receive call containing the cross-chain message
///
/// **Returns**: Vector of Move calls forming a complete PTB for message execution
public fun build_lz_receive_ptb<T>(
    oft: &OFT<T>,
    endpoint: &EndpointV2,
    composer_manager: &OFTComposerManager,
    call: &Call<LzReceiveParam, Void>,
    clock: &Clock,
): vector<MoveCall> {
    let mut builder = move_calls_builder::new();
    let message = oft_msg_codec::decode(*call.param().message());
    if (message.is_composed()) {
        add_lz_receive_compose_call<T>(
            &mut builder,
            oft,
            endpoint,
            object::id_address(composer_manager),
            message.send_to(),
            clock,
        );
    } else {
        add_lz_receive_call<T>(&mut builder, oft, clock);
    };
    builder.build()
}

/// Adds a standard lz_receive call to the PTB builder for simple token transfers.
///
/// **Parameters**:
/// - `builder`: PTB builder to add the call to
/// - `oft`: Target OFT instance that will process the token transfer
fun add_lz_receive_call<T>(builder: &mut MoveCallsBuilder, oft: &OFT<T>, clock: &Clock) {
    let oapp_object = oft.oapp_object();
    builder.add(
        move_call::create(
            oft_package(),
            b"oft".to_ascii_string(),
            b"lz_receive".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(oft)),
                argument::create_object(oapp_object),
                argument::create_id(ptb_builder_helper::lz_receive_call_id()),
                argument::create_object(object::id_address(clock)),
            ],
            vector[type_name::get<T>()],
            false,
            vector[],
        ),
    );
}

/// Adds a compose-enabled lz_receive call to the PTB builder for complex cross-chain workflows.
///
/// **Parameters**:
/// - `builder`: PTB builder to add the compose call to
/// - `oft`: Target OFT instance that will process the compose transfer
/// - `endpoint`: LayerZero endpoint managing compose message queuing
/// - `composer_manager`: Address of the composer manager for token routing
/// - `composer`: Target composer address that will execute the compose logic
fun add_lz_receive_compose_call<T>(
    builder: &mut MoveCallsBuilder,
    oft: &OFT<T>,
    endpoint: &EndpointV2,
    composer_manager: address,
    composer: address,
    clock: &Clock,
) {
    let compose_queue = endpoint.get_compose_queue(composer);
    let oapp_object = oft.oapp_object();
    builder.add(
        move_call::create(
            oft_package(),
            b"oft".to_ascii_string(),
            b"lz_receive_with_compose".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(oft)),
                argument::create_object(oapp_object),
                argument::create_object(compose_queue),
                argument::create_object(composer_manager),
                argument::create_id(ptb_builder_helper::lz_receive_call_id()),
                argument::create_object(object::id_address(clock)),
            ],
            vector[type_name::get<T>()],
            false,
            vector[],
        ),
    );
}

/// Returns the current package address for OFT operations.
///
/// When upgrading OFT contracts, create a new struct (e.g., OFTPtbBuilder2)
/// and update this function to use the new type to get the latest package address:
/// ```
/// fun oft_package(): address {
///     package::package_of_type<OFTPtbBuilder2>()
/// }
/// ```
/// This approach ensures PTB builders always reference the most recent
/// package version after contract upgrades.
fun oft_package(): address {
    package::package_of_type<OFTPtbBuilder>()
}
