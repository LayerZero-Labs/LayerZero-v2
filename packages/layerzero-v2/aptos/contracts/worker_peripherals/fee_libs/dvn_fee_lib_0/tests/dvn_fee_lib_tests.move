#[test_only]
module dvn_fee_lib_0::dvn_fee_lib_tests {
    use std::account::{Self, create_signer_for_test};

    use dvn_fee_lib_0::dvn_fee_lib::{apply_premium, get_calldata_size_for_fee, get_dvn_fee, get_dvn_fee_internal};
    use endpoint_v2_common::contract_identity::make_call_ref_for_test;
    use endpoint_v2_common::native_token_test_helpers::initialize_native_token_for_test;
    use price_feed_module_0::eid_model_pair::{
        Self,
        ARBITRUM_MODEL_TYPE,
        DEFAULT_MODEL_TYPE,
        EidModelPair,
        new_eid_model_pair,
        OPTIMISM_MODEL_TYPE
    };
    use price_feed_module_0::price::{Self, EidTaggedPrice, tag_price_with_eid};
    use worker_common::worker_config::{Self, WORKER_ID_DVN};

    const APTOS_NATIVE_DECIMAL_RATE: u128 = 100_000_000;

    // Test params
    const CHAIN_FEE: u128 = 1 * 100_000_000; // 1 native * 1e18 e.g. on ethereum

    #[test]
    fun test_get_fee() {
        // 1. Set up the price feed (@price_feed_module_0, @1111)
        use price_feed_module_0::feeds;

        initialize_native_token_for_test();
        let feed = &create_signer_for_test(@1111);
        let updater = &create_signer_for_test(@9999);
        feeds::initialize(feed);
        feeds::enable_feed_updater(feed, @9999);

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
            WORKER_ID_DVN(),
            worker,
            @0x501ead,
            vector[@111],
            vector[@222],
            @0xfee11b,
        );
        worker_config::set_dvn_dst_config(
            &make_call_ref_for_test(worker),
            10101,
            1000,
            50,
            100,
        );
        worker_common::multisig::initialize_for_worker_test_only(worker, 1, vector[
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a"
        ]);
        worker_config::set_price_feed(&make_call_ref_for_test(worker), @price_feed_module_0, @1111);

        let (fee, deposit) = get_dvn_fee(
            @222,
            worker,
            10101,
            @1234,
            b"unused header",
            b"unused hash",
            2,
            b"1123",
        );

        assert!(fee != 0, 0);
        assert!(deposit == @1234, 0);

        // test with a different deposit address
        account::create_account_for_test(@4321);
        worker_config::set_deposit_address(&make_call_ref_for_test(worker), @4321);

        let (_fee, deposit) = get_dvn_fee(
            @222,
            worker,
            10101,
            @1234,
            b"unused header",
            b"unused hash",
            2,
            b"1123",
        );
        assert!(deposit == @4321, 0);
    }

    #[test]
    fun test_get_fee_internal() {
        initialize_native_token_for_test();
        // Set up the worker (@1234)
        let worker = @1234;
        initialize_native_token_for_test();
        worker_config::initialize_for_worker_test_only(
            worker,
            WORKER_ID_DVN(),
            worker,
            @0x501ead,
            vector[@111],
            vector[@222],
            @0xfee11b,
        );
        worker_config::set_dvn_dst_config(
            &make_call_ref_for_test(worker),
            10101,
            900,
            10050,
            1,
        );
        worker_common::multisig::initialize_for_worker_test_only(worker, 1, vector[
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a"
        ]);
        worker_config::set_price_feed(&make_call_ref_for_test(worker), @1111, @2222);

        let called = false;
        assert!(!called, 0);

        let fee = get_dvn_fee_internal(
            worker,
            10101,
            |price_feed, feed_address, total_gas| {
                called = true;
                assert!(price_feed == @1111, 0);
                assert!(feed_address == @2222, 1);
                // from the dvn_dst_config
                assert!(total_gas == 900, 2);

                // 20_000_000 for APTOS 8-decimals - adjust for other native tokens
                let native_price_usd = 20_000_000 * worker_config::get_native_decimals_rate() / 100_000_000;
                (40000, 200, 1_000_000, native_price_usd)
            },
        );

        assert!(called, 1);

        // (10050 multiplier_bps) * (40000 chain_fee) / 10000 = 40200
        // vs.
        // 40000 chain_fee + (1 floor margin) * (100_000_000 native_decimals_rate) / 20_000_000 native_price_usd  = 40005
        // 40200 > 40005
        assert!(fee == 40200, 0);
    }

    #[test]
    fun test_get_fee_with_delegate() {
        // other worker
        initialize_native_token_for_test();
        worker_config::initialize_for_worker_test_only(
            @5555,
            1,
            @5555,
            @0x501ead,
            vector[@111],
            vector[@222],
            @0xfee11b,
        );
        let other_worker_call_ref = &make_call_ref_for_test(@5555);
        worker_config::set_price_feed(
            other_worker_call_ref,
            @0xabcd,
            @1234,
        );

        // Set up the worker (@1234)
        let worker = @1234;
        initialize_native_token_for_test();
        worker_config::initialize_for_worker_test_only(
            worker,
            WORKER_ID_DVN(),
            worker,
            @0x501ead,
            vector[@111],
            vector[@222],
            @0xfee11b,
        );
        worker_config::set_dvn_dst_config(
            &make_call_ref_for_test(worker),
            10101,
            900,
            10050,
            1,
        );
        worker_common::multisig::initialize_for_worker_test_only(worker, 1, vector[
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a"
        ]);
        worker_config::set_price_feed_delegate(
            &make_call_ref_for_test(worker),
            @5555,
        );

        let called = false;
        assert!(!called, 0);

        let fee = get_dvn_fee_internal(
            worker,
            10101,
            |price_feed, feed_address, total_gas| {
                called = true;
                assert!(price_feed == @0xabcd, 0);
                assert!(feed_address == @1234, 1);
                // from the dvn_dst_config
                assert!(total_gas == 900, 2);

                // 200_000 for APTOS 8-decimals - adjust for other native tokens
                let native_price_usd = 200_000 * worker_config::get_native_decimals_rate() / 100_000_000;
                (40000, 200, 100_000, native_price_usd)
            },
        );

        assert!(called, 1);

        // (10050 multiplier_bps) * (40000 chain_fee) / 10000 = 40200
        // vs.
        // 40000 chain_fee + (1 floor margin) * (100_000_000 native_decimals_rate) / 200_000 native_price_usd  = 40500
        // 40200 < 40500
        assert!(fee == 40500, 0);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EWORKER_PAUSED)]
    fun test_get_fee_will_fail_if_worker_paused() {
        let worker = @1234;
        initialize_native_token_for_test();
        worker_common::worker_config::initialize_for_worker_test_only(
            worker,
            WORKER_ID_DVN(),
            worker,
            @0x501ead,
            vector[@111],
            vector[@222],
            @0xfee11b,
        );
        worker_config::set_worker_pause(&make_call_ref_for_test(worker), true);

        get_dvn_fee(
            @555,
            worker,
            12,
            @1001,
            b"123",
            x"1234567890123456789012345678901234567890123456789012345678901234",
            2,
            b"1123"
        );
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::ESENDER_DENIED)]
    fun test_get_fee_will_fail_if_sender_not_allowed() {
        let worker = @1234;
        initialize_native_token_for_test();
        worker_common::worker_config::initialize_for_worker_test_only(
            worker,
            WORKER_ID_DVN(),
            worker,
            @0x501ead,
            vector[@111],
            vector[@222],
            @0xfee11b,
        );
        // create an allowlist without the sender
        worker_config::set_allowlist(&make_call_ref_for_test(worker), @55555555, true);

        get_dvn_fee(
            @555,
            worker,
            12,
            @1001, // not on allowlist
            b"123",
            x"1234567890123456789012345678901234567890123456789012345678901234",
            2,
            b"1123"
        );
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EWORKER_AUTH_UNSUPPORTED_MSGLIB)]
    fun test_get_fee_will_fail_if_msglib_not_supported() {
        let worker = @1234;
        initialize_native_token_for_test();
        worker_common::worker_config::initialize_for_worker_test_only(
            worker,
            WORKER_ID_DVN(),
            worker,
            @0x501ead,
            vector[@111],
            vector[@222],
            @0xfee11b,
        );

        // not selecting msglib as supported

        get_dvn_fee(
            @555,
            worker,
            12,
            @1991,
            b"123",
            x"1234567890123456789012345678901234567890123456789012345678901234",
            2,
            b"1123"
        );
    }

    #[test]
    fun test_apply_premium_no_native_price_usd_or_floor_margin_usd_set() {
        // if native_price_usd is not set or floor_margin_usd is not set, fee = fee_with_multiplier
        // fee = 100_000_000 * 120% = 120_000_000
        let expected_fee = 120_000_000;
        assert!(apply_premium(CHAIN_FEE, 0, 12000, 0, 10500, APTOS_NATIVE_DECIMAL_RATE) == expected_fee, 0);
        assert!(
            apply_premium(
                CHAIN_FEE,
                500_000_000_000_000_000_000,
                12000,
                0,
                10500,
                APTOS_NATIVE_DECIMAL_RATE,
            ) == expected_fee,
            1,
        );
        assert!(
            apply_premium(
                CHAIN_FEE,
                0,
                12000,
                10_000_000_000_000_000_000 /* 0.10 usd */,
                10500,
                APTOS_NATIVE_DECIMAL_RATE,
            ) == expected_fee,
            2,
        );
    }

    #[test]
    fun test_apply_premium_with_floor_margin_greater() {
        // chain_fee = 100_000_000 (1 native)
        // native_price_usd = 1 USD = 100_000_000_000_000_000_000
        // floor_margin_usd = 2 USD = 200_000_000_000_000_000_000
        // floor_margin_in_native = 
        // 100_000_000 (chain_fee) + 200_000_000_000_000_000_000 (floor_margin_usd) * 100_000_000 (native_decimals_rate) / 100_000_000_000_000_000_000 (native_price_usd) 
        // = 300_000_000
        let fee = apply_premium(
            CHAIN_FEE,
            100_000_000_000_000_000_000,
            12000, 200_000_000_000_000_000_000 /* 2usd */,
            10500,
            APTOS_NATIVE_DECIMAL_RATE,
        );
        let expected_fee = 300_000_000;
        assert!(fee == expected_fee, 0);
    }

    #[test]
    fun test_apply_premium_with_floor_margin_less() {
        // chain_fee = 100_000_000 (1 native)
        // native_price_usd = 1 USD = 100_000_000_000_000_000_000
        // floor_margin_usd = 0.02 USD = 2_000_000_000_000_000_000
        // floor_margin_in_native = 
        // 100_000_000 (chain_fee) + 100_000_000_000_000_000_000 (floor_margin_usd) * 100_000_000 (native_decimals_rate) / 100_000_000_000_000_000_000 (native_price_usd) 
        // = 300_000_000
        let fee = apply_premium(
            CHAIN_FEE,
            100_000_000_000_000_000_000,
            12000,
            2_000_000_000_000_000_000 /* 2usd */,
            10500,
            APTOS_NATIVE_DECIMAL_RATE,
        );
        let expected_fee = 120_000_000;
        assert!(fee == expected_fee, 0);
    }

    #[test]
    fun test_get_calldata_size_for_fee() {
        let worker = @1234;
        initialize_native_token_for_test();
        worker_common::worker_config::initialize_for_worker_test_only(
            worker,
            WORKER_ID_DVN(),
            worker,
            @0x501ead,
            vector[@111],
            vector[@222],
            @0xfee11b,
        );
        worker_common::multisig::initialize_for_worker_test_only(worker, 1, vector[
            x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a",
        ]);

        get_calldata_size_for_fee(worker);
    }
}
