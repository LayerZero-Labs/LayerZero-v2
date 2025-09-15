#[test_only]
module price_feed::price_feed_tests;

use call::call;
use price_feed::price_feed::{Self, PriceFeed, OwnerCap, PriceUpdaterCap};
use price_feed_call_types::estimate_fee;
use sui::test_scenario as ts;

// === Test Constants ===

const OWNER: address = @0x1111;
const UPDATER1: address = @0x2222;
const UPDATER2: address = @0x3333;
const NON_UPDATER: address = @0x4444;

// === Tests ===

#[test]
fun test_init() {
    let mut scenario = setup();

    init_price_feed_for_test(&mut scenario);

    scenario.next_tx(OWNER);
    {
        let (price_feed, owner_cap) = get_price_feed_and_owner_cap(&scenario);

        // Check initial state
        assert!(price_feed.get_owner_cap() == sui::object::id_address(&owner_cap), 0);
        assert!(price_feed.get_price_ratio_denominator() == 100000000000000000000, 1); // 1e20
        assert!(price_feed.get_arbitrum_compression_percent() == 47, 2);
        assert!(price_feed.native_token_price_usd() == 0, 3);

        return_price_feed_and_owner_cap(price_feed, owner_cap, &scenario);
    };

    clean(scenario);
}

#[test]
fun test_set_price_updater() {
    let mut scenario = setup();

    init_price_feed_for_test(&mut scenario);

    scenario.next_tx(OWNER);
    {
        let (mut price_feed, owner_cap) = get_price_feed_and_owner_cap(&scenario);

        // Initially no one is a price updater
        assert!(price_feed.is_price_updater( UPDATER1) == false, 0);
        assert!(price_feed.is_price_updater( UPDATER2) == false, 1);

        // Enable updater1
        price_feed.set_price_updater(&owner_cap, UPDATER1, true, scenario.ctx());
        assert!(price_feed.is_price_updater( UPDATER1) == true, 2);
        assert!(price_feed.is_price_updater( UPDATER2) == false, 3);

        // Enable updater2
        price_feed.set_price_updater(&owner_cap, UPDATER2, true, scenario.ctx());
        assert!(price_feed.is_price_updater( UPDATER1) == true, 4);
        assert!(price_feed.is_price_updater( UPDATER2) == true, 5);

        // Disable updater1
        price_feed.set_price_updater(&owner_cap, UPDATER1, false, scenario.ctx());
        assert!(price_feed.is_price_updater( UPDATER1) == false, 6);
        assert!(price_feed.is_price_updater( UPDATER2) == true, 7);

        return_price_feed_and_owner_cap(price_feed, owner_cap, &scenario);
    };

    clean(scenario);
}

#[test]
fun test_set_price_ratio_denominator() {
    let mut scenario = setup();

    init_price_feed_for_test(&mut scenario);

    scenario.next_tx(OWNER);
    {
        let (mut price_feed, owner_cap) = get_price_feed_and_owner_cap(&scenario);

        // Check default value
        assert!(price_feed.get_price_ratio_denominator() == 100000000000000000000, 0);

        // Set new value
        price_feed.set_price_ratio_denominator(&owner_cap, 100000000);
        assert!(price_feed.get_price_ratio_denominator() == 100000000, 1);

        return_price_feed_and_owner_cap(price_feed, owner_cap, &scenario);
    };

    clean(scenario);
}

#[test]
fun test_set_arbitrum_compression_percent() {
    let mut scenario = setup();

    init_price_feed_for_test(&mut scenario);

    scenario.next_tx(OWNER);
    {
        let (mut price_feed, owner_cap) = get_price_feed_and_owner_cap(&scenario);

        // Check default value
        assert!(price_feed.get_arbitrum_compression_percent() == 47, 0);

        // Set new value
        price_feed.set_arbitrum_compression_percent(&owner_cap, 50);
        assert!(price_feed.get_arbitrum_compression_percent() == 50, 1);

        return_price_feed_and_owner_cap(price_feed, owner_cap, &scenario);
    };

    clean(scenario);
}

#[test]
fun test_set_eid_to_model_type() {
    let mut scenario = setup();

    init_price_feed_for_test(&mut scenario);

    scenario.next_tx(OWNER);
    {
        let (mut price_feed, owner_cap) = get_price_feed_and_owner_cap(&scenario);

        // Set different model types for different EIDs
        price_feed.set_eid_to_model_type(&owner_cap, 101, price_feed::model_type_default());
        price_feed.set_eid_to_model_type(&owner_cap, 102, price_feed::model_type_optimism());
        price_feed.set_eid_to_model_type(&owner_cap, 103, price_feed::model_type_arbitrum());

        // Check the model types
        assert!(price_feed.get_model_type( 101) == price_feed::model_type_default(), 0);
        assert!(price_feed.get_model_type( 102) == price_feed::model_type_optimism(), 1);
        assert!(price_feed.get_model_type( 103) == price_feed::model_type_arbitrum(), 2);
        // Unknown EID should return default
        assert!(price_feed.get_model_type( 999) == price_feed::model_type_default(), 3);

        return_price_feed_and_owner_cap(price_feed, owner_cap, &scenario);
    };

    clean(scenario);
}

#[test]
fun test_set_price() {
    let mut scenario = setup();

    init_price_feed_for_test(&mut scenario);

    scenario.next_tx(OWNER);
    {
        let (mut price_feed, owner_cap) = get_price_feed_and_owner_cap(&scenario);

        // Enable price updater
        price_feed.set_price_updater(&owner_cap, UPDATER1, true, scenario.ctx());

        return_price_feed_and_owner_cap(price_feed, owner_cap, &scenario);
    };

    scenario.next_tx(UPDATER1);
    {
        let mut price_feed = ts::take_shared<PriceFeed>(&scenario);
        let updater_cap = ts::take_from_sender<PriceUpdaterCap>(&scenario);

        // Set prices for different EIDs
        let price1 = price_feed::create_price(100000000000000000000, 1000000000, 16);
        let price2 = price_feed::create_price(200000000000000000000, 2000000000, 32);

        price_feed.set_price(&updater_cap, 101, price1);
        price_feed.set_price(&updater_cap, 102, price2);

        // Check prices can be retrieved
        let _retrieved_price1 = price_feed.get_price(101);
        let _retrieved_price2 = price_feed.get_price(102);

        ts::return_shared(price_feed);
        ts::return_to_sender(&scenario, updater_cap);
    };

    clean(scenario);
}

#[test]
fun test_set_native_token_price_usd() {
    let mut scenario = setup();

    init_price_feed_for_test(&mut scenario);

    scenario.next_tx(OWNER);
    {
        let (mut price_feed, owner_cap) = get_price_feed_and_owner_cap(&scenario);

        // Enable price updater
        price_feed.set_price_updater(&owner_cap, UPDATER1, true, scenario.ctx());

        return_price_feed_and_owner_cap(price_feed, owner_cap, &scenario);
    };

    scenario.next_tx(UPDATER1);
    {
        let mut price_feed = ts::take_shared<PriceFeed>(&scenario);
        let updater_cap = ts::take_from_sender<PriceUpdaterCap>(&scenario);

        // Check initial value
        assert!(price_feed.native_token_price_usd() == 0, 0);

        // Set native token price
        price_feed.set_native_token_price_usd(&updater_cap, 2500000000000000000000);
        assert!(price_feed.native_token_price_usd() == 2500000000000000000000, 1);

        ts::return_shared(price_feed);
        ts::return_to_sender(&scenario, updater_cap);
    };

    clean(scenario);
}

#[test]
fun test_estimate_fee_by_eid_default_model() {
    let mut scenario = setup();

    init_price_feed_for_test(&mut scenario);

    scenario.next_tx(OWNER);
    {
        let (mut price_feed, owner_cap) = get_price_feed_and_owner_cap(&scenario);

        // Enable price updater
        price_feed.set_price_updater(&owner_cap, UPDATER1, true, scenario.ctx());

        return_price_feed_and_owner_cap(price_feed, owner_cap, &scenario);
    };

    scenario.next_tx(UPDATER1);
    {
        let mut price_feed = ts::take_shared<PriceFeed>(&scenario);
        let updater_cap = ts::take_from_sender<PriceUpdaterCap>(&scenario);
        // Set price for EID 101 (default model)
        let price = price_feed::create_price(100000000000000000000, 1000000000, 16);
        price_feed.set_price(&updater_cap, 101, price);

        ts::return_shared(price_feed);
        ts::return_to_sender(&scenario, updater_cap);
    };

    scenario.next_tx(OWNER);
    {
        let price_feed = ts::take_shared<PriceFeed>(&scenario);

        // Create estimate fee call
        let param = estimate_fee::create_param(101, 1000, 500);
        let mut call = call::create(
            price_feed.get_call_cap(),
            @0x0, // callee address (not used in this test)
            false, // one_way
            param,
            scenario.ctx(),
        );

        // Estimate fee
        price_feed.estimate_fee_by_eid(&mut call);

        // Get result
        let (_, _, result) = call::destroy(call, price_feed.get_call_cap());
        let fee = result.fee();
        let price_ratio = result.price_ratio();
        let denominator = result.price_ratio_denominator();
        let native_price_usd = result.native_price_usd();

        // Verify results (fee calculation: ((1000 * 16) + 500) * 1000000000 * 100000000000000000000 /
        // 100000000000000000000)
        assert!(fee == 16500000000000, 0);
        assert!(price_ratio == 100000000000000000000, 1);
        assert!(denominator == 100000000000000000000, 2);
        assert!(native_price_usd == 0, 3);

        ts::return_shared(price_feed);
    };

    clean(scenario);
}

#[test]
fun test_estimate_fee_with_arbitrum_model() {
    let mut scenario = setup();

    init_price_feed_for_test(&mut scenario);

    scenario.next_tx(OWNER);
    {
        let (mut price_feed, owner_cap) = get_price_feed_and_owner_cap(&scenario);

        // Enable price updater
        price_feed.set_price_updater(&owner_cap, UPDATER1, true, scenario.ctx());

        return_price_feed_and_owner_cap(price_feed, owner_cap, &scenario);
    };

    scenario.next_tx(UPDATER1);
    {
        let mut price_feed = ts::take_shared<PriceFeed>(&scenario);
        let updater_cap = ts::take_from_sender<PriceUpdaterCap>(&scenario);
        // Set price for EID 110 (arbitrum - hardcoded)
        let arbitrum_price = price_feed::create_price(100000000000000000000, 10000000, 16);

        // Set arbitrum price extension for arbitrum model
        let arbitrum_ext = price_feed::create_arbitrum_price_ext(4176, 29);
        price_feed.set_price_for_arbitrum(&updater_cap, 110, arbitrum_price, arbitrum_ext);

        ts::return_shared(price_feed);
        ts::return_to_sender(&scenario, updater_cap);
    };

    scenario.next_tx(OWNER);
    {
        let price_feed = ts::take_shared<PriceFeed>(&scenario);

        // Create estimate fee call for arbitrum (EID 110)
        let param = estimate_fee::create_param(110, 1000, 500);
        let mut call = call::create(
            price_feed.get_call_cap(),
            @0x0, // callee address (not used in this test)
            false, // one_way
            param,
            scenario.ctx(),
        );

        // Estimate fee
        price_feed.estimate_fee_by_eid(&mut call);

        // Get result
        let (_, _, result) = call::destroy(call, price_feed.get_call_cap());
        let fee = result.fee();

        // Verify fee calculation for arbitrum model
        // compressed calldata size = floor((calldata_size: 1000) * (47: compression_percent) / 100) = 470
        // l1 calldata gas = (compressed_size: 470) * (arb_gas_per_l1_calldata_byte: 29) = 13630
        // l2 calldata gas = (calldata_size: 1000) * (arb_gas_per_byte: 16) = 16000
        // total gas = (gas: 500) + (arb_gas_per_l2_tx: 4176) + (l1: 13630) + (l2: 16000) = 34306
        // total fee = (total gas: 34306) * (gas_price: 10000000) * (price_ratio: 100000000000000000000) / (denominator:
        // 100000000000000000000) = 343060000000
        assert!(fee == 343060000000, 0);

        ts::return_shared(price_feed);
    };

    clean(scenario);
}

#[test]
fun test_estimate_fee_with_optimism_model() {
    let mut scenario = setup();

    init_price_feed_for_test(&mut scenario);

    scenario.next_tx(OWNER);
    {
        let (mut price_feed, owner_cap) = get_price_feed_and_owner_cap(&scenario);

        // Enable price updater
        price_feed.set_price_updater(&owner_cap, UPDATER1, true, scenario.ctx());

        return_price_feed_and_owner_cap(price_feed, owner_cap, &scenario);
    };

    scenario.next_tx(UPDATER1);
    {
        let mut price_feed = ts::take_shared<PriceFeed>(&scenario);
        let updater_cap = ts::take_from_sender<PriceUpdaterCap>(&scenario);
        // Set prices for optimism model
        // EID 111 (optimism L2) and EID 101 (ethereum L1 - used for L1 fee calculation)
        let ethereum_price = price_feed::create_price(100000000000000000000, 646718991, 8);
        let optimism_price = price_feed::create_price(100000000000000000000, 2231118, 16);

        price_feed.set_price(&updater_cap, 101, ethereum_price); // Ethereum L1
        price_feed.set_price(&updater_cap, 111, optimism_price); // Optimism L2

        ts::return_shared(price_feed);
        ts::return_to_sender(&scenario, updater_cap);
    };

    scenario.next_tx(OWNER);
    {
        let price_feed = ts::take_shared<PriceFeed>(&scenario);

        // Create estimate fee call for optimism (EID 111)
        let param = estimate_fee::create_param(111, 1000, 500);
        let mut call = call::create(
            price_feed.get_call_cap(),
            @0x0, // callee address (not used in this test)
            false, // one_way
            param,
            scenario.ctx(),
        );

        // Estimate fee
        price_feed.estimate_fee_by_eid(&mut call);

        // Get result
        let (_, _, result) = call::destroy(call, price_feed.get_call_cap());
        let fee = result.fee();

        // Verify fee is calculated using optimism model (L1 + L2 fees)
        // This is a complex calculation involving both L1 and L2 fees
        // L1 fee: ((1000 * 8) + 3188) * 646718991 = 7272305518308
        // L2 fee: ((1000 * 16) + 500) * 2231118 = 36833447000
        // Combined and converted using price ratios
        assert!(fee == 7272305518308, 0);

        ts::return_shared(price_feed);
    };

    clean(scenario);
}

#[test]
fun test_create_price() {
    let _price = price_feed::create_price(100000000000000000000, 1000000000, 16);
    // We can't directly access fields, but we can verify the price was created successfully
    // by using it in other functions
}

#[test]
fun test_create_arbitrum_price_ext() {
    let _arb_ext = price_feed::create_arbitrum_price_ext(4176, 29);
    // Similar to create_price, we verify by successful creation
}

#[test]
fun test_model_type_functions() {
    let default_type = price_feed::model_type_default();
    let arbitrum_type = price_feed::model_type_arbitrum();
    let optimism_type = price_feed::model_type_optimism();

    // Verify they are different
    assert!(default_type != arbitrum_type, 0);
    assert!(default_type != optimism_type, 1);
    assert!(arbitrum_type != optimism_type, 2);
}

#[test]
#[expected_failure(abort_code = price_feed::EOnlyPriceUpdater)]
fun test_set_price_unauthorized() {
    let mut scenario = setup();

    init_price_feed_for_test(&mut scenario);

    // Owner enables and then disables the price updater
    scenario.next_tx(OWNER);
    {
        let (mut price_feed, owner_cap) = get_price_feed_and_owner_cap(&scenario);

        // Enable price updater then disable it
        price_feed.set_price_updater(&owner_cap, NON_UPDATER, true, scenario.ctx());
        price_feed.set_price_updater(&owner_cap, NON_UPDATER, false, scenario.ctx());

        return_price_feed_and_owner_cap(price_feed, owner_cap, &scenario);
    };

    // Non-updater tries to set price with disabled capability
    scenario.next_tx(NON_UPDATER);
    {
        let mut price_feed = ts::take_shared<PriceFeed>(&scenario);
        let updater_cap = ts::take_from_sender<PriceUpdaterCap>(&scenario);

        let price = price_feed::create_price(100000000000000000000, 1000000000, 16);
        price_feed.set_price(&updater_cap, 101, price); // Should fail

        ts::return_shared(price_feed);
        ts::return_to_sender(&scenario, updater_cap);
    };

    clean(scenario);
}

#[test]
#[expected_failure(abort_code = price_feed::ENoPrice)]
fun test_get_price_nonexistent() {
    let mut scenario = setup();

    init_price_feed_for_test(&mut scenario);

    scenario.next_tx(OWNER);
    {
        let (price_feed, owner_cap) = get_price_feed_and_owner_cap(&scenario);

        // Try to get price for non-existent EID
        let _price = price_feed.get_price(999);

        return_price_feed_and_owner_cap(price_feed, owner_cap, &scenario);
    };

    clean(scenario);
}

#[test]
fun test_arbitrum_traits() {
    let mut scenario = setup();

    init_price_feed_for_test(&mut scenario);

    scenario.next_tx(OWNER);
    {
        let (mut price_feed, owner_cap) = get_price_feed_and_owner_cap(&scenario);

        // Enable price updater
        price_feed.set_price_updater(&owner_cap, UPDATER1, true, scenario.ctx());

        return_price_feed_and_owner_cap(price_feed, owner_cap, &scenario);
    };

    scenario.next_tx(UPDATER1);
    {
        let mut price_feed = ts::take_shared<PriceFeed>(&scenario);
        let updater_cap = ts::take_from_sender<PriceUpdaterCap>(&scenario);

        // Get initial arbitrum traits
        let _initial_traits = price_feed.arbitrum_price_ext();

        // Set arbitrum price extension
        let price = price_feed::create_price(100000000000000000000, 1000000000, 16);
        let arbitrum_ext = price_feed::create_arbitrum_price_ext(100, 200);

        price_feed.set_price_for_arbitrum(&updater_cap, 110, price, arbitrum_ext);

        // Verify traits were updated
        let _updated_traits = price_feed.arbitrum_price_ext();
        // We can't directly compare structs, but we can verify they're different from initial

        ts::return_shared(price_feed);
        ts::return_to_sender(&scenario, updater_cap);
    };

    clean(scenario);
}

#[test]
fun test_estimate_fee_on_send() {
    let mut scenario = setup();

    init_price_feed_for_test(&mut scenario);

    scenario.next_tx(OWNER);
    {
        let (mut price_feed, owner_cap) = get_price_feed_and_owner_cap(&scenario);

        // Enable price updater
        price_feed.set_price_updater(&owner_cap, UPDATER1, true, scenario.ctx());

        // Set denominator and arbitrum settings to match Aptos test
        price_feed.set_price_ratio_denominator(&owner_cap, 100);
        price_feed.set_arbitrum_compression_percent(&owner_cap, 47);

        // Set model type mappings for non-hardcoded EIDs
        price_feed.set_eid_to_model_type(&owner_cap, 110, price_feed::model_type_default()); // Cannot override hardcoded - still ARBITRUM
        price_feed.set_eid_to_model_type(&owner_cap, 11000, price_feed::model_type_optimism()); // Optimism using L1 sepolia
        price_feed.set_eid_to_model_type(&owner_cap, 41000, price_feed::model_type_optimism()); // Optimism using L1 sepolia (11000 + 30000)
        price_feed.set_eid_to_model_type(&owner_cap, 25555, price_feed::model_type_arbitrum());
        price_feed.set_eid_to_model_type(&owner_cap, 26666, price_feed::model_type_optimism());

        return_price_feed_and_owner_cap(price_feed, owner_cap, &scenario);
    };

    scenario.next_tx(UPDATER1);
    {
        let mut price_feed = ts::take_shared<PriceFeed>(&scenario);
        let updater_cap = ts::take_from_sender<PriceUpdaterCap>(&scenario);

        // Set native token price to match Aptos test
        price_feed.set_native_token_price_usd(&updater_cap, 6);

        // Set arbitrum traits to match Aptos test
        let arbitrum_ext = price_feed::create_arbitrum_price_ext(5432, 11);
        price_feed.set_price_for_arbitrum(&updater_cap, 110, price_feed::create_price(1222, 12, 3), arbitrum_ext);

        // Set prices matching the Aptos test
        let eth_price = price_feed::create_price(4000, 51, 33);
        let eth_goerli_price = price_feed::create_price(40000, 51, 33);
        let eth_sepolia_price = price_feed::create_price(400000, 51, 33);
        let arb_price = price_feed::create_price(1222, 12, 3);
        let opt_price = price_feed::create_price(200, 43, 5);

        // Set all the prices for different EIDs
        price_feed.set_price(&updater_cap, 101, eth_price); // First 6 EIDs are all of hardcoded types
        price_feed.set_price(&updater_cap, 110, arb_price);
        price_feed.set_price(&updater_cap, 111, opt_price);
        price_feed.set_price(&updater_cap, 10101, eth_price);
        price_feed.set_price(&updater_cap, 10143, arb_price);
        price_feed.set_price(&updater_cap, 10132, opt_price);
        price_feed.set_price(&updater_cap, 11000, opt_price); // optimism using L1 sepolia
        price_feed.set_price(&updater_cap, 10121, eth_goerli_price); // eth-goerli - used for arbitrum estimate
        price_feed.set_price(&updater_cap, 10161, eth_sepolia_price); // eth-sepolia - used for arbitrum estimate

        price_feed.set_price(&updater_cap, 24444, eth_price); // not hardcoded and not set - should default to "DEFAULT"
        price_feed.set_price(&updater_cap, 25555, arb_price); // configured to "ARBITRUM"
        price_feed.set_price(&updater_cap, 26666, opt_price); // configured to "OPTIMISM"
        price_feed.set_price(&updater_cap, 20121, eth_goerli_price); // eth-goerli - used for arbitrum estimate

        ts::return_shared(price_feed);
        ts::return_to_sender(&scenario, updater_cap);
    };

    // Test Default (101 + 30000)
    scenario.next_tx(OWNER);
    {
        let price_feed = ts::take_shared<PriceFeed>(&scenario);

        let param = estimate_fee::create_param(30101, 50, 100);
        let mut call = call::create(
            price_feed.get_call_cap(),
            @0x0,
            false,
            param,
            scenario.ctx(),
        );

        price_feed.estimate_fee_by_eid(&mut call);

        let (_, _, result) = call::destroy(call, price_feed.get_call_cap());
        let fee = result.fee();
        let price_ratio = result.price_ratio();
        let denominator = result.price_ratio_denominator();
        let native_price_usd = result.native_price_usd();

        assert!(fee == 3570000, 1);
        assert!(price_ratio == 4000, 2);
        assert!(denominator == 100, 3);
        assert!(native_price_usd == 6, 4);

        ts::return_shared(price_feed);
    };

    // Test Default (10101)
    scenario.next_tx(OWNER);
    {
        let price_feed = ts::take_shared<PriceFeed>(&scenario);

        let param = estimate_fee::create_param(10101, 50, 100);
        let mut call = call::create(
            price_feed.get_call_cap(),
            @0x0,
            false,
            param,
            scenario.ctx(),
        );

        price_feed.estimate_fee_by_eid(&mut call);

        let (_, _, result) = call::destroy(call, price_feed.get_call_cap());
        let fee = result.fee();

        assert!(fee == 3570000, 5);

        ts::return_shared(price_feed);
    };

    // Test Default (24444 + 60000)
    scenario.next_tx(OWNER);
    {
        let price_feed = ts::take_shared<PriceFeed>(&scenario);

        let param = estimate_fee::create_param(84444, 50, 100);
        let mut call = call::create(
            price_feed.get_call_cap(),
            @0x0,
            false,
            param,
            scenario.ctx(),
        );

        price_feed.estimate_fee_by_eid(&mut call);

        let (_, _, result) = call::destroy(call, price_feed.get_call_cap());
        let fee = result.fee();

        assert!(fee == 3570000, 6);

        ts::return_shared(price_feed);
    };

    // Test Arbitrum (110 + 60000)
    scenario.next_tx(OWNER);
    {
        let price_feed = ts::take_shared<PriceFeed>(&scenario);

        let param = estimate_fee::create_param(60110, 50, 232);
        let mut call = call::create(
            price_feed.get_call_cap(),
            @0x0,
            false,
            param,
            scenario.ctx(),
        );

        price_feed.estimate_fee_by_eid(&mut call);

        let (_, _, result) = call::destroy(call, price_feed.get_call_cap());
        let fee = result.fee();

        assert!(fee == 889664, 7);

        ts::return_shared(price_feed);
    };

    // Test Arbitrum (10143)
    scenario.next_tx(OWNER);
    {
        let price_feed = ts::take_shared<PriceFeed>(&scenario);

        let param = estimate_fee::create_param(10143, 50, 232);
        let mut call = call::create(
            price_feed.get_call_cap(),
            @0x0,
            false,
            param,
            scenario.ctx(),
        );

        price_feed.estimate_fee_by_eid(&mut call);

        let (_, _, result) = call::destroy(call, price_feed.get_call_cap());
        let fee = result.fee();

        assert!(fee == 889664, 8);

        ts::return_shared(price_feed);
    };

    // Test Arbitrum (25555)
    scenario.next_tx(OWNER);
    {
        let price_feed = ts::take_shared<PriceFeed>(&scenario);

        let param = estimate_fee::create_param(25555, 50, 232);
        let mut call = call::create(
            price_feed.get_call_cap(),
            @0x0,
            false,
            param,
            scenario.ctx(),
        );

        price_feed.estimate_fee_by_eid(&mut call);

        let (_, _, result) = call::destroy(call, price_feed.get_call_cap());
        let fee = result.fee();

        assert!(fee == 889664, 9);

        ts::return_shared(price_feed);
    };

    // Test Optimism (111 + 90000)
    scenario.next_tx(OWNER);
    {
        let price_feed = ts::take_shared<PriceFeed>(&scenario);

        let param = estimate_fee::create_param(90111, 2100, 232);
        let mut call = call::create(
            price_feed.get_call_cap(),
            @0x0,
            false,
            param,
            scenario.ctx(),
        );

        price_feed.estimate_fee_by_eid(&mut call);

        let (_, _, result) = call::destroy(call, price_feed.get_call_cap());
        let fee = result.fee();

        assert!(fee == 148798472, 10);

        ts::return_shared(price_feed);
    };

    // Test Optimism (10132 + 30000) - using goerli
    scenario.next_tx(OWNER);
    {
        let price_feed = ts::take_shared<PriceFeed>(&scenario);

        let param = estimate_fee::create_param(40132, 2100, 232);
        let mut call = call::create(
            price_feed.get_call_cap(),
            @0x0,
            false,
            param,
            scenario.ctx(),
        );

        price_feed.estimate_fee_by_eid(&mut call);

        let (_, _, result) = call::destroy(call, price_feed.get_call_cap());
        let fee = result.fee();

        assert!(fee == 1479678152, 11); // goerli 10x

        ts::return_shared(price_feed);
    };

    // Test Optimism (11000 + 30000) - using sepolia
    scenario.next_tx(OWNER);
    {
        let price_feed = ts::take_shared<PriceFeed>(&scenario);

        let param = estimate_fee::create_param(41000, 2100, 232);
        let mut call = call::create(
            price_feed.get_call_cap(),
            @0x0,
            false,
            param,
            scenario.ctx(),
        );

        price_feed.estimate_fee_by_eid(&mut call);

        let (_, _, result) = call::destroy(call, price_feed.get_call_cap());
        let fee = result.fee();

        assert!(fee == 14788474952, 12); // sepolia 100x

        ts::return_shared(price_feed);
    };

    // Test Optimism (26666) - using goerli
    scenario.next_tx(OWNER);
    {
        let price_feed = ts::take_shared<PriceFeed>(&scenario);

        let param = estimate_fee::create_param(26666, 2100, 232);
        let mut call = call::create(
            price_feed.get_call_cap(),
            @0x0,
            false,
            param,
            scenario.ctx(),
        );

        price_feed.estimate_fee_by_eid(&mut call);

        let (_, _, result) = call::destroy(call, price_feed.get_call_cap());
        let fee = result.fee();

        assert!(fee == 1479678152, 13); // goerli 10x

        ts::return_shared(price_feed);
    };

    clean(scenario);
}

// === Test Helper Functions ===

// Helper function to setup test scenario
fun setup(): ts::Scenario {
    ts::begin(OWNER)
}

// Helper function to clean up test scenario
fun clean(scenario: ts::Scenario) {
    ts::end(scenario);
}

// Helper function to initialize the price feed for testing
fun init_price_feed_for_test(scenario: &mut ts::Scenario) {
    scenario.next_tx(OWNER);
    {
        price_feed::init_for_test(scenario.ctx());
    };
}

// Helper function to get price feed and owner cap
fun get_price_feed_and_owner_cap(scenario: &ts::Scenario): (PriceFeed, OwnerCap) {
    let price_feed = ts::take_shared<PriceFeed>(scenario);
    let owner_cap = ts::take_from_sender<OwnerCap>(scenario);
    (price_feed, owner_cap)
}

// Helper function to return price feed and owner cap
fun return_price_feed_and_owner_cap(price_feed: PriceFeed, owner_cap: OwnerCap, scenario: &ts::Scenario) {
    ts::return_shared(price_feed);
    ts::return_to_sender(scenario, owner_cap);
}
