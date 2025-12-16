#[test_only]
module oft::test_coin;

use iota::coin::{Self, TreasuryCap, CoinMetadata};

/// Test coin with 18 decimals (standard)
/// The struct name must match the module name for OTW to work
public struct TEST_COIN has drop {}

#[test_only]
/// Manual initialization for 18-decimal test coin
public fun init_for_testing(ctx: &mut TxContext): (TreasuryCap<TEST_COIN>, CoinMetadata<TEST_COIN>) {
    init_for_testing_with_decimals(18, ctx)
}

#[test_only]
/// Manual initialization for test coin with custom decimals
public fun init_for_testing_with_decimals(
    decimals: u8,
    ctx: &mut TxContext,
): (TreasuryCap<TEST_COIN>, CoinMetadata<TEST_COIN>) {
    let (treasury_cap, coin_metadata) = coin::create_currency(
        TEST_COIN {},
        decimals,
        b"TEST",
        b"Test Coin",
        b"A test coin for adapter testing",
        option::none(),
        ctx,
    );
    (treasury_cap, coin_metadata)
}

#[test_only]
public fun build_otw_for_testing(): TEST_COIN {
    TEST_COIN {}
}
