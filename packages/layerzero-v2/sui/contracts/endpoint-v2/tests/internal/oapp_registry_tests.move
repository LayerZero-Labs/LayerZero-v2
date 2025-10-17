#[test_only]
module endpoint_v2::oapp_registry_tests;

use endpoint_v2::{
    messaging_channel,
    oapp_registry::{Self, OAppRegistry, OAppRegisteredEvent, OAppInfoSetEvent, DelegateSetEvent}
};
use sui::{event, test_scenario::{Self, Scenario}, test_utils};

// === Test Constants ===

const OAPP_1: address = @0x1234;
const OAPP_2: address = @0x5678;
const DELEGATE_1: address = @0xd1d1;
const DELEGATE_2: address = @0xd2d2;

// === Test Data ===

fun create_test_oapp_info(): vector<u8> {
    vector[0x01, 0x02, 0x03, 0x04] // version + payload example
}

fun create_updated_oapp_info(): vector<u8> {
    vector[0x02, 0x05, 0x06, 0x07] // updated version + payload
}

// === Helper Functions ===

fun setup(): (Scenario, OAppRegistry) {
    let mut scenario = test_scenario::begin(@0x0);
    let registry = oapp_registry::new(scenario.ctx());
    (scenario, registry)
}

fun clean(scenario: Scenario, registry: OAppRegistry) {
    test_utils::destroy(registry);
    test_scenario::end(scenario);
}

// === Tests ===

#[test]
fun test_full_oapp_lifecycle() {
    let (mut scenario, mut registry) = setup();
    let initial_info = create_test_oapp_info();
    let updated_info = create_updated_oapp_info();

    // Step 1: Register oapp
    let messaging_channel = messaging_channel::create(OAPP_1, scenario.ctx());
    registry.register_oapp(OAPP_1, messaging_channel, initial_info);

    // Verify OAppRegisteredEvent was emitted
    let expected_registered_event = oapp_registry::create_oapp_registered_event(
        OAPP_1,
        messaging_channel,
        initial_info,
    );
    test_utils::assert_eq(event::events_by_type<OAppRegisteredEvent>()[0], expected_registered_event);

    // Step 2: Verify initial state
    assert!(registry.is_registered(OAPP_1), 0);
    assert!(*registry.get_oapp_info(OAPP_1) == initial_info, 1);
    let initial_channel = registry.get_messaging_channel(OAPP_1);
    assert!(initial_channel != @0x0, 2);

    // Step 3: Update oapp_info
    registry.set_oapp_info(OAPP_1, updated_info);

    // Verify OAppInfoSetEvent was emitted
    let expected_info_set_event = oapp_registry::create_oapp_info_set_event(
        OAPP_1,
        updated_info,
    );
    test_utils::assert_eq(event::events_by_type<OAppInfoSetEvent>()[0], expected_info_set_event);

    // Step 4: Verify updated state
    assert!(registry.is_registered(OAPP_1), 3);
    assert!(*registry.get_oapp_info(OAPP_1) == updated_info, 4); // Info updated
    let final_channel = registry.get_messaging_channel(OAPP_1);
    assert!(final_channel == initial_channel, 5); // Channel unchanged

    clean(scenario, registry);
}

#[test]
#[expected_failure(abort_code = oapp_registry::EOAppRegistered)]
fun test_register_oapp_already_registered() {
    let (mut scenario, mut registry) = setup();
    let oapp_info = create_test_oapp_info();

    // Register oapp first time
    let messaging_channel = messaging_channel::create(OAPP_1, scenario.ctx());
    registry.register_oapp(OAPP_1, messaging_channel, oapp_info);

    // Try to register the same oapp again - should fail
    registry.register_oapp(OAPP_1, messaging_channel, oapp_info);

    clean(scenario, registry);
}

#[test]
fun test_set_oapp_info_new() {
    let (mut scenario, mut registry) = setup();
    let initial_info = create_test_oapp_info();
    let updated_info = create_updated_oapp_info();

    // Register oapp first
    let messaging_channel = messaging_channel::create(OAPP_1, scenario.ctx());
    registry.register_oapp(OAPP_1, messaging_channel, initial_info);

    // Update oapp_info
    registry.set_oapp_info(OAPP_1, updated_info);

    // Verify the info was updated
    assert!(*registry.get_oapp_info(OAPP_1) == updated_info, 0);

    // Verify OAppInfoSetEvent was emitted
    let expected_event = oapp_registry::create_oapp_info_set_event(
        OAPP_1,
        updated_info,
    );
    test_utils::assert_eq(event::events_by_type<OAppInfoSetEvent>()[0], expected_event);

    clean(scenario, registry);
}

#[test]
#[expected_failure(abort_code = oapp_registry::EOAppNotRegistered)]
fun test_set_oapp_info_unregistered_oapp() {
    let (scenario, mut registry) = setup();
    let new_info = create_test_oapp_info();

    registry.set_oapp_info(OAPP_1, new_info);

    clean(scenario, registry);
}

#[test]
#[expected_failure(abort_code = oapp_registry::EOAppNotRegistered)]
fun test_get_messaging_channel_not_registered() {
    let (scenario, registry) = setup();

    // Try to get messaging channel for unregistered oapp
    registry.get_messaging_channel(OAPP_1);

    clean(scenario, registry);
}

#[test]
#[expected_failure(abort_code = oapp_registry::EOAppNotRegistered)]
fun test_get_oapp_info_not_registered() {
    let (scenario, registry) = setup();

    // Try to get oapp_info for unregistered oapp
    registry.get_oapp_info(OAPP_1);

    clean(scenario, registry);
}

#[test]
fun test_empty_oapp_info() {
    let (mut scenario, mut registry) = setup();
    let empty_info = vector::empty<u8>();

    // Register oapp with empty oapp_info - should work
    let messaging_channel = messaging_channel::create(OAPP_1, scenario.ctx());
    registry.register_oapp(OAPP_1, messaging_channel, empty_info);
    assert!(registry.is_registered(OAPP_1), 0);
    assert!(*registry.get_oapp_info(OAPP_1) == empty_info, 1);

    clean(scenario, registry);
}

#[test]
fun test_same_package_different_oapps() {
    let (mut scenario, mut registry) = setup();
    let oapp_info_1 = create_test_oapp_info();
    let oapp_info_2 = create_updated_oapp_info();

    // Register multiple oapps with the same package address
    let messaging_channel_1 = messaging_channel::create(OAPP_1, scenario.ctx());
    let messaging_channel_2 = messaging_channel::create(OAPP_2, scenario.ctx());
    registry.register_oapp(OAPP_1, messaging_channel_1, oapp_info_1);
    registry.register_oapp(OAPP_2, messaging_channel_2, oapp_info_2);

    // Verify both OAppRegisteredEvents were emitted
    let events = event::events_by_type<OAppRegisteredEvent>();

    let expected_event_1 = oapp_registry::create_oapp_registered_event(
        OAPP_1,
        messaging_channel_1,
        oapp_info_1,
    );
    let expected_event_2 = oapp_registry::create_oapp_registered_event(
        OAPP_2,
        messaging_channel_2,
        oapp_info_2,
    );
    test_utils::assert_eq(events[0], expected_event_1);
    test_utils::assert_eq(events[1], expected_event_2);

    // Both should be registered successfully
    assert!(registry.is_registered(OAPP_1), 0);
    assert!(registry.is_registered(OAPP_2), 1);

    // But different messaging channels
    let channel_1 = registry.get_messaging_channel(OAPP_1);
    let channel_2 = registry.get_messaging_channel(OAPP_2);
    assert!(channel_1 != channel_2, 4);

    clean(scenario, registry);
}

#[test]
fun test_set_delegate() {
    let (mut scenario, mut registry) = setup();
    let oapp_info = create_test_oapp_info();

    // Register oapp first
    let messaging_channel = messaging_channel::create(OAPP_1, scenario.ctx());
    registry.register_oapp(OAPP_1, messaging_channel, oapp_info);

    // Initially delegate should be @0x0
    assert!(registry.get_delegate(OAPP_1) == @0x0, 0);

    // Set delegate
    registry.set_delegate(OAPP_1, DELEGATE_1);

    // Verify delegate was set
    assert!(registry.get_delegate(OAPP_1) == DELEGATE_1, 1);

    // Verify DelegateSetEvent was emitted
    let delegate_set_event = oapp_registry::create_delegate_set_event(OAPP_1, DELEGATE_1);
    test_utils::assert_eq(event::events_by_type<DelegateSetEvent>()[0], delegate_set_event);

    // Update delegate
    registry.set_delegate(OAPP_1, DELEGATE_2);
    assert!(registry.get_delegate(OAPP_1) == DELEGATE_2, 2);

    // Verify second DelegateSetEvent was emitted
    let updated_delegate_event = oapp_registry::create_delegate_set_event(OAPP_1, DELEGATE_2);
    test_utils::assert_eq(event::events_by_type<DelegateSetEvent>()[1], updated_delegate_event);

    // Set delegate to @0x0 (remove delegate)
    registry.set_delegate(OAPP_1, @0x0);
    assert!(registry.get_delegate(OAPP_1) == @0x0, 3);

    // Verify final DelegateSetEvent was emitted with @0x0
    let remove_delegate_event = oapp_registry::create_delegate_set_event(OAPP_1, @0x0);
    test_utils::assert_eq(event::events_by_type<DelegateSetEvent>()[2], remove_delegate_event);

    clean(scenario, registry);
}

#[test]
#[expected_failure(abort_code = oapp_registry::EOAppNotRegistered)]
fun test_set_delegate_unregistered_oapp() {
    let (scenario, mut registry) = setup();

    // Try to set delegate for unregistered oapp - should fail
    registry.set_delegate(OAPP_1, DELEGATE_1);

    clean(scenario, registry);
}

#[test]
#[expected_failure(abort_code = oapp_registry::EOAppNotRegistered)]
fun test_get_delegate_unregistered_oapp() {
    let (scenario, registry) = setup();

    // Try to get delegate for unregistered oapp - should fail
    registry.get_delegate(OAPP_1);

    clean(scenario, registry);
}
