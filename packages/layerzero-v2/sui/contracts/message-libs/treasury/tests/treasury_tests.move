#[test_only]
module treasury::treasury_tests;

use sui::{event, test_scenario::{Self, Scenario}};
use treasury::treasury::{
    Self,
    Treasury,
    AdminCap,
    FeeRecipientSetEvent,
    NativeFeeBpSetEvent,
    ZroFeeSetEvent,
    ZroEnabledSetEvent,
    FeeEnabledSetEvent
};

// === Test Constants ===

const ADMIN: address = @0xa;
const FEE_RECIPIENT: address = @0xfee;

// === Test Helper Functions ===

fun setup_test_environment(): (Scenario, Treasury, AdminCap) {
    let mut scenario = test_scenario::begin(ADMIN);

    treasury::init_for_test(scenario.ctx());
    scenario.next_tx(ADMIN);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let treasury = scenario.take_shared<Treasury>();

    (scenario, treasury, admin_cap)
}

fun cleanup_test_environment(scenario: Scenario, admin_cap: AdminCap, treasury: Treasury) {
    test_scenario::return_shared(treasury);
    scenario.return_to_sender(admin_cap);
    scenario.end();
}

// === Initialization Tests ===

#[test]
fun test_treasury_initialization() {
    let (scenario, treasury, admin_cap) = setup_test_environment();

    // Verify initial state matches EVM defaults
    assert!(treasury.fee_recipient() == @0x0, 0);
    assert!(treasury.native_fee_bp() == 0, 1);
    assert!(treasury.zro_fee() == 0, 2);
    assert!(treasury.zro_enabled() == false, 3);
    assert!(treasury.fee_enabled() == false, 4); // Matches EVM default

    cleanup_test_environment(scenario, admin_cap, treasury);
}

// === Core Fee Logic Tests ===

#[test]
fun test_get_fee_disabled_by_default() {
    let (scenario, treasury, admin_cap) = setup_test_environment();

    // When fee_enabled = false, should return (0, 0) regardless of other settings
    let (native_fee, zro_fee) = treasury.get_fee(1000, false);
    assert!(native_fee == 0, 0);
    assert!(zro_fee == 0, 1);

    let (native_fee, zro_fee) = treasury.get_fee(1000, true);
    assert!(native_fee == 0, 2);
    assert!(zro_fee == 0, 3);

    cleanup_test_environment(scenario, admin_cap, treasury);
}

#[test]
fun test_get_fee_native_payment_enabled() {
    let (scenario, mut treasury, admin_cap) = setup_test_environment();

    // Enable fees and set 5% native fee (500 BPS)
    treasury.set_fee_recipient(&admin_cap, FEE_RECIPIENT);
    treasury.set_fee_enabled(&admin_cap, true);
    treasury.set_native_fee_bp(&admin_cap, 500);

    // Test various amounts
    let (native_fee, zro_fee) = treasury.get_fee(1000, false);
    assert!(native_fee == 50, 0); // 1000 * 500 / 10000 = 50
    assert!(zro_fee == 0, 1);

    let (native_fee, zro_fee) = treasury.get_fee(10000, false);
    assert!(native_fee == 500, 2); // 10000 * 500 / 10000 = 500
    assert!(zro_fee == 0, 3);

    let (native_fee, zro_fee) = treasury.get_fee(0, false);
    assert!(native_fee == 0, 4); // 0 * 500 / 10000 = 0
    assert!(zro_fee == 0, 5);

    cleanup_test_environment(scenario, admin_cap, treasury);
}

#[test]
fun test_get_fee_zro_payment_enabled() {
    let (scenario, mut treasury, admin_cap) = setup_test_environment();
    treasury.set_fee_recipient(&admin_cap, FEE_RECIPIENT);

    // Enable fees, ZRO, and set ZRO fee
    treasury.set_fee_enabled(&admin_cap, true);
    treasury.set_zro_enabled(&admin_cap, true);
    treasury.set_zro_fee(&admin_cap, 1000);

    // Test ZRO payment
    let (native_fee, zro_fee) = treasury.get_fee(5000, true);
    assert!(native_fee == 0, 0);
    assert!(zro_fee == 1000, 1);

    cleanup_test_environment(scenario, admin_cap, treasury);
}

#[test]
#[expected_failure(abort_code = treasury::EZroNotEnabled)]
fun test_get_fee_zro_payment_disabled() {
    let (scenario, mut treasury, admin_cap) = setup_test_environment();
    treasury.set_fee_recipient(&admin_cap, FEE_RECIPIENT);

    // Enable fees but keep ZRO disabled
    treasury.set_fee_enabled(&admin_cap, true);
    // zro_enabled remains false

    // Should fail when trying to pay in ZRO
    treasury.get_fee(1000, true);

    cleanup_test_environment(scenario, admin_cap, treasury);
}

// === Admin Configuration Tests ===

#[test]
fun test_set_fee_enabled() {
    let (scenario, mut treasury, admin_cap) = setup_test_environment();
    treasury.set_fee_recipient(&admin_cap, FEE_RECIPIENT);

    // Initially disabled
    assert!(treasury.fee_enabled() == false, 0);

    // Enable fees
    treasury.set_fee_enabled(&admin_cap, true);
    assert!(treasury.fee_enabled() == true, 1);

    // Disable fees again
    treasury.set_fee_enabled(&admin_cap, false);
    assert!(treasury.fee_enabled() == false, 2);

    // Return objects and check events
    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(treasury);

    // Verify events were emitted
    let events = event::events_by_type<FeeEnabledSetEvent>();
    assert!(events.length() == 2, 3);

    // Check first event: fee_enabled = true
    let expected_event1 = treasury::create_fee_enabled_set_event(true);
    assert!(events[0] == expected_event1, 4);

    // Check second event: fee_enabled = false
    let expected_event2 = treasury::create_fee_enabled_set_event(false);
    assert!(events[1] == expected_event2, 5);

    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = treasury::EInvalidFeeRecipient)]
fun test_set_fee_enabled_without_fee_recipient() {
    let (scenario, mut treasury, admin_cap) = setup_test_environment();
    treasury.set_fee_enabled(&admin_cap, true);
    cleanup_test_environment(scenario, admin_cap, treasury);
}

#[test]
fun test_set_fee_recipient() {
    let (scenario, mut treasury, admin_cap) = setup_test_environment();

    // Set fee recipient
    treasury.set_fee_recipient(&admin_cap, FEE_RECIPIENT);
    assert!(treasury.fee_recipient() == FEE_RECIPIENT, 0);

    // Change fee recipient
    let new_recipient = @0xbeef;
    treasury.set_fee_recipient(&admin_cap, new_recipient);
    assert!(treasury.fee_recipient() == new_recipient, 1);

    // Return objects and check events
    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(treasury);

    // Verify events were emitted
    let events = event::events_by_type<FeeRecipientSetEvent>();
    assert!(events.length() == 2, 2);

    // Check first event: fee_recipient = FEE_RECIPIENT
    let expected_event1 = treasury::create_fee_recipient_set_event(FEE_RECIPIENT);
    assert!(events[0] == expected_event1, 3);

    // Check second event: fee_recipient = new_recipient
    let expected_event2 = treasury::create_fee_recipient_set_event(new_recipient);
    assert!(events[1] == expected_event2, 4);

    test_scenario::end(scenario);
}

#[test]
fun test_set_native_fee_bp() {
    let (scenario, mut treasury, admin_cap) = setup_test_environment();

    // Test valid BPS values
    treasury.set_native_fee_bp(&admin_cap, 0);
    assert!(treasury.native_fee_bp() == 0, 0);

    treasury.set_native_fee_bp(&admin_cap, 500); // 5%
    assert!(treasury.native_fee_bp() == 500, 1);

    treasury.set_native_fee_bp(&admin_cap, 10000); // 100%
    assert!(treasury.native_fee_bp() == 10000, 2);

    // Return objects and check events
    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(treasury);

    // Verify events were emitted
    let events = event::events_by_type<NativeFeeBpSetEvent>();
    assert!(events.length() == 3, 3);

    // Check first event: native_fee_bp = 0
    let expected_event1 = treasury::create_native_fee_bp_set_event(0);
    assert!(events[0] == expected_event1, 4);

    // Check second event: native_fee_bp = 500
    let expected_event2 = treasury::create_native_fee_bp_set_event(500);
    assert!(events[1] == expected_event2, 5);

    // Check third event: native_fee_bp = 10000
    let expected_event3 = treasury::create_native_fee_bp_set_event(10000);
    assert!(events[2] == expected_event3, 6);

    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = treasury::EInvalidNativeFeeBp)]
fun test_set_native_fee_bp_invalid() {
    let (scenario, mut treasury, admin_cap) = setup_test_environment();

    // Should fail with BPS > 10000
    treasury.set_native_fee_bp(&admin_cap, 10001);

    cleanup_test_environment(scenario, admin_cap, treasury);
}

#[test]
#[expected_failure(abort_code = treasury::EInvalidFeeRecipient)]
fun test_set_fee_recipient_zero_address() {
    let (scenario, mut treasury, admin_cap) = setup_test_environment();

    // Should fail when trying to set fee recipient to @0x0
    treasury.set_fee_recipient(&admin_cap, @0x0);

    cleanup_test_environment(scenario, admin_cap, treasury);
}

#[test]
fun test_set_zro_fee() {
    let (scenario, mut treasury, admin_cap) = setup_test_environment();

    // Test various ZRO fee values
    treasury.set_zro_fee(&admin_cap, 0);
    assert!(treasury.zro_fee() == 0, 0);

    treasury.set_zro_fee(&admin_cap, 1000);
    assert!(treasury.zro_fee() == 1000, 1);

    treasury.set_zro_fee(&admin_cap, 18446744073709551615u64); // max u64
    assert!(treasury.zro_fee() == 18446744073709551615u64, 2);

    // Return objects and check events
    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(treasury);

    // Verify events were emitted
    let events = event::events_by_type<ZroFeeSetEvent>();
    assert!(events.length() == 3, 3);

    // Check first event: zro_fee = 0
    let expected_event1 = treasury::create_zro_fee_set_event(0);
    assert!(events[0] == expected_event1, 4);

    // Check second event: zro_fee = 1000
    let expected_event2 = treasury::create_zro_fee_set_event(1000);
    assert!(events[1] == expected_event2, 5);

    // Check third event: zro_fee = max u64
    let expected_event3 = treasury::create_zro_fee_set_event(18446744073709551615u64);
    assert!(events[2] == expected_event3, 6);

    test_scenario::end(scenario);
}

#[test]
fun test_set_zro_enabled() {
    let (scenario, mut treasury, admin_cap) = setup_test_environment();
    treasury.set_fee_recipient(&admin_cap, FEE_RECIPIENT);

    // Initially disabled
    assert!(treasury.zro_enabled() == false, 0);

    // Enable ZRO
    treasury.set_zro_enabled(&admin_cap, true);
    assert!(treasury.zro_enabled() == true, 1);

    // Disable ZRO again
    treasury.set_zro_enabled(&admin_cap, false);
    assert!(treasury.zro_enabled() == false, 2);

    // Return objects and check events
    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(treasury);

    // Verify events were emitted
    let events = event::events_by_type<ZroEnabledSetEvent>();
    assert!(events.length() == 2, 3);

    // Check first event: zro_enabled = true
    let expected_event1 = treasury::create_zro_enabled_set_event(true);
    assert!(events[0] == expected_event1, 4);

    // Check second event: zro_enabled = false
    let expected_event2 = treasury::create_zro_enabled_set_event(false);
    assert!(events[1] == expected_event2, 5);

    test_scenario::end(scenario);
}

// === Edge Cases & Boundary Tests ===

#[test]
fun test_fee_calculation_edge_cases() {
    let (scenario, mut treasury, admin_cap) = setup_test_environment();
    treasury.set_fee_recipient(&admin_cap, FEE_RECIPIENT);

    treasury.set_fee_enabled(&admin_cap, true);

    // Test 0% fee (0 BPS)
    treasury.set_native_fee_bp(&admin_cap, 0);
    let (native_fee, zro_fee) = treasury.get_fee(1000, false);
    assert!(native_fee == 0, 0);
    assert!(zro_fee == 0, 1);

    // Test 100% fee (10000 BPS)
    treasury.set_native_fee_bp(&admin_cap, 10000);
    let (native_fee, zro_fee) = treasury.get_fee(1000, false);
    assert!(native_fee == 1000, 2); // 1000 * 10000 / 10000 = 1000
    assert!(zro_fee == 0, 3);

    // Test maximum total fee with minimal BPS
    let max_safe_input = 18446744073709551615u64 / 10000; // Avoid overflow
    treasury.set_native_fee_bp(&admin_cap, 1); // 0.01%
    let (native_fee, zro_fee) = treasury.get_fee(max_safe_input, false);
    assert!(native_fee == max_safe_input / 10000, 4);
    assert!(zro_fee == 0, 5);

    cleanup_test_environment(scenario, admin_cap, treasury);
}

#[test]
fun test_precision_and_rounding() {
    let (scenario, mut treasury, admin_cap) = setup_test_environment();
    treasury.set_fee_recipient(&admin_cap, FEE_RECIPIENT);

    treasury.set_fee_enabled(&admin_cap, true);
    treasury.set_native_fee_bp(&admin_cap, 1); // 0.01%

    // Test rounding behavior (integer division truncates)
    let (native_fee, zro_fee) = treasury.get_fee(9999, false);
    assert!(native_fee == 0, 0); // 9999 * 1 / 10000 = 0 (rounded down)
    assert!(zro_fee == 0, 1);

    let (native_fee, zro_fee) = treasury.get_fee(10000, false);
    assert!(native_fee == 1, 2); // 10000 * 1 / 10000 = 1
    assert!(zro_fee == 0, 3);

    let (native_fee, zro_fee) = treasury.get_fee(20000, false);
    assert!(native_fee == 2, 4); // 20000 * 1 / 10000 = 2
    assert!(zro_fee == 0, 5);

    cleanup_test_environment(scenario, admin_cap, treasury);
}

// === Integration Tests ===

#[test]
fun test_complete_workflow() {
    let (scenario, mut treasury, admin_cap) = setup_test_environment();
    treasury.set_fee_recipient(&admin_cap, FEE_RECIPIENT);

    // === STEP 1: Initial Configuration ===
    treasury.set_fee_recipient(&admin_cap, FEE_RECIPIENT);
    treasury.set_native_fee_bp(&admin_cap, 250); // 2.5%
    treasury.set_zro_fee(&admin_cap, 500);
    treasury.set_zro_enabled(&admin_cap, true);
    treasury.set_fee_enabled(&admin_cap, true);

    // === STEP 2: Test Native Fee Calculation ===
    let total_worker_fee = 10000;
    let (native_fee, zro_fee) = treasury.get_fee(total_worker_fee, false);
    assert!(native_fee == 250, 0); // 10000 * 250 / 10000 = 250
    assert!(zro_fee == 0, 1);

    // === STEP 3: Test ZRO Fee Calculation ===
    let (native_fee, zro_fee) = treasury.get_fee(total_worker_fee, true);
    assert!(native_fee == 0, 2);
    assert!(zro_fee == 500, 3);

    // === STEP 4: Test Fee Disable ===
    treasury.set_fee_enabled(&admin_cap, false);
    let (native_fee, zro_fee) = treasury.get_fee(total_worker_fee, false);
    assert!(native_fee == 0, 4); // Should return 0 when disabled
    assert!(zro_fee == 0, 5);

    cleanup_test_environment(scenario, admin_cap, treasury);
}

// === View Function Tests ===

#[test]
fun test_view_functions_consistency() {
    let (scenario, mut treasury, admin_cap) = setup_test_environment();

    // Set all configuration values
    let fee_recipient = @0xabcd;
    let native_fee_bp = 750; // 7.5%
    let zro_fee = 2000;
    let zro_enabled = true;
    let fee_enabled = true;

    treasury.set_fee_recipient(&admin_cap, fee_recipient);
    treasury.set_native_fee_bp(&admin_cap, native_fee_bp);
    treasury.set_zro_fee(&admin_cap, zro_fee);
    treasury.set_zro_enabled(&admin_cap, zro_enabled);
    treasury.set_fee_enabled(&admin_cap, fee_enabled);

    // Verify all view functions return correct values
    assert!(treasury.fee_recipient() == fee_recipient, 0);
    assert!(treasury.native_fee_bp() == native_fee_bp, 1);
    assert!(treasury.zro_fee() == zro_fee, 2);
    assert!(treasury.zro_enabled() == zro_enabled, 3);
    assert!(treasury.fee_enabled() == fee_enabled, 4);

    cleanup_test_environment(scenario, admin_cap, treasury);
}
