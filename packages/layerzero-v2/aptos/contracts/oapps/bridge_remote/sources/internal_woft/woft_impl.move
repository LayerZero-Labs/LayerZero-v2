module bridge_remote::woft_impl {
    use std::event::emit;
    use std::fungible_asset::{Self, BurnRef, FungibleAsset, Metadata, MintRef, MutateMetadataRef, TransferRef};
    use std::object::{Self, address_from_constructor_ref, address_to_object, ExtendRef, Object};
    use std::option::{Self, Option};
    use std::primary_fungible_store;
    use std::string::{String, utf8};
    use std::table::{Self, Table};

    use bridge_remote::oapp_core::{combine_options, get_admin};
    use bridge_remote::oapp_store::OAPP_ADDRESS;
    use bridge_remote::woft_core::{Self, no_fee_debit_view, remove_dust};
    use endpoint_v2_common::bytes32::{Bytes32, from_bytes32};
    use oft_common::oft_fee_detail::{new_oft_fee_detail, OftFeeDetail};
    use oft_common::oft_limit::{new_unbounded_oft_limit, OftLimit};

    friend bridge_remote::wrapped_assets;
    friend bridge_remote::oapp_receive;
    friend bridge_remote::bridge;

    #[test_only]
    friend bridge_remote::woft_impl_tests;
    #[test_only]
    friend bridge_remote::oapp_receive_using_woft_impl_tests;
    #[test_only]
    friend bridge_remote::woft_using_woft_impl_tests;
    #[test_only]
    friend bridge_remote::bridge_tests;

    struct WoftImplStore has key {
        woft_impls: Table<Bytes32, WoftImpl>,
        default_fee_bps: u64,
        fee_deposit_address: address,
    }

    struct WoftImpl has store {
        metadata: Object<Metadata>,
        mint_ref: MintRef,
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
        mutate_metadata_ref: MutateMetadataRef,
        fee_bps: Option<u64>,
        releasable_refs: Option<ReleaseableRefs>
    }

    /// The Fungible Asset and Object references that are preserved in case they need to be released
    struct ReleaseableRefs has store {
        metadata_extend_ref: ExtendRef,
        metadata_transfer_ref: object::TransferRef,
        fa_mutate_ref: MutateMetadataRef,
        fa_transfer_ref: fungible_asset::TransferRef,
        fa_mint_ref: MintRef,
        fa_burn_ref: BurnRef,
    }

    // ================================================= WOFT Handlers ================================================

    /// How much of the received value should be credited to the recipient
    public(friend) fun credit(
        token: Bytes32,
        to: address,
        amount_ld: u64,
        _src_eid: u32,
        lz_receive_value: Option<FungibleAsset>,
    ): u64 acquires WoftImplStore {
        // Default implementation does not make special use of LZ Receive Value sent; just deposit to the Admin address
        // as to not trigger an error
        option::for_each(lz_receive_value, |fa| primary_fungible_store::deposit(get_admin(), fa));

        // Mint the extracted amount to the recipient
        primary_fungible_store::mint(&token_store(token).mint_ref, to, amount_ld);

        amount_ld
    }

    /// How sent value should be debited from the sender
    ///
    /// @return (amount_sent_ld, amount_received_ld)
    public(friend) fun debit_fungible_asset(
        token: Bytes32,
        _sender: address,
        fa: &mut FungibleAsset,
        min_amount_ld: u64,
        dst_eid: u32,
    ): (u64, u64) acquires WoftImplStore {
        assert_metadata(token, fa);

        // Calculate the exact send amount
        let amount_ld = fungible_asset::amount(fa);
        let (amount_sent_ld, amount_received_ld) = debit_view(token, amount_ld, min_amount_ld, dst_eid);

        // Extract the exact send amount from the provided fungible asset
        let extracted_fa = fungible_asset::extract(fa, amount_sent_ld);

        // Remove the fee from the extracted amount and deposit it to the fee deposit address
        let bridge_fee_fa = fungible_asset::extract(&mut extracted_fa, amount_sent_ld - amount_received_ld);
        primary_fungible_store::deposit(store().fee_deposit_address, bridge_fee_fa);

        // Burn the extracted amount
        fungible_asset::burn(&token_store(token).burn_ref, extracted_fa);

        (amount_sent_ld, amount_received_ld)
    }

    /// Show how much the user will send and receive given the amount they provide
    ///
    /// @return (amount_sent_ld, amount_received_ld)
    public(friend) fun debit_view(
        token: Bytes32,
        amount_ld: u64,
        min_amount_ld: u64,
        _dst_eid: u32
    ): (u64, u64) acquires WoftImplStore {
        let (fee_bps, _is_default) = get_fee_bps(token);

        if (fee_bps == 0) {
            // If there is no fee, the amount sent and received is simply the amount provided minus dust, which is left
            // in the wallet
            no_fee_debit_view(token, amount_ld, min_amount_ld)
        } else {
            // The amount sent is the amount provided. The excess dust is consumed as a "fee" even if the dust could be
            // left in the wallet in order to provide a more predictable experience for the user
            let amount_sent_ld = amount_ld;

            // Calculate the preliminary fee based on the amount provided; this may increase when dust is added to it.
            // The actual fee is the amount sent - amount received, which is fee + dust removed
            let preliminary_fee = (amount_ld * fee_bps) / 10_000;

            // Compute the received amount first, which is the amount after fee and dust removal
            let amount_received_ld = remove_dust(token, amount_ld - preliminary_fee);

            // Ensure the amount received is greater than the minimum amount
            assert!(amount_received_ld >= min_amount_ld, ESLIPPAGE_EXCEEDED);

            (amount_sent_ld, amount_received_ld)
        }
    }

    /// Change this to override the Executor and DVN options of the WOFT transmission
    public(friend) fun build_options(
        message_type: u16,
        dst_eid: u32,
        extra_options: vector<u8>,
        _user_sender: address,
        _amount_received_ld: u64,
        _to: Bytes32,
        _compose_msg: vector<u8>,
    ): vector<u8> {
        combine_options(dst_eid, message_type, extra_options)
    }

    /// Implement this function to inspect the message and options before quoting and sending
    public(friend) fun inspect_message(
        _message: &vector<u8>,
        _options: &vector<u8>,
        _is_sending: bool,
    ) {}

    /// Change this to override the WOFT limit and fees provided when quoting. The fees should reflect the difference
    /// between the amount sent and the amount received returned from debit() and debit_view()
    public(friend) fun woft_limit_and_fees(
        token: Bytes32,
        dst_eid: u32,
        _to: vector<u8>,
        amount_ld: u64,
        min_amount_ld: u64,
        _extra_options: vector<u8>,
        _compose_msg: vector<u8>,
    ): (OftLimit, vector<OftFeeDetail>) acquires WoftImplStore {
        (new_unbounded_oft_limit(), fee_details_with_possible_fee(token, amount_ld, min_amount_ld, dst_eid))
    }

    /// Specify the fee details based the configured fee and the amount sent
    fun fee_details_with_possible_fee(
        token: Bytes32,
        amount_ld: u64,
        min_amount_ld: u64,
        dst_eid: u32,
    ): vector<OftFeeDetail> acquires WoftImplStore {
        let (amount_sent_ld, amount_received_ld) = debit_view(token, amount_ld, min_amount_ld, dst_eid);
        let fee = amount_sent_ld - amount_received_ld;
        if (fee != 0) {
            vector[new_oft_fee_detail(fee, false, utf8(b"OFT Fee"))]
        } else {
            vector[]
        }
    }

    // =================================================== Metadata ===================================================

    public(friend) fun metadata(token: Bytes32): Object<Metadata> acquires WoftImplStore {
        token_store(token).metadata
    }

    fun assert_metadata(token: Bytes32, fa: &FungibleAsset) acquires WoftImplStore {
        let fa_metadata = fungible_asset::metadata_from_asset(fa);
        assert!(fa_metadata == metadata(token), EWRONG_FA_METADATA);
    }

    public(friend) fun balance(token: Bytes32, account: address): u64 acquires WoftImplStore {
        primary_fungible_store::balance(account, metadata(token))
    }

    // ================================================= Configuration ================================================

    // The maximum fee that can be set is 100%
    const MAX_FEE_BPS: u64 = 10_000;

    /// Set the fee deposit address
    public(friend) fun set_fee_deposit_address(fee_deposit_address: address) acquires WoftImplStore {
        store_mut().fee_deposit_address = fee_deposit_address;
        emit(FeeDepositAddressSet { fee_deposit_address });
    }

    /// Set the default fee (in BPS) for outbound sends
    /// This fee is used when a token does not have a custom fee set
    public(friend) fun set_default_fee_bps(fee_bps: u64) acquires WoftImplStore {
        store_mut().default_fee_bps = fee_bps;
        emit(DefaultFeeSet { fee_bps });
    }

    #[view]
    /// Get the default fee (in BPS) for outbound sends
    public(friend) fun get_default_fee_bps(): u64 acquires WoftImplStore {
        store().default_fee_bps
    }

    /// Set the fee (in BPS) for outbound sends
    public(friend) fun set_fee_bps(token: Bytes32, fee_bps: u64) acquires WoftImplStore {
        assert!(fee_bps <= MAX_FEE_BPS, EINVALID_FEE);
        token_store_mut(token).fee_bps = option::some(fee_bps);
        emit(FeeSet { token, fee_bps });
    }

    /// Unset the fee (in BPS) for outbound sends.  After unsetting the fee falls back to the default fee.
    public(friend) fun unset_fee_bps(token: Bytes32) acquires WoftImplStore {
        token_store_mut(token).fee_bps = option::none();
        emit(FeeUnset { token });
    }

    /// Get the fee (in BPS) for outbound sends (and whether or not the default fee is used)
    ///
    /// @return (fee_bps, is_default_fee)
    public(friend) fun get_fee_bps(token: Bytes32): (u64, bool) acquires WoftImplStore {
        let token_fee = token_store(token).fee_bps;
        if (option::is_some(&token_fee)) {
            // Token has custom fee
            (*option::borrow(&token_fee), false)
        } else {
            // Token uses default fee
            (store().default_fee_bps, true)
        }
    }

    /// Update the icon URI for the token
    public(friend) fun set_icon_uri(token: Bytes32, icon_uri: String) acquires WoftImplStore {
        fungible_asset::mutate_metadata(
            &token_store(token).mutate_metadata_ref,
            option::none(),
            option::none(),
            option::none(),
            option::some(icon_uri),
            option::none(),
        );
    }

    /// Update the project URI for the token
    public(friend) fun set_project_uri(token: Bytes32, project_uri: String) acquires WoftImplStore {
        fungible_asset::mutate_metadata(
            &token_store(token).mutate_metadata_ref,
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::some(project_uri),
        );
    }

    /// Release the references for the token
    public(friend) fun release_refs(token: Bytes32): (
        ExtendRef,
        object::TransferRef,
        MutateMetadataRef,
        fungible_asset::TransferRef,
        MintRef,
        BurnRef,
    ) acquires WoftImplStore {
        let token_store = token_store_mut(token);

        let ReleaseableRefs {
            metadata_extend_ref,
            metadata_transfer_ref,
            fa_mutate_ref,
            fa_transfer_ref,
            fa_mint_ref,
            fa_burn_ref,
        } = option::extract(&mut token_store.releasable_refs);

        (metadata_extend_ref, metadata_transfer_ref, fa_mutate_ref, fa_transfer_ref, fa_mint_ref, fa_burn_ref)
    }

    // ================================================ Initialization ================================================

    public(friend) fun initialize(
        factory: &signer,
        token: Bytes32,
        token_name: String,
        symbol: String,
        shared_decimals: u8,
        local_decimals: u8,
    ) acquires WoftImplStore {
        // Create the Fungible Asset, using an object seeded by the unique peer token address
        let constructor_ref = &object::create_named_object(factory, from_bytes32(token));
        object::disable_ungated_transfer(&object::generate_transfer_ref(constructor_ref));
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            token_name,
            symbol,
            local_decimals,
            utf8(b""),
            utf8(b""),
        );

        // Initialize the general WOFT configuration
        let metadata = address_to_object<Metadata>(address_from_constructor_ref(constructor_ref));
        woft_core::initialize(token, metadata, local_decimals, shared_decimals);

        // Instantiate this WOFT implementation
        table::add(&mut store_mut().woft_impls, token, WoftImpl {
            metadata: address_to_object<Metadata>(address_from_constructor_ref(constructor_ref)),
            mint_ref: fungible_asset::generate_mint_ref(constructor_ref),
            burn_ref: fungible_asset::generate_burn_ref(constructor_ref),
            transfer_ref: fungible_asset::generate_transfer_ref(constructor_ref),
            mutate_metadata_ref: fungible_asset::generate_mutate_metadata_ref(constructor_ref),
            fee_bps: option::none(),
            releasable_refs: option::some(ReleaseableRefs {
                metadata_extend_ref: object::generate_extend_ref(constructor_ref),
                metadata_transfer_ref: object::generate_transfer_ref(constructor_ref),
                fa_mutate_ref: fungible_asset::generate_mutate_metadata_ref(constructor_ref),
                fa_transfer_ref: fungible_asset::generate_transfer_ref(constructor_ref),
                fa_mint_ref: fungible_asset::generate_mint_ref(constructor_ref),
                fa_burn_ref: fungible_asset::generate_burn_ref(constructor_ref),
            })
        });
    }

    fun init_module(account: &signer) {
        move_to(move account, WoftImplStore {
            woft_impls: table::new(),
            default_fee_bps: 0,
            fee_deposit_address: @bridge_remote_admin,
        });
    }

    #[test_only]
    public fun init_module_for_test() {
        init_module(&std::account::create_signer_for_test(OAPP_ADDRESS()));
    }

    // =================================================== Helpers ====================================================

    #[test_only]
    public fun mint_tokens_for_test(token: Bytes32, amount_ld: u64): FungibleAsset acquires WoftImplStore {
        fungible_asset::mint(&token_store(token).mint_ref, amount_ld)
    }

    inline fun token_store(token: Bytes32): &WoftImpl {
        table::borrow(&store().woft_impls, token)
    }

    inline fun token_store_mut(token: Bytes32): &mut WoftImpl {
        table::borrow_mut(&mut store_mut().woft_impls, token)
    }

    inline fun store(): &WoftImplStore {
        borrow_global(OAPP_ADDRESS())
    }

    inline fun store_mut(): &mut WoftImplStore {
        borrow_global_mut(OAPP_ADDRESS())
    }

    // ==================================================== Events ====================================================

    #[event]
    struct FeeDepositAddressSet has drop, store {
        fee_deposit_address: address,
    }

    #[event]
    struct DefaultFeeSet has drop, store {
        fee_bps: u64,
    }

    #[event]
    struct FeeSet has drop, store {
        token: Bytes32,
        fee_bps: u64,
    }

    #[event]
    struct FeeUnset has drop, store {
        token: Bytes32,
    }

    #[test_only]
    public fun fee_deposit_address_set_event(fee_deposit_address: address): FeeDepositAddressSet {
        FeeDepositAddressSet { fee_deposit_address }
    }

    #[test_only]
    public fun default_fee_set_event(fee_bps: u64): DefaultFeeSet {
        DefaultFeeSet { fee_bps }
    }

    #[test_only]
    public fun fee_set_event(token: Bytes32, fee_bps: u64): FeeSet {
        FeeSet { token, fee_bps }
    }

    #[test_only]
    public fun fee_unset_event(token: Bytes32): FeeUnset {
        FeeUnset { token }
    }

    // ================================================== Error Codes =================================================

    const EINVALID_FEE: u64 = 1;
    const ENOT_IMPLEMENTED: u64 = 2;
    const EUNAUTHORIZED: u64 = 3;
    const EWRONG_FA_METADATA: u64 = 4;
    const ESLIPPAGE_EXCEEDED: u64 = 5;
}