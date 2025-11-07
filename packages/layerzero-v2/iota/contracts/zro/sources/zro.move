module zro::zro;

use iota::coin;

public struct ZRO has drop {}

fun init(otw: ZRO, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = coin::create_currency(
        otw,
        9, // decimals
        b"ZRO", // symbol
        b"LayerZero", // name
        b"LayerZero", // description
        option::none(), // icon_url
        ctx,
    );
    transfer::public_transfer(treasury_cap, ctx.sender());
    transfer::public_transfer(metadata, ctx.sender());
}
