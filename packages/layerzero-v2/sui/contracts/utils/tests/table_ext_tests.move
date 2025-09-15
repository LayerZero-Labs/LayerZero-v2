#[test_only]
module utils::table_ext_tests;

use sui::{table::{Self, Table}, test_scenario::{Self as ts, Scenario}};
use utils::table_ext;

const ADMIN: address = @0x0;

fun create_test_table(scenario: &mut Scenario): Table<u64, u64> {
    table::new<u64, u64>(scenario.ctx())
}

#[test]
fun test_table_upsert() {
    let mut scenario = ts::begin(ADMIN);
    let mut test_table = create_test_table(&mut scenario);

    // Insert a new key-value pair
    let mut inserted = table_ext::upsert!(&mut test_table, 1, 100);

    assert!(inserted, 0);
    assert!(test_table.contains(1), 1);
    assert!(test_table.borrow(1) == 100, 2);

    // Update existing key-value pair
    inserted = table_ext::upsert!(&mut test_table, 1, 200);
    assert!(!inserted, 3);
    assert!(test_table.contains(1), 4);
    assert!(test_table.borrow(1) == 200, 5);

    test_table.drop();
    scenario.end();
}

#[test]
fun test_table_remove() {
    let mut scenario = ts::begin(ADMIN);
    let mut test_table = create_test_table(&mut scenario);

    // Add a key first
    test_table.add(1, 100);

    // Remove existing key
    let mut removed = table_ext::try_remove!(&mut test_table, 1);

    // Should return true for successful removal
    assert!(option::some(100) == removed, 0);
    assert!(!test_table.contains(1), 1);

    // Try to remove non-existing key
    removed = table_ext::try_remove!(&mut test_table, 1);

    // Should return false for non-existing key
    assert!(removed.is_none(), 2);

    test_table.destroy_empty();
    scenario.end();
}

#[test]
fun test_table_borrow_with_default() {
    let mut scenario = ts::begin(ADMIN);
    let mut test_table = create_test_table(&mut scenario);

    // Add a key
    test_table.add(1, 100);

    // Get existing key
    let mut value = table_ext::borrow_with_default!(&test_table, 1, &999);

    // Should return the actual value, not default
    assert!(*value == 100, 0);

    // Get non-existing key
    value = table_ext::borrow_with_default!(&test_table, 2, &999);

    // Should return the default value
    assert!(*value == 999, 1);

    test_table.drop();
    scenario.end();
}

#[test]
fun test_table_borrow_mut_with_default() {
    let mut scenario = ts::begin(ADMIN);
    let mut test_table = create_test_table(&mut scenario);

    // Add a key
    test_table.add(1, 100);

    // Get existing key
    let mut value = table_ext::borrow_mut_with_default!(&mut test_table, 1, 999);

    // Should return the actual value, not default
    assert!(*value == 100, 0);

    // Get non-existing key
    value = table_ext::borrow_mut_with_default!(&mut test_table, 2, 999);

    // Should return the default value
    assert!(*value == 999, 1);

    // Update the value
    *value = 200;
    value = table_ext::borrow_mut_with_default!(&mut test_table, 2, 999);
    assert!(*value == 200, 2);

    test_table.drop();
    scenario.end();
}

#[test]
fun test_table_borrow_or_abort() {
    let mut scenario = ts::begin(ADMIN);
    let mut test_table = create_test_table(&mut scenario);

    // Add a key
    test_table.add(1, 100);

    // Borrow existing key - should succeed
    let value = table_ext::borrow_or_abort!(&test_table, 1, 42);
    assert!(*value == 100, 0);

    test_table.drop();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = 42, location = Self)]
fun test_table_borrow_or_abort_fails() {
    let mut scenario = ts::begin(ADMIN);
    let test_table = create_test_table(&mut scenario);

    // Try to borrow non-existing key - should abort with custom error code
    let _value = table_ext::borrow_or_abort!(&test_table, 1, 42);

    test_table.drop();
    scenario.end();
}

#[test]
fun test_table_borrow_mut_or_abort() {
    let mut scenario = ts::begin(ADMIN);
    let mut test_table = create_test_table(&mut scenario);

    // Add a key
    test_table.add(1, 100);

    // Borrow mutable existing key - should succeed
    let value = table_ext::borrow_mut_or_abort!(&mut test_table, 1, 42);
    assert!(*value == 100, 0);

    // Update the value
    *value = 200;

    // Verify the update
    assert!(*test_table.borrow(1) == 200, 1);

    test_table.drop();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = 42, location = Self)]
fun test_table_borrow_mut_or_abort_fails() {
    let mut scenario = ts::begin(ADMIN);
    let mut test_table = create_test_table(&mut scenario);

    // Try to borrow mutable non-existing key - should abort with custom error code
    let _value = table_ext::borrow_mut_or_abort!(&mut test_table, 1, 42);

    test_table.drop();
    scenario.end();
}
