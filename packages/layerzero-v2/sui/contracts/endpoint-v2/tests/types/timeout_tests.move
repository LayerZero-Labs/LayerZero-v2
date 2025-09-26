#[test_only]
module endpoint_v2::timeout_tests;

use endpoint_v2::timeout;
use sui::{clock::{Self, Clock}, test_scenario::{Self as ts, Scenario}};

const SENDER: address = @0x0;
const TEST_LIB: address = @0x123;

fun create_clock_at_time(scenario: &mut Scenario, seconds: u64): Clock {
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(seconds * 1000);
    clock
}

#[test]
fun test_create_timeout() {
    let expiry = 1000u64;
    let lib = TEST_LIB;

    let timeout = timeout::create(expiry, lib);

    assert!(timeout.expiry() == expiry, 0);
    assert!(timeout.fallback_lib() == lib, 1);
}

#[test]
fun test_is_expired_before_expiry() {
    let mut scenario = ts::begin(SENDER);

    let timeout = timeout::create(1000, TEST_LIB);
    let clock = create_clock_at_time(&mut scenario, 500); // Before expiry

    assert!(!timeout.is_expired(&clock), 0);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_is_expired_at_expiry() {
    let mut scenario = ts::begin(SENDER);

    let timeout = timeout::create(1000, TEST_LIB);
    let clock = create_clock_at_time(&mut scenario, 1000); // Exactly at expiry

    assert!(timeout.is_expired(&clock), 0);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_is_expired_after_expiry() {
    let mut scenario = ts::begin(SENDER);

    let timeout = timeout::create(1000, TEST_LIB);
    let clock = create_clock_at_time(&mut scenario, 1500); // After expiry

    assert!(timeout.is_expired(&clock), 0);

    clock.destroy_for_testing();
    scenario.end();
}
