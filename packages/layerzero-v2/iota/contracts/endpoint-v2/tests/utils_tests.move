#[test_only]
module endpoint_v2::utils_tests;

use endpoint_v2::utils;
use utils::bytes32;

#[test]
fun test_compute_guid() {
    let src_eid: u32 = 1;
    let sender = bytes32::from_address(@0x3);
    let dst_eid: u32 = 2;
    let receiver = bytes32::from_address(@0x4);
    let nonce: u64 = 0x1234;

    let guid = utils::compute_guid(nonce, src_eid, sender, dst_eid, receiver);

    // 4e80f6fdccb10b2634b15fd900819c9d609ae2c61047ed47718f1dcca05587e4 generate from aptos
    let expected_guid = x"4e80f6fdccb10b2634b15fd900819c9d609ae2c61047ed47718f1dcca05587e4";
    assert!(guid.to_bytes() == expected_guid, 0);
}

#[test]
fun test_compute_payload() {
    let guid = bytes32::from_bytes(b"................................");
    let message = vector<u8>[18, 19, 20];
    let payload = utils::build_payload(guid, message);

    let expected = vector<u8>[
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46,
        46, // 32 periods
        18,
        19,
        20, // message
    ];
    assert!(payload == expected, 1);
}

#[test]
fun test_transfer_coin_with_value() {
    use iota::test_scenario;
    use iota::coin::{Self, Coin};
    use iota::iota::IOTA;

    let admin = @0xBABE;
    let recipient = @0xCAFE;
    let mut scenario = test_scenario::begin(admin);

    // Create a coin with value
    let coin = coin::mint_for_testing<IOTA>(100, scenario.ctx());

    // Transfer the coin to recipient
    utils::transfer_coin(coin, recipient);

    // Advance to next transaction to see the effects
    scenario.next_tx(admin);

    // Verify recipient received the coin
    assert!(test_scenario::has_most_recent_for_address<Coin<IOTA>>(recipient), 0);

    scenario.end();
}

#[test]
fun test_transfer_coin_zero_value() {
    use iota::test_scenario;
    use iota::coin::{Self, Coin};
    use iota::iota::IOTA;

    let admin = @0xBABE;
    let recipient = @0xCAFE;
    let mut scenario = test_scenario::begin(admin);

    // Create a zero-value coin
    let coin = coin::mint_for_testing<IOTA>(0, scenario.ctx());

    // Transfer the zero-value coin (should be destroyed)
    utils::transfer_coin(coin, recipient);

    // Advance to next transaction to see the effects
    scenario.next_tx(admin);

    // Verify recipient did not receive any coin (since zero-value coin was destroyed)
    assert!(!test_scenario::has_most_recent_for_address<Coin<IOTA>>(recipient), 0);

    scenario.end();
}

#[test]
fun test_transfer_coin_option_some() {
    use iota::test_scenario;
    use iota::coin::{Self, Coin};
    use iota::iota::IOTA;

    let admin = @0xBABE;
    let recipient = @0xCAFE;
    let mut scenario = test_scenario::begin(admin);

    // Create a coin and wrap it in an Option
    let coin = coin::mint_for_testing<IOTA>(100, scenario.ctx());
    let coin_option = option::some(coin);

    // Transfer the coin option to recipient
    utils::transfer_coin_option(coin_option, recipient);

    // Advance to next transaction to see the effects
    scenario.next_tx(admin);

    // Verify recipient received the coin
    assert!(test_scenario::has_most_recent_for_address<Coin<IOTA>>(recipient), 0);

    scenario.end();
}

#[test]
fun test_transfer_coin_option_none() {
    use iota::test_scenario;
    use iota::coin::Coin;
    use iota::iota::IOTA;

    let admin = @0xBABE;
    let recipient = @0xCAFE;
    let mut scenario = test_scenario::begin(admin);

    // Create a None option
    let coin_option: Option<Coin<IOTA>> = option::none();

    // Transfer the None option (should be destroyed without transferring anything)
    utils::transfer_coin_option(coin_option, recipient);

    // Advance to next transaction to see the effects
    scenario.next_tx(admin);

    // Verify recipient did not receive any coin (since option was None)
    assert!(!test_scenario::has_most_recent_for_address<Coin<IOTA>>(recipient), 0);

    scenario.end();
}

#[test]
fun test_transfer_coin_option_some_zero_value() {
    use iota::test_scenario;
    use iota::coin::{Self, Coin};
    use iota::iota::IOTA;

    let admin = @0xBABE;
    let recipient = @0xCAFE;
    let mut scenario = test_scenario::begin(admin);

    // Create a zero-value coin and wrap it in an Option
    let coin = coin::mint_for_testing<IOTA>(0, scenario.ctx());
    let coin_option = option::some(coin);

    // Transfer the coin option to recipient (zero-value coin should not be transferred)
    utils::transfer_coin_option(coin_option, recipient);

    // Advance to next transaction to see the effects
    scenario.next_tx(admin);

    // Verify recipient did not receive any coin (since zero-value coin was destroyed)
    assert!(!test_scenario::has_most_recent_for_address<Coin<IOTA>>(recipient), 0);

    scenario.end();
}
