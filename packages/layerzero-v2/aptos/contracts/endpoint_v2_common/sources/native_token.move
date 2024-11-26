/// This module provides a function to withdraw gas token using Coin methods.
///
/// This is necessary for chains that have a Coin representation of the gas token. The coin::withdraw function is aware
/// of both Coin<AptosCoin> and FungibleAsset(@0xa) balances unlike the fungible_asset::withdraw function which is only
/// aware of FungibleAsset(@0xa) balances.
///
/// This module should be swapped with native_token_fa.move for chains that have a fully FungibleAsset-based gas token.
module endpoint_v2_common::native_token {
    use std::aptos_coin::AptosCoin;
    use std::coin;
    use std::fungible_asset::FungibleAsset;

    public fun withdraw(account: &signer, amount: u64): FungibleAsset {
        let coin = coin::withdraw<AptosCoin>(move account, amount);
        coin::coin_to_fungible_asset(coin)
    }
}
