/// This module contains the general/internal store of the WOFT OApp
module bridge_remote::woft_store {
    use std::fungible_asset::Metadata;
    use std::object::Object;
    use std::table::{Self, Table};

    use bridge_remote::oapp_store::OAPP_ADDRESS;
    use endpoint_v2_common::bytes32::Bytes32;

    friend bridge_remote::woft_core;

    /// The WOFT store
    struct WoftStore has key {
        tokens: Table<Bytes32, Token>,
        fa_to_token_lookup: Table<Object<Metadata>, Bytes32>,
    }

    /// Token configuration
    struct Token has store {
        shared_decimals: u8,
        decimal_conversion_rate: u64,
        metadata: Object<Metadata>,
    }

    /// Get the decimal conversion rate of the WOFT, this is the multiplier to convert a shared decimals to a local
    /// decimals representation
    public(friend) fun decimal_conversion_rate(token: Bytes32): u64 acquires WoftStore {
        token_store(token).decimal_conversion_rate
    }

    /// Get the shared decimals of the WOFT, this is the number of decimals that are preserved on wire transmission
    public(friend) fun shared_decimals(token: Bytes32): u8 acquires WoftStore {
        token_store(token).shared_decimals
    }

    public(friend) fun get_token_from_metadata(metadata: Object<Metadata>): Bytes32 acquires WoftStore {
        *table::borrow(&store().fa_to_token_lookup, metadata)
    }

    public(friend) fun get_metadata_from_token(token: Bytes32): Object<Metadata> acquires WoftStore {
        table::borrow(&store().tokens, token).metadata
    }

    public(friend) fun has_token(token: Bytes32): bool acquires WoftStore {
        table::contains(&store().tokens, token)
    }

    public(friend) fun has_metadata(metadata: Object<Metadata>): bool acquires WoftStore {
        table::contains(&store().fa_to_token_lookup, metadata)
    }

    // ==================================================== Helpers ===================================================

    inline fun store(): &WoftStore { borrow_global(OAPP_ADDRESS()) }

    inline fun store_mut(): &mut WoftStore { borrow_global_mut(OAPP_ADDRESS()) }

    inline fun token_store(token: Bytes32): &Token { table::borrow(&store().tokens, token) }

    inline fun token_store_mut(token: Bytes32): &mut Token { table::borrow_mut(&mut store_mut().tokens, token) }

    // ================================================ Initialization ================================================

    public(friend) fun initialize(
        token: Bytes32,
        metadata: Object<Metadata>,
        shared_decimals: u8,
        decimal_conversion_rate: u64,
    ) acquires WoftStore {
        // Prevent re-initialization
        assert!(!table::contains(&store().tokens, token), EALREADY_INITIALIZED);

        // General token configuration
        table::add(&mut store_mut().tokens, token, Token {
            shared_decimals,
            decimal_conversion_rate,
            metadata,
        });

        // Add the metadata to token reverse lookup table
        // This table is necessary to allow users to query by the Fungible Asset metadata address rather than the token
        // address on the peer WAB
        table::add(&mut store_mut().fa_to_token_lookup, metadata, token);
    }

    fun init_module(account: &signer) {
        move_to(account, WoftStore {
            tokens: table::new(),
            fa_to_token_lookup: table::new(),
        })
    }

    #[test_only]
    public fun init_module_for_test() {
        init_module(&std::account::create_signer_for_test(OAPP_ADDRESS()));
    }

    // ================================================== Error Codes =================================================

    const EALREADY_INITIALIZED: u64 = 1;
    const ENO_CHANGE: u64 = 2;
}
