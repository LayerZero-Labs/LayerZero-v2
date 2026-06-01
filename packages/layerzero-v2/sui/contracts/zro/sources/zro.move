module zro::zro;

use sui::coin_registry::{Self, CoinRegistry};

public struct ZRO has key {
    id: UID,
}

#[allow(lint(self_transfer))]
public fun new_currency(registry: &mut CoinRegistry, ctx: &mut TxContext) {
    let (builder, treasury_cap) = coin_registry::new_currency<ZRO>(
        registry,
        9, // decimals
        b"ZRO".to_string(), // symbol
        b"LayerZero".to_string(), // name
        b"LayerZero".to_string(), // description
        b"".to_string(), // icon_url
        ctx,
    );
    let metadata_cap = builder.finalize(ctx);
    transfer::public_transfer(treasury_cap, ctx.sender());
    transfer::public_transfer(metadata_cap, ctx.sender());
}
