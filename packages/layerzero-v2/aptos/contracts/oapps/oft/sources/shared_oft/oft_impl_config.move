module oft::oft_impl_config {
    use std::event::emit;
    use std::math64::min;
    use std::string::utf8;
    use std::table::{Self, Table};
    use std::timestamp;

    use oft::oapp_core::get_admin;
    use oft::oapp_store::OAPP_ADDRESS;
    use oft::oft_core::{no_fee_debit_view, remove_dust};
    use oft_common::oft_fee_detail::{new_oft_fee_detail, OftFeeDetail};

    #[test_only]
    friend oft::oft_impl_config_tests;

    // **Important** Please delete any friend declarations to unused / deleted modules
    friend oft::oft_fa;
    friend oft::oft_adapter_fa;
    friend oft::oft_coin;
    friend oft::oft_adapter_coin;

    struct Config has key {
        fee_bps: u64,
        fee_deposit_address: address,
        blocklist_enabled: bool,
        blocklist: Table<address, bool>,
        rate_limit_by_eid: Table<u32, RateLimit>,
    }

    const MAX_U64: u64 = 0xffffffffffffffff;

    // =============================================== Fee Configuration ==============================================

    // The maximum fee that can be set is 100%
    const MAX_FEE_BPS: u64 = 10_000;

    /// Set the fee deposit address
    /// This is where OFT fees collected are deposited
    public(friend) fun set_fee_deposit_address(fee_deposit_address: address) acquires Config {
        // The fee deposit address must exist as an account to prevent revert for Coin deposits
        assert!(std::account::exists_at(fee_deposit_address), EINVALID_DEPOSIT_ADDRESS);
        assert!(store().fee_deposit_address != fee_deposit_address, ESETTING_UNCHANGED);
        store_mut().fee_deposit_address = fee_deposit_address;
        emit(FeeDepositAddressSet { fee_deposit_address });
    }

    /// Get the fee deposit address
    public(friend) fun fee_deposit_address(): address acquires Config { store().fee_deposit_address }

    /// Set the fee for the OFT
    public(friend) fun set_fee_bps(fee_bps: u64) acquires Config {
        assert!(fee_bps <= MAX_FEE_BPS, EINVALID_FEE);
        assert!(fee_bps != store().fee_bps, ESETTING_UNCHANGED);
        store_mut().fee_bps = fee_bps;
        emit(FeeSet { fee_bps });
    }

    /// Get the fee for the OFT
    public(friend) fun fee_bps(): u64 acquires Config { store().fee_bps }

    /// Calculate the amount sent and received after applying the fee
    /// If there is a zero fee, untransferable dust is to be left in user's wallet
    /// If there is a non-zero fee, untransferable dust is to be consumed as a fee
    /// This is consistent with EVM fee-enabled OFTs vs non-fee OFTs (we match fee = 0 with non-fee OFT behavior)
    public(friend) fun debit_view_with_possible_fee(
        amount_ld: u64,
        min_amount_ld: u64,
    ): (u64, u64) acquires Config {
        let fee_bps = store().fee_bps;
        if (fee_bps == 0) {
            // If there is no fee, the amount sent and received is simply the amount provided minus dust, which is left
            // in the wallet
            no_fee_debit_view(amount_ld, min_amount_ld)
        } else {
            // The amount sent is the amount provided. The excess dust is consumed as a "fee" even if the dust could be
            // left in the wallet in order to provide a more predictable experience for the user
            let amount_sent_ld = amount_ld;

            // Calculate the preliminary fee based on the amount provided; this may increase when dust is added to it.
            // The actual fee is the amount sent - amount received, which is fee + dust removed
            let preliminary_fee = ((((amount_ld as u128) * (fee_bps as u128)) / 10_000) as u64);

            // Compute the received amount first, which is the amount after fee and dust removal
            let amount_received_ld = remove_dust(amount_ld - preliminary_fee);

            // Ensure the amount received is greater than the minimum amount
            assert!(amount_received_ld >= min_amount_ld, ESLIPPAGE_EXCEEDED);

            (amount_sent_ld, amount_received_ld)
        }
    }

    /// Specify the fee details based the configured fee and the amount sent
    public(friend) fun fee_details_with_possible_fee(
        amount_ld: u64,
        min_amount_ld: u64
    ): vector<OftFeeDetail> acquires Config {
        let (amount_sent_ld, amount_received_ld) = debit_view_with_possible_fee(amount_ld, min_amount_ld);
        let fee = amount_sent_ld - amount_received_ld;
        if (fee != 0) {
            vector[new_oft_fee_detail(fee, false, utf8(b"OFT Fee"))]
        } else {
            vector[]
        }
    }

    // ============================================ Blocklist Configuration ===========================================

    /// Permanently disable the ability to blocklist accounts
    /// This will also effectively restore any previously blocked accounts to unblocked status (is_blocklisted() will
    /// return false for all accounts)
    /// This is a one-way operation, once this is called, the blocklist capability cannot be restored
    public(friend) fun irrevocably_disable_blocklist() acquires Config {
        assert!(store().blocklist_enabled, EBLOCKLIST_ALREADY_DISABLED);
        store_mut().blocklist_enabled = false;
        emit(BlocklistingDisabled {})
    }

    /// Check if the blocklisting capability is enabled
    public(friend) fun can_blocklist(): bool acquires Config {
        store().blocklist_enabled
    }

    /// Add or remove an account from the blocklist
    public(friend) fun set_blocklist(wallet: address, blocklist: bool) acquires Config {
        assert!(store().blocklist_enabled, EBLOCKLIST_DISABLED);
        assert!(is_blocklisted(wallet) != blocklist, ESETTING_UNCHANGED);
        if (blocklist) {
            table::upsert(&mut store_mut().blocklist, wallet, true)
        } else {
            table::remove(&mut store_mut().blocklist, wallet);
        };
        emit(BlocklistSet { wallet, blocked: blocklist });
    }

    /// Check if an account is blocked
    public(friend) fun is_blocklisted(wallet: address): bool acquires Config {
        store().blocklist_enabled && *table::borrow_with_default(&store().blocklist, wallet, &false)
    }

    /// Revert if an account is blocked
    public(friend) fun assert_not_blocklisted(wallet: address) acquires Config {
        assert!(!is_blocklisted(wallet), EADDRESS_BLOCKED);
    }

    /// Provide the admin address and emit a BlockedAmountRedirected event if an account is blocked
    /// This is to be used in conjunction with a deposit(to) call and provides the admin address instead of the
    /// recipient address if recipient is blocklisted. This also emits a message to alert that blocklisted funds have
    /// been received
    public(friend) fun redirect_to_admin_if_blocklisted(recipient: address, amount_ld: u64): address acquires Config {
        if (!is_blocklisted(recipient)) {
            recipient
        } else {
            emit(BlockedAmountRedirected {
                amount_ld,
                blocked_address: recipient,
                redirected_to: get_admin(),
            });
            get_admin()
        }
    }

    // ======================================= Sending Rate Limit Configuration =======================================

    struct RateLimit has store, drop, copy {
        limit: u64,
        window_seconds: u64,
        in_flight_on_last_update: u64,
        last_update: u64,
    }

    /// Set the rate limit (local_decimals) and the window (seconds) at the current timestamp
    /// The capacity of the rate limit increased by limit_ld/window_s until it reaches the limit and stays there
    public(friend) fun set_rate_limit(dst_eid: u32, limit: u64, window_seconds: u64) acquires Config {
        set_rate_limit_at_timestamp(dst_eid, limit, window_seconds, timestamp::now_seconds());
    }

    /// Set or update the rate limit for a given EID at a specified timestamp
    public(friend) fun set_rate_limit_at_timestamp(
        dst_eid: u32,
        limit: u64,
        window_seconds: u64,
        timestamp: u64
    ) acquires Config {
        assert!(window_seconds > 0, EINVALID_WINDOW);

        // If the rate limit is already set, checkpoint the in-flight amount before updating the rate limit.
        if (has_rate_limit(dst_eid)) {
            let (prior_limit, prior_window_seconds) = rate_limit_config(dst_eid);
            assert!(limit != prior_limit || window_seconds != prior_window_seconds, ESETTING_UNCHANGED);

            // Checkpoint the in-flight amount before updating the rate settings. If this is not saved, it could change
            // the in-flight calculation amount retroactively
            checkpoint_rate_limit_in_flight(dst_eid, timestamp);

            let rate_limit_store = table::borrow_mut(&mut store_mut().rate_limit_by_eid, dst_eid);
            rate_limit_store.limit = limit;
            rate_limit_store.window_seconds = window_seconds;
            emit(RateLimitUpdated { dst_eid, limit, window_seconds });
        } else {
            table::upsert(&mut store_mut().rate_limit_by_eid, dst_eid, RateLimit {
                limit,
                window_seconds,
                in_flight_on_last_update: 0,
                last_update: timestamp,
            });
            emit(RateLimitSet { dst_eid, limit, window_seconds });
        };
    }

    /// Unset the rate limit for a given EID
    public(friend) fun unset_rate_limit(eid: u32) acquires Config {
        assert!(table::contains(&store().rate_limit_by_eid, eid), ESETTING_UNCHANGED);
        table::remove(&mut store_mut().rate_limit_by_eid, eid);
        emit(RateLimitUnset { eid });
    }

    /// Checkpoint the in-flight amount for a given EID for the provided timestamp.
    /// This should whenever there is a change in rate limit or before consuming rate limit capacity
    public(friend) fun checkpoint_rate_limit_in_flight(eid: u32, timestamp: u64) acquires Config {
        let inflight = in_flight_at_time(eid, timestamp);
        let rate_limit = table::borrow_mut(&mut store_mut().rate_limit_by_eid, eid);
        rate_limit.in_flight_on_last_update = inflight;
        rate_limit.last_update = timestamp;
    }


    /// Check if a rate limit is set for a given EID
    public(friend) fun has_rate_limit(eid: u32): bool acquires Config {
        table::contains(&store().rate_limit_by_eid, eid)
    }

    /// Get the rate limit and window (in seconds) for a given EID
    public(friend) fun rate_limit_config(eid: u32): (u64, u64) acquires Config {
        if (!has_rate_limit(eid)) {
            (0, 0)
        } else {
            let rate_limit = *table::borrow(&store().rate_limit_by_eid, eid);
            (rate_limit.limit, rate_limit.window_seconds)
        }
    }

    /// Get the in-flight amount for a given EID at present
    public(friend) fun in_flight(eid: u32): u64 acquires Config {
        in_flight_at_time(eid, timestamp::now_seconds())
    }

    /// Get the in-flight amount for a given EID. The in-flight count is the amount of the rate limit that has been
    /// consumed linearly decayed to the provided timestamp
    public(friend) fun in_flight_at_time(eid: u32, timestamp: u64): u64 acquires Config {
        if (!has_rate_limit(eid)) {
            0
        } else {
            let rate_limit = *table::borrow(&store().rate_limit_by_eid, eid);
            if (timestamp > rate_limit.last_update) {
                // If the timestamp is greater than the last update, calculate the decayed in-flight amount
                let elapsed = min(timestamp - rate_limit.last_update, rate_limit.window_seconds);
                let decay = ((((elapsed as u128) * (rate_limit.limit as u128)) / (rate_limit.window_seconds as u128)) as u64);

                // Ensure the decayed in-flight amount is not negative
                if (decay < rate_limit.in_flight_on_last_update) {
                    rate_limit.in_flight_on_last_update - decay
                } else {
                    0
                }
            } else {
                // If not, return the unaltered in-flight amount at the last checkpoint
                rate_limit.in_flight_on_last_update
            }
        }
    }

    /// Calculate the spare rate limit capacity for a given EID at present
    public(friend) fun rate_limit_capacity(eid: u32): u64 acquires Config {
        rate_limit_capacity_at_time(eid, timestamp::now_seconds())
    }

    /// Calculate the spare rate limit capacity for a given EID at the proviced timestamp
    public(friend) fun rate_limit_capacity_at_time(eid: u32, timestamp: u64): u64 acquires Config {
        if (!has_rate_limit(eid)) {
            return MAX_U64
        };
        let rate_limit = *table::borrow(&store().rate_limit_by_eid, eid);
        if (rate_limit.limit > in_flight_at_time(eid, timestamp)) {
            rate_limit.limit - in_flight_at_time(eid, timestamp)
        } else {
            0
        }
    }

    /// Consume rate limit capacity for a given EID or abort if the capacity is exceeded
    public(friend) fun try_consume_rate_limit_capacity(eid: u32, amount: u64) acquires Config {
        if (!has_rate_limit(eid)) return;
        try_consume_rate_limit_capacity_at_time(eid, amount, timestamp::now_seconds());
    }

    /// Consume rate limit capacity for a given EID or abort if the capacity is exceeded at a provided timestamp
    public(friend) fun try_consume_rate_limit_capacity_at_time(
        eid: u32,
        amount: u64,
        timestamp: u64
    ) acquires Config {
        checkpoint_rate_limit_in_flight(eid, timestamp);
        let rate_limit = table::borrow_mut(&mut store_mut().rate_limit_by_eid, eid);
        assert!(rate_limit.in_flight_on_last_update + amount <= rate_limit.limit, EEXCEEDED_RATE_LIMIT);
        rate_limit.in_flight_on_last_update = rate_limit.in_flight_on_last_update + amount;
    }

    /// Release rate limit capacity for a given EID
    /// This is used to when wanting to rate limit by net inflow - outflow
    /// This will release the capacity back to the rate limit up to the limit itself
    public(friend) fun release_rate_limit_capacity(eid: u32, amount: u64) acquires Config {
        if (!has_rate_limit(eid)) return;

        let rate_limit = table::borrow_mut(&mut store_mut().rate_limit_by_eid, eid);
        if (amount >= rate_limit.in_flight_on_last_update) {
            rate_limit.in_flight_on_last_update = 0;
        } else {
            rate_limit.in_flight_on_last_update = rate_limit.in_flight_on_last_update - amount;
        }
    }

    // ==================================================== Helpers ===================================================

    inline fun store(): &Config { borrow_global(OAPP_ADDRESS()) }

    inline fun store_mut(): &mut Config { borrow_global_mut(OAPP_ADDRESS()) }

    // ==================================================== Events ====================================================

    #[event]
    struct FeeDepositAddressSet has drop, store {
        fee_deposit_address: address,
    }

    #[event]
    struct FeeSet has drop, store {
        fee_bps: u64,
    }

    #[event]
    struct BlocklistingDisabled has drop, store {}

    #[event]
    struct BlocklistSet has drop, store {
        wallet: address,
        blocked: bool,
    }

    #[event]
    struct BlockedAmountRedirected has drop, store {
        amount_ld: u64,
        blocked_address: address,
        redirected_to: address,
    }

    #[event]
    struct RateLimitSet has drop, store {
        dst_eid: u32,
        limit: u64,
        window_seconds: u64,
    }

    #[event]
    struct RateLimitUpdated has drop, store {
        dst_eid: u32,
        limit: u64,
        window_seconds: u64,
    }

    #[event]
    struct RateLimitUnset has drop, store {
        eid: u32,
    }

    #[test_only]
    public fun fee_deposit_address_set_event(fee_deposit_address: address): FeeDepositAddressSet {
        FeeDepositAddressSet { fee_deposit_address }
    }

    #[test_only]
    public fun fee_set_event(fee_bps: u64): FeeSet {
        FeeSet { fee_bps }
    }

    #[test_only]
    public fun blocklisting_disabled_event(): BlocklistingDisabled {
        BlocklistingDisabled {}
    }

    #[test_only]
    public fun blocklist_set_event(wallet: address, blocked: bool): BlocklistSet {
        BlocklistSet { wallet, blocked }
    }

    #[test_only]
    public fun blocked_amount_redirected_event(
        amount_ld: u64,
        blocked_address: address,
        redirected_to: address
    ): BlockedAmountRedirected {
        BlockedAmountRedirected { amount_ld, blocked_address, redirected_to }
    }

    #[test_only]
    public fun rate_limit_set_event(dst_eid: u32, limit: u64, window_seconds: u64): RateLimitSet {
        RateLimitSet { dst_eid, limit, window_seconds }
    }

    #[test_only]
    public fun rate_limit_updated_event(dst_eid: u32, limit: u64, window_seconds: u64): RateLimitUpdated {
        RateLimitUpdated { dst_eid, limit, window_seconds }
    }

    #[test_only]
    public fun rate_limit_unset_event(eid: u32): RateLimitUnset {
        RateLimitUnset { eid }
    }

    // ================================================ Initialization ================================================

    fun init_module(account: &signer) {
        move_to(move account, Config {
            fee_bps: 0,
            fee_deposit_address: @oft_admin,
            blocklist_enabled: true,
            blocklist: table::new(),
            rate_limit_by_eid: table::new(),
        });
    }

    #[test_only]
    public fun init_module_for_test() {
        init_module(&std::account::create_signer_for_test(OAPP_ADDRESS()));
    }

    // ================================================== Error Codes =================================================

    const EADDRESS_BLOCKED: u64 = 1;
    const EBLOCKLIST_ALREADY_DISABLED: u64 = 2;
    const EBLOCKLIST_DISABLED: u64 = 3;
    const EEXCEEDED_RATE_LIMIT: u64 = 4;
    const EINVALID_DEPOSIT_ADDRESS: u64 = 5;
    const EINVALID_FEE: u64 = 6;
    const EINVALID_WINDOW: u64 = 7;
    const ESETTING_UNCHANGED: u64 = 8;
    const ESLIPPAGE_EXCEEDED: u64 = 9;
}
