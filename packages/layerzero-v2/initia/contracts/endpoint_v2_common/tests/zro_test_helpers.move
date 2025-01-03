#[test_only]
module endpoint_v2_common::zro_test_helpers {
    use std::account::create_signer_for_test;
    use std::fungible_asset;
    use std::fungible_asset::{Metadata, MintRef};
    use std::object;
    use std::object::{address_from_constructor_ref, Object, object_from_constructor_ref};
    use std::option;
    use std::primary_fungible_store::create_primary_store_enabled_fungible_asset;
    use std::string::utf8;

    public fun create_fa(name: vector<u8>): (address, Object<Metadata>, MintRef) {
        let lz = &create_signer_for_test(@layerzero_treasury_admin);
        let constructor = object::create_named_object(lz, name);
        create_primary_store_enabled_fungible_asset(
            &constructor,
            option::none(),
            utf8(b"ZRO"),
            utf8(b"ZRO"),
            8,
            utf8(b""),
            utf8(b""),
        );
        let mint_ref = fungible_asset::generate_mint_ref(&constructor);
        let addr = address_from_constructor_ref(&constructor);
        let metadata = object_from_constructor_ref<Metadata>(&constructor);
        (addr, metadata, mint_ref)
    }
}
