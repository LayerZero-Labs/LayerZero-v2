#[test_only]
module executor_fee_lib_0::executor_fee_lib_tests {
    use std::account;
    use std::account::create_signer_for_test;

    use endpoint_v2_common::bytes32;
    use endpoint_v2_common::contract_identity::make_call_ref_for_test;
    use endpoint_v2_common::native_token_test_helpers::initialize_native_token_for_test;
    use endpoint_v2_common::serde;
    use executor_fee_lib_0::executor_fee_lib::{
        apply_premium_to_gas, calculate_executor_dst_amount_and_total_gas, convert_and_apply_premium_to_value,
        get_executor_fee, get_executor_fee_internal, is_v1_eid,
    };
    use executor_fee_lib_0::executor_option::{
        append_executor_options, new_executor_options, new_lz_compose_option, new_lz_receive_option,
        new_native_drop_option,
    };
    use price_feed_module_0::eid_model_pair;
    use price_feed_module_0::eid_model_pair::{
        ARBITRUM_MODEL_TYPE, DEFAULT_MODEL_TYPE, EidModelPair, new_eid_model_pair, OPTIMISM_MODEL_TYPE,
    };
    use price_feed_module_0::price;
    use price_feed_module_0::price::{EidTaggedPrice, tag_price_with_eid};
    use worker_common::worker_config::{Self, set_executor_dst_config};

    #[test]
    fun test_get_fee() {
        // 1. Set up the price feed (@price_feed_module_0, @1111)
        use price_feed_module_0::feeds;
        let feed = &create_signer_for_test(@1111);
        let updater = &create_signer_for_test(@9999);
        feeds::initialize(feed);
        feeds::enable_feed_updater(feed, @9999);

        initialize_native_token_for_test();

        // These prices are the same as used in the individual model tests
        // We are testing whether we get the expected model response
        // Using different price ratios for goerli, sepolia to see that arbitrum calcs are using the correct L2 price
        let eth_price = price::new_price(4000, 51, 33);
        let eth_goerli_price = price::new_price(40000, 51, 33);
        let eth_sepolia_price = price::new_price(400000, 51, 33);
        let arb_price = price::new_price(1222, 12, 3);
        let opt_price = price::new_price(200, 43, 5);

        feeds::set_denominator(feed, 100);
        feeds::set_arbitrum_compression_percent(feed, 47);
        feeds::set_arbitrum_traits(updater, @1111, 5432, 11);
        feeds::set_native_token_price_usd(updater, @1111, 6);

        // Test some non-hardcoded model types
        let eid_model_pairs = vector<EidModelPair>[
            new_eid_model_pair(
                110,
                DEFAULT_MODEL_TYPE()
            ), // cannot override hardcoded type - this will still be "ARBITRUM"
            new_eid_model_pair(11000, OPTIMISM_MODEL_TYPE()), // optimism using L1 sepolia
            new_eid_model_pair(25555, ARBITRUM_MODEL_TYPE()),
            new_eid_model_pair(26666, OPTIMISM_MODEL_TYPE()),
        ];

        let pairs_serialized = eid_model_pair::serialize_eid_model_pair_list(&eid_model_pairs);
        feeds::set_eid_models(feed, pairs_serialized);

        let list = vector<EidTaggedPrice>[
            tag_price_with_eid(101, eth_price), // First 6 EIDs are all of hardcoded types
            tag_price_with_eid(110, arb_price),
            tag_price_with_eid(111, opt_price),
            tag_price_with_eid(10101, eth_price),
            tag_price_with_eid(10143, arb_price),
            tag_price_with_eid(10132, opt_price),
            tag_price_with_eid(11000, opt_price), // optimism using L1 sepolia
            tag_price_with_eid(10121, eth_goerli_price), // eth-goerli - used for arbitrum estimate
            tag_price_with_eid(10161, eth_sepolia_price), // eth-sepolia - used for arbitrum estimate

            tag_price_with_eid(24444, eth_price), // not hardcoded and not set - should default to "DEFAULT"
            tag_price_with_eid(25555, arb_price), // configured to "ARBITRUM"
            tag_price_with_eid(26666, opt_price), // configured to "OPTIMISM"
            tag_price_with_eid(20121, eth_goerli_price), // eth-goerli - used for arbitrum estimate
        ];
        let prices_serialized = price::serialize_eid_tagged_price_list(&list);
        feeds::set_price(updater, @1111, prices_serialized);

        let (fee, price_ratio, denominator, native_token_price) = feeds::estimate_fee_on_send(
            @1111,
            10101,
            50,
            100,
        );
        assert!(fee == 3570000, 0);
        assert!(price_ratio == 4000, 1);
        assert!(denominator == 100, 2);
        assert!(native_token_price == 6, 3);

        // 2. Set up the worker (@1234)
        let worker = @1234;
        initialize_native_token_for_test();
        worker_config::initialize_for_worker_test_only(
            worker,
            1,
            worker,
            @0x501ead,
            vector[@111],
            vector[@222],
            @0xfee11b,
        );
        worker_config::set_executor_dst_config(
            &make_call_ref_for_test(worker),
            10101,
            1000,
            50,
            100,
            100000000000,
            100002132,
        );
        worker_config::set_price_feed(
            &make_call_ref_for_test(worker),
            @price_feed_module_0,
            @1111,
        );

        let options = serde::bytes_of(|buf| append_executor_options(buf, &new_executor_options(
            vector[
                new_lz_receive_option(100, 0),
            ],
            vector[],
            vector[],
            false,
        )));
        let (fee, deposit) = get_executor_fee(
            @222,
            worker,
            10101,
            @5555,
            1000,
            options,
        );

        assert!(fee != 0, 0);
        // worker address
        assert!(deposit == @1234, 1);

        // test after updating deposit address
        account::create_account_for_test(@4321);
        worker_config::set_deposit_address(&make_call_ref_for_test(worker), @4321);

        let options = serde::bytes_of(|buf| append_executor_options(buf, &new_executor_options(
            vector[
                new_lz_receive_option(100, 0),
            ],
            vector[],
            vector[],
            false,
        )));

        let (_fee, deposit) = get_executor_fee(
            @222,
            worker,
            10101,
            @5555,
            1000,
            options,
        );

        assert!(deposit == @4321, 1);
    }

    #[test]
    fun test_get_fee_internal() {
        initialize_native_token_for_test();
        // Set up the worker (@1234)
        let worker = @1234;
        worker_config::initialize_for_worker_test_only(
            worker,
            1,
            worker,
            @0x501ead,
            vector[@111],
            vector[@222],
            @0xfee11b,
        );
        worker_config::set_executor_dst_config(
            &make_call_ref_for_test(worker),
            10101,
            1000,
            50,
            100,
            100000000000,
            100002132,
        );
        worker_config::set_price_feed(
            &make_call_ref_for_test(worker),
            @0x501ead,
            @111,
        );

        let called = false;
        assert!(!called, 0);

        let fee = get_executor_fee_internal(
            worker,
            10101,
            new_executor_options(
                vector[
                    new_lz_receive_option(100, 0),
                ],
                vector[],
                vector[],
                false,
            ),
            |price_feed_module, feed_address, total_gas| {
                called = true;
                assert!(price_feed_module == @0x501ead, 0);
                assert!(feed_address == @111, 1);

                // [Calculate Executor DST Amount and Gas] 1000 (lz_receive base gas) + 100 (lz_receive gas) = 200
                assert!(total_gas == 1100, 1);
                (20000 /*chain fee*/, 40 /*price_ratio*/, 1_000_000 /*denominator*/, 0 /*native_price_usd*/)
            }
        );
        assert!(called, 2);

        // [Apply Premium to gas] 20000 (fee) * 50 (multiplier) / 10000 = 100
        assert!(fee == 100, 0);
    }

    #[test]
    fun test_get_fee_works_with_delegated_price_feed() {
        initialize_native_token_for_test();
        // other worker
        worker_config::initialize_for_worker_test_only(
            @5555,
            1,
            @5555,
            @0x501ead,
            vector[@111],
            vector[@222],
            @0xfee11b,
        );
        worker_config::set_price_feed(
            &make_call_ref_for_test(@5555),
            @0xabcd,
            @1234,
        );

        // Set up the worker (@1234)
        let worker = @1234;
        worker_config::initialize_for_worker_test_only(
            worker,
            1,
            worker,
            @0x501ead,
            vector[@111],
            vector[@222],
            @0xfee11b,
        );
        worker_config::set_executor_dst_config(
            &make_call_ref_for_test(worker),
            10101,
            1000,
            50,
            100,
            100000000000,
            100002132,
        );
        worker_config::set_price_feed_delegate(
            &make_call_ref_for_test(worker),
            @5555,
        );

        let called = false;
        assert!(!called, 0);

        let fee = get_executor_fee_internal(
            worker,
            10101,
            new_executor_options(
                vector[
                    new_lz_receive_option(100, 0),
                ],
                vector[],
                vector[],
                false,
            ),
            |price_feed_module, feed_address, total_gas| {
                called = true;
                assert!(price_feed_module == @0xabcd, 0);
                assert!(feed_address == @1234, 1);

                // [Calculate Executor DST Amount and Gas] 1000 (lz_receive base gas) + 100 (lz_receive gas) = 200
                assert!(total_gas == 1100, 1);
                (20000 /*chain fee*/, 40 /*price_ratio*/, 1_000_000 /*denominator*/, 0 /*native_price_usd*/)
            }
        );
        assert!(called, 2);

        // [Apply Premium to gas] 20000 (fee) * 50 (multiplier) / 10000 = 100
        assert!(fee == 100, 0);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EWORKER_PAUSED)]
    fun test_get_fee_will_fail_if_worker_paused() {
        let worker = @1234;
        initialize_native_token_for_test();
        worker_common::worker_config::initialize_for_worker_test_only(
            worker,
            1,
            worker,
            @0x501ead,
            vector[@111],
            vector[@222],
            @0xfee11b,
        );
        worker_config::set_worker_pause(&make_call_ref_for_test(worker), true);

        let options = serde::bytes_of(|buf| append_executor_options(buf, &new_executor_options(
            vector[],
            vector[],
            vector[],
            false,
        )));

        get_executor_fee(
            @0xfee11b,
            worker,
            12,
            @555,
            1000,
            options,
        );
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::ESENDER_DENIED)]
    fun test_get_fee_will_fail_if_sender_not_allowed() {
        let worker = @1234;
        initialize_native_token_for_test();
        worker_common::worker_config::initialize_for_worker_test_only(
            worker,
            1,
            worker,
            @0x501ead,
            vector[@111],
            vector[@222],
            @0xfee11b,
        );
        // create an allowlist without the sender
        worker_config::set_allowlist(&make_call_ref_for_test(worker), @55555555, true);

        worker_config::set_worker_fee_lib(&make_call_ref_for_test(worker), @0xfee11b);
        set_executor_dst_config(
            &make_call_ref_for_test(worker),
            12,
            1000,
            50,
            100,
            100000000000,
            100002132,
        );

        let options = serde::bytes_of(|buf| append_executor_options(buf, &new_executor_options(
            vector[],
            vector[],
            vector[],
            false,
        )));

        get_executor_fee(
            @222,
            worker,
            12,
            @555,
            1000,
            options,
        );
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EWORKER_AUTH_UNSUPPORTED_MSGLIB)]
    fun test_get_fee_will_fail_if_msglib_not_supported() {
        let worker = @1234;
        initialize_native_token_for_test();
        worker_common::worker_config::initialize_for_worker_test_only(
            worker,
            1,
            worker,
            @0x501ead,
            vector[@111],
            vector[@222],
            @0xfee11b,
        );

        worker_config::set_worker_fee_lib(&make_call_ref_for_test(worker), @0xfee11b);
        set_executor_dst_config(
            &make_call_ref_for_test(worker),
            12,
            1000,
            50,
            100,
            100000000000,
            100002132,
        );

        let options = serde::bytes_of(|buf| append_executor_options(buf, &new_executor_options(
            vector[],
            vector[],
            vector[],
            false,
        )));

        get_executor_fee(
            @1234, // not @222
            worker,
            12,
            @555,
            1000,
            options,
        );
    }

    #[test]
    fun test_apply_premium_to_gas_uses_multiplier_if_gt_fee_with_margin() {
        let fee = apply_premium_to_gas(
            20000,
            10500,
            1,
            1,
            1,
        );
        assert!(fee == 21000, 0); // 20000 * 10500 / 10000
    }

    #[test]
    fun test_apply_premium_to_gas_uses_margin_if_gt_fee_with_multiplier() {
        let fee = apply_premium_to_gas(
            20000,
            10500,
            6000,
            2000,
            1000,
        );
        assert!(fee == 23000, 0); // 20000 + (6000 * 1000) / 2000
    }

    #[test]
    fun test_apply_premium_to_gas_uses_margin_if_native_price_used_is_0() {
        let fee = apply_premium_to_gas(
            20000,
            10500,
            6000,
            0,
            1000,
        );
        assert!(fee == 21000, 0);  // 20000 * 10500 / 10000;
    }

    #[test]
    fun test_apply_premium_to_gas_uses_multiplier_if_margin_usd_is_0() {
        let fee = apply_premium_to_gas(
            20000,
            10500,
            0,
            1,
            1,
        );
        assert!(fee == 21000, 0); // 20000 * 10500 / 10000
    }

    #[test]
    fun test_convert_and_apply_premium_to_value() {
        let fee = convert_and_apply_premium_to_value(
            9512000,
            123,
            1_000,
            600, // 6%
        );
        assert!(fee == 70198, 0); // (((9512000*123)/1000) * 600) / 10000;
    }

    #[test]
    fun test_convert_and_apply_premium_to_value_returns_0_if_value_is_0() {
        let fee = convert_and_apply_premium_to_value(
            0,
            112312323,
            1,
            1000, // 10%
        );
        assert!(fee == 0, 0);
    }

    #[test]
    fun test_is_v1_eid() {
        assert!(is_v1_eid(1), 0);
        assert!(is_v1_eid(29999), 1);
        assert!(!is_v1_eid(30000), 2);
        assert!(!is_v1_eid(130000), 3);
    }

    #[test]
    fun test_calculate_executor_dst_amount_and_gas() {
        let lz_receive_options = vector[
            new_lz_receive_option(100, 200),
            new_lz_receive_option(300, 0),
        ];
        let native_drop_options = vector[
            new_native_drop_option(100, bytes32::from_address(@123)),
            new_native_drop_option(200, bytes32::from_address(@456)),
        ];
        let lz_compose_options = vector[
            new_lz_compose_option(0, 400, 500),
            new_lz_compose_option(1, 400, 500),
        ];
        let options = new_executor_options(
            lz_receive_options,
            native_drop_options,
            lz_compose_options,
            false,
        );

        let (dst_amount, total_gas) = calculate_executor_dst_amount_and_total_gas(
            false, // is_v1_eid
            100, // lz_receive_base_gas
            200, // lz_compose_base_gas
            100000000000, // native_cap
            options,
        );

        let expected_total_gas = 0
            + 100 // lz_receive_base_gas
            + 100 // lz_receive gas
            + 300 // lz_receive gas
            + 200 // lz_compose_base_gas
            + 400 // lz_compose gas
            + 200 // lz_compose_base_gas
            + 400; // lz_compose gas

        let expected_dst_amount = 0
            + 200 // lz_receive value
            + 0 // lz_receive value
            + 100 // native_drop amount
            + 200 // native_drop amount
            + 500 // lz_compose value
            + 500; // lz_compose value

        assert!(dst_amount == expected_dst_amount, 0);
        assert!(total_gas == expected_total_gas, 1);

        // do again but use ordered execution option
        let options = new_executor_options(
            lz_receive_options,
            native_drop_options,
            lz_compose_options,
            true,
        );

        let (dst_amount, total_gas) = calculate_executor_dst_amount_and_total_gas(
            false, // is_v1_eid
            100, // lz_receive_base_gas
            200, // lz_compose_base_gas
            100000000000, // native_cap
            options,
        );

        // 2% addtional fee, no change in dst_amount
        let expected_total_gas = expected_total_gas * 102 / 100;
        assert!(dst_amount == expected_dst_amount, 1);
        assert!(total_gas == expected_total_gas, 2);
    }

    #[test]
    #[expected_failure(abort_code = executor_fee_lib_0::executor_fee_lib::EEXECUTOR_ZERO_LZRECEIVE_GAS_PROVIDED)]
    fun test_calculate_executor_dst_amount_and_gas_should_fail_if_no_lz_receive_gas_provided() {
        let lz_receive_options = vector[
            new_lz_receive_option(0, 200),
            new_lz_receive_option(0, 0),
        ];
        let native_drop_options = vector[];
        let lz_compose_options = vector[];

        let options = new_executor_options(
            lz_receive_options,
            native_drop_options,
            lz_compose_options,
            false,
        );

        calculate_executor_dst_amount_and_total_gas(
            false, // is_v1_eid
            100, // lz_receive_base_gas
            200, // lz_compose_base_gas
            100000000000, // native_cap
            options,
        );
    }

    #[test]
    #[expected_failure(abort_code = executor_fee_lib_0::executor_fee_lib::EEXECUTOR_ZERO_LZCOMPOSE_GAS_PROVIDED)]
    fun test_calculate_executor_dst_amount_and_gas_should_fail_if_lz_compose_gas_not_provided_on_any_of_the_options() {
        let lz_receive_options = vector[
            new_lz_receive_option(100, 200),
            new_lz_receive_option(300, 0),
        ];
        let native_drop_options = vector[];
        let lz_compose_options = vector[
            new_lz_compose_option(0, 400, 500),
            new_lz_compose_option(1, 0, 500),
        ];

        let options = new_executor_options(
            lz_receive_options,
            native_drop_options,
            lz_compose_options,
            false,
        );

        calculate_executor_dst_amount_and_total_gas(
            false, // is_v1_eid
            100, // lz_receive_base_gas
            200, // lz_compose_base_gas
            100000000000, // native_cap
            options,
        );
    }

    #[test]
    #[expected_failure(abort_code = executor_fee_lib_0::executor_fee_lib::EEXECUTOR_NATIVE_AMOUNT_EXCEEDS_CAP)]
    fun test_calculate_executor_dst_amount_and_gas_should_fail_if_native_amount_exceeds_cap() {
        let lz_receive_options = vector[
            new_lz_receive_option(100, 200),
            new_lz_receive_option(300, 0),
        ];
        let native_drop_options = vector[
            new_native_drop_option(100, bytes32::from_address(@123)),
            new_native_drop_option(200, bytes32::from_address(@456)),
        ];
        let lz_compose_options = vector[];

        let options = new_executor_options(
            lz_receive_options,
            native_drop_options,
            lz_compose_options,
            false,
        );

        calculate_executor_dst_amount_and_total_gas(
            false, // is_v1_eid
            100, // lz_receive_base_gas
            200, // lz_compose_base_gas
            100, // native_cap (less than the 500 total native amount)
            options,
        );
    }

    #[test]
    #[expected_failure(abort_code = executor_fee_lib_0::executor_fee_lib::EEV1_DOES_NOT_SUPPORT_LZ_RECEIVE_WITH_VALUE)]
    fun test_calculate_executor_dst_amount_and_gas_should_fail_if_v1_eid_and_lz_receive_value_provided() {
        let lz_receive_options = vector[
            new_lz_receive_option(100, 200),
            new_lz_receive_option(300, 0),
        ];
        let native_drop_options = vector[];
        let lz_compose_options = vector[];

        let options = new_executor_options(
            lz_receive_options,
            native_drop_options,
            lz_compose_options,
            false,
        );

        calculate_executor_dst_amount_and_total_gas(
            true, // is_v1_eid
            100, // lz_receive_base_gas
            200, // lz_compose_base_gas
            100000000000, // native_cap
            options,
        );
    }

    #[test]
    #[expected_failure(abort_code = executor_fee_lib_0::executor_fee_lib::EEV1_DOES_NOT_SUPPORT_LZ_COMPOSE_WITH_VALUE)]
    fun test_calculate_executor_dst_amount_and_gas_should_fail_if_v1_eid_and_lz_compose_value_provided() {
        let lz_receive_options = vector[
            new_lz_receive_option(100, 0),
            new_lz_receive_option(300, 0),
        ];
        let native_drop_options = vector[];
        let lz_compose_options = vector[
            new_lz_compose_option(0, 400, 500),
            new_lz_compose_option(1, 400, 0),
        ];

        let options = new_executor_options(
            lz_receive_options,
            native_drop_options,
            lz_compose_options,
            true,
        );

        calculate_executor_dst_amount_and_total_gas(
            true, // is_v1_eid
            100, // lz_receive_base_gas
            200, // lz_compose_base_gas
            100000000000, // native_cap
            options,
        );
    }
}
