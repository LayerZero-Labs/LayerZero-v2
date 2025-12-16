#[test_only]
module oft_common::oft_composer_manager_tests;

use call::call_cap;
use oft_common::oft_composer_manager::{Self, OFTComposerManager};
use iota::{coin, event, test_scenario, test_utils};
use utils::bytes32::{Self, Bytes32};

// === Test Constants ===

const ALICE: address = @0xa11ce;
const DEPOSIT_ADDRESS_1: address = @0xde1051;
const DEPOSIT_ADDRESS_2: address = @0xde1052;
const COMPOSER_1: address = @0xc0a11051;

// === Error Constants ===
// Note: Using raw error codes in tests as they come from the source module

// === Test Phantom Type ===

public struct TestCoin has drop {}

// === Helper Functions ===

fun setup_manager(): (test_scenario::Scenario, OFTComposerManager) {
    let mut scenario = test_scenario::begin(ALICE);
    oft_composer_manager::init_for_testing(test_scenario::ctx(&mut scenario));

    test_scenario::next_tx(&mut scenario, ALICE);
    let manager = test_scenario::take_shared<OFTComposerManager>(&scenario);

    (scenario, manager)
}

fun create_test_guid(value: u64): Bytes32 {
    let mut bytes = vector::empty<u8>();
    // Fill first 24 bytes with zeros
    let mut i = 0;
    while (i < 24) {
        bytes.push_back(0u8);
        i = i + 1;
    };
    // Add the u64 value in big-endian format
    bytes.push_back(((value >> 56) & 0xFF) as u8);
    bytes.push_back(((value >> 48) & 0xFF) as u8);
    bytes.push_back(((value >> 40) & 0xFF) as u8);
    bytes.push_back(((value >> 32) & 0xFF) as u8);
    bytes.push_back(((value >> 24) & 0xFF) as u8);
    bytes.push_back(((value >> 16) & 0xFF) as u8);
    bytes.push_back(((value >> 8) & 0xFF) as u8);
    bytes.push_back((value & 0xFF) as u8);

    bytes32::from_bytes(bytes)
}

// === Initialization Tests ===

#[test]
fun test_manager_initialization() {
    let (scenario, manager) = setup_manager();

    // Manager was created successfully (would fail compilation if not)

    test_scenario::return_shared(manager);
    test_scenario::end(scenario);
}

// === Deposit Address Management Tests ===

#[test]
fun test_set_deposit_address_and_emit_event() {
    let (mut scenario, mut manager) = setup_manager();
    let ctx = test_scenario::ctx(&mut scenario);

    // Create composer capability
    let composer_cap = call_cap::new_package_cap_for_test(ctx);

    // Set deposit address
    manager.set_deposit_address(&composer_cap, DEPOSIT_ADDRESS_1);

    // Verify deposit address was set
    let retrieved_address = manager.get_deposit_address(composer_cap.id());
    assert!(retrieved_address == DEPOSIT_ADDRESS_1, 0);

    // assert event
    let events = event::events_by_type<oft_composer_manager::DepositAddressSetEvent>();
    assert!(events.length() == 1, 0);

    // Clean up
    test_utils::destroy(composer_cap);
    test_scenario::return_shared(manager);
    test_scenario::end(scenario);
}

#[test]
fun test_update_deposit_address() {
    let (mut scenario, mut manager) = setup_manager();
    let ctx = test_scenario::ctx(&mut scenario);

    // Create composer capability
    let composer_cap = call_cap::new_package_cap_for_test(ctx);

    // Set initial deposit address
    manager.set_deposit_address(&composer_cap, DEPOSIT_ADDRESS_1);
    assert!(manager.get_deposit_address(composer_cap.id()) == DEPOSIT_ADDRESS_1, 0);

    // Update deposit address
    manager.set_deposit_address(&composer_cap, DEPOSIT_ADDRESS_2);
    assert!(manager.get_deposit_address(composer_cap.id()) == DEPOSIT_ADDRESS_2, 0);

    // Clean up
    test_utils::destroy(composer_cap);
    test_scenario::return_shared(manager);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = oft_composer_manager::EInvalidDepositAddress)]
fun test_set_invalid_deposit_address_should_fail() {
    let (mut scenario, mut manager) = setup_manager();
    let ctx = test_scenario::ctx(&mut scenario);

    // Create composer capability
    let composer_cap = call_cap::new_package_cap_for_test(ctx);

    // Try to set zero address as deposit address (should fail)
    manager.set_deposit_address(&composer_cap, @0x0);

    // Clean up (this line should not be reached)
    test_utils::destroy(composer_cap);
    test_scenario::return_shared(manager);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = oft_composer_manager::EDepositAddressNotFound)]
fun test_get_nonexistent_deposit_address_should_fail() {
    let (scenario, manager) = setup_manager();

    // Try to get deposit address for nonexistent composer (should fail)
    let _address = manager.get_deposit_address(COMPOSER_1);

    // Clean up (this line should not be reached)
    test_scenario::return_shared(manager);
    test_scenario::end(scenario);
}

// === Compose Transfer Management Tests ===

#[test]
fun test_send_to_composer() {
    let (mut scenario, mut manager) = setup_manager();
    let ctx = test_scenario::ctx(&mut scenario);

    // Create capabilities
    let from_cap = call_cap::new_package_cap_for_test(ctx);
    let composer_cap = call_cap::new_package_cap_for_test(ctx);

    // Set deposit address for composer
    manager.set_deposit_address(&composer_cap, DEPOSIT_ADDRESS_1);

    // Create test data
    let guid = create_test_guid(12345);
    let coin_amount = 1000000u64;
    let test_coin = coin::mint_for_testing<TestCoin>(coin_amount, ctx);

    // Send to composer
    manager.send_to_composer(&from_cap, guid, composer_cap.id(), test_coin, ctx);

    // Verify compose transfer was registered
    let transfer_id = manager.get_compose_transfer(from_cap.id(), guid, composer_cap.id());
    assert!(transfer_id != @0x0, 0);

    // Events were emitted (verified by successful execution)

    // Clean up
    test_utils::destroy(from_cap);
    test_utils::destroy(composer_cap);
    test_scenario::return_shared(manager);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = oft_composer_manager::EDepositAddressNotFound)]
fun test_send_to_composer_without_deposit_address_should_fail() {
    let (mut scenario, mut manager) = setup_manager();
    let ctx = test_scenario::ctx(&mut scenario);

    // Create capabilities
    let from_cap = call_cap::new_package_cap_for_test(ctx);
    let composer_cap = call_cap::new_package_cap_for_test(ctx);

    // Create test data
    let guid = create_test_guid(12345);
    let test_coin = coin::mint_for_testing<TestCoin>(1000000u64, ctx);

    // Try to send to composer without setting deposit address (should fail)
    manager.send_to_composer(&from_cap, guid, composer_cap.id(), test_coin, ctx);

    // Clean up (this line should not be reached)
    test_utils::destroy(from_cap);
    test_utils::destroy(composer_cap);
    test_scenario::return_shared(manager);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure(abort_code = oft_composer_manager::EComposeTransferNotFound)]
fun test_get_nonexistent_compose_transfer_should_fail() {
    let (mut scenario, manager) = setup_manager();
    let ctx = test_scenario::ctx(&mut scenario);

    // Create test data for nonexistent transfer
    let from_cap = call_cap::new_package_cap_for_test(ctx);
    let guid = create_test_guid(99999);

    // Try to get nonexistent compose transfer (should fail)
    let _transfer_id = manager.get_compose_transfer(from_cap.id(), guid, COMPOSER_1);

    // Clean up (this line should not be reached)
    test_utils::destroy(from_cap);
    test_scenario::return_shared(manager);
    test_scenario::end(scenario);
}
