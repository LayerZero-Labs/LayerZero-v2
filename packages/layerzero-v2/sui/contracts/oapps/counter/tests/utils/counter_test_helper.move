// This module is only used to help with the testing of the counter contract.
#[test_only]
module counter::counter_test_helper;

use call::{call::Call, call_cap};
use counter::{counter::{Self, Counter}, deployments::Deployments, scenario_utils};
use endpoint_v2::{
    endpoint_send::SendParam as EndpointSendParam,
    endpoint_v2::EndpointV2,
    messaging_channel::MessagingChannel,
    messaging_composer::{ComposeSentEvent, ComposeQueue},
    messaging_receipt::MessagingReceipt
};
use message_lib_common::packet_v1_codec::{Self, PacketHeader};
use oapp::oapp::{AdminCap as CounterAdminCap, OApp};
use sui::{coin::Coin, sui::SUI, test_scenario::{Self, Scenario}, test_utils};
use utils::{buffer_reader, bytes32::Bytes32};
use zro::zro::ZRO;

// === Public Functions ===

/// Setup multiple counter instances, each corresponding to an endpoint
public fun setup_counter(scenario: &mut Scenario, sender: address, eids: vector<u32>, deployments: &mut Deployments) {
    // Create all counter instances
    create_counter_instances(scenario, sender, eids, deployments);

    // Configure peer connections between counters
    configure_counter_peers(scenario, sender, eids, deployments);
}

/// Create counter instances
fun create_counter_instances(
    scenario: &mut Scenario,
    sender: address,
    eids: vector<u32>,
    deployments: &mut Deployments,
) {
    eids.do!(|eid| {
        scenario.next_tx(sender);
        counter::init_for_test(scenario);

        scenario.next_tx(sender);
        let mut counter = scenario.take_shared<Counter>();
        let mut oapp = scenario.take_shared<OApp>();
        let counter_admin_cap = scenario.take_from_sender<CounterAdminCap>();
        let mut endpoint = deployments.get_deployment_object<EndpointV2>(scenario, eid);

        counter.init_counter_for_test(
            &mut oapp,
            &counter_admin_cap,
            &mut endpoint,
            b"lz_receive_info",
            b"lz_compose_info",
            scenario.ctx(),
        );

        // Get the MessagingChannel address from the endpoint's oapp registry
        let oapp_call_cap_address = counter.call_cap_address();
        let messaging_channel_address = endpoint.get_messaging_channel(oapp_call_cap_address);

        // Get the ComposeQueue address from the endpoint's composer registry
        let composer_address = counter.composer_address();
        let compose_queue_address = endpoint.get_compose_queue(composer_address);

        deployments.set_deployment<Counter>(eid, object::id_address(&counter));
        deployments.set_deployment<OApp>(eid, object::id_address(&oapp));
        deployments.set_deployment<CounterAdminCap>(eid, object::id_address(&counter_admin_cap));
        deployments.set_deployment<MessagingChannel>(eid, messaging_channel_address);
        deployments.set_deployment<ComposeQueue>(eid, compose_queue_address);

        test_scenario::return_shared<Counter>(counter);
        test_scenario::return_shared<EndpointV2>(endpoint);
        test_scenario::return_shared<OApp>(oapp);
        scenario.return_to_sender<CounterAdminCap>(counter_admin_cap);
    });
}

/// Configure peer connections between counters
fun configure_counter_peers(scenario: &mut Scenario, sender: address, eids: vector<u32>, deployments: &Deployments) {
    eids.do!(|eid| {
        configure_single_counter_peers(scenario, sender, eid, eids, deployments);
    });
}

/// Configure peer connections for a single counter with other counters
fun configure_single_counter_peers(
    scenario: &mut Scenario,
    sender: address,
    eid: u32,
    eids: vector<u32>,
    deployments: &Deployments,
) {
    scenario.next_tx(sender);
    let mut messaging_channel = scenario_utils::take_shared_by_address<MessagingChannel>(
        scenario,
        deployments.get_deployment<MessagingChannel>(eid),
    );
    let counter = scenario_utils::take_shared_by_address<Counter>(
        scenario,
        deployments.get_deployment<Counter>(eid),
    );
    let counter_admin_cap = scenario_utils::take_from_sender_by_address<CounterAdminCap>(
        scenario,
        deployments.get_deployment<CounterAdminCap>(eid),
    );

    let mut oapp = scenario_utils::take_shared_by_address<OApp>(
        scenario,
        deployments.get_deployment<OApp>(eid),
    );

    eids.do!(|remote_eid| {
        if (eid != remote_eid) {
            setup_peer_connection(
                scenario,
                &mut oapp,
                &counter_admin_cap,
                &mut messaging_channel,
                eid, // current chain's eid
                remote_eid,
                deployments,
            );
        };
    });

    // Clean up resources
    test_scenario::return_shared<MessagingChannel>(messaging_channel);
    test_scenario::return_shared<Counter>(counter);
    test_scenario::return_shared<OApp>(oapp);
    scenario.return_to_sender<CounterAdminCap>(counter_admin_cap);
}

/// Setup a single peer connection
fun setup_peer_connection(
    scenario: &mut Scenario,
    oapp: &mut OApp,
    counter_admin_cap: &CounterAdminCap,
    messaging_channel: &mut MessagingChannel,
    eid: u32, // current chain's eid
    remote_eid: u32,
    deployments: &Deployments,
) {
    let counter_remote = deployments.get_deployment_object<Counter>(scenario, remote_eid);
    let remote_oapp = utils::bytes32::from_address(counter_remote.call_cap_address());

    // Get the endpoint for the current chain (eid)
    let endpoint = deployments.get_deployment_object<EndpointV2>(scenario, eid);

    oapp.set_peer(
        counter_admin_cap,
        &endpoint,
        messaging_channel,
        remote_eid,
        remote_oapp,
        scenario.ctx(),
    );

    test_scenario::return_shared<Counter>(counter_remote);
    test_scenario::return_shared<EndpointV2>(endpoint);
}

/// Execute counter increment operation and return the call for further processing
public fun increment(
    scenario: &mut Scenario,
    sender: address,
    refund_address: address,
    deployments: &Deployments,
    src_eid: u32,
    dst_eid: u32,
    msg_type: u8,
    options: vector<u8>,
    native_fee: Coin<SUI>,
    zro_fee: Option<Coin<ZRO>>,
): Call<EndpointSendParam, MessagingReceipt> {
    scenario.next_tx(sender);
    let mut counter = deployments.get_deployment_object<Counter>(scenario, src_eid);
    let endpoint = deployments.get_deployment_object<EndpointV2>(scenario, src_eid);
    let src_oapp = deployments.get_deployment_object<OApp>(scenario, src_eid);

    // Create send call
    let send_call = counter.increment(
        &src_oapp,
        dst_eid,
        msg_type,
        options,
        native_fee,
        zro_fee,
        refund_address,
        scenario.ctx(),
    );

    // Return objects - the call will be handled by the caller
    test_scenario::return_shared<Counter>(counter);
    test_scenario::return_shared<EndpointV2>(endpoint);
    test_scenario::return_shared<OApp>(src_oapp);

    send_call
}

/// Handle LayerZero message receive
public fun lz_receive(
    scenario: &mut Scenario,
    sender: address,
    deployments: &Deployments,
    dst_eid: u32,
    encoded_packet: vector<u8>,
    value: Coin<SUI>,
) {
    scenario.next_tx(sender);
    let mut dst_counter = deployments.get_deployment_object<Counter>(scenario, dst_eid);
    let dst_endpoint = deployments.get_deployment_object<EndpointV2>(scenario, dst_eid);
    let mut messaging_composer = deployments.get_deployment_object<ComposeQueue>(scenario, dst_eid);
    let mut messaging_channel = deployments.get_deployment_object<MessagingChannel>(scenario, dst_eid);
    let dst_oapp = deployments.get_deployment_object<OApp>(scenario, dst_eid);

    // Parse packet to extract all required information
    let (header, guid, message) = decode_packet_for_test(encoded_packet);
    let src_eid = header.src_eid();
    let message_sender = header.sender();
    let nonce = header.nonce();

    // Create a mock executor CallCap
    let executor_cap = call_cap::new_package_cap_for_test(scenario.ctx());

    let receive_call = dst_endpoint.lz_receive(
        &executor_cap,
        &mut messaging_channel,
        src_eid,
        message_sender,
        nonce,
        guid,
        message,
        vector::empty<u8>(),
        option::some(value),
        scenario.ctx(),
    );

    dst_counter.lz_receive(&dst_oapp, &mut messaging_composer, receive_call, scenario.ctx());

    // Clean up resources
    test_scenario::return_shared<Counter>(dst_counter);
    test_scenario::return_shared<EndpointV2>(dst_endpoint);
    test_scenario::return_shared<ComposeQueue>(messaging_composer);
    test_scenario::return_shared<MessagingChannel>(messaging_channel);
    test_scenario::return_shared<OApp>(dst_oapp);
    test_utils::destroy(executor_cap);
}

public fun lz_receive_aba(
    scenario: &mut Scenario,
    sender: address,
    deployments: &Deployments,
    dst_eid: u32,
    encoded_packet: vector<u8>,
    value: Coin<SUI>,
): Call<EndpointSendParam, MessagingReceipt> {
    scenario.next_tx(sender);
    let mut dst_counter = deployments.get_deployment_object<Counter>(scenario, dst_eid);
    let dst_endpoint = deployments.get_deployment_object<EndpointV2>(scenario, dst_eid);
    let mut messaging_channel = deployments.get_deployment_object<MessagingChannel>(scenario, dst_eid);
    let dst_oapp = deployments.get_deployment_object<OApp>(scenario, dst_eid);

    // Parse packet to extract all required information
    let (header, guid, message) = decode_packet_for_test(encoded_packet);
    let src_eid = header.src_eid();
    let message_sender = header.sender();
    let nonce = header.nonce();

    // Create a mock executor CallCap
    let executor_cap = call_cap::new_package_cap_for_test(scenario.ctx());

    let receive_call = dst_endpoint.lz_receive(
        &executor_cap,
        &mut messaging_channel,
        src_eid,
        message_sender,
        nonce,
        guid,
        message,
        vector::empty<u8>(),
        option::some(value),
        scenario.ctx(),
    );

    let send_to_src_call = dst_counter.lz_receive_aba(&dst_oapp, receive_call, scenario.ctx());

    // Clean up resources
    test_scenario::return_shared<Counter>(dst_counter);
    test_scenario::return_shared<EndpointV2>(dst_endpoint);
    test_scenario::return_shared<MessagingChannel>(messaging_channel);
    test_scenario::return_shared<OApp>(dst_oapp);
    test_utils::destroy(executor_cap);

    send_to_src_call
}

/// Handle LayerZero compose message
public fun lz_compose(
    scenario: &mut Scenario,
    sender: address,
    deployments: &Deployments,
    dst_eid: u32,
    compose_sent_event: ComposeSentEvent,
    compose_value: Coin<SUI>,
) {
    scenario.next_tx(sender);
    let mut dst_counter = deployments.get_deployment_object<Counter>(scenario, dst_eid);
    let dst_endpoint = deployments.get_deployment_object<EndpointV2>(scenario, dst_eid);
    let mut messaging_composer = deployments.get_deployment_object<ComposeQueue>(scenario, dst_eid);

    // Create a mock executor CallCap
    let executor_cap = call_cap::new_package_cap_for_test(scenario.ctx());

    let compose_call = dst_endpoint.lz_compose(
        &executor_cap,
        &mut messaging_composer,
        compose_sent_event.get_compose_sent_event_from(),
        compose_sent_event.get_compose_sent_event_guid(),
        compose_sent_event.get_compose_sent_event_index(),
        compose_sent_event.get_compose_sent_event_message(),
        vector::empty<u8>(),
        option::some(compose_value),
        scenario.ctx(),
    );
    dst_counter.lz_compose(compose_call, scenario.ctx());

    // Clean up resources
    test_scenario::return_shared<Counter>(dst_counter);
    test_scenario::return_shared<EndpointV2>(dst_endpoint);
    test_scenario::return_shared<ComposeQueue>(messaging_composer);
    test_utils::destroy(executor_cap);
}

/// Handle LayerZero compose message for ABA
public fun lz_compose_aba(
    scenario: &mut Scenario,
    sender: address,
    deployments: &Deployments,
    dst_eid: u32,
    compose_sent_event: ComposeSentEvent,
    compose_value: Coin<SUI>,
): Call<EndpointSendParam, MessagingReceipt> {
    scenario.next_tx(sender);
    let mut dst_counter = deployments.get_deployment_object<Counter>(scenario, dst_eid);
    let dst_endpoint = deployments.get_deployment_object<EndpointV2>(scenario, dst_eid);
    let mut messaging_composer = deployments.get_deployment_object<ComposeQueue>(scenario, dst_eid);
    let dst_oapp = deployments.get_deployment_object<OApp>(scenario, dst_eid);

    // Create a mock executor CallCap
    let executor_cap = call_cap::new_package_cap_for_test(scenario.ctx());

    let compose_call = dst_endpoint.lz_compose(
        &executor_cap,
        &mut messaging_composer,
        compose_sent_event.get_compose_sent_event_from(),
        compose_sent_event.get_compose_sent_event_guid(),
        compose_sent_event.get_compose_sent_event_index(),
        compose_sent_event.get_compose_sent_event_message(),
        vector::empty<u8>(),
        option::some(compose_value),
        scenario.ctx(),
    );
    let send_to_src_call = dst_counter.lz_compose_aba(&dst_oapp, compose_call, scenario.ctx());

    // Clean up resources
    test_scenario::return_shared<Counter>(dst_counter);
    test_scenario::return_shared<EndpointV2>(dst_endpoint);
    test_scenario::return_shared<ComposeQueue>(messaging_composer);
    test_scenario::return_shared<OApp>(dst_oapp);
    test_utils::destroy(executor_cap);

    send_to_src_call
}

fun decode_packet_for_test(encoded: vector<u8>): (PacketHeader, Bytes32, vector<u8>) {
    let mut reader = buffer_reader::create(encoded);
    let header = packet_v1_codec::decode_header(reader.read_fixed_len_bytes(81));
    let guid = reader.read_bytes32();
    let message = reader.read_bytes_until_end();
    (header, guid, message)
}
