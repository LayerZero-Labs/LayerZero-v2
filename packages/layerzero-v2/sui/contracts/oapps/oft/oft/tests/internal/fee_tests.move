/// Unit tests for the SendFee extension module.
///
/// This test module covers:
/// - SendFee creation and initialization
/// - Fee calculation and application logic
/// - Setter and getter functionality
/// - Fee validation (valid/invalid fee_bps)
/// - Edge cases and precision testing
/// - Error conditions
/// - EID-specific fee configuration
/// - Enable/disable fee mechanism
#[test_only]
module oft::fee_tests;

use oft::oft_fee::{Self, OFTFee};
use sui::test_utils;

// === Test Constants ===

const ALICE: address = @0xa11ce;
const BOB: address = @0xb0b;

// Send Fee test constants
const VALID_FEE_BPS: u64 = 250; // 2.5%
const MAX_FEE_BPS: u64 = 10_000; // 100%
const INVALID_FEE_BPS: u64 = 10_001; // > 100%

// Destination endpoint IDs for testing
const DST_EID_1: u32 = 101;
const DST_EID_2: u32 = 102;
const DST_EID_3: u32 = 103;

// === Error Codes ===

const E_INVALID_FEE_BPS: u64 = 0;
const E_INVALID_FEE_AMOUNT: u64 = 1;
const E_INVALID_FEE_DEPOSIT_ADDRESS: u64 = 2;

// === Send Fee Creation Tests ===

#[test]
fun test_create_send_fee_valid() {
    let fee_bps = VALID_FEE_BPS;
    let fee_deposit_address = BOB;

    let fee = create_fee(fee_bps, fee_deposit_address, DST_EID_1);

    assert!(oft_fee::fee_bps(&fee, DST_EID_1) == fee_bps, E_INVALID_FEE_BPS);
    assert!(oft_fee::fee_deposit_address(&fee) == fee_deposit_address, E_INVALID_FEE_DEPOSIT_ADDRESS);

    test_utils::destroy(fee);
}

#[test]
fun test_create_send_fee_max_fee() {
    let fee_bps = MAX_FEE_BPS;
    let fee_deposit_address = BOB;

    let fee = create_fee(fee_bps, fee_deposit_address, DST_EID_1);

    assert!(oft_fee::fee_bps(&fee, DST_EID_1) == MAX_FEE_BPS, E_INVALID_FEE_BPS);
    assert!(oft_fee::fee_deposit_address(&fee) == fee_deposit_address, E_INVALID_FEE_DEPOSIT_ADDRESS);

    test_utils::destroy(fee);
}

#[test]
#[expected_failure(abort_code = oft_fee::EInvalidFeeBps)]
fun test_create_send_fee_invalid_fee_bps() {
    let fee_bps = INVALID_FEE_BPS;
    let fee_deposit_address = BOB;

    let fee = create_fee(fee_bps, fee_deposit_address, DST_EID_1);

    test_utils::destroy(fee);
}

// === Fee Calculation Tests ===

#[test]
fun test_apply_fee_basic() {
    let fee_bps = VALID_FEE_BPS; // 2.5%
    let fee = create_fee(fee_bps, BOB, DST_EID_1);

    // Test with 1000 units
    let amount_ld = 1000u64;
    let expected_after_fee = 975u64; // 1000 - (1000 * 250 / 10000) = 1000 - 25 = 975

    let actual_after_fee = oft_fee::apply_fee(&fee, DST_EID_1, amount_ld);
    assert!(actual_after_fee == expected_after_fee, E_INVALID_FEE_AMOUNT);

    test_utils::destroy(fee);
}

#[test]
fun test_apply_fee_zero_amount() {
    let fee_bps = VALID_FEE_BPS;
    let fee = create_fee(fee_bps, BOB, DST_EID_1);

    let amount_ld = 0u64;
    let expected_after_fee = 0u64;

    let actual_after_fee = oft_fee::apply_fee(&fee, DST_EID_1, amount_ld);
    assert!(actual_after_fee == expected_after_fee, E_INVALID_FEE_AMOUNT);

    test_utils::destroy(fee);
}

#[test]
fun test_apply_fee_max_fee_rate() {
    let fee_bps = MAX_FEE_BPS; // 100%
    let fee = create_fee(fee_bps, BOB, DST_EID_1);

    let amount_ld = 1000u64;
    let expected_after_fee = 0u64; // 100% fee means nothing left

    let actual_after_fee = oft_fee::apply_fee(&fee, DST_EID_1, amount_ld);
    assert!(actual_after_fee == expected_after_fee, E_INVALID_FEE_AMOUNT);

    test_utils::destroy(fee);
}

#[test]
fun test_apply_fee_large_amounts() {
    let fee_bps = VALID_FEE_BPS; // 2.5%
    let fee = create_fee(fee_bps, BOB, DST_EID_1);

    // Test with large amount
    let amount_ld = 1000000000u64; // 1 billion
    let fee_amount = (((amount_ld as u128) * (fee_bps as u128)) / 10_000) as u64;
    let expected_after_fee = amount_ld - fee_amount;

    let actual_after_fee = oft_fee::apply_fee(&fee, DST_EID_1, amount_ld);
    assert!(actual_after_fee == expected_after_fee, E_INVALID_FEE_AMOUNT);

    test_utils::destroy(fee);
}

// === Setter and Getter Tests ===

#[test]
fun test_set_fee_bps_valid() {
    let mut fee = create_fee(VALID_FEE_BPS, BOB, DST_EID_1);
    let new_fee_bps = 500u64; // 5%

    oft_fee::set_fee_bps(&mut fee, DST_EID_1, new_fee_bps);

    assert!(oft_fee::fee_bps(&fee, DST_EID_1) == new_fee_bps, E_INVALID_FEE_BPS);

    test_utils::destroy(fee);
}

#[test]
fun test_set_fee_bps_zero() {
    let mut fee = create_fee(VALID_FEE_BPS, BOB, DST_EID_1);
    let new_fee_bps = 0u64;

    oft_fee::set_fee_bps(&mut fee, DST_EID_1, new_fee_bps);

    assert!(oft_fee::fee_bps(&fee, DST_EID_1) == new_fee_bps, E_INVALID_FEE_BPS);

    test_utils::destroy(fee);
}

#[test]
fun test_set_fee_bps_max() {
    let mut fee = create_fee(VALID_FEE_BPS, BOB, DST_EID_1);
    let new_fee_bps = MAX_FEE_BPS;

    oft_fee::set_fee_bps(&mut fee, DST_EID_1, new_fee_bps);

    assert!(oft_fee::fee_bps(&fee, DST_EID_1) == new_fee_bps, E_INVALID_FEE_BPS);

    test_utils::destroy(fee);
}

#[test]
#[expected_failure(abort_code = oft_fee::EInvalidFeeBps)]
fun test_set_fee_bps_invalid() {
    let mut fee = create_fee(VALID_FEE_BPS, BOB, DST_EID_1);

    // This should fail because fee_bps > MAX_FEE_BPS
    oft_fee::set_fee_bps(&mut fee, DST_EID_1, INVALID_FEE_BPS);

    test_utils::destroy(fee);
}

#[test]
fun test_set_fee_deposit_address() {
    let mut fee = create_fee(VALID_FEE_BPS, BOB, DST_EID_1);
    let new_address = ALICE;

    oft_fee::set_fee_deposit_address(&mut fee, new_address);

    assert!(oft_fee::fee_deposit_address(&fee) == new_address, E_INVALID_FEE_DEPOSIT_ADDRESS);

    test_utils::destroy(fee);
}

#[test]
fun test_getter_functions() {
    let fee_bps = 1500u64; // 15%
    let fee_deposit_address = ALICE;
    let fee = create_fee(fee_bps, fee_deposit_address, DST_EID_1);

    // Test getter functions
    assert!(oft_fee::fee_bps(&fee, DST_EID_1) == fee_bps, E_INVALID_FEE_BPS);
    assert!(oft_fee::fee_deposit_address(&fee) == fee_deposit_address, E_INVALID_FEE_DEPOSIT_ADDRESS);

    test_utils::destroy(fee);
}

// === Edge Cases and Precision Tests ===

#[test]
fun test_fee_calculations_precision() {
    // Test various fee rates for precision
    let test_amounts = vector[1u64, 10u64, 100u64, 999u64, 1000u64, 10000u64];
    let test_fee_rates = vector[1u64, 10u64, 100u64, 1000u64, 5000u64]; // 0.01%, 0.1%, 1%, 10%, 50%

    let mut i = 0;
    while (i < test_amounts.length()) {
        let amount = *test_amounts.borrow(i);

        let mut j = 0;
        while (j < test_fee_rates.length()) {
            let fee_bps = *test_fee_rates.borrow(j);
            let fee = create_fee(fee_bps, BOB, DST_EID_1);

            let result = oft_fee::apply_fee(&fee, DST_EID_1, amount);
            let expected_fee = (((amount as u128) * (fee_bps as u128)) / 10_000) as u64;
            let expected_result = amount - expected_fee;

            assert!(result == expected_result, E_INVALID_FEE_AMOUNT);

            test_utils::destroy(fee);
            j = j + 1;
        };

        i = i + 1;
    };
}

#[test]
fun test_fee_calculations_edge_values() {
    // Test edge case values for fee calculations
    // Use different EIDs for different fee rates to avoid conflicts
    let fee_1bp = create_fee(1u64, BOB, DST_EID_1); // 0.01% for DST_EID_1
    let fee_9999bp = create_fee(9999u64, BOB, DST_EID_2); // 99.99% for DST_EID_2

    // Test with minimum non-zero amount
    let min_amount = 1u64;
    let result_1bp = oft_fee::apply_fee(&fee_1bp, DST_EID_1, min_amount);
    let result_9999bp = oft_fee::apply_fee(&fee_9999bp, DST_EID_2, min_amount);

    // For 1 unit with 0.01% fee: fee = 0 (rounded down), so result = 1
    assert!(result_1bp == 1, E_INVALID_FEE_AMOUNT);
    // For 1 unit with 99.99% fee: fee = 0 (rounded down), so result = 1
    assert!(result_9999bp == 1, E_INVALID_FEE_AMOUNT);

    // Test with larger amounts where rounding matters
    let large_amount = 10000u64;
    let result_1bp_large = oft_fee::apply_fee(&fee_1bp, DST_EID_1, large_amount);
    let result_9999bp_large = oft_fee::apply_fee(&fee_9999bp, DST_EID_2, large_amount);

    // For 10000 units with 0.01% fee: fee = 1, so result = 9999
    assert!(result_1bp_large == 9999, E_INVALID_FEE_AMOUNT);
    // For 10000 units with 99.99% fee: fee = 9999, so result = 1
    assert!(result_9999bp_large == 1, E_INVALID_FEE_AMOUNT);

    test_utils::destroy(fee_1bp);
    test_utils::destroy(fee_9999bp);
}

// === New Tests for EID-specific and Enable/Disable Features ===

#[test]
fun test_eid_specific_fees() {
    let mut ctx = tx_context::dummy();
    let mut fee = oft_fee::new(&mut ctx);
    oft_fee::set_fee_deposit_address(&mut fee, BOB);

    // Set different fees for different destinations
    let fee_bps_1 = 100u64; // 1% for DST_EID_1
    let fee_bps_2 = 200u64; // 2% for DST_EID_2
    let default_fee = 50u64; // 0.5% default

    // Set default fee
    oft_fee::set_default_fee_bps(&mut fee, default_fee);

    // Set specific fees for different destinations
    oft_fee::set_fee_bps(&mut fee, DST_EID_1, fee_bps_1);
    oft_fee::set_fee_bps(&mut fee, DST_EID_2, fee_bps_2);

    // Test that each destination has its own fee
    assert!(oft_fee::fee_bps(&fee, DST_EID_1) == fee_bps_1, E_INVALID_FEE_BPS);
    assert!(oft_fee::fee_bps(&fee, DST_EID_2) == fee_bps_2, E_INVALID_FEE_BPS);
    assert!(oft_fee::effective_fee_bps(&fee, DST_EID_3) == default_fee, E_INVALID_FEE_BPS); // Uses default

    // Test fee application for different destinations
    let amount = 1000u64;
    let result_1 = oft_fee::apply_fee(&fee, DST_EID_1, amount);
    let result_2 = oft_fee::apply_fee(&fee, DST_EID_2, amount);
    let result_3 = oft_fee::apply_fee(&fee, DST_EID_3, amount);

    assert!(result_1 == 990u64, E_INVALID_FEE_AMOUNT); // 1000 - 10 (1%)
    assert!(result_2 == 980u64, E_INVALID_FEE_AMOUNT); // 1000 - 20 (2%)
    assert!(result_3 == 995u64, E_INVALID_FEE_AMOUNT); // 1000 - 5 (0.5%)

    test_utils::destroy(fee);
}

#[test]
fun test_fee_enable_disable() {
    let mut ctx = tx_context::dummy();
    let mut fee = oft_fee::new(&mut ctx);
    oft_fee::set_fee_deposit_address(&mut fee, BOB);

    let specific_fee = 300u64; // 3%
    let default_fee = 100u64; // 1%

    // Set default fee
    oft_fee::set_default_fee_bps(&mut fee, default_fee);

    // Set specific fee for DST_EID_1 (enabled)
    oft_fee::set_fee_bps(&mut fee, DST_EID_1, specific_fee);

    // Verify enabled fee is used
    assert!(oft_fee::fee_bps(&fee, DST_EID_1) == specific_fee, E_INVALID_FEE_BPS);
    assert!(oft_fee::has_oft_fee(&fee, DST_EID_1), 0);

    // Unset the specific fee (should fall back to default)
    oft_fee::unset_fee_bps(&mut fee, DST_EID_1);

    // Verify default fee is now used
    assert!(oft_fee::effective_fee_bps(&fee, DST_EID_1) == default_fee, E_INVALID_FEE_BPS);
    assert!(oft_fee::has_oft_fee(&fee, DST_EID_1), 1); // Still has fee (default)

    // Test with actual amounts
    let amount = 1000u64;
    let result_disabled = oft_fee::apply_fee(&fee, DST_EID_1, amount);
    assert!(result_disabled == 990u64, E_INVALID_FEE_AMOUNT); // Uses default: 1000 - 10 (1%)

    // Re-enable the specific fee
    oft_fee::set_fee_bps(&mut fee, DST_EID_1, specific_fee);
    let result_enabled = oft_fee::apply_fee(&fee, DST_EID_1, amount);
    assert!(result_enabled == 970u64, E_INVALID_FEE_AMOUNT); // Uses specific: 1000 - 30 (3%)

    // Test destination with no specific fee (uses default)
    assert!(oft_fee::effective_fee_bps(&fee, DST_EID_2) == default_fee, E_INVALID_FEE_BPS);

    // Set default to 0 and verify destinations without specific fees have no fee
    oft_fee::set_default_fee_bps(&mut fee, 0);
    assert!(oft_fee::effective_fee_bps(&fee, DST_EID_2) == 0, E_INVALID_FEE_BPS);
    assert!(!oft_fee::has_oft_fee(&fee, DST_EID_2), 2); // No fee

    test_utils::destroy(fee);
}

// === Unset Fee Tests ===

#[test]
fun test_unset_fee_bps_valid() {
    let mut ctx = tx_context::dummy();
    let mut fee = oft_fee::new(&mut ctx);
    oft_fee::set_fee_deposit_address(&mut fee, BOB);

    let specific_fee = 300u64; // 3%
    let default_fee = 100u64; // 1%

    // Set default fee
    oft_fee::set_default_fee_bps(&mut fee, default_fee);

    // Set specific fee for DST_EID_1
    oft_fee::set_fee_bps(&mut fee, DST_EID_1, specific_fee);

    // Verify specific fee is set
    assert!(oft_fee::fee_bps(&fee, DST_EID_1) == specific_fee, E_INVALID_FEE_BPS);

    // Remove the specific fee
    oft_fee::unset_fee_bps(&mut fee, DST_EID_1);

    // Verify it now uses default fee
    assert!(oft_fee::effective_fee_bps(&fee, DST_EID_1) == default_fee, E_INVALID_FEE_BPS);

    // Test fee calculation with default fee
    let amount = 1000u64;
    let result = oft_fee::apply_fee(&fee, DST_EID_1, amount);
    assert!(result == 990u64, E_INVALID_FEE_AMOUNT); // 1000 - 10 (1% default)

    test_utils::destroy(fee);
}

#[test]
#[expected_failure(abort_code = oft_fee::ENotFound)]
fun test_unset_fee_bps_not_found() {
    let mut ctx = tx_context::dummy();
    let mut fee = oft_fee::new(&mut ctx);
    oft_fee::set_fee_deposit_address(&mut fee, BOB);

    // Try to remove fee for destination that doesn't have specific fee set
    // This should fail with ENotFound
    oft_fee::unset_fee_bps(&mut fee, DST_EID_1);

    test_utils::destroy(fee);
}

#[test]
fun test_unset_fee_bps_with_zero_default() {
    let mut ctx = tx_context::dummy();
    let mut fee = oft_fee::new(&mut ctx);
    oft_fee::set_fee_deposit_address(&mut fee, BOB);

    let specific_fee = 500u64; // 5%
    // Default fee is 0 (no fees by default)

    // Set specific fee for DST_EID_1
    oft_fee::set_fee_bps(&mut fee, DST_EID_1, specific_fee);

    // Verify specific fee is set
    assert!(oft_fee::fee_bps(&fee, DST_EID_1) == specific_fee, E_INVALID_FEE_BPS);
    assert!(oft_fee::has_oft_fee(&fee, DST_EID_1), 0); // Has fee

    // Remove the specific fee
    oft_fee::unset_fee_bps(&mut fee, DST_EID_1);

    // Verify it now uses default fee (0)
    assert!(oft_fee::effective_fee_bps(&fee, DST_EID_1) == 0, E_INVALID_FEE_BPS);
    assert!(!oft_fee::has_oft_fee(&fee, DST_EID_1), 1); // No fee

    test_utils::destroy(fee);
}

// === Helper ===

fun create_fee(fee_bps: u64, fee_deposit_address: address, dst_eid: u32): OFTFee {
    let mut ctx = tx_context::dummy();
    let mut fee = oft_fee::new(&mut ctx);
    oft_fee::set_fee_bps(&mut fee, dst_eid, fee_bps);
    oft_fee::set_fee_deposit_address(&mut fee, fee_deposit_address);
    fee
}
