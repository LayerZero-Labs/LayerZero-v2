// This module will be shared with other oapp test modules.
#[test_only]
module counter::test_helper_with_sml;

use call::call::Call;
use counter::{deployments::Deployments, scenario_utils};
use endpoint_v2::{
    endpoint_quote::QuoteParam as EndpointQuoteParam,
    endpoint_send::SendParam as EndpointSendParam,
    endpoint_v2::{Self, EndpointV2, AdminCap},
    message_lib_type,
    messaging_channel::MessagingChannel,
    messaging_fee::MessagingFee,
    messaging_receipt::MessagingReceipt,
    utils
};
use message_lib_common::packet_v1_codec::{Self, PacketHeader};
use simple_message_lib::simple_message_lib::{Self, SimpleMessageLib, AdminCap as SmlAdminCap};
use sui::{clock::Clock, test_scenario::{Self, Scenario}};
use utils::{buffer_reader, bytes32::Bytes32, hash};

// === Public Functions ===

/// Setup a single endpoint
public fun setup_endpoint(scenario: &mut Scenario, sender: address, eid: u32, deployments: &mut Deployments) {
    endpoint_v2::init_for_test(scenario.ctx());
    scenario.next_tx(sender);
    let endpoint_admin_cap = scenario.take_from_sender<AdminCap>();
    let mut endpoint = scenario.take_shared<EndpointV2>();
    endpoint.init_eid(&endpoint_admin_cap, eid);

    deployments.set_deployment<EndpointV2>(eid, object::id_address(&endpoint));
    deployments.set_deployment<AdminCap>(eid, object::id_address(&endpoint_admin_cap));

    test_scenario::return_shared<EndpointV2>(endpoint);
    scenario.return_to_sender<AdminCap>(endpoint_admin_cap);
}

/// Setup Simple Message Library (SML) for the specified endpoint
public fun setup_sml(
    scenario: &mut Scenario,
    sender: address,
    eid: u32,
    remote_eids: vector<u32>,
    deployments: &mut Deployments,
    test_clock: &Clock,
) {
    scenario.next_tx(sender);
    let endpoint_admin_cap = scenario_utils::take_from_sender_by_address<AdminCap>(
        scenario,
        deployments.get_deployment<AdminCap>(eid),
    );
    let mut endpoint = scenario_utils::take_shared_by_address<EndpointV2>(
        scenario,
        deployments.get_deployment<EndpointV2>(eid),
    );

    simple_message_lib::init_for_test(scenario.ctx());

    scenario.next_tx(sender);
    let sml_admin_cap = scenario.take_from_sender<SmlAdminCap>();
    let sml = scenario.take_shared<SimpleMessageLib>();
    let message_lib_cap = sml.borrow_call_cap().id();

    // Register library with endpoint
    endpoint.register_library(
        &endpoint_admin_cap,
        message_lib_cap,
        message_lib_type::send_and_receive(),
    );

    remote_eids.do!(|dst_eid| {
        if (dst_eid != endpoint.eid()) {
            // Configure the endpoint to use the simple message library
            endpoint_v2::set_default_send_library(&mut endpoint, &endpoint_admin_cap, dst_eid, message_lib_cap);
            endpoint_v2::set_default_receive_library(
                &mut endpoint,
                &endpoint_admin_cap,
                dst_eid,
                message_lib_cap,
                0,
                test_clock,
            );
        };
    });

    deployments.set_deployment<SimpleMessageLib>(eid, object::id_address(&sml));
    deployments.set_deployment<SmlAdminCap>(eid, object::id_address(&sml_admin_cap));

    scenario.return_to_sender<AdminCap>(endpoint_admin_cap);
    scenario.return_to_sender<SmlAdminCap>(sml_admin_cap);
    test_scenario::return_shared<EndpointV2>(endpoint);
    test_scenario::return_shared<SimpleMessageLib>(sml);
}

/// Setup multiple endpoints with corresponding SMLs
public fun setup_endpoint_with_sml(
    scenario: &mut Scenario,
    sender: address,
    eids: vector<u32>,
    deployments: &mut Deployments,
    test_clock: &Clock,
) {
    eids.do!(|eid| {
        setup_endpoint(scenario, sender, eid, deployments);
        setup_sml(scenario, sender, eid, eids, deployments, test_clock);
    });
}

public fun quote(
    endpoint: &EndpointV2,
    sml: &SimpleMessageLib,
    messaging_channel: &MessagingChannel,
    quote_call: &mut Call<EndpointQuoteParam, MessagingFee>,
    ctx: &mut TxContext,
) {
    // Step 1: Endpoint processes quote and creates message lib call
    let mut message_lib_call = endpoint.quote(messaging_channel, quote_call, ctx);

    // Step 2: SML processes the quote (this will internally call endpoint.confirm_quote)
    sml.quote(&mut message_lib_call);
    endpoint.confirm_quote(quote_call, message_lib_call);
}

/// Execute the complete send call chain: endpoint.send -> SML.send -> OAppHelper.refund_send
/// Returns the encoded packet for test verification
public fun execute_send_call(
    scenario: &mut Scenario,
    sender: address,
    deployments: &Deployments,
    src_eid: u32,
    mut counter_call: Call<EndpointSendParam, MessagingReceipt>,
) {
    scenario.next_tx(sender); // Use the provided sender
    let endpoint = scenario_utils::take_shared_by_address<EndpointV2>(
        scenario,
        deployments.get_deployment<EndpointV2>(src_eid),
    );
    let sml = scenario_utils::take_shared_by_address<SimpleMessageLib>(
        scenario,
        deployments.get_deployment<SimpleMessageLib>(src_eid),
    );
    let mut messaging_channel = scenario_utils::take_shared_by_address<MessagingChannel>(
        scenario,
        deployments.get_deployment<MessagingChannel>(src_eid),
    );

    // Step 1: Endpoint processes the counter call and returns SML call
    let sml_call = endpoint.send(&mut messaging_channel, &mut counter_call, scenario.ctx());

    // Step 2: SimpleMessageLib processes the call
    sml.send(&endpoint, &mut messaging_channel, &mut counter_call, sml_call, scenario.ctx());

    // Step 3: Endpoint refund
    endpoint.refund(counter_call);

    // Return objects
    test_scenario::return_shared<EndpointV2>(endpoint);
    test_scenario::return_shared<SimpleMessageLib>(sml);
    test_scenario::return_shared<MessagingChannel>(messaging_channel);
}

/// Verify message packet with simplified packet parsing
public fun verify_message(
    scenario: &mut Scenario,
    sender: address,
    encoded_packet: vector<u8>,
    deployments: &Deployments,
    eid: u32,
    test_clock: &Clock,
) {
    scenario.next_tx(sender);
    let sml_admin_cap = scenario_utils::take_from_sender_by_address<SmlAdminCap>(
        scenario,
        deployments.get_deployment<SmlAdminCap>(eid),
    );
    let endpoint = scenario_utils::take_shared_by_address<EndpointV2>(
        scenario,
        deployments.get_deployment<EndpointV2>(eid),
    );
    let sml = scenario_utils::take_shared_by_address<SimpleMessageLib>(
        scenario,
        deployments.get_deployment<SimpleMessageLib>(eid),
    );
    let mut messaging_channel = scenario_utils::take_shared_by_address<MessagingChannel>(
        scenario,
        deployments.get_deployment<MessagingChannel>(eid),
    );

    let (header, guid, message) = decode_packet_for_test(encoded_packet);
    simple_message_lib::validate_packet(
        &sml,
        &endpoint,
        &sml_admin_cap,
        &mut messaging_channel,
        header.encode_header(),
        hash::keccak256!(&utils::build_payload(guid, message)),
        test_clock,
    );

    test_scenario::return_shared<EndpointV2>(endpoint);
    test_scenario::return_shared<SimpleMessageLib>(sml);
    test_scenario::return_shared<MessagingChannel>(messaging_channel);
    scenario.return_to_sender<SmlAdminCap>(sml_admin_cap);
}

fun decode_packet_for_test(encoded: vector<u8>): (PacketHeader, Bytes32, vector<u8>) {
    let mut reader = buffer_reader::create(encoded);
    let header = packet_v1_codec::decode_header(reader.read_fixed_len_bytes(81));
    let guid = reader.read_bytes32();
    let message = reader.read_bytes_until_end();
    (header, guid, message)
}
