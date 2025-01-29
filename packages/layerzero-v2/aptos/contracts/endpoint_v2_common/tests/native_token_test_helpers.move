#[test_only]
module endpoint_v2_common::native_token_test_helpers {
    use std::aptos_coin;
    use std::fungible_asset;
    use std::fungible_asset::FungibleAsset;
    use std::primary_fungible_store::ensure_primary_store_exists;

    public fun initialize_native_token_for_test() {
        let fa = aptos_coin::mint_apt_fa_for_test(0);
        fungible_asset::destroy_zero(fa);
    }

    public fun mint_native_token_for_test(amount: u64): FungibleAsset {
        aptos_coin::mint_apt_fa_for_test(amount)
    }

    public fun burn_token_for_test(token: FungibleAsset) {
        let metadata = fungible_asset::asset_metadata(&token);
        let burn_loc = ensure_primary_store_exists(@0x0, metadata);
        fungible_asset::deposit(burn_loc, token);
    }
}
