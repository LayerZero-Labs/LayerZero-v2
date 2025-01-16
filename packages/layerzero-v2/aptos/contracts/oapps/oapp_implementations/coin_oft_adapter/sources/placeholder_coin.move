/// Placeholder module that registers a PlaceholderCoin implementation with the Coin module.
module oft::placeholder_coin {
    use std::coin;
    use std::string::utf8;

    struct Store has key {
        mint_cap: coin::MintCapability<PlaceholderCoin>,
        burn_cap: coin::BurnCapability<PlaceholderCoin>,
    }

    struct PlaceholderCoin {}

    fun init_module(account: &signer) {
        // Register the PlaceholderCoin implementation with the Coin module
        let (
            burn_cap,
            freeze_cap,
            mint_cap,
        ) = coin::initialize<PlaceholderCoin>(
            account,
            utf8(b"Placeholder Coin"),
            utf8(b"PLC"),
            8,
            false,
        );

        move_to(move account, Store {
            mint_cap,
            burn_cap,
        });

        coin::destroy_freeze_cap(freeze_cap);
    }

    #[test_only]
    public fun init_module_for_test() {
        init_module(&std::account::create_signer_for_test(oft::oapp_store::OAPP_ADDRESS()));
    }

    #[test_only]
    public fun mint_for_test(amount: u64): std::coin::Coin<PlaceholderCoin> acquires Store {
        coin::mint(amount, &borrow_global<Store>(@oft).mint_cap)
    }

    #[test_only]
    public fun burn_for_test(coin: coin::Coin<PlaceholderCoin>) acquires Store {
        coin::burn(coin, &borrow_global<Store>(@oft).burn_cap)
    }
}
