#[test_only]
module oft::oft_impl_config_tests {
    use std::account::create_account_for_test;
    use std::event::was_event_emitted;
    use std::string::utf8;
    use std::vector;

    use oft::oapp_store;
    use oft::oft_core;
    use oft::oft_impl_config::{
        Self,
        assert_not_blocklisted,
        blocked_amount_redirected_event,
        blocklisting_disabled_event,
        debit_view_with_possible_fee,
        fee_bps,
        fee_details_with_possible_fee,
        has_rate_limit,
        in_flight_at_time,
        irrevocably_disable_blocklist,
        is_blocklisted,
        rate_limit_capacity_at_time,
        rate_limit_config,
        rate_limit_set_event,
        rate_limit_updated_event, redirect_to_admin_if_blocklisted, release_rate_limit_capacity, set_blocklist,
        set_fee_bps, try_consume_rate_limit_capacity_at_time, unset_rate_limit,
    };
    use oft::oft_store;
    use oft_common::oft_fee_detail;

    const MAX_U64: u64 = 0xffffffffffffffff;

    fun setup() {
        oapp_store::init_module_for_test();
        oft_store::init_module_for_test();
        oft_impl_config::init_module_for_test();
        oft_core::initialize(8, 6);
    }

    #[test]
    fun test_set_fee_deposit_address() {
        setup();

        let deposit_address = @0x1234;
        create_account_for_test(deposit_address);

        assert!(oft_impl_config::fee_deposit_address() == @oft_admin, 1);
        oft_impl_config::set_fee_deposit_address(deposit_address);
        assert!(oft_impl_config::fee_deposit_address() == deposit_address, 2);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_impl_config::EINVALID_DEPOSIT_ADDRESS)]
    fun test_set_fee_deposit_address_invalid() {
        setup();

        let deposit_address = @0x1234;
        oft_impl_config::set_fee_deposit_address(deposit_address);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_impl_config::ESETTING_UNCHANGED)]
    fun test_set_fee_deposit_address_unchanged() {
        setup();

        let deposit_address = @0x1234;
        create_account_for_test(deposit_address);

        oft_impl_config::set_fee_deposit_address(deposit_address);
        oft_impl_config::set_fee_deposit_address(deposit_address);
    }

    #[test]
    fun test_set_fee_bps() {
        setup();

        // Set the fee to 10%
        let fee_bps = 1000;
        set_fee_bps(fee_bps);
        assert!(fee_bps() == fee_bps, 1);

        let (sent, received) = debit_view_with_possible_fee(1234, 1000);
        // Send amount should include dust if there is a fee
        assert!(sent == 1234, 1);
        // Received amount should be 90% of the sent amount with dust removed: 1234 - 120 = 1114 => 1100 (dust removed)
        assert!(received == 1100, 2);

        let fee_details = fee_details_with_possible_fee(1234, 1000);
        assert!(vector::length(&fee_details) == 1, 1);
        let (fee, is_reward) = oft_fee_detail::fee_amount_ld(vector::borrow(&fee_details, 0));
        assert!(fee == 134, 1);
        assert!(is_reward == false, 2);
        assert!(oft_fee_detail::description(vector::borrow(&fee_details, 0)) == utf8(b"OFT Fee"), 2);

        // Set the fee to 0%
        let fee_bps = 0;
        set_fee_bps(fee_bps);

        let (sent, received) = debit_view_with_possible_fee(1234, 1000);
        // Sent and amount should be 100% of the amount with dust removed with no fee: 1234 => 1200 (dust removed)
        assert!(sent == 1200, 3);
        assert!(received == 1200, 4);

        // Expect no fee details if there is no fee
        let fee_details = fee_details_with_possible_fee(1234, 1000);
        assert!(vector::length(&fee_details) == 0, 1);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_impl_config::ESETTING_UNCHANGED)]
    fun test_set_fee_bps_fails_if_unchanged() {
        setup();

        // Set the fee to 10%
        let fee_bps = 1000;
        set_fee_bps(fee_bps);
        set_fee_bps(fee_bps);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_impl_config::EINVALID_FEE)]
    fun test_set_fee_bps_invalid() {
        setup();

        // Set the fee to 101%
        let fee_bps = 10100;
        set_fee_bps(fee_bps);
    }

    #[test]
    fun test_set_blocklist() {
        setup();

        assert!(oft_impl_config::is_blocklisted(@0x1234) == false, 1);
        assert_not_blocklisted(@0x1234);
        let redirected_address = redirect_to_admin_if_blocklisted(@0x1234, 1111);
        assert!(redirected_address == @0x1234, 2);

        set_blocklist(@0x1234, true);
        assert!(oft_impl_config::is_blocklisted(@0x1234), 1);
        let redirected_address = redirect_to_admin_if_blocklisted(@0x1234, 1111);
        assert!(redirected_address == @oft_admin, 2);
        assert!(was_event_emitted(&blocked_amount_redirected_event(1111, @0x1234, @oft_admin)), 3);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_impl_config::ESETTING_UNCHANGED)]
    fun test_set_blocklist_fails_if_unchanged() {
        setup();

        set_blocklist(@0x1234, true);
        set_blocklist(@0x1234, true);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_impl_config::ESETTING_UNCHANGED)]
    fun test_set_blocklist_fails_if_unchanged_2() {
        setup();

        set_blocklist(@0x1234, false);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_impl_config::EBLOCKLIST_DISABLED)]
    fun test_cant_set_blocklist_if_disabled() {
        setup();

        assert!(oft_impl_config::is_blocklisted(@0x1234) == false, 1);
        assert_not_blocklisted(@0x1234);
        let redirected_address = redirect_to_admin_if_blocklisted(@0x1234, 1111);
        assert!(redirected_address == @0x1234, 2);

        irrevocably_disable_blocklist();
        assert!(was_event_emitted(&blocklisting_disabled_event()), 1);

        assert!(is_blocklisted(@0x1234) == false, 1);

        // Should not be able to set blocklist
        set_blocklist(@0x3333, true);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_impl_config::EADDRESS_BLOCKED)]
    fun test_assert_not_blocked() {
        setup();

        set_blocklist(@0x1234, true);
        assert_not_blocklisted(@0x1234);
    }

    #[test]
    fun set_rate_limit() {
        setup();

        // No rate limit configured
        assert!(has_rate_limit(30100) == false, 2);
        let (limit, window) = rate_limit_config(30100);
        assert!(limit == 0 && window == 0, 1);
        assert!(in_flight_at_time(30100, 10) == 0, 1);
        assert!(rate_limit_capacity_at_time(30100, 10) == MAX_U64, 2);

        // Configure rate limit (200/second)
        oft_impl_config::set_rate_limit_at_timestamp(30100, 20000, 1000, 100);
        assert!(was_event_emitted(&rate_limit_set_event(30100, 20000, 1000)), 1);
        assert!(has_rate_limit(30100) == true, 2);
        assert!(has_rate_limit(30200) == false, 2);  // Different eid
        let (limit, window) = rate_limit_config(30100);
        assert!(limit == 20000 && window == 1000, 1);
        assert!(in_flight_at_time(30100, 100) == 0, 1);
        assert!(rate_limit_capacity_at_time(30100, 100) == 20000, 2);

        // 100 seconds later
        assert!(in_flight_at_time(30100, 200) == 0, 1);
        assert!(rate_limit_capacity_at_time(30100, 200) == 20000, 2);

        // consume 10% of the capacity
        try_consume_rate_limit_capacity_at_time(30100, 2000, 200);
        assert!(in_flight_at_time(30100, 200) == 2000, 1);
        assert!(rate_limit_capacity_at_time(30100, 200) == 18000, 2);

        // 10 seconds later: in flight should decline by 20000/1000s * 10s = 200
        assert!(in_flight_at_time(30100, 210) == 1800, 1);
        assert!(rate_limit_capacity_at_time(30100, 210) == 18200, 2);

        // 20 seconds later: in flight should decline by 20000/1000s * 20s = 400
        assert!(in_flight_at_time(30100, 220) == 1600, 1);
        assert!(rate_limit_capacity_at_time(30100, 220) == 18400, 2);

        // update rate limit (300/second)
        oft_impl_config::set_rate_limit_at_timestamp(30100, 30000, 1000, 220);
        assert!(was_event_emitted(&rate_limit_updated_event(30100, 30000, 1000)), 1);
        // in flight shouldn't change, but capacity should be updated with the new limit in mind
        assert!(in_flight_at_time(30100, 220) == 1600, 1);
        assert!(rate_limit_capacity_at_time(30100, 220) == 28400, 2);

        // 10 seconds later: in flight should decline by 30000/1000s * 10s = 300
        assert!(in_flight_at_time(30100, 230) == 1300, 1);
        assert!(rate_limit_capacity_at_time(30100, 230) == 28700, 2);

        // 10 seconds later: in flight should decline by 30000/1000s * 10s = 300
        assert!(in_flight_at_time(30100, 240) == 1000, 1);
        assert!(rate_limit_capacity_at_time(30100, 240) == 29000, 2);

        // 100 seconds later: in flight should decline fully (without overshooting): 30000/1000s * 100s = 3000
        assert!(in_flight_at_time(30100, 300) == 0, 1);
        assert!(rate_limit_capacity_at_time(30100, 300) == 30000, 2);

        // Consume again
        try_consume_rate_limit_capacity_at_time(30100, 2000, 300);
        try_consume_rate_limit_capacity_at_time(30100, 2000, 310);
        // 2000 + (2000 - 30000/1000*10) = 3800
        assert!(in_flight_at_time(30100, 310) == 3700, 1);

        // Reduce rate limit to below the in flight
        oft_impl_config::set_rate_limit_at_timestamp(30100, 500, 1000, 320);

        // Rate limit capacity cannot go below 0, and should not abort
        assert!(rate_limit_capacity_at_time(30100, 320) == 0, 2);

        // Unset rate limit
        unset_rate_limit(30100);
        assert!(has_rate_limit(30100) == false, 2);
        let (limit, window) = rate_limit_config(30100);
        assert!(limit == 0 && window == 0, 1);
        assert!(in_flight_at_time(30100, 320) == 0, 1);
        assert!(rate_limit_capacity_at_time(30100, 320) == MAX_U64, 2);
    }

    #[test]
    #[expected_failure(abort_code = oft::oft_impl_config::ESETTING_UNCHANGED)]
    fun set_rate_limit_fails_if_unchanged() {
        setup();

        // Configure rate limit (200/second)
        oft_impl_config::set_rate_limit_at_timestamp(30100, 20000, 1000, 100);
        oft_impl_config::set_rate_limit_at_timestamp(30100, 20000, 1000, 200);
    }

    #[test]
    fun test_set_rate_limit_net() {
        setup();

        // No rate limit configured
        assert!(has_rate_limit(30100) == false, 2);
        let (limit, window) = rate_limit_config(30100);
        assert!(limit == 0 && window == 0, 1);
        assert!(in_flight_at_time(30100, 10) == 0, 1);
        assert!(rate_limit_capacity_at_time(30100, 10) == MAX_U64, 2);

        // Configure rate limit (200/second)
        oft_impl_config::set_rate_limit_at_timestamp(30100, 20000, 1000, 100);
        assert!(has_rate_limit(30100) == true, 2);

        // consume 100% of the capacity
        try_consume_rate_limit_capacity_at_time(30100, 20000, 0);
        assert!(in_flight_at_time(30100, 0) == 20000, 1);
        assert!(rate_limit_capacity_at_time(30100, 0) == 0, 2);

        // 50 seconds later: in flight should decline by 20000/1000s * 500s = 10000
        assert!(in_flight_at_time(30100, 500) == 10000, 1);
        assert!(rate_limit_capacity_at_time(30100, 500) == 10000, 2);

        // release most of remaining capacity
        release_rate_limit_capacity(30100, 9000);
        assert!(in_flight_at_time(30100, 500) == 1000, 1);
        assert!(rate_limit_capacity_at_time(30100, 500) == 19000, 2);

        // consume all of remaining capacity
        try_consume_rate_limit_capacity_at_time(30100, 19000, 500);
        assert!(in_flight_at_time(30100, 500) == 20000, 1);
        assert!(rate_limit_capacity_at_time(30100, 500) == 0, 2);

        // release excess capacity (5x limit) - should not overshoot
        release_rate_limit_capacity(30100, 100_000);
        assert!(in_flight_at_time(30100, 500) == 0, 1);
        assert!(rate_limit_capacity_at_time(30100, 500) == 20000, 2);
    }
}
