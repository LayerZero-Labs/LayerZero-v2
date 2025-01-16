/// This is an implementation of a Coin-standard, Adapter-style OFT.
///
/// An adapter can be used with a Coin that is already deployed, which cannot share burn and mint capabilities. This
/// relies on locking and unlocking the Coin in an escrow account rather than minting and burning.
///
/// Adapter OFTs should only be deployed on one chain per token (with the other EIDs having Native/mint-and-burn OFTs),
/// because there is not a rebalancing mechanism that can ensure pools maintain sufficient balance.
module oft::oft_adapter_coin {
    use std::account::create_account_if_does_not_exist;
    use std::aptos_account;
    use std::coin::{Self, Coin};
    use std::fungible_asset::{FungibleAsset, Metadata};
    use std::object::{Self, ExtendRef, Object};
    use std::option::{Self, Option};
    use std::primary_fungible_store;
    use std::signer::address_of;

    use endpoint_v2_common::bytes32::Bytes32;
    use oft::oapp_core::{assert_admin, combine_options};
    use oft::oapp_store::OAPP_ADDRESS;
    use oft::oft_core;
    use oft::oft_impl_config;
    use oft::oft_impl_config::{
        assert_not_blocklisted, debit_view_with_possible_fee, fee_details_with_possible_fee,
        redirect_to_admin_if_blocklisted,
        release_rate_limit_capacity, try_consume_rate_limit_capacity,
    };
    use oft::placeholder_coin::PlaceholderCoin;
    use oft_common::oft_fee_detail::OftFeeDetail;
    use oft_common::oft_limit::{Self, OftLimit};

    friend oft::oft;
    friend oft::oapp_receive;

    #[test_only]
    friend oft::oft_adapter_coin_tests;

    // ************************************************* CONFIGURATION *************************************************

    // *Important*: Update this to be the desired shared decimals of the Coin
    const SHARED_DECIMALS: u8 = 6;

    // *********************************************** END CONFIGURATION ***********************************************

    struct OftImpl has key {
        escrow_extend_ref: ExtendRef,
    }

    // ================================================= OFT Handlers =================================================

    /// The default *credit* behavior for a Coin Adapter OFT is to unlock the amount from escrow and credit the
    /// recipient. The recipient must have registered their coin store to receive the released amount.
    public(friend) fun credit(
        to: address,
        amount_ld: u64,
        src_eid: u32,
        lz_receive_value: Option<FungibleAsset>,
    ): u64 acquires OftImpl {
        // Default implementation does not make special use of LZ Receive Value sent; just deposit to the OFT address
        option::for_each(lz_receive_value, |fa| primary_fungible_store::deposit(@oft_admin, fa));

        // Release rate limit capacity for the pathway (net inflow)
        release_rate_limit_capacity(src_eid, amount_ld);

        // unlock the amount from escrow
        let escrow_signer = &object::generate_signer_for_extending(&store().escrow_extend_ref);
        let extracted = coin::withdraw<PlaceholderCoin>(escrow_signer, amount_ld);

        // Deposit the extracted amount to the recipient, or redirect to the admin if the recipient is blocklisted
        deposit_coin(redirect_to_admin_if_blocklisted(to, amount_ld), extracted);

        amount_ld
    }

    /// Unused in this implementation
    public(friend) fun debit_fungible_asset(
        _sender: address,
        _fa: &mut FungibleAsset,
        _min_amount_ld: u64,
        _dst_eid: u32,
    ): (u64, u64) {
        abort ENOT_IMPLEMENTED
    }

    /// The default *debit* behavior for a Coin Adapter OFT is to lock the deducted amount in escrow
    /// @return (amount_sent_ld, amount_received_ld)
    public(friend) fun debit_coin<CoinType>(
        sender: address,
        coin: &mut Coin<CoinType>,
        min_amount_ld: u64,
        dst_eid: u32,
    ): (u64, u64) acquires OftImpl {
        assert_not_blocklisted(sender);

        // Set the send amount to the amount provided in Coin
        let amount_ld = coin::value(coin);
        let (amount_sent_ld, amount_received_ld) = debit_view(amount_ld, min_amount_ld, dst_eid);

        // Consume rate limit capacity for the pathway (net outflow), based on the amount received on the other side
        try_consume_rate_limit_capacity(dst_eid, amount_received_ld);

        // Extract the exact send amount from the provided Coin
        let extracted_coin = coin::extract(coin, amount_sent_ld);

        // Extract the fee and deposit it to the fee deposit address
        let fee_ld = (amount_sent_ld - amount_received_ld);
        if (fee_ld > 0) {
            let fee_coin = coin::extract(&mut extracted_coin, fee_ld);
            std::aptos_account::deposit_coins<CoinType>(fee_deposit_address(), fee_coin);
        };

        // Lock the amount in escrow
        let escrow_address = escrow_address();
        std::aptos_account::deposit_coins<CoinType>(escrow_address, extracted_coin);

        (amount_sent_ld, amount_received_ld)
    }

    /// The default *debit_view* behavior for a Adapter OFT is to remove dust and use remainder as both the sent and
    /// received amounts, reflecting that no additional fees are removed
    public(friend) fun debit_view(amount_ld: u64, min_amount_ld: u64, _dst_eid: u32): (u64, u64) {
        debit_view_with_possible_fee(amount_ld, min_amount_ld)
    }

    /// Update this to override the Executor and DVN options of the OFT transmission
    public(friend) fun build_options(
        message_type: u16,
        dst_eid: u32,
        extra_options: vector<u8>,
        _user_sender: address,
        _amount_received_ld: u64,
        _to: Bytes32,
        _compose_msg: vector<u8>,
        _oft_cmd: vector<u8>,
    ): vector<u8> {
        combine_options(dst_eid, message_type, extra_options)
    }

    /// Implement this function to inspect the message and options before quoting and sending
    public(friend) fun inspect_message(
        _message: &vector<u8>,
        _options: &vector<u8>,
        _is_sending: bool,
    ) {}

    /// Change this to override the OFT limit and fees provided when quoting. The fees should reflect the difference
    /// between the amount sent and the amount received returned from debit() and debit_view()
    public(friend) fun oft_limit_and_fees(
        dst_eid: u32,
        _to: vector<u8>,
        amount_ld: u64,
        min_amount_ld: u64,
        _extra_options: vector<u8>,
        _compose_msg: vector<u8>,
        _oft_cmd: vector<u8>,
    ): (OftLimit, vector<OftFeeDetail>) {
        (rate_limited_oft_limit(dst_eid), fee_details_with_possible_fee(amount_ld, min_amount_ld))
    }

    // =========================================== Coin Deposit / Withdrawal ==========================================

    /// Deposit coin function abstracted from `oft.move` for cross-chain flexibility
    public(friend) fun deposit_coin<CoinType>(account: address, coin: Coin<CoinType>) {
        aptos_account::deposit_coins<CoinType>(account, coin)
    }

    /// Withdraw coin function abstracted from `oft.move` for cross-chain flexibility
    public(friend) fun withdraw_coin<CoinType>(account: &signer, amount_ld: u64): Coin<CoinType> {
        assert!(coin::balance<CoinType>(address_of(account)) >= amount_ld, EINSUFFICIENT_BALANCE);
        coin::withdraw<CoinType>(account, amount_ld)
    }

    // =================================================== Metadata ===================================================

    public(friend) fun send_standards_supported(): vector<vector<u8>> {
        vector[b"coin"]
    }

    /// Coin-based OFTs do not have a fungible asset Metadata Object
    public(friend) fun metadata(): Object<Metadata> {
        abort ENOT_IMPLEMENTED
    }

    public(friend) fun balance(account: address): u64 {
        coin::balance<PlaceholderCoin>(account)
    }

    // ================================================= Configuration ================================================

    /// Set the fee (in BPS) for outbound OFT sends
    public entry fun set_fee_bps(admin: &signer, fee_bps: u64) {
        assert_admin(address_of(admin));
        oft_impl_config::set_fee_bps(fee_bps);
    }

    #[view]
    /// Get the fee (in BPS) for outbound OFT sends
    public fun fee_bps(): u64 { oft_impl_config::fee_bps() }

    /// Set the fee deposit address for outbound OFT sends
    public entry fun set_fee_deposit_address(admin: &signer, fee_deposit_address: address) {
        assert_admin(address_of(admin));
        oft_impl_config::set_fee_deposit_address(fee_deposit_address);
    }

    #[view]
    /// Get the fee deposit address for outbound OFT sends
    public fun fee_deposit_address(): address { oft_impl_config::fee_deposit_address() }

    /// Permanently disable the ability to blocklist addresses
    public entry fun irrevocably_disable_blocklist(admin: &signer) {
        assert_admin(address_of(admin));
        oft_impl_config::irrevocably_disable_blocklist();
    }

    /// Set the blocklist status of a wallet address
    /// If a wallet is blocklisted
    /// - OFT sends from the wallet will be blocked
    /// - OFT receives to the wallet will be be diverted to the admin
    public entry fun set_blocklist(admin: &signer, wallet: address, block: bool) {
        assert_admin(address_of(admin));
        oft_impl_config::set_blocklist(wallet, block);
    }

    #[view]
    /// Get the blocklist status of a wallet address
    public fun is_blocklisted(wallet: address): bool { oft_impl_config::is_blocklisted(wallet) }

    /// Set the rate limit configuration for a given endpoint ID
    /// The rate limit is the maximum amount of OFT that can be sent to the endpoint within a given window
    /// The rate limit capacity recovers linearly at a rate of limit / window_seconds
    /// *Important*: Setting the rate limit does not reset the current "in-flight" volume (in-flight refers to the
    /// decayed rate limit consumption). This means that if the rate limit is set lower than the current in-flight
    /// volume, the endpoint will not be able to receive OFT until the in-flight volume decays below the new rate limit.
    /// In order to reset the in-flight volume, the rate limit must be unset and then set again.
    public entry fun set_rate_limit(admin: &signer, eid: u32, limit: u64, window_seconds: u64) {
        assert_admin(address_of(admin));
        oft_impl_config::set_rate_limit(eid, limit, window_seconds);
    }

    /// Unset the rate limit
    public entry fun unset_rate_limit(admin: &signer, eid: u32) {
        assert_admin(address_of(admin));
        oft_impl_config::unset_rate_limit(eid);
    }

    #[view]
    /// Get the rate limit configuration for a given endpoint ID
    /// @return (limit, window_seconds)
    public fun rate_limit_config(eid: u32): (u64, u64) { oft_impl_config::rate_limit_config(eid) }

    #[view]
    /// Get the amount of rate limit capacity currently consumed on this pathway
    public fun rate_limit_in_flight(eid: u32): u64 { oft_impl_config::in_flight(eid) }

    #[view]
    /// Get the rate limit capacity for a given endpoint ID
    public fun rate_limit_capacity(eid: u32): u64 { oft_impl_config::rate_limit_capacity(eid) }

    /// Create an OftLimit that reflects the rate limit for a given endpoint ID
    public fun rate_limited_oft_limit(eid: u32): OftLimit {
        oft_limit::new_oft_limit(0, oft_impl_config::rate_limit_capacity(eid))
    }

    // ================================================ Initialization ================================================

    fun init_module(account: &signer) {
        // Create and register the Escrow Account owned by the contract
        let constructor_ref = &object::create_named_object(account, b"coin_escrow");
        let escrow_extend_ref = object::generate_extend_ref(constructor_ref);

        // Disable the transfer of the escrow object
        object::disable_ungated_transfer(&object::generate_transfer_ref(constructor_ref));

        // Register the coin
        coin::register<PlaceholderCoin>(account);

        // Register the escrow account for the Coin
        // The escrow object must be registered as an account to be registerable to accept deposits
        let escrow_signer = &object::generate_signer_for_extending(&escrow_extend_ref);
        create_account_if_does_not_exist(address_of(escrow_signer));
        coin::register<PlaceholderCoin>(move escrow_signer);

        // Save the extend ref to be able to sign for the escrow on credit
        move_to(account, OftImpl { escrow_extend_ref });

        // Initialize the oft_core
        let local_decimals = coin::decimals<PlaceholderCoin>();
        oft_core::initialize(local_decimals, SHARED_DECIMALS);
    }

    #[test_only]
    public fun init_module_for_test() {
        init_module(&std::account::create_account_for_test(OAPP_ADDRESS()));
    }

    // ================================================ Storage Helpers ===============================================

    #[view]
    public fun escrow_address(): address acquires OftImpl {
        object::address_from_extend_ref(&store().escrow_extend_ref)
    }

    inline fun store(): &OftImpl {
        borrow_global<OftImpl>(OAPP_ADDRESS())
    }

    // ================================================== Error Codes =================================================

    const EINSUFFICIENT_BALANCE: u64 = 1;
    const ENOT_IMPLEMENTED: u64 = 2;
}