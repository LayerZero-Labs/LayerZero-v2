// This module is only used to help with the testing of the OFT contract.
#[test_only]
module oft::oft_test_helper;

use call::{call::Call, call_cap};
use endpoint_v2::{
    endpoint_send::SendParam as EndpointSendParam,
    endpoint_v2::{Self, EndpointV2},
    messaging_channel::MessagingChannel,
    messaging_composer::ComposeQueue,
    messaging_fee::MessagingFee,
    messaging_receipt::MessagingReceipt,
    outbound_packet,
    utils
};
use message_lib_common::packet_v1_codec::{Self, PacketHeader};
use oapp::oapp::{Self as oapp, AdminCap, OApp};
use oft::{
    deployments::Deployments,
    oft::{Self, OFT},
    oft_msg_codec,
    oft_send_context::OFTSendContext,
    oft_sender::{Self, OFTSender},
    send_param::SendParam,
    test_coin::{Self, TEST_COIN}
};
use oft_common::oft_composer_manager::{Self, OFTComposerManager};
use iota::{coin::{Self, Coin, CoinMetadata}, iota::IOTA, test_scenario::{Self, Scenario}, test_utils};
use utils::{buffer_reader, bytes32::{Self, Bytes32}};
use zro::zro::ZRO;

const SHARED_DECIMALS: u8 = 6;

// === Public Functions ===

/// Setup multiple OFT instances, each corresponding to an endpoint
public fun setup_oft(scenario: &mut Scenario, sender: address, eids: vector<u32>, deployments: &mut Deployments) {
    // Create all OFT instances
    create_oft_instances(scenario, sender, eids, deployments);

    // Configure peer connections between OFTs
    configure_oft_peers(scenario, sender, eids, deployments);
}

/// Create OFT instances
fun create_oft_instances(scenario: &mut Scenario, sender: address, eids: vector<u32>, deployments: &mut Deployments) {
    eids.do!(|eid| {
        scenario.next_tx(sender);

        // Create OFTComposerRegistry using the test helper function
        oft_composer_manager::init_for_testing(scenario.ctx());

        scenario.next_tx(sender);
        // Create test coin and share the metadata
        let (treasury_cap, coin_metadata) = test_coin::init_for_testing(scenario.ctx());
        transfer::public_share_object(coin_metadata);

        scenario.next_tx(sender);
        let mut endpoint = deployments.take_shared_object<EndpointV2>(scenario, eid);

        // Create OApp and CallCap for the OFT
        let oft_cap = call_cap::new_package_cap_for_test(scenario.ctx());
        let admin_cap = oapp::create_admin_cap_for_test(scenario.ctx());
        let oapp = oapp::create_oapp_for_test(&oft_cap, &admin_cap, scenario.ctx());

        // Get addresses before moving the objects
        let admin_cap_address = object::id_address(&admin_cap);
        let coin_metadata = scenario.take_shared<CoinMetadata<TEST_COIN>>();
        let coin_metadata_address = object::id_address(&coin_metadata);

        // Create OFT
        let (oft, migration_cap) = oft::init_oft_for_test<TEST_COIN>(
            &oapp,
            oft_cap,
            treasury_cap,
            &coin_metadata,
            SHARED_DECIMALS,
            scenario.ctx(),
        );

        let oft_address = object::id_address(&oft);

        // Register the OFT with the endpoint for proper cross-chain messaging
        oft::register_oapp_for_test(
            &oft,
            &mut endpoint,
            b"oft_lz_receive",
            scenario.ctx(),
        );

        // Register the OFT as a composer using its call_cap (creates ComposeQueue for lz_receive)
        endpoint.register_composer(
            oft.cap_for_test(),
            b"oft_lz_compose_info", // mock compose info
            scenario.ctx(),
        );

        // Get the MessagingChannel and ComposeQueue addresses
        let oapp_call_cap_address = oft.oft_cap_id();
        let messaging_channel_address = endpoint.get_messaging_channel(oapp_call_cap_address);
        let compose_queue_address = endpoint.get_compose_queue(oapp_call_cap_address);

        // Get the composer registry from shared objects (it should be created before setup_oft)
        let mut composer_registry = scenario.take_shared<OFTComposerManager>();
        composer_registry.set_deposit_address(oft.cap_for_test(), object::id_address(&oft));

        // Share the oft object
        oft::share_oft_for_test(oft);

        let composer_registry_address = object::id_address(&composer_registry);
        test_scenario::return_shared<OFTComposerManager>(composer_registry);

        deployments.set_deployment<OApp>(eid, object::id_address(&oapp));
        deployments.set_deployment<OFT<TEST_COIN>>(eid, oft_address);
        deployments.set_deployment<AdminCap>(eid, admin_cap_address);
        deployments.set_deployment<MessagingChannel>(eid, messaging_channel_address);
        deployments.set_deployment<ComposeQueue>(eid, compose_queue_address);
        deployments.set_deployment<CoinMetadata<TEST_COIN>>(eid, coin_metadata_address);
        deployments.set_deployment<OFTComposerManager>(eid, composer_registry_address);

        test_scenario::return_shared<EndpointV2>(endpoint);
        // CoinMetadata is created as a shared object by the coin::create_currency function
        test_scenario::return_shared<CoinMetadata<TEST_COIN>>(coin_metadata);
        oapp::share_oapp_for_test(oapp);
        transfer::public_transfer(admin_cap, sender);
        transfer::public_transfer(migration_cap, sender);
    });
}

/// Configure peer connections between OFTs
fun configure_oft_peers(scenario: &mut Scenario, sender: address, eids: vector<u32>, deployments: &Deployments) {
    eids.do!(|eid| {
        configure_single_oft_peers(scenario, sender, eid, eids, deployments);
    });
}

/// Configure peer connections for a single OFT with other OFTs
fun configure_single_oft_peers(
    scenario: &mut Scenario,
    sender: address,
    eid: u32,
    eids: vector<u32>,
    deployments: &Deployments,
) {
    scenario.next_tx(sender);
    let mut messaging_channel = deployments.take_shared_object<MessagingChannel>(scenario, eid);
    let admin_cap = deployments.take_owned_object<AdminCap>(scenario, eid);
    let mut oapp = deployments.take_shared_object<OApp>(scenario, eid);

    eids.do!(|remote_eid| {
        if (eid != remote_eid) {
            setup_peer_connection(
                scenario,
                &mut oapp,
                &admin_cap,
                &mut messaging_channel,
                eid,
                remote_eid,
                deployments,
            );
        };
    });

    // Clean up resources
    test_scenario::return_shared<MessagingChannel>(messaging_channel);
    test_scenario::return_shared<OApp>(oapp);
    scenario.return_to_sender<AdminCap>(admin_cap);
}

/// Setup a single peer connection
fun setup_peer_connection(
    scenario: &mut Scenario,
    oapp: &mut OApp,
    admin_cap: &AdminCap,
    messaging_channel: &mut MessagingChannel,
    src_eid: u32,
    dst_eid: u32,
    deployments: &Deployments,
) {
    // Get the remote OFT to obtain its call cap address
    let remote_oft = deployments.take_shared_object<OFT<TEST_COIN>>(scenario, dst_eid);
    let endpoint = deployments.take_shared_object<EndpointV2>(scenario, src_eid);

    oapp.set_peer(
        admin_cap,
        &endpoint,
        messaging_channel,
        dst_eid,
        bytes32::from_address(remote_oft.oft_cap_id()),
        scenario.ctx(),
    );

    test_scenario::return_shared<OFT<TEST_COIN>>(remote_oft);
    test_scenario::return_shared<EndpointV2>(endpoint);
}

public fun quote_send(
    scenario: &mut Scenario,
    to: address,
    deployments: &Deployments,
    src_eid: u32,
    dst_eid: u32,
    amount_ld: u64,
    pay_in_zro: bool,
    compose_msg: vector<u8>,
): MessagingFee {
    let oapp = deployments.take_shared_object<OApp>(scenario, src_eid);
    let oft = deployments.take_shared_object<OFT<TEST_COIN>>(scenario, src_eid);
    let endpoint = deployments.take_shared_object<EndpointV2>(scenario, src_eid);
    let messaging_channel = deployments.take_shared_object<MessagingChannel>(scenario, src_eid);
    let admin_cap = deployments.take_owned_object<AdminCap>(scenario, src_eid);

    // Create send param
    let send_param = create_send_param(dst_eid, to, amount_ld, compose_msg);

    let clock = iota::clock::create_for_testing(scenario.ctx());
    let mut quote_call = oft.quote_send(&oapp, scenario.sender(), &send_param, pay_in_zro, scenario.ctx());
    iota::clock::destroy_for_testing(clock);
    let message_lib_call = endpoint.quote(&messaging_channel, &mut quote_call, scenario.ctx());
    endpoint.confirm_quote(&mut quote_call, message_lib_call);

    // Destroy the quote call before returning the oft to avoid borrowing issues
    let (_, _, result) = quote_call.destroy(oft.cap_for_test());

    test_scenario::return_shared<OApp>(oapp);
    test_scenario::return_shared<OFT<TEST_COIN>>(oft);
    test_scenario::return_shared<EndpointV2>(endpoint);
    test_scenario::return_shared<MessagingChannel>(messaging_channel);
    scenario.return_to_sender<AdminCap>(admin_cap);

    result
}

/// Execute OFT send operation and return the call for further processing
public fun send(
    scenario: &mut Scenario,
    sender: address,
    to: address,
    refund_address: address,
    deployments: &Deployments,
    src_eid: u32,
    dst_eid: u32,
    amount_ld: u64,
    native_fee: Coin<IOTA>,
    zro_fee: Option<Coin<ZRO>>,
    compose_msg: vector<u8>,
    with_compose: bool,
): (OFTSender, Call<EndpointSendParam, MessagingReceipt>, OFTSendContext) {
    scenario.next_tx(sender);
    let mut oapp = deployments.take_shared_object<OApp>(scenario, src_eid);
    let mut oft = deployments.take_shared_object<OFT<TEST_COIN>>(scenario, src_eid);
    let endpoint = deployments.take_shared_object<EndpointV2>(scenario, src_eid);
    let messaging_channel = deployments.take_shared_object<MessagingChannel>(scenario, src_eid);
    let admin_cap = deployments.take_owned_object<AdminCap>(scenario, src_eid);

    // Mint coins for testing
    let mut coin_provided = oft.mint_for_testing(amount_ld, scenario.ctx());

    // Create send param
    let send_param = create_send_param(dst_eid, to, amount_ld, compose_msg);

    let clock = iota::clock::create_for_testing(scenario.ctx());
    let composer_callcap = call_cap::new_individual_cap(scenario.ctx());
    let oft_sender = if (with_compose) {
        oft_sender::call_cap_sender(&composer_callcap)
    } else {
        oft_sender::tx_sender(scenario.ctx())
    };
    let (send_call, oft_send_context) = oft.send(
        &mut oapp,
        &oft_sender,
        &send_param,
        &mut coin_provided,
        native_fee,
        zro_fee,
        option::some(refund_address),
        &clock,
        scenario.ctx(),
    );

    // Return objects - the call will be handled by the caller
    test_scenario::return_shared<OApp>(oapp);
    test_scenario::return_shared<OFT<TEST_COIN>>(oft);
    test_scenario::return_shared<EndpointV2>(endpoint);
    test_scenario::return_shared<MessagingChannel>(messaging_channel);
    scenario.return_to_sender<AdminCap>(admin_cap);
    utils::transfer_coin(coin_provided, sender); // return excessive coin back to sender
    test_utils::destroy(composer_callcap);
    test_utils::destroy(clock);
    (oft_sender, send_call, oft_send_context)
}

/// Handle LayerZero message receive for OFT
public fun lz_receive(
    scenario: &mut Scenario,
    sender: address,
    deployments: &Deployments,
    dst_eid: u32,
    encoded_packet: vector<u8>,
    value: Coin<IOTA>,
    with_compose: bool,
) {
    scenario.next_tx(sender);
    let dst_oapp = deployments.take_shared_object<OApp>(scenario, dst_eid);
    let mut dst_oft = deployments.take_shared_object<OFT<TEST_COIN>>(scenario, dst_eid);
    let dst_endpoint = deployments.take_shared_object<EndpointV2>(scenario, dst_eid);
    let mut compose_queue = deployments.take_shared_object<ComposeQueue>(scenario, dst_eid);
    let mut messaging_channel = deployments.take_shared_object<MessagingChannel>(scenario, dst_eid);

    // Get composer registry if needed for compose operations
    let mut composer_registry_opt = if (with_compose) {
        option::some(deployments.take_shared_object<OFTComposerManager>(scenario, dst_eid))
    } else {
        option::none()
    };

    // Parse packet to extract all required information
    let (header, guid, message) = decode_packet_for_test(encoded_packet);
    let src_eid = header.src_eid();
    let message_sender = header.sender();
    let nonce = header.nonce();

    // Create a mock executor CallCap
    let executor_cap = call_cap::new_individual_cap(scenario.ctx());

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

    let clock = iota::clock::create_for_testing(scenario.ctx());

    if (with_compose) {
        let mut composer_registry = option::extract(&mut composer_registry_opt);
        dst_oft.lz_receive_with_compose(
            &dst_oapp,
            &mut compose_queue,
            &mut composer_registry,
            receive_call,
            &clock,
            scenario.ctx(),
        );
        option::fill(&mut composer_registry_opt, composer_registry);
    } else {
        dst_oft.lz_receive(&dst_oapp, receive_call, &clock, scenario.ctx());
    };

    // Clean up resources
    test_scenario::return_shared<OApp>(dst_oapp);
    test_scenario::return_shared<OFT<TEST_COIN>>(dst_oft);
    test_scenario::return_shared<EndpointV2>(dst_endpoint);
    test_scenario::return_shared<ComposeQueue>(compose_queue);
    test_scenario::return_shared<MessagingChannel>(messaging_channel);

    // Return composer registry if it was used
    if (option::is_some(&composer_registry_opt)) {
        let composer_registry = option::extract(&mut composer_registry_opt);
        test_scenario::return_shared<OFTComposerManager>(composer_registry);
    };
    option::destroy_none(composer_registry_opt);

    test_utils::destroy(clock);
    test_utils::destroy(executor_cap);
}

public fun create_inbound_packet(
    scenario: &mut Scenario,
    deployments: &Deployments,
    sender: address,
    src_eid: u32,
    dst_eid: u32,
    amount_ld: u64,
    compose_msg: vector<u8>,
): vector<u8> {
    // Advance to the next transaction to ensure shared objects are available
    scenario.next_tx(sender);
    let src_endpoint = deployments.take_shared_object<EndpointV2>(scenario, src_eid);
    let src_oft = deployments.take_shared_object<OFT<TEST_COIN>>(scenario, src_eid);
    let dst_messaging_channel = deployments.take_shared_object<MessagingChannel>(scenario, dst_eid);
    let dst_oft = deployments.take_shared_object<OFT<TEST_COIN>>(scenario, dst_eid);

    let nonce =
        endpoint_v2::get_inbound_nonce(&dst_messaging_channel, src_eid, bytes32::from_address(src_oft.oft_cap_id())) + 1;
    let send_param = create_send_param(dst_eid, sender, amount_ld, compose_msg);
    let compose_from = if (compose_msg.is_empty()) {
        option::none()
    } else {
        option::some(bytes32::from_address(sender))
    };
    let compose_msg_opt = if (compose_msg.is_empty()) {
        option::none()
    } else {
        option::some(compose_msg)
    };
    let message = oft_msg_codec::encode(
        send_param.to(),
        src_oft.to_sd_for_test(amount_ld),
        compose_from,
        compose_msg_opt,
    );
    let packet = outbound_packet::create_for_test(
        nonce,
        src_eid,
        src_oft.oft_cap_id(),
        dst_eid,
        bytes32::from_address(dst_oft.oft_cap_id()),
        message,
    );
    let encoded = packet_v1_codec::encode_packet(&packet);

    test_scenario::return_shared<OFT<TEST_COIN>>(src_oft);
    test_scenario::return_shared<EndpointV2>(src_endpoint);
    test_scenario::return_shared<MessagingChannel>(dst_messaging_channel);
    test_scenario::return_shared<OFT<TEST_COIN>>(dst_oft);

    encoded
}

fun decode_packet_for_test(encoded: vector<u8>): (PacketHeader, Bytes32, vector<u8>) {
    let mut reader = buffer_reader::create(encoded);
    let header = packet_v1_codec::decode_header(reader.read_fixed_len_bytes(81));
    let guid = reader.read_bytes32();
    let message = reader.read_bytes_until_end();
    (header, guid, message)
}

/// Helper function to mint test coins
public fun mint_test_coin(amount: u64, ctx: &mut TxContext): Coin<TEST_COIN> {
    // Since mint transfers to sender, we need to get the coin from balance
    // For simplicity in testing, use mint_for_testing
    coin::mint_for_testing<TEST_COIN>(amount, ctx)
}

/// Helper function to create send param
public fun create_send_param(dst_eid: u32, to: address, amount_ld: u64, compose_msg: vector<u8>): SendParam {
    use oft::send_param;
    send_param::create(
        dst_eid,
        bytes32::from_address(to),
        amount_ld,
        ((amount_ld as u256) * 99 / 100) as u64, // min_amount_ld with 1% slippage
        vector::empty<u8>(), // extra_options
        compose_msg,
        vector::empty<u8>(), // oft_cmd
    )
}

/// Get OFT balance for an address
public fun get_oft_balance(
    scenario: &mut Scenario,
    sender: address,
    _deployments: &Deployments,
    _eid: u32,
    _user: address,
): u64 {
    scenario.next_tx(sender);
    // This would require accessing user's coin balance
    // For simplicity in tests, we'll track this via events or state
    0 // Placeholder - in real tests you'd check the user's coin balance
}
