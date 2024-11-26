module treasury::treasury {
    use std::account;
    use std::event::emit;
    use std::fungible_asset::{Self, FungibleAsset};
    use std::object::object_address;
    use std::primary_fungible_store;
    use std::signer::address_of;

    use endpoint_v2_common::universal_config;

    #[test_only]
    friend treasury::treasury_tests;

    const TREASURY_ADMIN: address = @layerzero_treasury_admin;

    // Treasury Fee cannot be set above 100%
    const MAX_BPS: u64 = 10000;

    struct TreasuryConfig has key {
        // The native treasury fee (in basis points of worker fee subtotal)
        native_fee_bps: u64,
        // The ZRO treasury fee (a fixed amount per message)
        zro_fee: u64,
        // Whether the treasury fee can be paid in ZRO
        zro_enabled: bool,
        // The address to which the treasury fee should be deposited
        deposit_address: address,
    }

    fun init_module(account: &signer) {
        move_to(account, TreasuryConfig {
            native_fee_bps: 0,
            zro_fee: 0,
            zro_enabled: false,
            deposit_address: TREASURY_ADMIN,
        });
    }

    #[test_only]
    public fun init_module_for_test() {
        let account = &std::account::create_signer_for_test(@treasury);
        init_module(account);
    }

    // ================================================== Admin Only ==================================================

    inline fun assert_admin(admin: address) {
        assert!(admin == TREASURY_ADMIN, EUNAUTHORIZED);
    }

    /// Updates the address to which the treasury fee is sent (must be a valid account)
    public entry fun update_deposit_address(account: &signer, deposit_address: address) acquires TreasuryConfig {
        assert!(account::exists_at(deposit_address), EINVALID_ACCOUNT_ADDRESS);
        assert_admin(address_of(move account));
        config_mut().deposit_address = deposit_address;
        emit(DepositAddressUpdated { new_deposit_address: deposit_address });
    }

    /// Enables receipt of ZRO
    public entry fun set_zro_enabled(account: &signer, enabled: bool) acquires TreasuryConfig {
        assert_admin(address_of(move account));
        config_mut().zro_enabled = enabled;
        emit(ZroEnabledSet { enabled });
    }

    /// Sets the treasury fee in basis points of the worker fee subtotal
    public entry fun set_native_bp(account: &signer, native_bps: u64) acquires TreasuryConfig {
        assert_admin(address_of(move account));
        assert!(native_bps <= MAX_BPS, EINVALID_FEE);
        config_mut().native_fee_bps = native_bps;
        emit(NativeBpSet { native_bps });
    }

    /// Sets the treasury fee in ZRO (as a fixed amount)
    public entry fun set_zro_fee(account: &signer, zro_fixed_fee: u64) acquires TreasuryConfig {
        assert_admin(address_of(move account));
        config_mut().zro_fee = zro_fixed_fee;
        emit(ZroFeeSet { zro_fee: zro_fixed_fee });
    }

    // =============================================== Public Functions ===============================================

    #[view]
    /// Calculates the treasury fee based on the worker fee (excluding treasury) and whether the fee should be paid in
    /// ZRO. If the fee should be paid in ZRO, the fee is returned in ZRO, otherwise the fee is returned is Native token
    public fun get_fee(total_worker_fee: u64, pay_in_zro: bool): u64 acquires TreasuryConfig {
        if (pay_in_zro) {
            assert!(get_zro_enabled(), EPAY_IN_ZRO_NOT_ENABLED);
            config().zro_fee
        } else {
            total_worker_fee * config().native_fee_bps / 10000
        }
    }

    #[view]
    public fun get_native_bp(): u64 acquires TreasuryConfig { config().native_fee_bps }

    #[view]
    public fun get_zro_fee(): u64 acquires TreasuryConfig { config().zro_fee }

    #[view]
    public fun get_zro_enabled(): bool acquires TreasuryConfig { config().zro_enabled }

    #[view]
    public fun get_deposit_address(): address acquires TreasuryConfig { config().deposit_address }

    /// Pay the fee to the treasury. The fee is calculated based on the worker fee (excluding treasury), and whether
    /// the FungibleAsset payment is in ZRO or Native token. The fee is extracted from the provided &mut FungibleAsset
    public fun pay_fee(
        total_worker_fee: u64,
        payment: &mut FungibleAsset,
    ): (u64) acquires TreasuryConfig {
        let metadata = fungible_asset::asset_metadata(payment);

        if (object_address(&metadata) == @native_token_metadata_address) {
            let fee = get_fee(total_worker_fee, false);
            deposit_fungible_asset(fee, payment);
            fee
        } else if (config().zro_enabled && universal_config::is_zro_metadata(metadata)) {
            let fee = get_fee(total_worker_fee, true);
            deposit_fungible_asset(fee, payment);
            fee
        } else if (!config().zro_enabled) {
            abort EPAY_IN_ZRO_NOT_ENABLED
        } else {
            abort EUNEXPECTED_TOKEN_TYPE
        }
    }

    /// Deposits the payment into the treasury
    fun deposit_fungible_asset(charge: u64, payment: &mut FungibleAsset) acquires TreasuryConfig {
        let deposit_address = config().deposit_address;
        let deposit = fungible_asset::extract(payment, charge);
        primary_fungible_store::deposit(deposit_address, deposit);
    }

    // =============================================== Helper Functions ===============================================

    inline fun config(): &TreasuryConfig { borrow_global(@treasury) }

    inline fun config_mut(): &mut TreasuryConfig { borrow_global_mut(@treasury) }

    // ==================================================== Events ====================================================

    #[event]
    struct ZroEnabledSet has drop, store {
        enabled: bool,
    }

    #[event]
    struct NativeBpSet has drop, store {
        native_bps: u64,
    }

    #[event]
    struct ZroFeeSet has drop, store {
        zro_fee: u64,
    }

    #[event]
    struct DepositAddressUpdated has drop, store {
        new_deposit_address: address,
    }

    #[test_only]
    public fun zro_enabled_set_event(enabled: bool): ZroEnabledSet {
        ZroEnabledSet { enabled }
    }

    #[test_only]
    public fun native_bp_set_event(native_bp: u64): NativeBpSet {
        NativeBpSet { native_bps: native_bp }
    }

    #[test_only]
    public fun zro_fee_set_event(zro_fee: u64): ZroFeeSet {
        ZroFeeSet { zro_fee }
    }

    #[test_only]
    public fun deposit_address_updated_event(new_deposit_address: address): DepositAddressUpdated {
        DepositAddressUpdated { new_deposit_address }
    }

    // ================================================== Error Codes =================================================

    const EUNEXPECTED_TOKEN_TYPE: u64 = 1;
    const EINVALID_ACCOUNT_ADDRESS: u64 = 2;
    const EINVALID_FEE: u64 = 3;
    const EPAY_IN_ZRO_NOT_ENABLED: u64 = 4;
    const EUNAUTHORIZED: u64 = 5;
}
