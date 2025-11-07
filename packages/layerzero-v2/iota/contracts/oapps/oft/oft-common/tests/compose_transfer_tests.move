#[test_only]
module oft_common::compose_transfer_tests;

use oft_common::compose_transfer;
use iota::{coin, test_scenario};
use utils::bytes32;

// === Test Constants ===

const ALICE: address = @0xa11ce;

// === Test Phantom Type ===

public struct TestCoin has drop {}

// === Basic Tests ===

#[test]
fun test_create_and_destroy_compose_transfer() {
    let mut scenario = test_scenario::begin(ALICE);
    let ctx = test_scenario::ctx(&mut scenario);

    // Create test data
    let from_address = ALICE;
    let guid = bytes32::from_address(@0x1234);
    let coin_amount = 1000000u64;
    let test_coin = coin::mint_for_testing<TestCoin>(coin_amount, ctx);

    // Create compose transfer
    let compose_transfer = compose_transfer::create(from_address, guid, test_coin, ctx);

    // Compose transfer was created successfully (would fail compilation if not)

    // Destroy and verify components
    let (recovered_from, recovered_guid, recovered_coin) = compose_transfer::destroy(compose_transfer);

    // Verify recovered values
    assert!(recovered_from == from_address, 0);
    assert!(recovered_guid == guid, 0);
    assert!(coin::value(&recovered_coin) == coin_amount, 0);

    // Clean up
    coin::burn_for_testing(recovered_coin);
    test_scenario::end(scenario);
}
