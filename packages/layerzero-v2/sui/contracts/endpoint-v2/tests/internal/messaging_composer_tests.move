#[test_only]
module endpoint_v2::messaging_composer_tests;

use endpoint_v2::messaging_composer::{
    Self,
    ComposeQueue,
    ComposerRegistry,
    ComposeSentEvent,
    ComposeDeliveredEvent,
    LzComposeAlertEvent,
    ComposerRegisteredEvent,
    ComposerInfoSetEvent
};
use std::ascii;
use sui::{event, test_scenario::{Self as ts, Scenario}, test_utils};
use utils::{bytes32::{Self, Bytes32}, hash};

// === Test Constants ===

const OAPP: address = @0x1;
const TO: address = @0x2;
const EXECUTOR: address = @0x3;
const INDEX: u16 = 0;
const MESSAGE: vector<u8> = b"foobar";
const GUID: vector<u8> = b"guidguidguidguidguidguidguidguid";

// Additional constants for composer registry tests
const COMPOSER_1: address = @0x101;
const COMPOSER_2: address = @0x102;

// === Helper functions ===

fun setup(): (Scenario, ComposeQueue) {
    let mut scenario = ts::begin(@0x0);
    // Create composer using the new flow - register in registry first
    let mut registry = messaging_composer::new_composer_registry(scenario.ctx());
    registry.register_composer(TO, b"test_info", scenario.ctx());
    let compose_queue_addr = registry.get_compose_queue(TO);
    scenario.next_tx(@0x0);
    let composer = scenario.take_shared_by_id<ComposeQueue>(object::id_from_address(compose_queue_addr));
    test_utils::destroy(registry);
    (scenario, composer)
}

fun setup_registry(): (Scenario, ComposerRegistry) {
    let mut scenario = ts::begin(@0x0);
    let registry = messaging_composer::new_composer_registry(scenario.ctx());
    (scenario, registry)
}

fun clean(scenario: Scenario, composer: ComposeQueue) {
    test_utils::destroy(composer);
    ts::end(scenario);
}

fun clean_registry(scenario: Scenario, registry: ComposerRegistry) {
    test_utils::destroy(registry);
    ts::end(scenario);
}

fun create_test_composer_info(): vector<u8> {
    vector[0x01, 0x02, 0x03, 0x04] // version + payload example
}

fun create_updated_composer_info(): vector<u8> {
    vector[0x02, 0x05, 0x06, 0x07] // updated version + payload
}

// === Tests ===

#[test]
fun test_register_composer() {
    let (mut scenario, mut registry) = setup_registry();
    let composer_info = create_test_composer_info();

    // Initially composer should not be registered
    assert!(!registry.is_registered(COMPOSER_1), 0);

    // Register the composer
    registry.register_composer(COMPOSER_1, composer_info, scenario.ctx());

    // Verify composer is now registered
    assert!(registry.is_registered(COMPOSER_1), 1);
    assert!(*registry.get_composer_info(COMPOSER_1) == composer_info, 2);

    // Verify messaging composer address is valid
    let messaging_composer_addr = registry.get_compose_queue(COMPOSER_1);
    assert!(messaging_composer_addr != @0x0, 3);

    // Verify event was emitted
    let expected_event = messaging_composer::create_composer_registered_event(
        COMPOSER_1,
        messaging_composer_addr,
        composer_info,
    );
    let events = event::events_by_type<ComposerRegisteredEvent>();
    assert!(events.length() == 1, 4);
    test_utils::assert_eq(events[0], expected_event);

    clean_registry(scenario, registry);
}

#[test]
fun test_register_same_package_different_composers() {
    let (mut scenario, mut registry) = setup_registry();
    let composer_info_1 = create_test_composer_info();
    let composer_info_2 = create_updated_composer_info();

    // Register two composers
    registry.register_composer(COMPOSER_1, composer_info_1, scenario.ctx());
    registry.register_composer(COMPOSER_2, composer_info_2, scenario.ctx());

    // Both should be registered successfully
    assert!(registry.is_registered(COMPOSER_1), 0);
    assert!(registry.is_registered(COMPOSER_2), 1);

    // Both should have different compose info and messaging composers
    assert!(*registry.get_composer_info(COMPOSER_1) == composer_info_1, 2);
    assert!(*registry.get_composer_info(COMPOSER_2) == composer_info_2, 3);

    let addr_1 = registry.get_compose_queue(COMPOSER_1);
    let addr_2 = registry.get_compose_queue(COMPOSER_2);
    assert!(addr_1 != addr_2, 4);

    // Verify both registration events were emitted
    let expected_event_1 = messaging_composer::create_composer_registered_event(
        COMPOSER_1,
        addr_1,
        composer_info_1,
    );
    let expected_event_2 = messaging_composer::create_composer_registered_event(
        COMPOSER_2,
        addr_2,
        composer_info_2,
    );
    let events = event::events_by_type<ComposerRegisteredEvent>();
    assert!(events.length() == 2, 5);
    test_utils::assert_eq(events[0], expected_event_1);
    test_utils::assert_eq(events[1], expected_event_2);

    clean_registry(scenario, registry);
}

#[test]
#[expected_failure(abort_code = messaging_composer::EComposerRegistered)]
fun test_register_composer_already_registered() {
    let (mut scenario, mut registry) = setup_registry();
    let composer_info = create_test_composer_info();

    // Register composer first time
    registry.register_composer(COMPOSER_1, composer_info, scenario.ctx());

    // Try to register the same composer again - should fail
    registry.register_composer(COMPOSER_1, composer_info, scenario.ctx());

    clean_registry(scenario, registry);
}

#[test]
fun test_register_composer_empty_composer_info() {
    let (mut scenario, mut registry) = setup_registry();
    let empty_info = vector::empty<u8>();

    // Register composer with empty composer_info - should work
    registry.register_composer(COMPOSER_1, empty_info, scenario.ctx());
    assert!(registry.is_registered(COMPOSER_1), 0);
    assert!(*registry.get_composer_info(COMPOSER_1) == empty_info, 1);

    clean_registry(scenario, registry);
}

#[test]
fun test_set_composer_info() {
    let (mut scenario, mut registry) = setup_registry();
    let initial_info = create_test_composer_info();
    let updated_info = create_updated_composer_info();

    // Register composer first
    registry.register_composer(COMPOSER_1, initial_info, scenario.ctx());

    // Update composer_info
    registry.set_composer_info(COMPOSER_1, updated_info);

    // Verify the info was updated
    assert!(*registry.get_composer_info(COMPOSER_1) == updated_info, 0);

    // Verify event was emitted
    let expected_event = messaging_composer::create_composer_info_set_event(
        COMPOSER_1,
        updated_info,
    );
    let events = event::events_by_type<ComposerInfoSetEvent>();
    // Should have 1 event (from set_composer_info, not from register_composer)
    assert!(events.length() >= 1, 1);
    test_utils::assert_eq(events[events.length() - 1], expected_event);

    clean_registry(scenario, registry);
}

#[test]
#[expected_failure(abort_code = messaging_composer::EComposerNotRegistered)]
fun test_set_composer_info_unregistered_composer() {
    let (scenario, mut registry) = setup_registry();
    let new_info = create_test_composer_info();

    registry.set_composer_info(COMPOSER_1, new_info);

    clean_registry(scenario, registry);
}

#[test]
fun test_set_empty_composer_info() {
    let (mut scenario, mut registry) = setup_registry();
    let initial_info = create_test_composer_info();
    let empty_info = vector::empty<u8>();

    // Register composer first
    registry.register_composer(COMPOSER_1, initial_info, scenario.ctx());

    // Set empty composer_info - should work
    registry.set_composer_info(COMPOSER_1, empty_info);
    assert!(*registry.get_composer_info(COMPOSER_1) == empty_info, 0);

    clean_registry(scenario, registry);
}

#[test]
#[expected_failure(abort_code = messaging_composer::EComposerNotRegistered)]
fun test_get_messaging_composer_not_registered() {
    let (scenario, registry) = setup_registry();

    // Try to get messaging composer for unregistered composer
    registry.get_compose_queue(COMPOSER_1);

    clean_registry(scenario, registry);
}

#[test]
#[expected_failure(abort_code = messaging_composer::EComposerNotRegistered)]
fun test_get_composer_info_not_registered() {
    let (scenario, registry) = setup_registry();

    // Try to get composer_info for unregistered composer
    registry.get_composer_info(COMPOSER_1);

    clean_registry(scenario, registry);
}

#[test]
fun test_send_compose() {
    let (scenario, mut composer) = setup();
    let guid: Bytes32 = bytes32::from_bytes(GUID);

    // send first compose
    let message = MESSAGE;
    composer.send_compose(OAPP, guid, INDEX, message);
    let message_hash = hash::keccak256!(&message);
    assert!(composer.get_compose_message_hash(OAPP, guid, INDEX) == message_hash, 0);
    let compose_sent_event = messaging_composer::create_compose_sent_event(
        OAPP,
        TO,
        guid,
        INDEX,
        message,
    );
    test_utils::assert_eq(event::events_by_type<ComposeSentEvent>()[0], compose_sent_event);
    assert!(composer.get_compose_queue_length() == 1, 1);

    // send another compose
    let message_2 = b"barfoo2";
    composer.send_compose(OAPP, guid, INDEX+1, message_2);
    let message_hash_2 = hash::keccak256!(&message_2);
    assert!(composer.get_compose_message_hash(OAPP, guid, INDEX+1) == message_hash_2, 0);
    let compose_sent_event_2 = messaging_composer::create_compose_sent_event(
        OAPP,
        TO,
        guid,
        INDEX+1,
        message_2,
    );
    test_utils::assert_eq(event::events_by_type<ComposeSentEvent>()[1], compose_sent_event_2);
    assert!(composer.get_compose_queue_length() == 2, 2);

    clean(scenario, composer);
}

#[test, expected_failure(abort_code = messaging_composer::EComposeExists)]
fun test_send_same_compose() {
    let (scenario, mut composer) = setup();
    let guid: Bytes32 = bytes32::from_bytes(GUID);

    composer.send_compose(OAPP, guid, INDEX, MESSAGE);
    composer.send_compose(OAPP, guid, INDEX, MESSAGE);

    clean(scenario, composer);
}

#[test]
fun test_send_compose_and_clear() {
    let (scenario, mut composer) = setup();
    let guid: Bytes32 = bytes32::from_bytes(GUID);

    composer.send_compose(OAPP, guid, INDEX, MESSAGE);
    composer.clear_compose(OAPP, guid, INDEX, MESSAGE);
    assert!(composer.get_compose_message_hash(OAPP, guid, INDEX) == bytes32::ff_bytes32(), 0);
    let compose_delivered_event = messaging_composer::create_compose_delivered_event(
        OAPP,
        TO,
        guid,
        INDEX,
    );
    test_utils::assert_eq(
        event::events_by_type<ComposeDeliveredEvent>()[0],
        compose_delivered_event,
    );

    clean(scenario, composer);
}

#[test, expected_failure(abort_code = messaging_composer::EComposeNotFound)]
fun test_cannot_clear_before_send_compose() {
    let (scenario, mut composer) = setup();
    let guid: Bytes32 = bytes32::from_bytes(GUID);
    composer.clear_compose(OAPP, guid, INDEX, MESSAGE);
    clean(scenario, composer);
}

#[test, expected_failure(abort_code = messaging_composer::EComposeMessageMismatch)]
fun test_cannot_clear_same_message_twice() {
    let (scenario, mut composer) = setup();
    let guid: Bytes32 = bytes32::from_bytes(GUID);
    composer.send_compose(OAPP, guid, INDEX, MESSAGE);
    composer.clear_compose(OAPP, guid, INDEX, MESSAGE);
    composer.clear_compose(OAPP, guid, INDEX, MESSAGE);
    clean(scenario, composer);
}

#[test, expected_failure(abort_code = messaging_composer::EComposeMessageMismatch)]
fun test_clear_with_wrong_message() {
    let (scenario, mut composer) = setup();
    let guid: Bytes32 = bytes32::from_bytes(GUID);
    composer.send_compose(OAPP, guid, INDEX, MESSAGE);
    composer.clear_compose(OAPP, guid, INDEX, b"wrong_message");
    clean(scenario, composer);
}

#[test]
fun test_lz_compose_alert() {
    let guid: Bytes32 = bytes32::from_bytes(GUID);
    let extra_data = b"extra_data";
    let reason = ascii::string(b"reason");
    messaging_composer::lz_compose_alert(
        EXECUTOR,
        OAPP,
        TO,
        guid,
        INDEX,
        100,
        100,
        MESSAGE,
        extra_data,
        reason,
    );
    let lz_compose_alert_event = messaging_composer::create_lz_compose_alert_event(
        EXECUTOR,
        OAPP,
        TO,
        guid,
        INDEX,
        100,
        100,
        MESSAGE,
        extra_data,
        reason,
    );
    test_utils::assert_eq(event::events_by_type<LzComposeAlertEvent>()[0], lz_compose_alert_event);
}
