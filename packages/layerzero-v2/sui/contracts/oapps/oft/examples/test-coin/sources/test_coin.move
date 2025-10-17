module test_coin::test_coin;

use sui::coin;

public struct TEST_COIN has drop {}

fun init(witness: TEST_COIN, ctx: &mut TxContext) {
    let (treasury, metadata) = coin::create_currency(
        witness,
        6, // decimals
        b"TEST",
        b"Test Coin",
        b"Test coin for OFT Adapter",
        option::none(),
        ctx,
    );
    transfer::public_transfer(treasury, ctx.sender());
    transfer::public_share_object(metadata);
}
