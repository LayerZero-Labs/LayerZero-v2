#[test_only]
module price_feed_module_0::feeds_tests {
    use std::event::was_event_emitted;
    use std::signer::address_of;

    use price_feed_module_0::eid_model_pair;
    use price_feed_module_0::eid_model_pair::{
        ARBITRUM_MODEL_TYPE, DEFAULT_MODEL_TYPE, EidModelPair, new_eid_model_pair, OPTIMISM_MODEL_TYPE,
    };
    use price_feed_module_0::feeds::{
        disable_feed_updater, enable_feed_updater, estimate_fee_on_send, estimate_fee_with_arbitrum_model,
        estimate_fee_with_default_model, estimate_fee_with_optimism_model, feed_updater_set_event,
        get_arbitrum_compression_percent, get_arbitrum_price_traits, get_l1_lookup_id_for_optimism_model,
        get_model_type, get_native_token_price_usd, get_price, get_price_ratio_denominator, initialize,
        is_price_updater, set_arbitrum_compression_percent, set_arbitrum_traits, set_denominator, set_eid_models,
        set_native_token_price_usd, set_price,
    };
    use price_feed_module_0::price::{Self, EidTaggedPrice, tag_price_with_eid};

    #[test(feed = @1111)]
    fun test_enable_disable_feed_updater(feed: &signer) {
        initialize(feed);

        let feed_address = address_of(feed);
        assert!(!is_price_updater(@3333, feed_address), 1);
        assert!(!is_price_updater(@4444, feed_address), 2);

        enable_feed_updater(feed, @3333);
        assert!(was_event_emitted(&feed_updater_set_event(@1111, @3333, true)), 0);
        assert!(is_price_updater(@3333, feed_address), 1);
        assert!(!is_price_updater(@4444, feed_address), 2);

        enable_feed_updater(feed, @4444);
        assert!(was_event_emitted(&feed_updater_set_event(@1111, @4444, true)), 0);
        assert!(is_price_updater(@3333, feed_address), 1);
        assert!(is_price_updater(@4444, feed_address), 2);

        disable_feed_updater(feed, @3333);
        assert!(was_event_emitted(&feed_updater_set_event(@1111, @3333, false)), 0);
        assert!(!is_price_updater(@3333, feed_address), 1);
        assert!(is_price_updater(@4444, feed_address), 2);

        disable_feed_updater(feed, @4444);
        assert!(was_event_emitted(&feed_updater_set_event(@1111, @4444, false)), 0);
        assert!(!is_price_updater(@3333, feed_address), 1);
        assert!(!is_price_updater(@4444, feed_address), 2);
    }

    #[test(feed = @1111)]
    fun test_set_denominator(feed: &signer) {
        initialize(feed);
        let feed_address = address_of(feed);
        assert!(get_price_ratio_denominator(feed_address) == 100_000_000_000_000_000_000, 1);  // default
        set_denominator(feed, 1_0000_0000);
        assert!(get_price_ratio_denominator(feed_address) == 1_0000_0000, 2);
    }

    #[test(feed = @1111)]
    fun test_set_arbitrum_compression_percent(feed: &signer) {
        initialize(feed);
        let feed_address = address_of(feed);

        // check default value
        assert!(get_arbitrum_compression_percent(feed_address) == 47, 1);

        // set value and check
        set_arbitrum_compression_percent(feed, 50);
        assert!(get_arbitrum_compression_percent(feed_address) == 50, 2);
    }

    #[test(feed = @1111)]
    fun test_set_eid_to_model_type(feed: &signer) {
        initialize(feed);
        let feed_address = address_of(feed);

        let list = vector<EidModelPair>[
            new_eid_model_pair(101, DEFAULT_MODEL_TYPE()),
            new_eid_model_pair(102, OPTIMISM_MODEL_TYPE()),
            new_eid_model_pair(103, ARBITRUM_MODEL_TYPE()),
        ];

        let params = eid_model_pair::serialize_eid_model_pair_list(&list);
        set_eid_models(feed, params);

        assert!(get_model_type(feed_address, 101) == DEFAULT_MODEL_TYPE(), 1);
        assert!(get_model_type(feed_address, 102) == OPTIMISM_MODEL_TYPE(), 2);
        assert!(get_model_type(feed_address, 103) == ARBITRUM_MODEL_TYPE(), 3);
    }

    #[test(feed = @1111, updater = @9999, feed_2 = @2222)]
    fun test_set_price(feed: &signer, updater: &signer, feed_2: &signer) {
        initialize(feed);
        let feed_address = address_of(feed);
        enable_feed_updater(feed, @9999);

        // unrelated feed that with the same updater enabled
        initialize(feed_2);
        let feed_address_2 = address_of(feed_2);
        enable_feed_updater(feed_2, @9999);

        // Serialize and set prices
        let list = vector<EidTaggedPrice>[
            tag_price_with_eid(101, price::new_price(1, 2, 3)),
            tag_price_with_eid(102, price::new_price(4, 5, 6)),
            tag_price_with_eid(103, price::new_price(7, 8, 9)),
        ];
        let prices = price::serialize_eid_tagged_price_list(&list);
        set_price(updater, feed_address, prices);

        // Set price on another feed to make sure there isn't interference
        let list = vector<EidTaggedPrice>[
            tag_price_with_eid(102, price::new_price(400, 500, 600)),
        ];
        let prices = price::serialize_eid_tagged_price_list(&list);
        set_price(updater, feed_address_2, prices);

        // Feed should be updated
        let (price_ratio, _gas_price_in_unit, _gas_per_byte) = get_price(feed_address, 101);
        assert!(price_ratio == 1, 1);
        let (_price_ratio, gas_price_in_unit, _gas_per_byte) = get_price(feed_address, 102);
        assert!(gas_price_in_unit == 5, 2);
        let (_price_ratio, _gas_price_in_unit, gas_per_byte) = get_price(feed_address, 103);
        assert!(gas_per_byte == 9, 3);
    }

    #[test(feed = @1111, updater = @9999)]
    fun test_set_arbitrum_traits(feed: &signer, updater: &signer) {
        initialize(feed);
        let feed_address = address_of(feed);
        enable_feed_updater(feed, @9999);

        set_arbitrum_traits(updater, feed_address, 100, 200);

        let (gas_per_l2_tx, gas_per_l1_calldata_byte) = get_arbitrum_price_traits(feed_address);
        assert!(gas_per_l2_tx == 100, 1);
        assert!(gas_per_l1_calldata_byte == 200, 2);
    }

    #[test(feed = @1111, updater = @9999)]
    fun test_set_native_token_price_usd(feed: &signer, updater: &signer) {
        initialize(feed);
        let feed_address = address_of(feed);
        enable_feed_updater(feed, @9999);

        set_native_token_price_usd(updater, feed_address, 100);
        assert!(get_native_token_price_usd(feed_address) == 100, 1);
    }

    #[test(feed = @1111, updater = @9999)]
    fun test_estimate_fee_on_send(feed: &signer, updater: &signer) {
        initialize(feed);
        enable_feed_updater(feed, @9999);

        // These prices are the same as used in the individual model tests
        // We are testing whether we get the expected model response
        // Using different price ratios for goerli, sepolia to see that arbitrum calcs are using the correct L2 price
        let eth_price = price::new_price(4000, 51, 33);
        let eth_goerli_price = price::new_price(40000, 51, 33);
        let eth_sepolia_price = price::new_price(400000, 51, 33);
        let arb_price = price::new_price(1222, 12, 3);
        let opt_price = price::new_price(200, 43, 5);

        set_denominator(feed, 100);
        set_arbitrum_compression_percent(feed, 47);
        set_arbitrum_traits(updater, @1111, 5432, 11);
        set_native_token_price_usd(updater, @1111, 6);

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
        set_eid_models(feed, pairs_serialized);

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
        set_price(updater, @1111, prices_serialized);

        // Variety of tests to make sure that the correct model is used and that the parameters are correctly provided
        // to each model. Testing for different networks (10000 intervals) and also for different versions (30000
        // intervals).
        // For the arbitrum calculations, we need to make sure that it is able to pull from the right l1 chain
        // Also, testing if the % 30000 is working by adding multiples of 30000 to EIDs

        // Default (101 + 30000)
        let (fee, price_ratio, denominator, native_token_price_usd) = estimate_fee_on_send(@1111, 30101, 50, 100);
        assert!(fee == 3570000, 1);
        assert!(price_ratio == 4000, 2);
        assert!(denominator == 100, 3);
        assert!(native_token_price_usd == 6, 4);

        // Default (10101)
        let (fee, _pr, _d, _ntp) = estimate_fee_on_send(@1111, 10101, 50, 100);
        assert!(fee == 3570000, 5);

        // Default (24444 + 60000)
        let (fee, _pr, _d, _ntp) = estimate_fee_on_send(@1111, 84444, 50, 100);
        assert!(fee == 3570000, 6);

        // Arbitrum (110 + 60000)
        let (fee, _pr, _d, _ntp) = estimate_fee_on_send(@1111, 60110, 50, 232);
        assert!(fee == 889664, 7);

        // Arbitrum (10143)
        let (fee, _pr, _d, _ntp) = estimate_fee_on_send(@1111, 10143, 50, 232);
        assert!(fee == 889664, 8);

        // Arbitrum (25555)
        let (fee, _pr, _d, _ntp) = estimate_fee_on_send(@1111, 25555, 50, 232);
        assert!(fee == 889664, 9);

        // Optimism (111 + 90000)
        let (fee, _pr, _d, _ntp) = estimate_fee_on_send(@1111, 90111, 2100, 232);
        assert!(fee == 148798472, 10);

        // Optimism (10132 + 30000)
        let (fee, _pr, _d, _ntp) = estimate_fee_on_send(@1111, 40132, 2100, 232);
        assert!(fee == 1479678152, 11);  // goreli 10x

        // Optimism (11000 + 30000)
        let (fee, _pr, _d, _ntp) = estimate_fee_on_send(@1111, 41000, 2100, 232);
        assert!(fee == 14788474952, 11);  // sepolia 100x

        // Optimism (26666)
        let (fee, _pr, _d, _ntp) = estimate_fee_on_send(@1111, 26666, 2100, 232);
        assert!(fee == 1479678152, 12);   // goerli 10x
    }

    #[test]
    fun test_estimate_fee_with_default_model() {
        let price = price::new_price(100000000000000000000, 1000000000, 16);
        let fee = estimate_fee_with_default_model(1000, 500, &price, 100000000000000000000);
        // gas: ((call data: 1000) * 16) + (gas: 500) = 16500
        // fee: (gas: 16500) * (gas price: 1000000000) * (price ratio: 100000000000000000000) / (denom: 100000000000000000000) = 16500000000000
        assert!(fee == 16500000000000, 0);
    }

    #[test]
    fun test_estimate_fee_with_arbitrum_model() {
        let price = price::new_price(100000000000000000000, 10000000, 16);
        let fee = estimate_fee_with_arbitrum_model(
            1000,
            500,
            &price,
            100000000000000000000,
            47,
            29,
            4176,
        );
        assert!(fee == 343060000000, 0);
        // compressed calldata size = floor((calldata_size: 1000) * (47: compression_percent) / 100) = 470
        // l1 calldata gas = (compressed_size: 470) * (arb_gas_per_l1_calldata_byte: 29) = 13630
        // l2 calldata gas = (calldata_size: 1000) * (arb_gas_per_byte: 16) = 16000
        // total gas = (gas: 500) + (arb_gas_per_l2_tx: 4176) + (l1: 13630) + (l2: 16000) = 34306
        // total fee = (total gas: 34306) * (gas_price: 10000000) * (price_ratio: 100000000000000000000) / (denominator: 100000000000000000000) = 343060000000
    }

    #[test]
    fun test_estimate_fee_with_optimism_model() {
        let ethereum_price = price::new_price(100000000000000000000, 646718991, 8);
        let optimism_price = price::new_price(100000000000000000000, 2231118, 16);
        let fee = estimate_fee_with_optimism_model(
            1000,
            500,
            &ethereum_price,
            &optimism_price,
            100000000000000000000,
        );
        assert!(fee == 7272305518308, 0);
    }

    #[test]
    fun test_get_l1_lookup_id_for_optimism_model() {
        assert!(get_l1_lookup_id_for_optimism_model(111) == 101, 1); // eth
        assert!(get_l1_lookup_id_for_optimism_model(10132) == 10121, 2); // eth-goerli
        assert!(get_l1_lookup_id_for_optimism_model(10500) == 10161, 2); // eth-sepolia
        assert!(get_l1_lookup_id_for_optimism_model(20132) == 20121, 3); // eth-goerli
    }
}
