module dvn_fee_lib_0::dvn_fee_lib {
    use msglib_types::worker_options::DVN_WORKER_ID;
    use price_feed_router_0::router as price_feed_router;
    use worker_common::multisig;
    use worker_common::worker_config;

    #[test_only]
    friend dvn_fee_lib_0::dvn_fee_lib_tests;

    const EXECUTE_FIXED_BYTES: u64 = 68;
    const SIGNATURE_RAW_BYTES: u64 = 65;
    const VERIFY_BYTES: u64 = 320;

    #[view]
    // Get the total fee, including premiums for a DVN worker to verify a message
    public fun get_dvn_fee(
        msglib: address,
        worker: address,
        dst_eid: u32,
        sender: address,
        _packet_header: vector<u8>,
        _payload_hash: vector<u8>,
        _confirmations: u64,
        _options: vector<u8>,
    ): (u64, address) {
        worker_config::assert_fee_lib_supports_transaction(worker, DVN_WORKER_ID(), sender, msglib);
        let calldata_size = get_calldata_size_for_fee(worker);

        let fee = get_dvn_fee_internal(
            worker,
            dst_eid,
            // Price Feed Estimate Fee on Send - partially applying parameters available in scope
            |price_feed, feed_address, total_gas| price_feed_router::estimate_fee_on_send(
                price_feed,
                feed_address,
                dst_eid,
                calldata_size,
                total_gas,
            )
        );

        let deposit_address = worker_config::get_deposit_address(worker);
        (fee, deposit_address)
    }

    /// Get the total fee, including premiums for a DVN packet, while ensuring that this feelib is supported by the
    /// worker, the sender is allowed, and the worker is unpaused
    ///
    /// @param worker_address: The address of the worker
    /// @param dst_eid: The destination EID
    /// @param estimate_fee_on_send: fee estimator (via price feed, with partially applied parameters)
    ///        |price_feed, feed_address, total_gas| (fee, price ratio, denominator, native token price in USD)
    public(friend) inline fun get_dvn_fee_internal(
        worker_address: address,
        dst_eid: u32,
        estimate_fee_on_send: |address, address, u128| (u128, u128, u128, u128),
    ): u64 {
        let (gas, multiplier_bps, floor_margin_usd) = worker_config::get_dvn_dst_config_values(worker_address, dst_eid);
        assert!(gas != 0, err_EDVN_EID_NOT_SUPPORTED());

        let (price_feed_module, feed_address) = worker_config::get_effective_price_feed(worker_address);
        let (chain_fee, _, _, native_price_usd) = estimate_fee_on_send(
            price_feed_module,
            feed_address,
            (gas as u128)
        );

        let default_multiplier_bps = worker_config::get_default_multiplier_bps(worker_address);
        let native_decimals_rate = worker_config::get_native_decimals_rate();

        (apply_premium(
            chain_fee,
            native_price_usd,
            multiplier_bps,
            floor_margin_usd,
            default_multiplier_bps,
            native_decimals_rate,
        ) as u64)
    }

    /// Apply the premium to the fee. It takes the higher of using the multiplier or the floor margin
    public(friend) fun apply_premium(
        chain_fee: u128,
        native_price_usd: u128, // in native_decimals_rate
        multiplier_bps: u16,
        floor_margin_usd: u128,
        default_multiplier_bps: u16,
        native_decimals_rate: u128,
    ): u128 {
        let multiplier_bps = if (multiplier_bps == 0) default_multiplier_bps else multiplier_bps;
        // multiplier bps is 1e5 e.g. 12000 is 120%
        let fee_with_multiplier = chain_fee * (multiplier_bps as u128) / 10000;

        if (native_price_usd == 0 || floor_margin_usd == 0) {
            return fee_with_multiplier
        };

        let fee_with_floor_margin = chain_fee + (floor_margin_usd * native_decimals_rate) / native_price_usd;

        if (fee_with_floor_margin > fee_with_multiplier) { fee_with_floor_margin } else { fee_with_multiplier }
    }

    // =================================================== Internal ===================================================

    /// Get the calldata size for a fee; this scales with the number of quorum signatures required
    public(friend) fun get_calldata_size_for_fee(worker_address: address): u64 {
        let quorum = multisig::get_quorum(worker_address);

        let total_signature_bytes: u64 = quorum * SIGNATURE_RAW_BYTES;
        if (total_signature_bytes % 32 != 0) {
            total_signature_bytes = total_signature_bytes - (total_signature_bytes % 32) + 32;
        };
        // Total includes 64 byte overhead
        EXECUTE_FIXED_BYTES + VERIFY_BYTES + total_signature_bytes + 64
    }

    // ================================================== Error Codes =================================================

    const EDVN_EID_NOT_SUPPORTED: u64 = 1;

    public(friend) fun err_EDVN_EID_NOT_SUPPORTED(): u64 { EDVN_EID_NOT_SUPPORTED }
}
