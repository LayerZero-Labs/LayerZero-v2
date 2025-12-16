#[test_only]
module worker_registry::worker_registry_tests;

use call::call_cap;
use iota::{event, test_scenario::{Self as ts, Scenario}, test_utils};
use worker_registry::worker_registry::{Self, WorkerRegistry, WorkerInfoSetEvent};

// === Test Constants ===

const ADMIN: address = @0x0;

// === Test Data ===

fun create_test_worker_info(): vector<u8> {
    b"worker_info_v1_test_data"
}

fun create_updated_worker_info(): vector<u8> {
    b"worker_info_v2_updated_data"
}

// === Helper Functions ===

fun setup(): (Scenario, WorkerRegistry) {
    let mut scenario = ts::begin(ADMIN);
    let registry = worker_registry::init_for_test(scenario.ctx());
    (scenario, registry)
}

fun clean(scenario: Scenario, registry: WorkerRegistry) {
    test_utils::destroy(registry);
    ts::end(scenario);
}

// === Tests ===

#[test]
fun test_set_worker_info_new_worker() {
    let (mut scenario, mut registry) = setup();
    let worker_info = create_test_worker_info();

    // Create a call cap for the worker
    let worker_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let worker_address = worker_cap.id();

    // Set worker info
    registry.set_worker_info(&worker_cap, worker_info);

    // Verify WorkerInfoSetEvent was emitted
    let expected_event = worker_registry::create_worker_info_set_event(worker_address, worker_info);
    test_utils::assert_eq(event::events_by_type<WorkerInfoSetEvent>()[0], expected_event);

    // Verify worker info was set
    assert!(*registry.get_worker_info(worker_address) == worker_info, 0);

    test_utils::destroy(worker_cap);
    clean(scenario, registry);
}

#[test]
fun test_set_worker_info_update_existing() {
    let (mut scenario, mut registry) = setup();
    let initial_info = create_test_worker_info();
    let updated_info = create_updated_worker_info();

    // Create a call cap for the worker
    let worker_cap = call_cap::new_package_cap_for_test(scenario.ctx());
    let worker_address = worker_cap.id();

    // Set initial worker info
    registry.set_worker_info(&worker_cap, initial_info);

    // Update worker info
    registry.set_worker_info(&worker_cap, updated_info);

    // Verify two WorkerInfoSetEvents were emitted
    let events = event::events_by_type<WorkerInfoSetEvent>();
    assert!(events.length() == 2, 0);

    // Check first event
    let expected_event1 = worker_registry::create_worker_info_set_event(worker_address, initial_info);
    test_utils::assert_eq(events[0], expected_event1);

    // Check second event (update)
    let expected_event2 = worker_registry::create_worker_info_set_event(worker_address, updated_info);
    test_utils::assert_eq(events[1], expected_event2);

    // Verify worker info was updated
    assert!(*registry.get_worker_info(worker_address) == updated_info, 0);

    test_utils::destroy(worker_cap);
    clean(scenario, registry);
}

#[test]
fun test_set_worker_info_multiple_workers() {
    let (mut scenario, mut registry) = setup();
    let worker_info_1 = create_test_worker_info();
    let worker_info_2 = create_updated_worker_info();

    // Create call caps for two different workers
    let worker_cap_1 = call_cap::new_package_cap_for_test(scenario.ctx());
    let worker_cap_2 = call_cap::new_package_cap_for_test(scenario.ctx());
    let worker_address_1 = worker_cap_1.id();
    let worker_address_2 = worker_cap_2.id();

    // Set worker info for both workers
    registry.set_worker_info(&worker_cap_1, worker_info_1);
    registry.set_worker_info(&worker_cap_2, worker_info_2);

    // Verify two WorkerInfoSetEvents were emitted
    let events = event::events_by_type<WorkerInfoSetEvent>();
    assert!(events.length() == 2, 0);

    // Check events for both workers
    let expected_event1 = worker_registry::create_worker_info_set_event(worker_address_1, worker_info_1);
    let expected_event2 = worker_registry::create_worker_info_set_event(worker_address_2, worker_info_2);
    test_utils::assert_eq(events[0], expected_event1);
    test_utils::assert_eq(events[1], expected_event2);

    // Verify worker info was set
    assert!(*registry.get_worker_info(worker_address_1) == worker_info_1, 0);
    assert!(*registry.get_worker_info(worker_address_2) == worker_info_2, 1);

    test_utils::destroy(worker_cap_1);
    test_utils::destroy(worker_cap_2);
    clean(scenario, registry);
}

#[test]
#[expected_failure(abort_code = worker_registry::EWorkerInfoInvalid)]
fun test_set_worker_info_empty_data() {
    let (mut scenario, mut registry) = setup();
    let empty_info = b""; // Empty worker info

    // Create a call cap for the worker
    let worker_cap = call_cap::new_individual_cap(scenario.ctx());
    let worker_address = worker_cap.id();

    // Set empty worker info (should be allowed)
    registry.set_worker_info(&worker_cap, empty_info);

    // Verify WorkerInfoSetEvent was emitted with empty data
    let expected_event = worker_registry::create_worker_info_set_event(worker_address, empty_info);
    test_utils::assert_eq(event::events_by_type<WorkerInfoSetEvent>()[0], expected_event);

    // Verify worker info was set
    assert!(*registry.get_worker_info(worker_address) == empty_info, 0);

    test_utils::destroy(worker_cap);
    clean(scenario, registry);
}

#[test]
#[expected_failure(abort_code = worker_registry::EWorkerInfoNotFound)]
fun test_get_worker_info_not_found() {
    let (scenario, registry) = setup();
    let worker_address = @0x1;

    // Try to get worker info for unregistered worker
    registry.get_worker_info(worker_address);

    clean(scenario, registry);
}
