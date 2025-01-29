/// This module provides a function to withdraw the gas token from an account's balance using FungibleAsset methods.
///
/// On some chains, it is necessary to withdraw the gas token using coin-based functions and have the balance converted
/// to FungibleAsset. For those chains, this module should be used.
///
/// For chains that have a fully FungibleAsset-based, this conversion is not necessary. In these cases, this module can
/// be used in place of the native_token.move module.
module endpoint_v2_common::native_token {
    use std::fungible_asset::{FungibleAsset, Metadata};
    use std::object;
    use std::primary_fungible_store;

    public fun balance(account: address): u64 {
        let metadata = object::address_to_object<Metadata>(@native_token_metadata_address);
        primary_fungible_store::balance(account, metadata)
    }

    public fun withdraw(account: &signer, amount: u64): FungibleAsset {
        let metadata = object::address_to_object<Metadata>(@native_token_metadata_address);
        primary_fungible_store::withdraw(move account, metadata, amount)
    }
}
