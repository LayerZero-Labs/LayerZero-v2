#[test_only]
module oft::rate_limiter_test;

use oft::rate_limiter;
use std::u64;
use sui::{clock, test_scenario, test_utils};

const ALICE: address = @0xa11ce;
const DST_EID: u32 = 101;
const LIMIT: u64 = 1000;
const WINDOW_SECONDS: u64 = 3600; // 1 hour

#[test]
fun test_rate_limiter_basic_functionality() {
    let mut scenario = test_scenario::begin(ALICE);
    let test_clock = clock::create_for_testing(scenario.ctx());

    // Create rate limiter
    let mut limiter = rate_limiter::create(true, scenario.ctx());

    // Initially no rate limit should be set
    let (limit, window) = limiter.rate_limit_config(DST_EID);
    assert!(limit == 0 && window == 0, 0);

    // Set a rate limit
    limiter.set_rate_limit(DST_EID, LIMIT, WINDOW_SECONDS, &test_clock);

    // Verify rate limit is set
    let (limit, window) = limiter.rate_limit_config(DST_EID);
    assert!(limit == LIMIT, 1);
    assert!(window == WINDOW_SECONDS, 2);

    // Check initial capacity (should be full)
    let capacity = limiter.rate_limit_capacity(DST_EID, &test_clock);
    assert!(capacity == LIMIT, 4);

    // Check initial in-flight (should be zero)
    let in_flight = limiter.in_flight(DST_EID, &test_clock);
    assert!(in_flight == 0, 5);

    // Consume some capacity
    let consume_amount = 300;
    limiter.try_consume_rate_limit_capacity(DST_EID, consume_amount, &test_clock);

    // Check updated capacity and in-flight
    let new_capacity = limiter.rate_limit_capacity(DST_EID, &test_clock);
    let new_in_flight = limiter.in_flight(DST_EID, &test_clock);
    assert!(new_capacity == LIMIT - consume_amount, 6);
    assert!(new_in_flight == consume_amount, 7);

    // Release some capacity
    let release_amount = 100;
    limiter.release_rate_limit_capacity(DST_EID, release_amount, &test_clock);

    let final_capacity = limiter.rate_limit_capacity(DST_EID, &test_clock);
    let final_in_flight = limiter.in_flight(DST_EID, &test_clock);
    assert!(final_capacity == LIMIT - consume_amount + release_amount, 8);
    assert!(final_in_flight == consume_amount - release_amount, 9);

    // Unset rate limit
    limiter.unset_rate_limit(DST_EID);
    let (limit, window) = rate_limiter::rate_limit_config(&limiter, DST_EID);
    assert!(limit == 0 && window == 0, 10);

    // Clean up - objects are automatically destroyed when scenario ends
    clock::destroy_for_testing(test_clock);
    test_utils::destroy(limiter);
    scenario.end();
}

#[test]
fun test_rate_limiter_time_decay() {
    let mut scenario = test_scenario::begin(ALICE);
    let mut test_clock = clock::create_for_testing(scenario.ctx());

    // Create rate limiter
    let mut limiter = rate_limiter::create(true, scenario.ctx());
    let dst_eid = 30100;

    // No rate limit configured
    let (limit, window) = limiter.rate_limit_config(dst_eid);
    assert!(limit == 0 && window == 0, 1);
    assert!(limiter.in_flight(dst_eid, &test_clock) == 0, 1);
    assert!(limiter.rate_limit_capacity(dst_eid, &test_clock) == u64::max_value!(), 2);

    // Set initial clock time to 100 seconds
    test_clock.set_for_testing(100 * 1000); // Convert to milliseconds

    // Configure rate limit (20000 limit, 1000 second window)
    limiter.set_rate_limit(dst_eid, 20000, 1000, &test_clock);
    let (limit, window) = limiter.rate_limit_config(dst_eid);
    assert!(limit == 20000 && window == 1000, 2);

    // consume 100% of the capacity
    limiter.try_consume_rate_limit_capacity(dst_eid, 20000, &test_clock);
    assert!(limiter.in_flight( dst_eid, &test_clock) == 20000, 1);
    assert!(limiter.rate_limit_capacity( dst_eid, &test_clock) == 0, 2);

    // 500 seconds later: in flight should decline by 20000/1000s * 500s = 10000
    test_clock.set_for_testing(600 * 1000); // Convert to milliseconds
    assert!(limiter.in_flight( dst_eid, &test_clock) == 10000, 1);
    assert!(limiter.rate_limit_capacity( dst_eid, &test_clock) == 10000, 2);

    // release most of remaining capacity
    limiter.release_rate_limit_capacity(dst_eid, 9000, &test_clock);
    assert!(limiter.in_flight( dst_eid, &test_clock) == 1000, 1);
    assert!(limiter.rate_limit_capacity( dst_eid, &test_clock) == 19000, 2);

    // consume all of remaining capacity
    limiter.try_consume_rate_limit_capacity(dst_eid, 19000, &test_clock);
    assert!(limiter.in_flight( dst_eid, &test_clock) == 20000, 1);
    assert!(limiter.rate_limit_capacity( dst_eid, &test_clock) == 0, 2);

    // release excess capacity (5x limit) - should not overshoot
    limiter.release_rate_limit_capacity(dst_eid, 100_000, &test_clock);
    assert!(limiter.in_flight( dst_eid, &test_clock) == 0, 1);
    assert!(limiter.rate_limit_capacity( dst_eid, &test_clock) == 20000, 2);

    // Clean up
    test_utils::destroy(test_clock);
    test_utils::destroy(limiter);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = oft::rate_limiter::EExceededRateLimit)]
fun test_rate_limiter_capacity_exceeded() {
    let mut scenario = test_scenario::begin(ALICE);
    let test_clock = clock::create_for_testing(scenario.ctx());

    // Create rate limiter limiter and set rate limit
    let mut limiter = rate_limiter::create(true, scenario.ctx());
    limiter.set_rate_limit(DST_EID, LIMIT, WINDOW_SECONDS, &test_clock);

    // Try to consume more than the limit - should fail
    limiter.try_consume_rate_limit_capacity(DST_EID, LIMIT + 1, &test_clock);

    // Clean up (won't be reached due to expected failure)
    clock::destroy_for_testing(test_clock);
    test_utils::destroy(limiter);
    scenario.end();
}
