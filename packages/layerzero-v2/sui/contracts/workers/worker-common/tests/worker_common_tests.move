#[test_only]
module worker_common::worker_common_tests;

use sui::{event, test_scenario::{Self as ts, Scenario}, test_utils};
use worker_common::worker_common::{
    Self,
    Worker,
    OwnerCap,
    AdminCap,
    EWorkerAdminAlreadyExists,
    EWorkerAdminNotFound,
    EWorkerAttemptingToRemoveOnlyAdmin,
    EWorkerUnauthorized,
    EWorkerAlreadyOnAllowlist,
    EWorkerNotOnAllowlist,
    EWorkerAlreadyOnDenylist,
    EWorkerNotOnDenylist,
    EWorkerMessageLibAlreadySupported,
    EWorkerMessageLibNotSupported,
    EWorkerNotAllowed,
    EWorkerIsPaused,
    EWorkerNoAdminsProvided,
    EWorkerPauseStatusUnchanged
};

// === Test Constants ===

const ADMIN: address = @0xa;
const USER1: address = @0x1;
const USER2: address = @0x2;
const USER3: address = @0x3;
const DEPOSIT_ADDR: address = @0xdead;
const PRICE_FEED_ADDR: address = @0xfeed;
const WORKER_FEE_LIB_ADDR: address = @0xfee;
const MESSAGE_LIB_ADDR: address = @0x333;

// === Helper Functions ===

fun setup(): ts::Scenario {
    ts::begin(ADMIN)
}

fun clean(scenario: ts::Scenario) {
    ts::end(scenario);
}

fun create_test_worker(scenario: &mut Scenario): (Worker, OwnerCap) {
    let admins = vector[ADMIN];
    let supported_message_libs = vector[]; // Empty supported message libs for test
    let worker_cap = call::call_cap::new_package_cap_for_test(scenario.ctx());
    worker_common::create_worker(
        worker_cap,
        DEPOSIT_ADDR,
        supported_message_libs,
        PRICE_FEED_ADDR,
        WORKER_FEE_LIB_ADDR,
        1000u16, // 10% multiplier
        admins,
        scenario.ctx(),
    )
}

fun create_test_worker_with_admin(scenario: &mut Scenario): (Worker, OwnerCap, AdminCap) {
    let (worker, owner_cap) = create_test_worker(scenario);
    scenario.next_tx(ADMIN);
    let admin_cap = ts::take_from_sender<AdminCap>(scenario);
    (worker, owner_cap, admin_cap)
}

// === Worker Creation Tests ===

#[test]
#[allow(implicit_const_copy)]
fun test_create_worker() {
    let mut scenario = setup();

    let (worker, owner_cap, admin_cap) = create_test_worker_with_admin(&mut scenario);

    // Verify initial state
    assert!(worker.deposit_address() == DEPOSIT_ADDR, 1);
    assert!(worker.price_feed() == PRICE_FEED_ADDR, 2);
    assert!(worker.worker_fee_lib() == WORKER_FEE_LIB_ADDR, 3);
    assert!(worker.default_multiplier_bps() == 1000u16, 4);
    assert!(!worker.is_paused(), 5);

    // Verify admins are set correctly
    assert!(worker.is_admin(&admin_cap), 6);
    let user1_cap = worker_common::create_admin_cap_for_test(scenario.ctx());
    let user2_cap = worker_common::create_admin_cap_for_test(scenario.ctx());
    assert!(!worker.is_admin(&user1_cap), 7);
    assert!(!worker.is_admin(&user2_cap), 8);
    test_utils::destroy(user1_cap);
    test_utils::destroy(user2_cap);
    ts::return_to_sender(&scenario, admin_cap);

    // Verify admins function returns correct admin set
    let admin_set = worker.admins();
    assert!(admin_set.contains(&ADMIN), 9);
    assert!(!admin_set.contains(&USER1), 10);
    assert!(admin_set.size() == 1, 11);

    // Verify empty lists initially
    assert!(worker.allowlist_size() == 0, 12);
    assert!(!worker.is_on_allowlist(USER1), 13);
    assert!(!worker.is_on_denylist(USER1), 14);

    // Verify worker capability
    assert!(worker.worker_cap_address() != @0x0, 15);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
fun test_create_worker_basic() {
    let mut scenario = setup();

    let admins = vector[ADMIN];
    let supported_message_libs = vector[]; // Empty supported message libs for test
    let worker_cap = call::call_cap::new_package_cap_for_test(scenario.ctx());
    let (worker, owner_cap) = worker_common::create_worker(
        worker_cap,
        DEPOSIT_ADDR,
        supported_message_libs,
        PRICE_FEED_ADDR,
        WORKER_FEE_LIB_ADDR,
        500u16,
        admins,
        scenario.ctx(),
    );

    // OwnerCap is always created now
    scenario.next_tx(ADMIN);
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    assert!(worker.is_admin(&admin_cap), 1);
    ts::return_to_sender(&scenario, admin_cap);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerNoAdminsProvided)]
fun test_create_worker_with_empty_admins() {
    let mut scenario = setup();

    let empty_admins = vector::empty<address>();
    let supported_message_libs = vector[]; // Empty supported message libs for test
    let worker_cap = call::call_cap::new_package_cap_for_test(scenario.ctx());
    let (worker, owner_cap) = worker_common::create_worker(
        worker_cap,
        DEPOSIT_ADDR,
        supported_message_libs,
        PRICE_FEED_ADDR,
        WORKER_FEE_LIB_ADDR,
        1000u16,
        empty_admins,
        scenario.ctx(),
    );

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

// === Admin Management Tests ===

#[test]
#[allow(implicit_const_copy)]
fun test_set_admin() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Initially USER1 is not an admin
    assert!(!worker.is_admin_address(USER1), 2);

    // Add USER1 as admin
    worker.set_admin(&owner_cap, USER1, true, scenario.ctx());

    // Verify USER1 is now an admin
    assert!(worker.is_admin_address(USER1), 3);

    // Verify admins function reflects the change
    let admin_set = worker.admins();
    assert!(admin_set.contains(&ADMIN), 4);
    assert!(admin_set.contains(&USER1), 5);
    assert!(admin_set.size() == 2, 6);

    // Verify SetAdminEvent was emitted
    let expected_add_event = worker_common::create_set_admin_event(&worker, USER1, true);
    test_utils::assert_eq(event::events_by_type<worker_common::SetAdminEvent>()[1], expected_add_event);

    // Remove USER1 as admin
    worker.set_admin(&owner_cap, USER1, false, scenario.ctx());

    // Verify USER1 is no longer an admin
    assert!(!worker.is_admin_address(USER1), 7);

    // Verify admins function reflects the removal
    let admin_set_after_removal = worker.admins();
    assert!(admin_set_after_removal.contains(&ADMIN), 8);
    assert!(admin_set_after_removal.size() == 1, 9);

    // Verify ADMIN is still an admin (not the only one removed)
    assert!(worker.is_admin_address(ADMIN), 10);

    // Verify SetAdminEvent was emitted for removal
    let expected_remove_event = worker_common::create_set_admin_event(&worker, USER1, false);
    test_utils::assert_eq(event::events_by_type<worker_common::SetAdminEvent>()[2], expected_remove_event);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerAdminAlreadyExists)]
fun test_set_admin_add_existing() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Try to add ADMIN again (already exists)
    worker.set_admin(&owner_cap, ADMIN, true, scenario.ctx());

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerAdminNotFound)]
fun test_set_admin_remove_nonexistent() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Try to remove USER2 (not an admin)
    worker.set_admin(&owner_cap, USER2, false, scenario.ctx());

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerAttemptingToRemoveOnlyAdmin)]
fun test_set_admin_remove_only_admin() {
    let mut scenario = setup();

    // Create worker with only one admin (using create_test_worker which already has only ADMIN)
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Try to remove the only admin
    worker.set_admin(&owner_cap, ADMIN, false, scenario.ctx());

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
fun test_assert_admin_success() {
    let mut scenario = setup();
    let (worker, owner_cap, admin_cap) = create_test_worker_with_admin(&mut scenario);

    scenario.next_tx(ADMIN);

    // Should not abort for valid admin
    worker.assert_admin(&admin_cap);
    ts::return_to_sender(&scenario, admin_cap);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerUnauthorized)]
fun test_assert_admin_failure() {
    let mut scenario = setup();
    let (worker, owner_cap) = create_test_worker(&mut scenario);

    scenario.next_tx(USER2); // USER2 is not an admin

    // Should abort for non-admin
    let user2_cap = worker_common::create_admin_cap_for_test(scenario.ctx());
    worker.assert_admin(&user2_cap);
    test_utils::destroy(user2_cap);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

// === Allowlist/Denylist Tests ===

#[test]
fun test_set_allowlist() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Initially USER1 is not on allowlist
    assert!(!worker.is_on_allowlist(USER1), 1);
    assert!(worker.allowlist_size() == 0, 2);

    // Add USER1 to allowlist
    worker.set_allowlist(&owner_cap, USER1, true);

    // Verify USER1 is on allowlist
    assert!(worker.is_on_allowlist(USER1), 3);
    assert!(worker.allowlist_size() == 1, 4);

    // Verify SetAllowlistEvent was emitted for addition
    let expected_add_event = worker_common::create_set_allowlist_event(&worker, USER1, true);
    test_utils::assert_eq(event::events_by_type<worker_common::SetAllowlistEvent>()[0], expected_add_event);

    // Remove USER1 from allowlist
    worker.set_allowlist(&owner_cap, USER1, false);

    // Verify USER1 is no longer on allowlist
    assert!(!worker.is_on_allowlist(USER1), 5);
    assert!(worker.allowlist_size() == 0, 6);

    // Verify SetAllowlistEvent was emitted for removal
    let expected_remove_event = worker_common::create_set_allowlist_event(&worker, USER1, false);
    test_utils::assert_eq(event::events_by_type<worker_common::SetAllowlistEvent>()[1], expected_remove_event);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerAlreadyOnAllowlist)]
fun test_set_allowlist_add_existing() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Add USER1 to allowlist
    worker.set_allowlist(&owner_cap, USER1, true);

    // Try to add USER1 again
    worker.set_allowlist(&owner_cap, USER1, true);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerNotOnAllowlist)]
fun test_set_allowlist_remove_nonexistent() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Try to remove USER1 (not on allowlist)
    worker.set_allowlist(&owner_cap, USER1, false);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
fun test_set_denylist() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Initially USER1 is not on denylist
    assert!(!worker.is_on_denylist(USER1), 1);

    // Add USER1 to denylist
    worker.set_denylist(&owner_cap, USER1, true);

    // Verify USER1 is on denylist
    assert!(worker.is_on_denylist(USER1), 2);

    // Verify SetDenylistEvent was emitted for addition
    let expected_add_event = worker_common::create_set_denylist_event(&worker, USER1, true);
    test_utils::assert_eq(event::events_by_type<worker_common::SetDenylistEvent>()[0], expected_add_event);

    // Remove USER1 from denylist
    worker.set_denylist(&owner_cap, USER1, false);

    // Verify USER1 is no longer on denylist
    assert!(!worker.is_on_denylist(USER1), 3);

    // Verify SetDenylistEvent was emitted for removal
    let expected_remove_event = worker_common::create_set_denylist_event(&worker, USER1, false);
    test_utils::assert_eq(event::events_by_type<worker_common::SetDenylistEvent>()[1], expected_remove_event);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerAlreadyOnDenylist)]
fun test_set_denylist_add_existing() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Add USER1 to denylist
    worker.set_denylist(&owner_cap, USER1, true);

    // Try to add USER1 again
    worker.set_denylist(&owner_cap, USER1, true);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerNotOnDenylist)]
fun test_set_denylist_remove_nonexistent() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Try to remove USER1 (not on denylist)
    worker.set_denylist(&owner_cap, USER1, false);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

// === Supported Message Library Tests ===

#[test]
fun test_set_supported_message_lib() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Initially MESSAGE_LIB_ADDR is not supported
    assert!(!worker.is_supported_message_lib(MESSAGE_LIB_ADDR), 1);

    // Add MESSAGE_LIB_ADDR to supported message libs
    worker.set_supported_message_lib(&owner_cap, MESSAGE_LIB_ADDR, true);

    // Verify MESSAGE_LIB_ADDR is now supported
    assert!(worker.is_supported_message_lib(MESSAGE_LIB_ADDR), 2);

    // Verify SetSupportedMessageLibEvent was emitted for addition
    let expected_add_event = worker_common::create_set_supported_message_lib_event(&worker, MESSAGE_LIB_ADDR, true);
    test_utils::assert_eq(event::events_by_type<worker_common::SetSupportedMessageLibEvent>()[0], expected_add_event);

    // Remove MESSAGE_LIB_ADDR from supported message libs
    worker.set_supported_message_lib(&owner_cap, MESSAGE_LIB_ADDR, false);

    // Verify MESSAGE_LIB_ADDR is no longer supported
    assert!(!worker.is_supported_message_lib(MESSAGE_LIB_ADDR), 3);

    // Verify SetSupportedMessageLibEvent was emitted for removal
    let expected_remove_event = worker_common::create_set_supported_message_lib_event(&worker, MESSAGE_LIB_ADDR, false);
    test_utils::assert_eq(
        event::events_by_type<worker_common::SetSupportedMessageLibEvent>()[1],
        expected_remove_event,
    );

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerMessageLibAlreadySupported)]
fun test_set_supported_message_lib_add_existing() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Add MESSAGE_LIB_ADDR to supported message libs
    worker.set_supported_message_lib(&owner_cap, MESSAGE_LIB_ADDR, true);

    // Try to add MESSAGE_LIB_ADDR again
    worker.set_supported_message_lib(&owner_cap, MESSAGE_LIB_ADDR, true);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerMessageLibNotSupported)]
fun test_set_supported_message_lib_remove_nonexistent() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Try to remove MESSAGE_LIB_ADDR (not supported)
    worker.set_supported_message_lib(&owner_cap, MESSAGE_LIB_ADDR, false);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerUnauthorized)]
fun test_set_supported_message_lib_unauthorized() {
    let mut scenario = setup();
    let (mut worker1, owner_cap1) = create_test_worker(&mut scenario);
    let (worker2, owner_cap2) = create_test_worker(&mut scenario);

    scenario.next_tx(USER2); // USER2 is not the owner

    let new_message_lib = @0x777;
    // Try to use worker2's owner cap on worker1 (should fail)
    worker1.set_supported_message_lib(&owner_cap2, new_message_lib, true);

    test_utils::destroy(worker1);
    test_utils::destroy(worker2);
    test_utils::destroy(owner_cap1);
    test_utils::destroy(owner_cap2);
    clean(scenario);
}

// === ACL Logic Tests ===

#[test]
fun test_has_acl_empty_lists() {
    let mut scenario = setup();
    let (worker, owner_cap) = create_test_worker(&mut scenario);

    // When both allowlist and denylist are empty, everyone should have access
    assert!(worker.has_acl(USER1), 1);
    assert!(worker.has_acl(USER2), 2);
    assert!(worker.has_acl(USER3), 3);

    worker.assert_acl(USER1);
    worker.assert_acl(USER2);
    worker.assert_acl(USER3);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
fun test_has_acl_denylist_priority() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Add USER1 to both allowlist and denylist
    worker.set_allowlist(&owner_cap, USER1, true);
    worker.set_denylist(&owner_cap, USER1, true);

    // Denylist should take priority - USER1 should be denied
    assert!(!worker.has_acl(USER1), 1);

    // USER2 not on any list, but allowlist exists, so denied
    assert!(!worker.has_acl(USER2), 2);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
fun test_has_acl_allowlist_only() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Add USER1 to allowlist only
    worker.set_allowlist(&owner_cap, USER1, true);

    // USER1 should have access
    assert!(worker.has_acl(USER1), 1);

    // USER2 not on allowlist, so denied
    assert!(!worker.has_acl(USER2), 2);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
fun test_has_acl_denylist_only() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Add USER1 to denylist only
    worker.set_denylist(&owner_cap, USER1, true);

    // USER1 should be denied
    assert!(!worker.has_acl(USER1), 1);

    // USER2 not on denylist and allowlist is empty, so allowed
    assert!(worker.has_acl(USER2), 2);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerNotAllowed)]
fun test_assert_acl_failure() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Add USER1 to denylist
    worker.set_denylist(&owner_cap, USER1, true);

    // Should abort for denied user
    worker.assert_acl(USER1);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

// === Configuration Setter Tests ===

#[test]
fun test_set_deposit_address() {
    let mut scenario = setup();
    let (mut worker, owner_cap, admin_cap) = create_test_worker_with_admin(&mut scenario);

    let new_deposit = @0xbeef;

    worker.set_deposit_address(&admin_cap, new_deposit);
    ts::return_to_sender(&scenario, admin_cap);

    // Verify deposit address was updated
    assert!(worker.deposit_address() == new_deposit, 1);

    // Verify SetDepositAddressEvent was emitted
    let expected_event = worker_common::create_set_deposit_address_event(&worker, new_deposit);
    test_utils::assert_eq(event::events_by_type<worker_common::SetDepositAddressEvent>()[0], expected_event);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerUnauthorized)]
fun test_set_deposit_address_unauthorized() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    scenario.next_tx(USER2); // USER2 is not an admin

    let new_deposit = @0xbeef;
    let user2_cap = worker_common::create_admin_cap_for_test(scenario.ctx());
    worker.set_deposit_address(&user2_cap, new_deposit);

    test_utils::destroy(user2_cap);
    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
fun test_set_price_feed() {
    let mut scenario = setup();
    let (mut worker, owner_cap, admin_cap) = create_test_worker_with_admin(&mut scenario);

    let new_price_feed = @0xfeed2;
    worker.set_price_feed(&admin_cap, new_price_feed);
    ts::return_to_sender(&scenario, admin_cap);

    // Verify price feed was updated
    assert!(worker.price_feed() == new_price_feed, 1);

    // Verify SetPriceFeedEvent was emitted
    let expected_event = worker_common::create_set_price_feed_event(&worker, new_price_feed);
    test_utils::assert_eq(event::events_by_type<worker_common::SetPriceFeedEvent>()[0], expected_event);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerUnauthorized)]
fun test_set_price_feed_unauthorized() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    scenario.next_tx(USER2); // USER2 is not an admin

    let new_price_feed = @0xfeed2;
    let user2_cap = worker_common::create_admin_cap_for_test(scenario.ctx());
    worker.set_price_feed(&user2_cap, new_price_feed);
    test_utils::destroy(user2_cap);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
fun test_set_default_multiplier_bps() {
    let mut scenario = setup();
    let (mut worker, owner_cap, admin_cap) = create_test_worker_with_admin(&mut scenario);

    let new_multiplier = 2000u16; // 20%
    worker.set_default_multiplier_bps(&admin_cap, new_multiplier);
    ts::return_to_sender(&scenario, admin_cap);

    // Verify multiplier was updated
    assert!(worker.default_multiplier_bps() == new_multiplier, 1);

    // Verify SetDefaultMultiplierBpsEvent was emitted
    let expected_event = worker_common::create_set_default_multiplier_bps_event(&worker, new_multiplier);
    test_utils::assert_eq(event::events_by_type<worker_common::SetDefaultMultiplierBpsEvent>()[0], expected_event);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerUnauthorized)]
fun test_set_default_multiplier_bps_unauthorized() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    scenario.next_tx(USER2); // USER2 is not an admin

    let new_multiplier = 2000u16;
    let user2_cap = worker_common::create_admin_cap_for_test(scenario.ctx());
    worker.set_default_multiplier_bps(&user2_cap, new_multiplier);
    test_utils::destroy(user2_cap);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
fun test_set_worker_fee_lib() {
    let mut scenario = setup();
    let (mut worker, owner_cap, admin_cap) = create_test_worker_with_admin(&mut scenario);

    let new_fee_lib = @0xfee2;
    worker.set_worker_fee_lib(&admin_cap, new_fee_lib);
    ts::return_to_sender(&scenario, admin_cap);

    // Verify worker fee lib was updated
    assert!(worker.worker_fee_lib() == new_fee_lib, 1);

    // Verify SetWorkerFeeLibEvent was emitted
    let expected_event = worker_common::create_set_worker_fee_lib_event(&worker, new_fee_lib);
    test_utils::assert_eq(event::events_by_type<worker_common::SetWorkerFeeLibEvent>()[0], expected_event);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerUnauthorized)]
fun test_set_worker_fee_lib_unauthorized() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    scenario.next_tx(USER2); // USER2 is not an admin

    let new_fee_lib = @0xfee2;
    let user2_cap = worker_common::create_admin_cap_for_test(scenario.ctx());
    worker.set_worker_fee_lib(&user2_cap, new_fee_lib);
    test_utils::destroy(user2_cap);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
fun test_set_supported_option_types() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    scenario.next_tx(ADMIN); // Admin permission required

    let dst_eid = 123u32;
    let option_types = vector[1u8, 2u8, 3u8];
    let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
    worker.set_supported_option_types(&admin_cap, dst_eid, option_types);
    ts::return_to_sender(&scenario, admin_cap);

    // Verify option types were updated
    let retrieved_types = worker.get_supported_option_types(dst_eid);
    assert!(retrieved_types == vector[1u8, 2u8, 3u8], 1);

    // Verify SetSupportedOptionTypesEvent was emitted
    let expected_event = worker_common::create_set_supported_option_types_event(
        &worker,
        dst_eid,
        vector[1u8, 2u8, 3u8],
    );
    test_utils::assert_eq(event::events_by_type<worker_common::SetSupportedOptionTypesEvent>()[0], expected_event);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerUnauthorized)]
fun test_set_supported_option_types_unauthorized() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    scenario.next_tx(USER2); // USER2 is not an admin

    let dst_eid = 123u32;
    let option_types = vector[1u8, 2u8, 3u8];
    let user2_cap = worker_common::create_admin_cap_for_test(scenario.ctx());
    worker.set_supported_option_types(&user2_cap, dst_eid, option_types);
    test_utils::destroy(user2_cap);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
fun test_get_supported_option_types_empty() {
    let mut scenario = setup();
    let (worker, owner_cap) = create_test_worker(&mut scenario);

    let dst_eid = 999u32;
    let retrieved_types = worker.get_supported_option_types(dst_eid);

    // Should return empty vector for non-existent EID
    assert!(retrieved_types == vector::empty<u8>(), 5);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

// === Pause/Unpause Tests ===

#[test]
fun test_set_paused() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Initially not paused
    assert!(!worker.is_paused(), 1);

    // Pause the worker
    worker.set_paused(&owner_cap, true);

    // Verify worker is paused
    assert!(worker.is_paused(), 2);

    // Verify PausedEvent was emitted
    let expected_pause_event = worker_common::create_paused_event(&worker);
    test_utils::assert_eq(event::events_by_type<worker_common::PausedEvent>()[0], expected_pause_event);

    // Unpause the worker
    worker.set_paused(&owner_cap, false);

    // Verify worker is not paused
    assert!(!worker.is_paused(), 3);

    // Verify UnpausedEvent was emitted
    let expected_unpause_event = worker_common::create_unpaused_event(&worker);
    test_utils::assert_eq(event::events_by_type<worker_common::UnpausedEvent>()[0], expected_unpause_event);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerPauseStatusUnchanged)]
fun test_set_paused_no_state_change_true() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // First pause the worker
    worker.set_paused(&owner_cap, true);
    assert!(worker.is_paused(), 1);

    // Try to pause again (should fail - no state change)
    worker.set_paused(&owner_cap, true);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerPauseStatusUnchanged)]
fun test_set_paused_no_state_change_false() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Worker starts unpaused, try to unpause again (should fail - no state change)
    worker.set_paused(&owner_cap, false);

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
fun test_assert_worker_unpaused_success() {
    let mut scenario = setup();
    let (worker, owner_cap) = create_test_worker(&mut scenario);

    // Should not abort for unpaused worker
    worker.assert_worker_unpaused();

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

#[test]
#[expected_failure(abort_code = EWorkerIsPaused)]
fun test_assert_worker_unpaused_failure() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Pause the worker
    worker.set_paused(&owner_cap, true);

    // Should abort for paused worker
    worker.assert_worker_unpaused();

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}

// === View Functions and Getters Tests ===

#[test]
fun test_get_native_decimals_rate() {
    // Test the constant function
    let rate = worker_common::get_native_decimals_rate();
    assert!(rate == 1000000000u64, 5); // 10^9 for SUI
}

// === Complex Scenarios and Edge Cases ===

#[test]
fun test_complex_acl_scenario() {
    let mut scenario = setup();
    let (mut worker, owner_cap) = create_test_worker(&mut scenario);

    // Test the complex ACL logic described in the comments:
    // 1) if address is in denylist -> deny
    // 2) else if address is in allowlist OR allowlist is empty -> allow
    // 3) else deny

    // Initial state: both lists empty, everyone allowed
    assert!(worker.has_acl(USER1), 1);
    assert!(worker.has_acl(USER2), 2);
    assert!(worker.has_acl(USER3), 3);

    // Add USER1 to allowlist
    worker.set_allowlist(&owner_cap, USER1, true);
    assert!(worker.has_acl(USER1), 4); // On allowlist -> allow
    assert!(!worker.has_acl(USER2), 5); // Not on allowlist, allowlist not empty -> deny
    assert!(!worker.has_acl(USER3), 6); // Not on allowlist, allowlist not empty -> deny

    // Add USER2 to allowlist
    worker.set_allowlist(&owner_cap, USER2, true);
    assert!(worker.has_acl(USER1), 7); // On allowlist -> allow
    assert!(worker.has_acl(USER2), 8); // On allowlist -> allow
    assert!(!worker.has_acl(USER3), 9); // Not on allowlist, allowlist not empty -> deny

    // Add USER1 to denylist (should override allowlist)
    worker.set_denylist(&owner_cap, USER1, true);
    assert!(!worker.has_acl(USER1), 10); // On denylist -> deny (priority over allowlist)
    assert!(worker.has_acl(USER2), 11); // On allowlist, not on denylist -> allow
    assert!(!worker.has_acl(USER3), 12); // Not on allowlist, allowlist not empty -> deny

    // Add USER3 to denylist (not on allowlist)
    worker.set_denylist(&owner_cap, USER3, true);
    assert!(!worker.has_acl(USER1), 13); // On denylist -> deny
    assert!(worker.has_acl(USER2), 14); // On allowlist, not on denylist -> allow
    assert!(!worker.has_acl(USER3), 15); // On denylist -> deny

    // Remove USER1 from denylist (but still on allowlist)
    worker.set_denylist(&owner_cap, USER1, false);
    assert!(worker.has_acl(USER1), 16); // On allowlist, not on denylist -> allow
    assert!(worker.has_acl(USER2), 17); // On allowlist, not on denylist -> allow
    assert!(!worker.has_acl(USER3), 18); // On denylist -> deny

    // Remove all from allowlist (but USER3 still on denylist)
    worker.set_allowlist(&owner_cap, USER1, false);
    worker.set_allowlist(&owner_cap, USER2, false);
    assert!(worker.has_acl(USER1), 19); // Allowlist empty, not on denylist -> allow
    assert!(worker.has_acl(USER2), 20); // Allowlist empty, not on denylist -> allow
    assert!(!worker.has_acl(USER3), 21); // On denylist -> deny

    test_utils::destroy(worker);
    test_utils::destroy(owner_cap);
    clean(scenario);
}
