#[test_only]
module endpoint_v2::messaging_channel_tests;

use endpoint_v2::{
    endpoint_quote,
    endpoint_send,
    message_lib_send,
    messaging_channel::{
        Self,
        MessagingChannel,
        ChannelInitializedEvent,
        PacketVerifiedEvent,
        InboundNonceSkippedEvent,
        PacketNilifiedEvent,
        PacketBurntEvent,
        PacketDeliveredEvent,
        PacketSentEvent
    },
    messaging_fee,
    utils
};
use iota::{coin, event, test_scenario::{Self as ts, Scenario}, test_utils};
use utils::{bytes32::{Self, Bytes32}, hash};
use zro::zro;

// Test constants
const REMOTE_OAPP: address = @0x123;
const LOCAL_OAPP: address = @0x456;

const REMOTE_EID: u32 = 2;
const LOCAL_EID: u32 = 1;

// === Helper functions ===

// Helper function to setup test scenario and messaging channel
fun setup(): (Scenario, MessagingChannel) {
    let mut scenario = ts::begin(@0x0);
    let messaging_channel_address = messaging_channel::create(LOCAL_OAPP, scenario.ctx());
    scenario.next_tx(@0x0);
    let messaging_channel = scenario.take_shared_by_id<MessagingChannel>(
        object::id_from_address(messaging_channel_address),
    );
    (scenario, messaging_channel)
}

// Helper function to clean up test scenario and channel
fun clean(scenario: Scenario, messaging_channel: MessagingChannel) {
    test_utils::destroy(messaging_channel);
    ts::end(scenario);
}

// Helper function to create bytes32 from address
fun to_bytes32(addr: address): Bytes32 {
    bytes32::from_address(addr)
}

// Helper function to create test payload hash
fun create_payload_hash(message: vector<u8>): Bytes32 {
    hash::keccak256!(&message)
}

// === Tests ===

#[test]
fun test_inbound_nonce() {
    let (mut scenario, mut messaging_channel) = setup();

    let message = b"test message";
    let payload_hash = create_payload_hash(message);

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Initial inbound nonce should be 0
    let inbound_nonce = messaging_channel.inbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP));
    assert!(inbound_nonce == 0, 0);

    // Inbound nonce 1
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);
    let inbound_nonce = messaging_channel.inbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP));
    assert!(inbound_nonce == 1, 1);

    // Inbound nonce 5, but inbound nonce should still be 1
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 5, payload_hash);
    let inbound_nonce = messaging_channel.inbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP));
    assert!(inbound_nonce == 1, 2);

    // Inbound nonce 3, but inbound nonce should still be 1
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 3, payload_hash);
    let inbound_nonce = messaging_channel.inbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP));
    assert!(inbound_nonce == 1, 3);

    // After inbound nonce 2, inbound nonce should be 3
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 2, payload_hash);
    let inbound_nonce = messaging_channel.inbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP));
    assert!(inbound_nonce == 3, 4);

    // After inbound nonce 4, inbound nonce should be 5
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 4, payload_hash);
    let inbound_nonce = messaging_channel.inbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP));
    assert!(inbound_nonce == 5, 5);

    clean(scenario, messaging_channel);
}

#[test]
fun test_skip() {
    let (mut scenario, mut messaging_channel) = setup();

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Skip nonce 1, lazy inbound nonce should become 1
    messaging_channel.skip(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1);
    let lazy_nonce = messaging_channel.lazy_inbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP));
    assert!(lazy_nonce == 1, 0);
    let skip_event = messaging_channel::create_inbound_nonce_skipped_event(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        LOCAL_OAPP,
        1,
    );
    test_utils::assert_eq(event::events_by_type<InboundNonceSkippedEvent>()[0], skip_event);

    clean(scenario, messaging_channel);
}

#[test, expected_failure(abort_code = messaging_channel::EInvalidNonce)]
fun test_skip_invalid_nonce() {
    let (mut scenario, mut messaging_channel) = setup();

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Try to skip invalid nonce (should be current + 1, but trying current + 2)
    let current_inbound_nonce = messaging_channel.inbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP));
    messaging_channel.skip(REMOTE_EID, to_bytes32(REMOTE_OAPP), current_inbound_nonce + 2);

    // Clean up (won't reach here due to expected failure)
    clean(scenario, messaging_channel);
}

#[test]
fun test_nilify() {
    let (mut scenario, mut messaging_channel) = setup();

    let message = b"test message";
    let payload_hash = create_payload_hash(message);

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Nilify an unverified nonce should succeed
    messaging_channel.nilify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, bytes32::zero_bytes32());

    let expected_event1 = messaging_channel::create_packet_nilified_event(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        LOCAL_OAPP,
        1,
        bytes32::zero_bytes32(),
    );
    test_utils::assert_eq(event::events_by_type<PacketNilifiedEvent>()[0], expected_event1);

    // Nilify a verified but non-executed nonce should succeed
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);
    messaging_channel.nilify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);
    let stored_hash = messaging_channel.get_payload_hash(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1);
    assert!(stored_hash == bytes32::ff_bytes32(), 0);

    let expected_event2 = messaging_channel::create_packet_nilified_event(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        LOCAL_OAPP,
        1,
        payload_hash,
    );
    test_utils::assert_eq(event::events_by_type<PacketNilifiedEvent>()[1], expected_event2);

    // Nilify a non-executed nonce lower than lazyInboundNonce should succeed
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 2, payload_hash);
    messaging_channel.clear_payload(REMOTE_EID, to_bytes32(REMOTE_OAPP), 2, message);
    let lazy_nonce = messaging_channel.lazy_inbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP));
    assert!(lazy_nonce == 2, 1);

    let payload_hash = messaging_channel.get_payload_hash(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1);
    messaging_channel.nilify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);
    let stored_hash = messaging_channel.get_payload_hash(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1);
    assert!(stored_hash == bytes32::ff_bytes32(), 2);

    let lazy_nonce = messaging_channel.lazy_inbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP));
    assert!(lazy_nonce == 2, 3);

    let expected_event3 = messaging_channel::create_packet_nilified_event(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        LOCAL_OAPP,
        1,
        payload_hash,
    );
    test_utils::assert_eq(event::events_by_type<PacketNilifiedEvent>()[2], expected_event3);

    // Nilify should work on any nonce greater than lazy inbound nonce
    let max_nonce = std::u64::max_value!();
    messaging_channel.nilify(REMOTE_EID, to_bytes32(REMOTE_OAPP), max_nonce, bytes32::zero_bytes32());

    let expected_event4 = messaging_channel::create_packet_nilified_event(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        LOCAL_OAPP,
        max_nonce,
        bytes32::zero_bytes32(),
    );
    test_utils::assert_eq(event::events_by_type<PacketNilifiedEvent>()[3], expected_event4);

    clean(scenario, messaging_channel);
}

#[test, expected_failure(abort_code = messaging_channel::EPayloadHashNotFound)]
fun test_nilify_wrong_payload_hash() {
    let (mut scenario, mut messaging_channel) = setup();

    let message = b"test message";
    let payload_hash = create_payload_hash(message);
    let wrong_payload_hash = create_payload_hash(b"wrong message");

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Verify a packet
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);

    // Try to nilify with wrong payload hash - should fail
    messaging_channel.nilify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, wrong_payload_hash);

    // Clean up (won't reach here due to expected failure)
    clean(scenario, messaging_channel);
}

#[test, expected_failure(abort_code = messaging_channel::EPayloadHashNotFound)]
fun test_nilify_invalid_nonce() {
    let (mut scenario, mut messaging_channel) = setup();

    let message = b"test message";
    let payload_hash = create_payload_hash(message);

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Nilify an executed nonce should revert with InvalidNonce
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);
    messaging_channel.clear_payload(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, message);
    messaging_channel.nilify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);

    clean(scenario, messaging_channel);
}

#[test]
fun test_burn() {
    /*
        1        | 2        |
        verified | executed |
                 | lazyNonce|
        */
    let (mut scenario, mut messaging_channel) = setup();

    let message = b"test message";
    let payload_hash = create_payload_hash(message);

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Inbound nonces 1, 2
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 2, payload_hash);

    // Clear nonces 2 and 3 (this will set lazy_inbound_nonce to 3)
    messaging_channel.clear_payload(REMOTE_EID, to_bytes32(REMOTE_OAPP), 2, message);
    let lazy_nonce = messaging_channel.lazy_inbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP));
    assert!(lazy_nonce == 2, 0);

    // Burn a verified but non-executed nonce should succeed
    messaging_channel.burn(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);
    let expected_burnt_event = messaging_channel::create_packet_burnt_event(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        LOCAL_OAPP,
        1,
        payload_hash,
    );
    test_utils::assert_eq(event::events_by_type<PacketBurntEvent>()[0], expected_burnt_event);

    // Check that payload hash is removed
    assert!(!messaging_channel.has_payload_hash(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1), 1);

    clean(scenario, messaging_channel);
}

#[test, expected_failure(abort_code = messaging_channel::EInvalidNonce)]
fun test_burn_invalid_nonce() {
    /*
        1        | 2        | 3         |
        executed | executed | verified  |
                 | lazyNonce|           |
        */
    let (mut scenario, mut messaging_channel) = setup();

    let message = b"test message";
    let payload_hash = create_payload_hash(message);

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Inbound and clear some nonces to set lazy_inbound_nonce
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 2, payload_hash);
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 3, payload_hash);
    messaging_channel.clear_payload(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, message);
    messaging_channel.clear_payload(REMOTE_EID, to_bytes32(REMOTE_OAPP), 2, message);

    let lazy_nonce = messaging_channel.lazy_inbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP));

    // Burn should revert with InvalidNonce if the requested nonce is greater than lazyInboundNonce
    messaging_channel.burn(REMOTE_EID, to_bytes32(REMOTE_OAPP), lazy_nonce + 1, payload_hash);

    // Clean up (won't reach here due to expected failure)
    clean(scenario, messaging_channel);
}

#[test, expected_failure(abort_code = messaging_channel::EInvalidNonce)]
fun test_burn_invalid_nonce2() {
    /*
        1        | 2        | 3         |
        executed | executed | verified  |
                 | lazyNonce|           |
        */
    let (mut scenario, mut messaging_channel) = setup();

    let message = b"test message";
    let payload_hash = create_payload_hash(message);

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Inbound and clear some nonces to set lazy_inbound_nonce
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 2, payload_hash);
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 3, payload_hash);
    messaging_channel.clear_payload(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, message);
    messaging_channel.clear_payload(REMOTE_EID, to_bytes32(REMOTE_OAPP), 2, message);

    let lazy_nonce = messaging_channel.lazy_inbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP));

    // Burn should revert with InvalidNonce if the payload hash of the requested nonce is 0x0
    messaging_channel.burn(REMOTE_EID, to_bytes32(REMOTE_OAPP), lazy_nonce - 1, bytes32::zero_bytes32());

    // Clean up (won't reach here due to expected failure)
    clean(scenario, messaging_channel);
}

#[test, expected_failure(abort_code = messaging_channel::EPayloadHashNotFound)]
fun test_burn_wrong_payload_hash() {
    /*
        1        | 2        |
        verified | executed |
                 | lazyNonce|
        */
    let (mut scenario, mut messaging_channel) = setup();

    let message = b"test message";
    let payload_hash = create_payload_hash(message);
    let wrong_payload_hash = create_payload_hash(b"wrong message");

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Inbound a packet
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 2, payload_hash);
    messaging_channel.clear_payload(REMOTE_EID, to_bytes32(REMOTE_OAPP), 2, message);

    // Burn should revert with PayloadHashNotFound if the provided payload hash does not match the contents of
    // inboundPayloadHash
    messaging_channel.burn(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, wrong_payload_hash);

    // Clean up (won't reach here due to expected failure)
    clean(scenario, messaging_channel);
}

#[test]
fun test_clear() {
    let (mut scenario, mut messaging_channel) = setup();

    let message = b"test message";
    let payload_hash = create_payload_hash(message);

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Verify nonces 1, 2, 4
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 2, payload_hash);
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 4, payload_hash);

    // Clear nonce 2 successfully
    messaging_channel.clear_payload(REMOTE_EID, to_bytes32(REMOTE_OAPP), 2, message);
    let expected_event1 = messaging_channel::create_packet_delivered_event(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        2,
        LOCAL_OAPP,
    );
    test_utils::assert_eq(event::events_by_type<PacketDeliveredEvent>()[0], expected_event1);

    // Verify nonce 3
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 3, payload_hash);

    // Clear nonce 4 successfully
    messaging_channel.clear_payload(REMOTE_EID, to_bytes32(REMOTE_OAPP), 4, message);
    let expected_event2 = messaging_channel::create_packet_delivered_event(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        4,
        LOCAL_OAPP,
    );
    test_utils::assert_eq(event::events_by_type<PacketDeliveredEvent>()[1], expected_event2);

    // Check that payload hashes are removed
    assert!(!messaging_channel.has_payload_hash(REMOTE_EID, to_bytes32(REMOTE_OAPP), 2), 0);
    assert!(!messaging_channel.has_payload_hash(REMOTE_EID, to_bytes32(REMOTE_OAPP), 4), 1);

    clean(scenario, messaging_channel);
}

#[test, expected_failure(abort_code = messaging_channel::EInvalidNonce)]
fun test_clear_invalid_nonce() {
    let (mut scenario, mut messaging_channel) = setup();

    let message = b"test message";
    let payload_hash = create_payload_hash(message);

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Verify nonces 1, 2, 4 (skip 3)
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 2, payload_hash);
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 4, payload_hash);

    // Try to clear nonce 4 but should fail due to nonce 3 not being verified
    messaging_channel.clear_payload(REMOTE_EID, to_bytes32(REMOTE_OAPP), 4, message);

    // Clean up (won't reach here due to expected failure)
    clean(scenario, messaging_channel);
}

#[test, expected_failure(abort_code = messaging_channel::EPayloadHashNotFound)]
fun test_clear_invalid_payload() {
    let (mut scenario, mut messaging_channel) = setup();

    let message = b"test message";
    let wrong_message = b"wrong message";
    let payload_hash = create_payload_hash(message);

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Verify nonce 1
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);

    // Try to clear with wrong message - should fail
    messaging_channel.clear_payload(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, wrong_message);

    // Clean up (won't reach here due to expected failure)
    clean(scenario, messaging_channel);
}

#[test, expected_failure(abort_code = messaging_channel::EPayloadHashNotFound)]
fun test_clear_twice() {
    let (mut scenario, mut messaging_channel) = setup();

    let message = b"test message";
    let payload_hash = create_payload_hash(message);

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Verify nonce 1
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);

    // Clear successfully
    messaging_channel.clear_payload(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, message);

    // Trying to clear the same payload again should fail
    messaging_channel.clear_payload(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, message);

    // Clean up (won't reach here due to expected failure)
    clean(scenario, messaging_channel);
}

#[test]
fun test_next_guid() {
    let (mut scenario, mut messaging_channel) = setup();

    // Init channel
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Calculate expected GUID for nonce 1 (outbound_nonce + 1)
    let expected_guid = utils::compute_guid(
        1,
        LOCAL_EID,
        to_bytes32(LOCAL_OAPP),
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
    );

    let actual_guid = messaging_channel::next_guid(
        &messaging_channel,
        LOCAL_EID,
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
    );
    assert!(actual_guid == expected_guid, 0);

    clean(scenario, messaging_channel);
}

#[test, expected_failure(abort_code = messaging_channel::EAlreadyInitialized)]
fun test_channel_initialization() {
    let (mut scenario, mut messaging_channel) = setup();

    // Initially not registered
    assert!(!messaging_channel.is_channel_inited(REMOTE_EID, to_bytes32(REMOTE_OAPP)), 0);

    // Register channel
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    let expected_event = messaging_channel::create_channel_initialized_event(
        LOCAL_OAPP,
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
    );
    test_utils::assert_eq(event::events_by_type<ChannelInitializedEvent>()[0], expected_event);

    // Now should be registered
    assert!(messaging_channel.is_channel_inited(REMOTE_EID, to_bytes32(REMOTE_OAPP)), 1);

    // Get channel reference and check initial values
    assert!(messaging_channel.outbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP)) == 0, 2);
    assert!(messaging_channel.lazy_inbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP)) == 0, 3);
    assert!(messaging_channel.inbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP)) == 0, 4);

    // Registering again should fail
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    clean(scenario, messaging_channel);
}

#[test]
fun test_verify() {
    let (mut scenario, mut messaging_channel) = setup();

    let message = b"test message";
    let payload_hash = create_payload_hash(message);

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Verify packet
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);

    // Check that payload hash is stored
    assert!(messaging_channel.has_payload_hash(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1), 0);
    let stored_hash = messaging_channel.get_payload_hash(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1);
    assert!(stored_hash == payload_hash, 1);

    // Verify PacketVerifiedEvent was emitted
    let expected_event = messaging_channel::create_packet_verified_event(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        1,
        LOCAL_OAPP,
        payload_hash,
    );
    test_utils::assert_eq(event::events_by_type<PacketVerifiedEvent>()[0], expected_event);

    clean(scenario, messaging_channel);
}

#[test, expected_failure(abort_code = messaging_channel::EUninitializedChannel)]
fun test_verify_unregistered_channel() {
    let (scenario, mut messaging_channel) = setup();

    let message = b"test message";
    let payload_hash = create_payload_hash(message);

    // Don't register channel - should fail with EUnregisteredChannel
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);

    // Clean up (won't reach here due to expected failure)
    clean(scenario, messaging_channel);
}

#[test, expected_failure(abort_code = messaging_channel::EPathNotVerifiable)]
fun test_verify_not_verifiable() {
    let (mut scenario, mut messaging_channel) = setup();

    let message = b"test message";
    let payload_hash = create_payload_hash(message);

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Verify and clear a packet to advance lazy_inbound_nonce
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);
    messaging_channel.clear_payload(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, message);

    // Now lazy_inbound_nonce is 1, trying to verify nonce 1 again should fail
    // because nonce <= lazy_inbound_nonce and no payload hash exists
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);

    // Clean up (won't reach here due to expected failure)
    clean(scenario, messaging_channel);
}

#[test, expected_failure(abort_code = messaging_channel::EInvalidPayloadHash)]
fun test_verify_invalid_payload_hash() {
    let (mut scenario, mut messaging_channel) = setup();

    let payload_hash = bytes32::zero_bytes32(); // Invalid empty payload hash

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Should revert with EInvalidPayloadHash due to empty payload hash
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);

    // Clean up (won't reach here due to expected failure)
    clean(scenario, messaging_channel);
}

#[test]
fun test_verify_overwrite_existing() {
    let (mut scenario, mut messaging_channel) = setup();

    let message1 = b"first message";
    let message2 = b"second message";
    let payload_hash1 = create_payload_hash(message1);
    let payload_hash2 = create_payload_hash(message2);

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Verify first packet
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash1);
    let stored_hash = messaging_channel.get_payload_hash(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1);
    assert!(stored_hash == payload_hash1, 0);

    // Verify same nonce with different payload hash (should overwrite)
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash2);
    let stored_hash = messaging_channel.get_payload_hash(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1);
    assert!(stored_hash == payload_hash2, 1);

    // Verify two PacketVerifiedEvents were emitted
    let events = event::events_by_type<PacketVerifiedEvent>();
    assert!(events.length() == 2, 2);

    // Check first event
    let expected_event1 = messaging_channel::create_packet_verified_event(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        1,
        LOCAL_OAPP,
        payload_hash1,
    );
    test_utils::assert_eq(events[0], expected_event1);

    // Check second event
    let expected_event2 = messaging_channel::create_packet_verified_event(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        1,
        LOCAL_OAPP,
        payload_hash2,
    );
    test_utils::assert_eq(events[1], expected_event2);

    clean(scenario, messaging_channel);
}

#[test]
fun test_new_channel() {
    let (scenario, messaging_channel) = setup();

    // Check initial oapp
    assert!(messaging_channel.oapp() == LOCAL_OAPP, 0);

    clean(scenario, messaging_channel);
}

#[test]
fun test_quote() {
    let (mut scenario, mut messaging_channel) = setup();

    // Initialize channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Create quote parameters
    let message = b"test quote message";
    let options = b"test options";
    let pay_in_zro = false;
    let quote_param = endpoint_quote::create_param(REMOTE_EID, to_bytes32(REMOTE_OAPP), message, options, pay_in_zro);

    // Test quote function
    let quote_result = messaging_channel.quote(LOCAL_EID, &quote_param);

    // Verify the quote result has correct packet info
    let packet = quote_result.packet();
    assert!(packet.src_eid() == LOCAL_EID, 0);
    assert!(packet.dst_eid() == REMOTE_EID, 1);
    assert!(packet.sender() == LOCAL_OAPP, 2);
    assert!(packet.receiver() == to_bytes32(REMOTE_OAPP), 3);
    assert!(packet.nonce() == 1, 4); // First outbound nonce should be 1

    clean(scenario, messaging_channel);
}

#[test]
fun test_prepare_send() {
    let (mut scenario, mut messaging_channel) = setup();

    // Initialize channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Create send parameters
    let message = b"test send message";
    let options = b"test options";
    let native_fee = coin::zero<iota::iota::IOTA>(scenario.ctx());
    let zro_fee = option::none<coin::Coin<zro::ZRO>>();
    let refund_address = option::none<address>();
    let send_param = endpoint_send::create_param(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        message,
        options,
        native_fee,
        zro_fee,
        refund_address,
    );

    // Test prepare_send function
    let prepared_result = messaging_channel.send(LOCAL_EID, &send_param);

    // Verify the prepared result has correct packet info
    let packet = prepared_result.base().packet();
    assert!(packet.src_eid() == LOCAL_EID, 0);
    assert!(packet.dst_eid() == REMOTE_EID, 1);
    assert!(packet.sender() == LOCAL_OAPP, 2);
    assert!(packet.receiver() == to_bytes32(REMOTE_OAPP), 3);
    assert!(packet.nonce() == 1, 4); // First outbound nonce should be 1

    test_utils::destroy(send_param);

    clean(scenario, messaging_channel);
}

#[test]
fun test_confirm_send() {
    let (mut scenario, mut messaging_channel) = setup();

    // Initialize channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Create necessary objects for confirm_send test
    let message = b"test send message";
    let options = b"test options";
    let native_fee_amount = 1000u64;
    let native_fee = coin::mint_for_testing<iota::iota::IOTA>(native_fee_amount, scenario.ctx());
    let zro_fee = option::none<coin::Coin<zro::ZRO>>();
    let refund_address = option::none<address>();
    let mut send_param = endpoint_send::create_param(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        message,
        options,
        native_fee,
        zro_fee,
        refund_address,
    );

    // Call send to properly set the is_sending flag and get message lib parameters
    let message_lib_param = messaging_channel.send(LOCAL_EID, &send_param);

    // Create messaging fee and result
    let fee = messaging_fee::create(500u64, 0u64); // 500 native, 0 ZRO
    let encoded_packet = b"encoded packet data";
    let message_lib_result = message_lib_send::create_result(encoded_packet, fee);

    // Test confirm_send function
    let send_library = @0x123;
    let (receipt, paid_native, paid_zro) = messaging_channel.confirm_send(
        send_library,
        &mut send_param,
        message_lib_param,
        message_lib_result,
        scenario.ctx(),
    );

    // Verify results
    assert!(paid_native.value() == 500, 0); // Should match the fee
    assert!(paid_zro.value() == 0, 1); // No ZRO fee

    // Verify outbound nonce incremented
    assert!(messaging_channel.outbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP)) == 1, 2);

    // Verify PacketSentEvent was emitted
    let events = event::events_by_type<PacketSentEvent>();
    assert!(events.length() == 1, 3);
    let expected_event = messaging_channel::create_packet_sent_event(
        encoded_packet,
        send_library,
        options,
    );
    test_utils::assert_eq(events[0], expected_event);

    // Clean up
    coin::burn_for_testing(paid_native);
    coin::burn_for_testing(paid_zro);
    test_utils::destroy(receipt);
    test_utils::destroy(send_param);

    clean(scenario, messaging_channel);
}

#[test, expected_failure(abort_code = messaging_channel::EUninitializedChannel)]
fun test_channel_uninitialized() {
    let (scenario, messaging_channel) = setup();

    // Try to access uninitialized channel - should fail
    let _ = messaging_channel.outbound_nonce(REMOTE_EID, to_bytes32(REMOTE_OAPP));

    clean(scenario, messaging_channel);
}

#[test]
fun test_verifiable() {
    let (mut scenario, mut messaging_channel) = setup();

    let message = b"test message";
    let payload_hash = create_payload_hash(message);

    // Register channel first
    messaging_channel.init_channel(REMOTE_EID, to_bytes32(REMOTE_OAPP), scenario.ctx());

    // Test verifiable: nonce > lazy_inbound_nonce (should be true)
    assert!(messaging_channel.verifiable(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1), 0);
    assert!(messaging_channel.verifiable(REMOTE_EID, to_bytes32(REMOTE_OAPP), 5), 1);

    // Verify a packet
    messaging_channel.verify(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, payload_hash);

    // Test verifiable: nonce <= lazy_inbound_nonce with existing payload (should be true)
    assert!(messaging_channel.verifiable(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1), 2);

    // Clear the payload to advance lazy_inbound_nonce
    messaging_channel.clear_payload(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1, message);

    // Test verifiable: nonce <= lazy_inbound_nonce without payload (should be false)
    assert!(!messaging_channel.verifiable(REMOTE_EID, to_bytes32(REMOTE_OAPP), 1), 3);

    // Test verifiable: nonce > lazy_inbound_nonce (should still be true)
    assert!(messaging_channel.verifiable(REMOTE_EID, to_bytes32(REMOTE_OAPP), 2), 4);

    clean(scenario, messaging_channel);
}

#[test, expected_failure(abort_code = messaging_channel::EInsufficientNativeFee)]
fun test_split_fee_insufficient_native_fee() {
    let (mut scenario, _messagingChannel) = setup();

    // Create EndpointSendParam with insufficient native fee
    let message = b"test message";
    let options = b"test options";
    let native_fee_amount = 100u64; // Insufficient amount
    let native_fee = coin::mint_for_testing<iota::iota::IOTA>(native_fee_amount, scenario.ctx());
    let zro_fee = option::none<coin::Coin<zro::ZRO>>();
    let refund_address = option::none<address>();
    let mut send_param = endpoint_send::create_param(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        message,
        options,
        native_fee,
        zro_fee,
        refund_address,
    );

    // Create MessagingFee that requires more native fee than available
    let fee = messaging_fee::create(1000u64, 0u64); // 1000 native required, but only 100 available

    // Test split_fee function directly - should fail with EInsufficientNativeFee
    let (paid_native, paid_zro) = messaging_channel::test_split_fee(&mut send_param, &fee, scenario.ctx());

    // Clean up (won't reach here due to expected failure)
    coin::burn_for_testing(paid_native);
    coin::burn_for_testing(paid_zro);
    test_utils::destroy(send_param);
    test_utils::destroy(_messagingChannel);
    scenario.end();
}

#[test]
fun test_split_fee_with_zro_fee() {
    let (mut scenario, _messagingChannel) = setup();

    // Create EndpointSendParam with both native and ZRO fees
    let message = b"test message";
    let options = b"test options";
    let native_fee_amount = 1000u64;
    let native_fee = coin::mint_for_testing<iota::iota::IOTA>(native_fee_amount, scenario.ctx());
    let zro_fee_amount = 500u64;
    let zro_fee = option::some(coin::mint_for_testing<zro::ZRO>(zro_fee_amount, scenario.ctx()));
    let refund_address = option::none<address>();
    let mut send_param = endpoint_send::create_param(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        message,
        options,
        native_fee,
        zro_fee,
        refund_address,
    );

    // Create MessagingFee with both native and ZRO fees
    let fee = messaging_fee::create(800u64, 300u64); // 800 native, 300 ZRO

    // Test split_fee function directly
    let (paid_native, paid_zro) = messaging_channel::test_split_fee(&mut send_param, &fee, scenario.ctx());

    // Verify results
    assert!(paid_native.value() == 800, 0); // Should match native fee
    assert!(paid_zro.value() == 300, 1); // Should match ZRO fee

    // Verify remaining balances in send_param
    assert!(send_param.native_token().value() == 200, 2); // 1000 - 800 = 200 remaining
    assert!(send_param.zro_token().borrow().value() == 200, 3); // 500 - 300 = 200 remaining

    // Clean up
    coin::burn_for_testing(paid_native);
    coin::burn_for_testing(paid_zro);
    test_utils::destroy(send_param);
    test_utils::destroy(_messagingChannel);
    scenario.end();
}

#[test, expected_failure(abort_code = messaging_channel::EInsufficientZroFee)]
fun test_split_fee_insufficient_zro_fee() {
    let (mut scenario, _messagingChannel) = setup();

    // Create EndpointSendParam with insufficient ZRO fee
    let message = b"test message";
    let options = b"test options";
    let native_fee_amount = 1000u64;
    let native_fee = coin::mint_for_testing<iota::iota::IOTA>(native_fee_amount, scenario.ctx());
    let zro_fee_amount = 100u64; // Insufficient amount
    let zro_fee = option::some(coin::mint_for_testing<zro::ZRO>(zro_fee_amount, scenario.ctx()));
    let refund_address = option::none<address>();
    let mut send_param = endpoint_send::create_param(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        message,
        options,
        native_fee,
        zro_fee,
        refund_address,
    );

    // Create MessagingFee that requires more ZRO than available
    let fee = messaging_fee::create(500u64, 500u64); // 500 ZRO required, but only 100 available

    // Test split_fee function directly - should fail with EInsufficientZroFee
    let (paid_native, paid_zro) = messaging_channel::test_split_fee(&mut send_param, &fee, scenario.ctx());

    // Clean up (won't reach here due to expected failure)
    coin::burn_for_testing(paid_native);
    coin::burn_for_testing(paid_zro);
    test_utils::destroy(send_param);
    test_utils::destroy(_messagingChannel);
    scenario.end();
}

#[test]
fun test_split_fee_zero_zro_fee() {
    let (mut scenario, _messagingChannel) = setup();

    // Create EndpointSendParam with ZRO token present but zero ZRO fee required
    let message = b"test message";
    let options = b"test options";
    let native_fee_amount = 1000u64;
    let native_fee = coin::mint_for_testing<iota::iota::IOTA>(native_fee_amount, scenario.ctx());
    let zro_fee_amount = 500u64;
    let zro_fee = option::some(coin::mint_for_testing<zro::ZRO>(zro_fee_amount, scenario.ctx()));
    let refund_address = option::none<address>();
    let mut send_param = endpoint_send::create_param(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        message,
        options,
        native_fee,
        zro_fee,
        refund_address,
    );

    // Create MessagingFee with zero ZRO fee
    let fee = messaging_fee::create(800u64, 0u64); // 800 native, 0 ZRO

    // Test split_fee function directly
    let (paid_native, paid_zro) = messaging_channel::test_split_fee(&mut send_param, &fee, scenario.ctx());

    // Verify results
    assert!(paid_native.value() == 800, 0); // Should match native fee
    assert!(paid_zro.value() == 0, 1); // Should be zero since zro_fee is 0

    // Verify remaining balances in send_param
    assert!(send_param.native_token().value() == 200, 2); // 1000 - 800 = 200 remaining
    assert!(send_param.zro_token().borrow().value() == 500, 3); // No ZRO deducted, 500 remaining

    // Clean up
    coin::burn_for_testing(paid_native);
    coin::burn_for_testing(paid_zro);
    test_utils::destroy(send_param);
    test_utils::destroy(_messagingChannel);
    scenario.end();
}

#[test]
fun test_split_fee_no_zro_token() {
    let (mut scenario, _messagingChannel) = setup();

    // Create EndpointSendParam with no ZRO token
    let message = b"test message";
    let options = b"test options";
    let native_fee_amount = 1000u64;
    let native_fee = coin::mint_for_testing<iota::iota::IOTA>(native_fee_amount, scenario.ctx());
    let zro_fee = option::none<coin::Coin<zro::ZRO>>();
    let refund_address = option::none<address>();
    let mut send_param = endpoint_send::create_param(
        REMOTE_EID,
        to_bytes32(REMOTE_OAPP),
        message,
        options,
        native_fee,
        zro_fee,
        refund_address,
    );

    // Create MessagingFee with zero ZRO fee (since no ZRO token available)
    let fee = messaging_fee::create(600u64, 0u64); // 600 native, 0 ZRO

    // Test split_fee function directly
    let (paid_native, paid_zro) = messaging_channel::test_split_fee(&mut send_param, &fee, scenario.ctx());

    // Verify results
    assert!(paid_native.value() == 600, 0); // Should match native fee
    assert!(paid_zro.value() == 0, 1); // Should be zero since no ZRO token

    // Verify remaining balance in send_param
    assert!(send_param.native_token().value() == 400, 2); // 1000 - 600 = 400 remaining
    assert!(send_param.zro_token().is_none(), 3); // Should still be none

    // Clean up
    coin::burn_for_testing(paid_native);
    coin::burn_for_testing(paid_zro);
    test_utils::destroy(send_param);
    test_utils::destroy(_messagingChannel);
    scenario.end();
}
