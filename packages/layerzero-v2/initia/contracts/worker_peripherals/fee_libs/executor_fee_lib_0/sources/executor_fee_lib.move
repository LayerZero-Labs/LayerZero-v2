module executor_fee_lib_0::executor_fee_lib {
    use std::vector;

    use executor_fee_lib_0::executor_option::{Self, ExecutorOptions};
    use msglib_types::worker_options::EXECUTOR_WORKER_ID;
    use price_feed_router_0::router as price_feed_router;
    use worker_common::worker_config;

    #[test_only]
    friend executor_fee_lib_0::executor_fee_lib_tests;

    #[view]
    /// Get the total executor fee, including premiums for an Executor worker to send a message
    /// This checks that the Message Library is supported by the worker, the sender is allowed, the worker is
    /// unpaused, and that the worker is an executor
    public fun get_executor_fee(
        msglib: address,
        worker: address,
        dst_eid: u32,
        sender: address,
        message_size: u64,
        options: vector<u8>,
    ): (u64, address) {
        worker_config::assert_fee_lib_supports_transaction(worker, EXECUTOR_WORKER_ID(), sender, msglib);

        let executor_options = executor_option::extract_executor_options(&options, &mut 0);
        let fee = get_executor_fee_internal(
            worker,
            dst_eid,
            executor_options,
            // Price Feed Estimate Fee on Send - partially applying parameters available in scope
            |price_feed, feed_address, total_gas| price_feed_router::estimate_fee_on_send(
                price_feed,
                feed_address,
                dst_eid,
                message_size,
                total_gas,
            )
        );
        let deposit_address = worker_config::get_deposit_address(worker);
        (fee, deposit_address)
    }

    /// Get the total executor fee, using a provided price feed fee estimation function
    ///
    /// @param worker: The worker address
    /// @param dst_eid: The destination EID
    /// @param options: The executor options
    /// @param estimate_fee_on_send: fee estimator
    ///        |price_feed, feed_address, total_remote_gas| -> (local_chain_fee, price_ratio, denominator, native_price_usd)
    /// @return The total fee
    public(friend) inline fun get_executor_fee_internal(
        worker: address,
        dst_eid: u32,
        options: ExecutorOptions,
        estimate_fee_on_send: |address, address, u128| (u128, u128, u128, u128)
    ): u64 {
        let (
            lz_receive_base_gas, multiplier_bps, floor_margin_usd, native_cap, lz_compose_base_gas,
        ) = worker_config::get_executor_dst_config_values(worker, dst_eid);
        assert!(lz_receive_base_gas != 0, err_EEXECUTOR_EID_NOT_SUPPORTED());

        let (total_dst_amount, total_gas) = calculate_executor_dst_amount_and_total_gas(
            is_v1_eid(dst_eid),
            lz_receive_base_gas,
            lz_compose_base_gas,
            native_cap,
            options,
        );
        let (price_feed, feed_address) = worker_config::get_effective_price_feed(worker);
        let (chain_fee, price_ratio, denominator, native_price_usd) = estimate_fee_on_send(
            price_feed, feed_address, total_gas,
        );

        let default_multiplier_bps = worker_config::get_default_multiplier_bps(worker);
        let multiplier_bps = if (multiplier_bps == 0) default_multiplier_bps else multiplier_bps;
        let native_decimals_rate = worker_common::worker_config::get_native_decimals_rate();
        let fee = apply_premium_to_gas(
            chain_fee,
            multiplier_bps,
            floor_margin_usd,
            native_price_usd,
            native_decimals_rate,
        );
        fee = fee + convert_and_apply_premium_to_value(
            total_dst_amount,
            price_ratio,
            denominator,
            multiplier_bps,
        );
        (fee as u64)
    }

    // ================================================ Internal Functions ================================================

    /// Apply the premium to the fee, this will take the higher of the multiplier applied to the fee or the floor margin
    /// added to the fee
    public(friend) fun apply_premium_to_gas(
        fee: u128,
        multiplier_bps: u16,
        margin_usd: u128,
        native_price_usd: u128,
        native_decimals_rate: u128,
    ): u128 {
        let fee_with_multiplier = (fee * (multiplier_bps as u128)) / 10000;
        if (native_price_usd == 0 || margin_usd == 0) {
            return fee_with_multiplier
        };
        let fee_with_margin = (margin_usd * native_decimals_rate) / native_price_usd + fee;
        if (fee_with_margin > fee_with_multiplier) { fee_with_margin } else { fee_with_multiplier }
    }

    /// Convert the destination value to the local chain native token and apply a multiplier to the value
    public(friend) fun convert_and_apply_premium_to_value(
        value: u128,
        ratio: u128,
        denominator: u128,
        multiplier_bps: u16,
    ): u128 {
        if (value > 0) { (((value * ratio) / denominator) * (multiplier_bps as u128)) / 10000 } else 0
    }

    /// Check whether the EID is a V1 EID
    public(friend) fun is_v1_eid(eid: u32): bool { eid < 30000 }

    /// Calculate the Destination Amount and Total Gas for the Executor
    /// @return (destination amount, total gas)
    public(friend) fun calculate_executor_dst_amount_and_total_gas(
        is_v1_eid: bool,
        lz_receive_base_gas: u64,
        lz_compose_base_gas: u64,
        native_cap: u128,
        options: ExecutorOptions,
    ): (u128, u128) {
        let (
            lz_receive_options,
            native_drop_options,
            lz_compose_options,
            ordered_execution_option,
        ) = executor_option::unpack_options(options);

        // The total value to to be sent to the destination
        let dst_amount: u128 = 0;
        // The total gas to be used for the transaction
        let lz_receive_gas: u128 = 0;

        // Loop through LZ Receive options
        for (i in 0..vector::length(&lz_receive_options)) {
            let option = *vector::borrow(&lz_receive_options, i);
            let (gas, value) = executor_option::unpack_lz_receive_option(option);

            assert!(!is_v1_eid || value == 0, EEV1_DOES_NOT_SUPPORT_LZ_RECEIVE_WITH_VALUE);
            dst_amount = dst_amount + value;
            lz_receive_gas = lz_receive_gas + gas;
        };
        assert!(lz_receive_gas > 0, EEXECUTOR_ZERO_LZRECEIVE_GAS_PROVIDED);
        let total_gas = (lz_receive_base_gas as u128) + lz_receive_gas;

        // Loop through LZ Compose options
        for (i in 0..vector::length(&lz_compose_options)) {
            let option = *vector::borrow(&lz_compose_options, i);
            let (_index, gas, value) = executor_option::unpack_lz_compose_option(option);
            // Endpoint V1 doesnot support LZ Compose
            assert!(!is_v1_eid, EEV1_DOES_NOT_SUPPORT_LZ_COMPOSE_WITH_VALUE);
            assert!(gas > 0, EEXECUTOR_ZERO_LZCOMPOSE_GAS_PROVIDED);
            dst_amount = dst_amount + value;
            // The LZ Compose base gas is required for each LZ Compose, which is represented by the count of indexes.
            // However, this calculation is simplified to match the EVM calculation, which does not deduplicate based on
            // the Lz Compose index. Therefore, if there are multiple LZ Compose Options for a specific index, the
            // Lz Compose base gas will also be duplicated by the number of options on that index
            total_gas = total_gas + gas + (lz_compose_base_gas as u128);
        };

        // Loop through Native Drop options
        for (i in 0..vector::length(&native_drop_options)) {
            let option = *vector::borrow(&native_drop_options, i);
            let (amount, _receiver) = executor_option::unpack_native_drop_option(option);
            dst_amount = dst_amount + amount;
        };
        assert!(dst_amount <= native_cap, EEXECUTOR_NATIVE_AMOUNT_EXCEEDS_CAP);

        // If ordered execution is enabled, increase the gas by 2%
        if (ordered_execution_option) {
            total_gas = (total_gas * 102) / 100;
        };
        (dst_amount, total_gas)
    }

    // ================================================== Error Codes =================================================

    const EEV1_DOES_NOT_SUPPORT_LZ_COMPOSE_WITH_VALUE: u64 = 1;
    const EEV1_DOES_NOT_SUPPORT_LZ_RECEIVE_WITH_VALUE: u64 = 2;
    const EEXECUTOR_EID_NOT_SUPPORTED: u64 = 3;
    const EEXECUTOR_NATIVE_AMOUNT_EXCEEDS_CAP: u64 = 4;
    const EEXECUTOR_ZERO_LZCOMPOSE_GAS_PROVIDED: u64 = 5;
    const EEXECUTOR_ZERO_LZRECEIVE_GAS_PROVIDED: u64 = 6;

    public(friend) fun err_EEXECUTOR_EID_NOT_SUPPORTED(): u64 { EEXECUTOR_EID_NOT_SUPPORTED }
}