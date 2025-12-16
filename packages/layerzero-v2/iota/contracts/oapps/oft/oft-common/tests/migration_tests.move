#[test_only]
module oft_common::migration_tests;

use call::call_cap;
use oft_common::migration;
use iota::{bag, balance, coin, test_scenario};

// === Test Constants ===

const ALICE: address = @0xa11ce;

// === Test Phantom Type ===

public struct TestCoin has drop {}

// === Basic Tests ===

#[test]
fun test_create_and_destroy_migration_cap() {
    let mut scenario = test_scenario::begin(ALICE);
    let ctx = test_scenario::ctx(&mut scenario);

    // Create migration capability
    let migration_cap = migration::new_migration_cap(ctx);

    // Destroy the migration capability
    migration_cap.destroy_migration_cap();

    test_scenario::end(scenario);
}

// === Migration Ticket Tests ===

#[test]
fun test_create_and_destroy_migration_ticket() {
    let mut scenario = test_scenario::begin(ALICE);
    let ctx = test_scenario::ctx(&mut scenario);

    // Create migration capability
    let migration_cap = migration::new_migration_cap(ctx);

    // Create test data with escrow (simpler than treasury)
    let oft_cap = call_cap::new_package_cap_for_test(ctx);
    let escrow_balance = balance::create_for_testing<TestCoin>(1000000);
    let extra = bag::new(ctx);

    let oft_cap_id = oft_cap.id();

    // Create migration ticket with escrow (adapter OFT style)
    let migration_ticket = migration::create_migration_ticket(
        &migration_cap,
        oft_cap,
        option::none<coin::TreasuryCap<TestCoin>>(),
        option::some(escrow_balance),
        extra,
    );

    // Destroy migration ticket
    let (
        recovered_oft_cap,
        recovered_treasury_cap,
        recovered_escrow,
        recovered_extra,
    ) = migration::destroy_migration_ticket(migration_ticket, &migration_cap);

    // Verify recovered values
    assert!(recovered_oft_cap.id() == oft_cap_id, 0);
    assert!(option::is_none(&recovered_treasury_cap), 0);
    assert!(option::is_some(&recovered_escrow), 0);

    // Verify escrow balance
    let escrow = option::destroy_some(recovered_escrow);
    assert!(balance::value(&escrow) == 1000000, 0);

    // Clean up resources
    iota::test_utils::destroy(recovered_oft_cap);
    option::destroy_none(recovered_treasury_cap); // Handle the None treasury option
    balance::destroy_for_testing(escrow);
    bag::destroy_empty(recovered_extra);
    migration::destroy_migration_cap(migration_cap);

    test_scenario::end(scenario);
}

#[test]
fun test_migration_ticket_with_extra_data() {
    let mut scenario = test_scenario::begin(ALICE);
    let ctx = test_scenario::ctx(&mut scenario);

    // Create migration capability
    let migration_cap = migration::new_migration_cap(ctx);

    // Create components with extra data
    let oft_cap = call_cap::new_package_cap_for_test(ctx);
    let treasury_cap = coin::create_treasury_cap_for_testing<TestCoin>(ctx);
    let escrow_balance = option::none();

    // Create extra bag with some test data
    let mut extra = bag::new(ctx);
    bag::add(&mut extra, b"version", 1u64);
    bag::add(&mut extra, b"config", b"test_config");

    // Create migration ticket
    let migration_ticket = migration::create_migration_ticket(
        &migration_cap,
        oft_cap,
        option::some(treasury_cap),
        escrow_balance,
        extra,
    );

    // Destroy migration ticket
    let (
        recovered_oft_cap,
        recovered_treasury_cap,
        recovered_escrow,
        mut recovered_extra,
    ) = migration::destroy_migration_ticket(migration_ticket, &migration_cap);

    // Verify extra data was preserved
    assert!(bag::contains(&recovered_extra, b"version"), 0);
    assert!(bag::contains(&recovered_extra, b"config"), 0);

    let version: u64 = bag::remove(&mut recovered_extra, b"version");
    let config: vector<u8> = bag::remove(&mut recovered_extra, b"config");

    assert!(version == 1, 0);
    assert!(config == b"test_config", 0);

    // Clean up resources
    iota::test_utils::destroy(recovered_oft_cap);
    iota::test_utils::destroy(recovered_treasury_cap);
    option::destroy_none(recovered_escrow);
    bag::destroy_empty(recovered_extra);
    migration::destroy_migration_cap(migration_cap);

    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = migration::EEitherTreasuryOrEscrow)]
fun test_migration_ticket_with_both_treasury_and_escrow() {
    let mut scenario = test_scenario::begin(ALICE);
    let ctx = test_scenario::ctx(&mut scenario);

    // Create migration capability
    let migration_cap = migration::new_migration_cap(ctx);

    // Create components with both treasury and escrow
    let oft_cap = call_cap::new_package_cap_for_test(ctx);
    let treasury_cap = coin::create_treasury_cap_for_testing<TestCoin>(ctx);
    let escrow_balance = balance::create_for_testing<TestCoin>(1000000);
    let extra = bag::new(ctx);

    // Should fail to create migration ticket with both treasury and escrow
    let migration_ticket = migration::create_migration_ticket(
        &migration_cap,
        oft_cap,
        option::some(treasury_cap),
        option::some(escrow_balance),
        extra,
    );

    iota::test_utils::destroy(migration_ticket);
    migration::destroy_migration_cap(migration_cap);

    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = migration::EEitherTreasuryOrEscrow)]
fun test_migration_ticket_with_neither_treasury_nor_escrow() {
    let mut scenario = test_scenario::begin(ALICE);
    let ctx = test_scenario::ctx(&mut scenario);

    // Create migration capability
    let migration_cap = migration::new_migration_cap(ctx);

    // Create components with neither treasury nor escrow
    let oft_cap = call_cap::new_package_cap_for_test(ctx);
    let extra = bag::new(ctx);

    // Should fail to create migration ticket with neither treasury nor escrow
    let migration_ticket = migration::create_migration_ticket(
        &migration_cap,
        oft_cap,
        option::none<coin::TreasuryCap<TestCoin>>(),
        option::none(),
        extra,
    );

    iota::test_utils::destroy(migration_ticket);
    migration::destroy_migration_cap(migration_cap);

    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = migration::EInvalidMigrationCap)]
fun test_migration_ticket_with_invalid_migration_cap() {
    let mut scenario = test_scenario::begin(ALICE);
    let ctx = test_scenario::ctx(&mut scenario);

    // Create migration capability
    let migration_cap = migration::new_migration_cap(ctx);

    // Create components with valid migration cap
    let oft_cap = call_cap::new_package_cap_for_test(ctx);
    let treasury_cap = coin::create_treasury_cap_for_testing<TestCoin>(ctx);
    let extra = bag::new(ctx);

    // Create migration ticket with invalid migration cap
    let migration_ticket = migration::create_migration_ticket(
        &migration_cap,
        oft_cap,
        option::some(treasury_cap),
        option::none(),
        extra,
    );

    let fake_migration_cap = migration::new_migration_cap(ctx);
    // Destroy migration ticket
    let (
        recovered_oft_cap,
        recovered_treasury_cap,
        recovered_escrow,
        recovered_extra,
    ) = migration::destroy_migration_ticket(migration_ticket, &fake_migration_cap);

    iota::test_utils::destroy(fake_migration_cap);
    iota::test_utils::destroy(recovered_oft_cap);
    option::destroy_none(recovered_treasury_cap);
    option::destroy_none(recovered_escrow);
    bag::destroy_empty(recovered_extra);
    migration::destroy_migration_cap(migration_cap);

    test_scenario::end(scenario);
}
