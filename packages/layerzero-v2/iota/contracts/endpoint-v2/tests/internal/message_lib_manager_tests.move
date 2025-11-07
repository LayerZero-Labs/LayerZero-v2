#[test_only]
module endpoint_v2::message_lib_manager_tests;

use call::call_cap;
use endpoint_v2::{
    message_lib_manager::{
        Self,
        MessageLibManager,
        LibraryRegisteredEvent,
        DefaultSendLibrarySetEvent,
        DefaultReceiveLibrarySetEvent,
        DefaultReceiveLibraryTimeoutSetEvent,
        SendLibrarySetEvent,
        ReceiveLibrarySetEvent,
        ReceiveLibraryTimeoutSetEvent
    },
    message_lib_type
};
use iota::{clock::{Self, Clock}, event, test_scenario::{Self as ts, Scenario}, test_utils};

const ADMIN: address = @0x0;
const OAPP: address = @0xa;

// === Helper functions ===

fun create_clock_at_time(scenario: &mut Scenario, seconds: u64): Clock {
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(seconds * 1000);
    clock
}

fun set_clock_at_time(clock: &mut Clock, seconds: u64) {
    clock.set_for_testing(seconds * 1000);
}

// Helper function to setup test scenario and message lib manager
fun setup(): (Scenario, MessageLibManager, address, address, address) {
    let mut scenario = ts::begin(ADMIN);
    let mut manager = message_lib_manager::new(scenario.ctx());

    // Register different types of libraries like in Solidity tests
    let blocked_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let blocked_lib_address = blocked_lib_cap.id();
    manager.register_library(blocked_lib_address, message_lib_type::send_and_receive());

    let send_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let send_lib_address = send_lib_cap.id();
    manager.register_library(send_lib_address, message_lib_type::send());

    let receive_lib_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let receive_lib_address = receive_lib_cap.id();
    manager.register_library(receive_lib_address, message_lib_type::receive());

    test_utils::destroy(blocked_lib_cap);
    test_utils::destroy(send_lib_cap);
    test_utils::destroy(receive_lib_cap);
    (scenario, manager, blocked_lib_address, send_lib_address, receive_lib_address)
}

// Helper function to clean up test scenario and manager
fun clean(scenario: Scenario, manager: MessageLibManager) {
    test_utils::destroy(manager);
    scenario.end();
}

// === Library Registration Tests ===

#[test]
fun test_registered_libraries_empty_registry() {
    let mut scenario = ts::begin(ADMIN);
    let manager = message_lib_manager::new(scenario.ctx());

    // Test empty registry
    let libs = manager.registered_libraries(0, 10);
    assert!(libs.length() == 0, 0);

    test_utils::destroy(manager);
    scenario.end();
}

#[test]
fun test_registered_libraries_max_count_zero() {
    let (scenario, manager, _, _, _) = setup();

    // Test with max_count = 0
    let libs = manager.registered_libraries(0, 0);
    assert!(libs.length() == 0, 0);

    clean(scenario, manager);
}

#[test]
fun test_registered_libraries_start_at_end() {
    let (scenario, manager, _, _, _) = setup();

    // We have 3 libraries registered in setup
    let total_libs = manager.registered_libraries(0, 10).length();

    // Test start = total length (should return empty vector)
    let libs = manager.registered_libraries(total_libs, 5);
    assert!(libs.length() == 0, 0);

    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EInvalidBounds)]
fun test_registered_libraries_start_beyond_end() {
    let (scenario, manager, _, _, _) = setup();

    let total_libs = manager.registered_libraries(0, 10).length();

    // Test start > total length (should fail)
    let _ = manager.registered_libraries(total_libs + 1, 5);

    clean(scenario, manager);
}

#[test]
fun test_register_library() {
    let (mut scenario, mut manager, _, _, _) = setup();

    // Register new library
    let new_lib_cap = call_cap::new_individual_cap(scenario.ctx());

    // Check is_registered_library before registration
    assert!(!manager.is_registered_library(new_lib_cap.id()), 0);
    manager.register_library(new_lib_cap.id(), message_lib_type::send_and_receive());

    // Check all registered libraries
    let libs = manager.registered_libraries(0, 10);
    assert!(libs.length() == 4, 0);
    // Libraries are registered in order, but we can't easily get their addresses anymore
    // since get_library_from_original_package was removed
    assert!(libs[3] == new_lib_cap.id(), 4);
    assert!(manager.is_registered_library(new_lib_cap.id()), 5);
    assert!(manager.get_library_type(new_lib_cap.id()) == message_lib_type::send_and_receive(), 6);

    // Check event emission
    let events = event::events_by_type<LibraryRegisteredEvent>();
    assert!(events.length() > 0, 7); // Just verify an event was emitted

    test_utils::destroy(new_lib_cap);
    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EAlreadyRegistered)]
fun test_register_library_already_registered() {
    let (scenario, mut manager, blocked_lib_address, _, _) = setup();

    // Try to register same library again - should fail
    manager.register_library(blocked_lib_address, message_lib_type::send_and_receive());

    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EInvalidAddress)]
fun test_register_library_invalid_address() {
    let (scenario, mut manager, _, _, _) = setup();

    // Try to register library with @0x0 as address - should fail
    manager.register_library(@0x0, message_lib_type::send_and_receive());

    clean(scenario, manager);
}

// === Default Send Library Tests ===

#[test, expected_failure(abort_code = message_lib_manager::EOnlyRegisteredLib)]
fun test_set_default_send_library_with_unregistered_lib() {
    let (scenario, mut manager, _, _, _) = setup();

    // Try to set unregistered library as default - should fail
    manager.set_default_send_library(2, @0x999);

    clean(scenario, manager);
}

#[test]
fun test_set_default_send_library() {
    let (scenario, mut manager, blocked_lib_address, _, _) = setup();
    let dst_eid = 2u32;

    // Set new default
    manager.set_default_send_library(dst_eid, blocked_lib_address);

    let default_lib = manager.get_default_send_library(dst_eid);
    assert!(default_lib == blocked_lib_address, 0);

    // Check event emission
    let expected_event = message_lib_manager::create_default_send_library_set_event(
        dst_eid,
        blocked_lib_address,
    );
    let events = event::events_by_type<DefaultSendLibrarySetEvent>();
    test_utils::assert_eq(events[0], expected_event);

    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::ESameValue)]
fun test_set_default_send_library_same_value() {
    let (scenario, mut manager, blocked_lib_address, _, _) = setup();
    let dst_eid = 2u32;

    // Set default send library
    manager.set_default_send_library(dst_eid, blocked_lib_address);

    // Try to set same library again - should fail
    manager.set_default_send_library(dst_eid, blocked_lib_address);

    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EOnlySendLib)]
fun test_set_default_send_library_to_receive_only_lib() {
    let (scenario, mut manager, _, send_lib_address, receive_lib_address) = setup();

    // Set default send library
    manager.set_default_send_library(2, send_lib_address);

    // Try to set default send library to receive only library - should fail
    manager.set_default_send_library(2, receive_lib_address);

    clean(scenario, manager);
}

// === Default Receive Library Tests ===

#[test, expected_failure(abort_code = message_lib_manager::EOnlyRegisteredLib)]
fun test_set_default_receive_library_with_unregistered_lib() {
    let (mut scenario, mut manager, _, _, _) = setup();
    let clock = create_clock_at_time(&mut scenario, 1000);

    // Try to set unregistered library as default - should fail
    manager.set_default_receive_library(2, @0x999, 0, &clock);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

#[test]
fun test_set_default_receive_library() {
    let (mut scenario, mut manager, blocked_lib_address, _, _) = setup();
    let clock = create_clock_at_time(&mut scenario, 1000);
    let src_eid = 2u32;

    // Set new default
    manager.set_default_receive_library(src_eid, blocked_lib_address, 0, &clock);

    let default_lib = manager.get_default_receive_library(src_eid);
    assert!(default_lib == blocked_lib_address, 0);
    manager.assert_receive_library(OAPP, src_eid, blocked_lib_address, &clock);

    // Check event emissions
    let expected_event1 = message_lib_manager::create_default_receive_library_set_event(
        src_eid,
        blocked_lib_address,
    );
    let expected_event2 = message_lib_manager::create_default_receive_library_timeout_set_event(
        src_eid,
        @0x0, // old_lib is DEFAULT_LIB
        0, // expiry is 0 since grace_period is 0
    );
    let events1 = event::events_by_type<DefaultReceiveLibrarySetEvent>();
    let events2 = event::events_by_type<DefaultReceiveLibraryTimeoutSetEvent>();
    test_utils::assert_eq(events1[0], expected_event1);
    test_utils::assert_eq(events2[0], expected_event2);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::ESameValue)]
fun test_set_default_receive_library_same_value() {
    let (mut scenario, mut manager, blocked_lib_address, _, _) = setup();
    let clock = create_clock_at_time(&mut scenario, 1000);
    let src_eid = 2u32;

    // Set default receive library
    manager.set_default_receive_library(src_eid, blocked_lib_address, 0, &clock);

    // Try to set same library again - should fail
    manager.set_default_receive_library(src_eid, blocked_lib_address, 0, &clock);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EOnlyReceiveLib)]
fun test_set_default_receive_library_to_send_only_lib() {
    let (mut scenario, mut manager, _, send_lib_address, receive_lib_address) = setup();
    let clock = create_clock_at_time(&mut scenario, 1000);

    // Set default receive library
    manager.set_default_receive_library(2, receive_lib_address, 0, &clock);

    // Try to set default receive library to send only library - should fail
    manager.set_default_receive_library(2, send_lib_address, 0, &clock);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

// === Default Receive Library Timeout Tests ===

#[test, expected_failure(abort_code = message_lib_manager::EOnlyRegisteredLib)]
fun test_set_default_receive_library_timeout_with_unregistered_lib() {
    let (mut scenario, mut manager, _, _, _) = setup();
    let clock = create_clock_at_time(&mut scenario, 1000);

    // Try to set timeout for unregistered library - should fail
    manager.set_default_receive_library_timeout(2, @0x999, 2000, &clock);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EInvalidExpiry)]
fun test_set_default_receive_library_timeout_with_invalid_timestamp() {
    let (mut scenario, mut manager, blocked_lib_address, _, receive_lib_address) = setup();
    let clock = create_clock_at_time(&mut scenario, 1000);
    manager.set_default_receive_library(2, receive_lib_address, 0, &clock);

    // Try to set expiry in the past - should fail
    manager.set_default_receive_library_timeout(2, blocked_lib_address, 500, &clock);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

#[test]
fun test_set_default_receive_library_timeout() {
    let (mut scenario, mut manager, blocked_lib_address, _, receive_lib_address) = setup();
    let clock = create_clock_at_time(&mut scenario, 1000);
    let src_eid = 2u32;

    // Change default receive library with grace period
    manager.set_default_receive_library(src_eid, receive_lib_address, 0, &clock);
    manager.set_default_receive_library(src_eid, blocked_lib_address, 100, &clock);

    let timeout_opt = manager.get_default_receive_library_timeout(src_eid);
    assert!(timeout_opt.is_some(), 0);
    let timeout = timeout_opt.destroy_some();
    assert!(timeout.fallback_lib() == receive_lib_address, 1);
    assert!(timeout.expiry() == 1100, 2); // 1000 + 100

    // Set timeout to specific time and change the timeout library
    manager.set_default_receive_library_timeout(src_eid, blocked_lib_address, 1500, &clock);
    let timeout_opt2 = manager.get_default_receive_library_timeout(src_eid);
    assert!(timeout_opt2.is_some(), 3);
    let timeout2 = timeout_opt2.destroy_some();
    assert!(timeout2.fallback_lib() == blocked_lib_address, 4);
    assert!(timeout2.expiry() == 1500, 5);

    // Disable timeout
    manager.set_default_receive_library_timeout(src_eid, receive_lib_address, 0, &clock);
    let timeout_opt3 = manager.get_default_receive_library_timeout(src_eid);
    assert!(timeout_opt3.is_none(), 6);

    // Check event emissions for timeout operations
    let timeout_events = event::events_by_type<DefaultReceiveLibraryTimeoutSetEvent>();
    // Should have 4 events: initial set, change with grace period, specific timeout, disable timeout
    assert!(timeout_events.length() == 4, 7);

    let expected_timeout_event = message_lib_manager::create_default_receive_library_timeout_set_event(
        src_eid,
        receive_lib_address,
        0, // expiry is 0 when disabling timeout
    );
    test_utils::assert_eq(timeout_events[3], expected_timeout_event); // Check the last event (disable timeout)

    clock.destroy_for_testing();
    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EOnlyReceiveLib)]
fun test_set_default_receive_library_timeout_to_send_only_lib() {
    let (mut scenario, mut manager, _, send_lib_address, receive_lib_address) = setup();
    let clock = create_clock_at_time(&mut scenario, 1000);

    // Set default receive library
    manager.set_default_receive_library(2, receive_lib_address, 0, &clock);

    // Set default receive library timeout to send only library - should fail
    manager.set_default_receive_library_timeout(2, send_lib_address, 1000, &clock);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

// === OApp Send Library Tests ===

#[test]
fun test_set_send_library() {
    let (scenario, mut manager, blocked_lib_address, send_lib_address, _) = setup();
    let dst_eid = 2u32;

    // Set default send library
    manager.set_default_send_library(dst_eid, send_lib_address);

    // Set send library for oapp
    manager.set_send_library(OAPP, dst_eid, blocked_lib_address);

    let (lib, is_default) = manager.get_send_library(OAPP, dst_eid);
    assert!(lib == blocked_lib_address, 0);
    assert!(!is_default, 1);

    // Set back to default
    manager.set_send_library(OAPP, dst_eid, @0x0);
    let (lib, is_default) = manager.get_send_library(OAPP, dst_eid);
    assert!(lib == send_lib_address, 2);
    assert!(is_default, 3);

    // Check event emissions
    let send_lib_events = event::events_by_type<SendLibrarySetEvent>();
    assert!(send_lib_events.length() == 2, 4); // Two set operations

    let expected_event1 = message_lib_manager::create_send_library_set_event(
        OAPP,
        dst_eid,
        blocked_lib_address,
    );
    let expected_event2 = message_lib_manager::create_send_library_set_event(
        OAPP,
        dst_eid,
        @0x0, // Setting back to default
    );
    test_utils::assert_eq(send_lib_events[0], expected_event1);
    test_utils::assert_eq(send_lib_events[1], expected_event2);

    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EDefaultSendLibUnavailable)]
fun test_set_send_library_without_default() {
    let (scenario, mut manager, blocked_lib_address, _, _) = setup();

    // Try to set send library without default - should fail
    manager.set_send_library(OAPP, 2, blocked_lib_address);

    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EOnlyRegisteredLib)]
fun test_set_send_library_with_unregistered_lib() {
    let (scenario, mut manager, _, _, _) = setup();

    // Try to set unregistered library - should fail
    manager.set_send_library(OAPP, 2, @0x999);

    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::ESameValue)]
fun test_set_send_library_same_value() {
    let (scenario, mut manager, blocked_lib_address, send_lib_address, _) = setup();
    let dst_eid = 2u32;

    // Set default send library
    manager.set_default_send_library(dst_eid, send_lib_address);

    // Set send library
    manager.set_send_library(OAPP, dst_eid, blocked_lib_address);

    // Try to set same library again - should fail
    manager.set_send_library(OAPP, dst_eid, blocked_lib_address);

    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EOnlySendLib)]
fun test_set_send_library_to_receive_only_lib() {
    let (scenario, mut manager, _, send_lib_address, receive_lib_address) = setup();
    let dst_eid = 2u32;

    // Set default send library
    manager.set_default_send_library(dst_eid, send_lib_address);

    // Set send library to receive only library
    manager.set_send_library(OAPP, dst_eid, receive_lib_address);

    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EDefaultSendLibUnavailable)]
fun test_get_send_library_with_invalid_eid() {
    let (scenario, manager, _, _, _) = setup();

    // Try to get send library when no default is set - should fail
    let (_, _) = manager.get_send_library(OAPP, 4294967295u32); // max u32

    clean(scenario, manager);
}

// === OApp Receive Library Tests ===

#[test]
fun test_set_receive_library() {
    let (mut scenario, mut manager, blocked_lib_address, _, receive_lib_address) = setup();
    let clock = create_clock_at_time(&mut scenario, 1000);
    let src_eid = 2u32;

    // Set default receive library
    manager.set_default_receive_library(src_eid, receive_lib_address, 0, &clock);

    // Set receive library for oapp (can't use grace period with default)
    manager.set_receive_library(OAPP, src_eid, blocked_lib_address, 0, &clock);

    let (lib, is_default) = manager.get_receive_library(OAPP, src_eid);
    assert!(lib == blocked_lib_address, 0);
    assert!(!is_default, 1);

    // Set back to default
    manager.set_receive_library(OAPP, src_eid, @0x0, 0, &clock);
    let (lib, is_default) = manager.get_receive_library(OAPP, src_eid);
    assert!(lib == receive_lib_address, 2);
    assert!(is_default, 3);

    // Check event emissions
    let receive_lib_events = event::events_by_type<ReceiveLibrarySetEvent>();
    let receive_timeout_events = event::events_by_type<ReceiveLibraryTimeoutSetEvent>();
    assert!(receive_lib_events.length() == 2, 4); // Two set operations
    assert!(receive_timeout_events.length() == 2, 5); // Two timeout operations

    let expected_event1 = message_lib_manager::create_receive_library_set_event(
        OAPP,
        src_eid,
        blocked_lib_address,
    );
    let expected_event2 = message_lib_manager::create_receive_library_set_event(
        OAPP,
        src_eid,
        @0x0, // Setting back to default
    );
    test_utils::assert_eq(receive_lib_events[0], expected_event1);
    test_utils::assert_eq(receive_lib_events[1], expected_event2);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EDefaultReceiveLibUnavailable)]
fun test_set_receive_library_without_default() {
    let (mut scenario, mut manager, blocked_lib_address, _, _) = setup();
    let clock = create_clock_at_time(&mut scenario, 1000);
    let src_eid = 2u32;

    // Try to set receive library without default - should fail
    manager.set_receive_library(OAPP, src_eid, blocked_lib_address, 0, &clock);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EOnlyNonDefaultLib)]
fun test_set_receive_library_grace_period_with_default() {
    let (mut scenario, mut manager, blocked_lib_address, _, receive_lib_address) = setup();
    let clock = create_clock_at_time(&mut scenario, 1000);

    // Set default receive library
    manager.set_default_receive_library(2, receive_lib_address, 0, &clock);

    // Try to set grace period when transitioning from default - should fail
    manager.set_receive_library(OAPP, 2, blocked_lib_address, 1000, &clock);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EOnlyReceiveLib)]
fun test_set_receive_library_to_send_only_lib() {
    let (mut scenario, mut manager, _, send_lib_address, receive_lib_address) = setup();
    let dst_eid = 2u32;
    let clock = create_clock_at_time(&mut scenario, 0);

    // Set default receive library
    manager.set_default_receive_library(dst_eid, receive_lib_address, 0, &clock);

    // Set receive library to send only library
    manager.set_receive_library(OAPP, dst_eid, send_lib_address, 0, &clock);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EDefaultReceiveLibUnavailable)]
fun test_get_receive_library_with_invalid_eid() {
    let (scenario, manager, _, _, _) = setup();

    // Try to get receive library when no default is set - should fail
    let (_, _) = manager.get_receive_library(OAPP, 4294967295u32); // max u32

    clean(scenario, manager);
}

// === OApp Receive Library Timeout Tests ===

#[test]
fun test_set_receive_library_timeout() {
    let (mut scenario, mut manager, blocked_lib_address, _, receive_lib_address) = setup();
    let clock = create_clock_at_time(&mut scenario, 1000);
    let src_eid = 2u32;

    // Set default receive library
    manager.set_default_receive_library(src_eid, receive_lib_address, 0, &clock);

    // First set a non-default receive library
    manager.set_receive_library(OAPP, src_eid, blocked_lib_address, 0, &clock);
    manager.set_receive_library(OAPP, src_eid, receive_lib_address, 100, &clock);

    let timeout_opt = manager.get_receive_library_timeout(OAPP, src_eid);
    assert!(timeout_opt.is_some(), 0);
    let timeout = timeout_opt.destroy_some();
    assert!(timeout.fallback_lib() == blocked_lib_address, 1);
    assert!(timeout.expiry() == 1100, 2); // 1000 + 100

    // Set timeout to specific time and change the timeout library
    manager.set_receive_library_timeout(OAPP, src_eid, receive_lib_address, 1500, &clock);
    let timeout_opt2 = manager.get_receive_library_timeout(OAPP, src_eid);
    assert!(timeout_opt2.is_some(), 3);
    let timeout2 = timeout_opt2.destroy_some();
    assert!(timeout2.fallback_lib() == receive_lib_address, 4);
    assert!(timeout2.expiry() == 1500, 5);

    // Check event emissions for timeout operations
    let timeout_events = event::events_by_type<ReceiveLibraryTimeoutSetEvent>();
    assert!(timeout_events.length() == 3, 6); // Three timeout operations

    let expected_timeout_event = message_lib_manager::create_receive_library_timeout_set_event(
        OAPP,
        src_eid,
        receive_lib_address, // old_lib
        1500, // expiry
    );
    test_utils::assert_eq(timeout_events[2], expected_timeout_event); // Check the last timeout event

    clock.destroy_for_testing();
    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EDefaultReceiveLibUnavailable)]
fun test_set_receive_library_timeout_without_default() {
    let (mut scenario, mut manager, _, _, receive_lib_address) = setup();
    let clock = create_clock_at_time(&mut scenario, 1000);

    // Try to set timeout without default - should fail
    manager.set_receive_library_timeout(OAPP, 2, receive_lib_address, 1000, &clock);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EOnlyRegisteredLib)]
fun test_set_receive_library_timeout_with_unregistered_lib() {
    let (mut scenario, mut manager, _, _, receive_lib_address) = setup();
    let clock = create_clock_at_time(&mut scenario, 1000);

    // Set default receive library
    manager.set_default_receive_library(2, receive_lib_address, 0, &clock);

    // Try to set timeout with unregistered library - should fail
    manager.set_receive_library_timeout(OAPP, 2, @0x999, 2000, &clock);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EInvalidExpiry)]
fun test_set_receive_library_timeout_with_invalid_timestamp() {
    let (mut scenario, mut manager, blocked_lib_address, _, receive_lib_address) = setup();
    let clock = create_clock_at_time(&mut scenario, 1000);

    // Set default receive library
    manager.set_default_receive_library(2, receive_lib_address, 0, &clock);

    // First set a non-default receive library
    manager.set_receive_library(OAPP, 2, blocked_lib_address, 0, &clock);

    // Try to set expiry in the past - should fail
    manager.set_receive_library_timeout(OAPP, 2, receive_lib_address, 500, &clock);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EOnlyReceiveLib)]
fun test_set_receive_library_timeout_to_send_only_lib() {
    let (mut scenario, mut manager, blocked_lib_address, send_lib_address, receive_lib_address) = setup();
    let clock = create_clock_at_time(&mut scenario, 1000);

    // Set default receive library
    manager.set_default_receive_library(2, receive_lib_address, 0, &clock);

    // Set receive library to send only library
    manager.set_receive_library(OAPP, 2, blocked_lib_address, 0, &clock);

    // Try to set timeout to send only library - should fail
    manager.set_receive_library_timeout(OAPP, 2, send_lib_address, 1000, &clock);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

// === Library Validation Tests ===

#[test]
fun test_is_valid_receive_library_for_default_library() {
    let (mut scenario, mut manager, blocked_lib_address, _, receive_lib_address) = setup();
    let mut clock = create_clock_at_time(&mut scenario, 1000);
    let src_eid = 2u32;

    // Default receive library is RECEIVE_LIB
    manager.set_default_receive_library(src_eid, receive_lib_address, 0, &clock);

    let is_valid = manager.is_valid_receive_library(OAPP, src_eid, receive_lib_address, &clock);
    assert!(is_valid, 0);

    let is_valid_blocked = manager.is_valid_receive_library(OAPP, src_eid, blocked_lib_address, &clock);
    assert!(!is_valid_blocked, 1);

    // Change the default receive library to BLOCKED_LIB with grace period
    set_clock_at_time(&mut clock, 1000);
    manager.set_default_receive_library(src_eid, blocked_lib_address, 500, &clock);

    // Both RECEIVE_LIB and BLOCKED_LIB should be valid before timeout
    let is_valid_old = manager.is_valid_receive_library(OAPP, src_eid, receive_lib_address, &clock);
    let is_valid_new = manager.is_valid_receive_library(OAPP, src_eid, blocked_lib_address, &clock);
    assert!(is_valid_old, 2);
    assert!(is_valid_new, 3);

    // Just reached timeout, only BLOCKED_LIB should be valid
    set_clock_at_time(&mut clock, 1500);
    let is_valid_old_expired = manager.is_valid_receive_library(OAPP, src_eid, receive_lib_address, &clock);
    let is_valid_new_after = manager.is_valid_receive_library(OAPP, src_eid, blocked_lib_address, &clock);
    assert!(!is_valid_old_expired, 4);
    assert!(is_valid_new_after, 5);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

#[test]
fun test_is_valid_receive_library_for_non_default_library() {
    let (mut scenario, mut manager, blocked_lib_address, _, receive_lib_address) = setup();
    let mut clock = create_clock_at_time(&mut scenario, 1000);
    let src_eid = 2u32;

    // Set default library first
    manager.set_default_receive_library(src_eid, receive_lib_address, 0, &clock);

    // OApp sets receive library to different library
    manager.set_receive_library(OAPP, src_eid, blocked_lib_address, 0, &clock);

    // The new library should be valid, but the default library should not
    let is_valid_new = manager.is_valid_receive_library(OAPP, src_eid, blocked_lib_address, &clock);
    assert!(is_valid_new, 0);

    let is_valid_default = manager.is_valid_receive_library(OAPP, src_eid, receive_lib_address, &clock);
    assert!(!is_valid_default, 1);

    // OApp sets timeout for the default library before timeout
    manager.set_receive_library_timeout(OAPP, src_eid, receive_lib_address, 1500, &clock);

    // Both libraries should be valid before timeout
    let is_valid_new_with_timeout = manager.is_valid_receive_library(
        OAPP,
        src_eid,
        blocked_lib_address,
        &clock,
    );
    let is_valid_timeout = manager.is_valid_receive_library(OAPP, src_eid, receive_lib_address, &clock);
    assert!(is_valid_new_with_timeout, 2);
    assert!(is_valid_timeout, 3);

    // After timeout, only new library should be valid
    set_clock_at_time(&mut clock, 1600);
    let is_valid_new_after = manager.is_valid_receive_library(OAPP, src_eid, blocked_lib_address, &clock);
    let is_valid_timeout_expired = manager.is_valid_receive_library(
        OAPP,
        src_eid,
        receive_lib_address,
        &clock,
    );
    assert!(is_valid_new_after, 4);
    assert!(!is_valid_timeout_expired, 5);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EDefaultSendLibUnavailable)]
fun test_assert_send_library_without_default() {
    let (scenario, manager, _, _, _) = setup();
    manager.get_send_library(OAPP, 2);

    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EDefaultReceiveLibUnavailable)]
fun test_assert_receive_library_without_default() {
    let (mut scenario, manager, blocked_lib_address, _, _) = setup();
    let clock = create_clock_at_time(&mut scenario, 0);
    manager.assert_receive_library(OAPP, 2, blocked_lib_address, &clock);

    clock.destroy_for_testing();
    clean(scenario, manager);
}

#[test, expected_failure(abort_code = message_lib_manager::EInvalidReceiveLib)]
fun test_assert_invalid_receive_library() {
    let (mut scenario, mut manager, blocked_lib_address, _, receive_lib_address) = setup();
    let clock = create_clock_at_time(&mut scenario, 0);
    manager.set_default_receive_library(2, receive_lib_address, 0, &clock);
    manager.assert_receive_library(OAPP, 2, blocked_lib_address, &clock);

    clock.destroy_for_testing();
    clean(scenario, manager);
}
