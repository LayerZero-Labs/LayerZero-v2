module price_feed_module_0::feeds {
    use std::event::emit;
    use std::signer::address_of;
    use std::table::{Self, Table};
    use std::vector;

    use price_feed_module_0::eid_model_pair::{Self, ARBITRUM_MODEL_TYPE, DEFAULT_MODEL_TYPE, OPTIMISM_MODEL_TYPE};
    use price_feed_module_0::price::{Self, Price, split_eid_tagged_price};

    #[test_only]
    friend price_feed_module_0::feeds_tests;

    /// The data for a single price feed on this price feed module
    struct Feed has key {
        // The denominator for the price ratio remote price * price ratio / denominator = local price
        denominator: u128,
        // The compression percent for arbitrum (base 100)
        arbitrum_compression_percent: u64,
        // The model to use (which corresponds to chain type) for each destination EID
        model_type: Table<u32 /*eid*/, u16 /*model_type*/>,
        // The price ratio, gas price, and gas per byte for each destination EID
        prices: Table<u32 /*eid*/, Price>,
        // The base gas price for an Arbitrum L2 transaction
        arbitrum_gas_per_l2_tx: u128,
        // The gas price for an Arbitrum L1 calldata byte
        arbitrum_gas_per_l1_calldata_byte: u128,
        // The price, with `denominator` precision, of the native token in USD
        native_token_price_usd: u128,
        // The set of approved feed updaters (presence indicates approved, the value is always `true`)
        updaters: Table<address, bool>,
    }

    // =============================================== Only Feed Admins ===============================================

    /// Initializes a new feed under the signer's account address
    public entry fun initialize(account: &signer) {
        move_to(account, Feed {
            denominator: 100_000_000_000_000_000_000, // 1e20
            arbitrum_compression_percent: 47,
            model_type: table::new(),
            prices: table::new(),
            arbitrum_gas_per_l2_tx: 0,
            arbitrum_gas_per_l1_calldata_byte: 0,
            native_token_price_usd: 0,
            updaters: table::new(),
        });
    }

    /// Gives a feed updater permission to write to the signer's feed
    public entry fun enable_feed_updater(account: &signer, updater: address) acquires Feed {
        let feed_address = address_of(move account);
        table::upsert(feed_updaters_mut(feed_address), updater, true);
        emit(FeedUpdaterSet { feed_address, updater, enabled: true });
    }

    /// Revokes a feed updater's permission to write to the signer's feed
    public entry fun disable_feed_updater(account: &signer, updater: address) acquires Feed {
        let feed_address = address_of(move account);
        table::remove(feed_updaters_mut(feed_address), updater);
        emit(FeedUpdaterSet { feed_address, updater, enabled: false });
    }

    /// Sets the denominator for the feed
    public entry fun set_denominator(account: &signer, denominator: u128) acquires Feed {
        assert!(denominator > 0, EINVALID_DENOMNIATOR);
        let feed_address = address_of(move account);
        feed_data_mut(feed_address).denominator = denominator;
    }

    /// Sets the arbitrum compression percent (base 100) for the feed
    public entry fun set_arbitrum_compression_percent(account: &signer, percent: u64) acquires Feed {
        let feed_address = address_of(move account);
        feed_data_mut(feed_address).arbitrum_compression_percent = percent;
    }

    /// Sets the model type for multiple given destination EIDs
    /// The params are a serialized list of EidModelPair
    public entry fun set_eid_models(account: &signer, params: vector<u8>) acquires Feed {
        let feed_address = address_of(move account);

        let eid_to_model_list = eid_model_pair::deserialize_eid_model_pair_list(&params);
        let model_type_mut = &mut feed_data_mut(feed_address).model_type;
        for (i in 0..vector::length(&eid_to_model_list)) {
            let eid_model = vector::borrow(&eid_to_model_list, i);
            let dst_eid = eid_model_pair::get_dst_eid(eid_model);
            let model_type = eid_model_pair::get_model_type(eid_model);
            assert!(eid_model_pair::is_valid_model_type(model_type), EINVALID_MODEL_TYPE);
            table::upsert(model_type_mut, dst_eid, model_type);
        }
    }

    #[view]
    /// Gets the model type for a given destination EID
    /// @dev the model type can be default (0), arbitrum (1), or optimism (2)
    public fun get_model_type(feed_address: address, dst_eid: u32): u16 acquires Feed {
        let feed = feed_data(feed_address);
        *table::borrow_with_default(&feed.model_type, dst_eid, &DEFAULT_MODEL_TYPE())
    }

    // ============================================== Only Feed Updaters ==============================================

    /// Asserts that a feed updater is approved to write to a specific feed
    fun assert_valid_fee_updater(updater: address, feed: address) acquires Feed {
        assert!(is_price_updater(updater, feed), EUNAUTHORIZED_UPDATER);
    }

    /// Sets the price (serialized EidTagged<Price>) for a given destination EID
    public entry fun set_price(updater: &signer, feed: address, prices: vector<u8>) acquires Feed {
        let updater = address_of(move updater);
        assert_valid_fee_updater(updater, feed);

        let price_list = price::deserialize_eid_tagged_price_list(&prices);
        let prices_mut = &mut feed_data_mut(feed).prices;
        for (i in 0..vector::length(&price_list)) {
            let eid_tagged_price = vector::borrow(&price_list, i);
            let (eid, price) = split_eid_tagged_price(eid_tagged_price);
            table::upsert(prices_mut, eid, price);
        }
    }

    /// Sets the arbitrum traits for the feed
    public entry fun set_arbitrum_traits(
        updater: &signer,
        feed_address: address,
        gas_per_l2_tx: u128,
        gas_per_l1_calldata_byte: u128,
    ) acquires Feed {
        let updater = address_of(move updater);
        assert_valid_fee_updater(updater, feed_address);

        let feed_data_mut = feed_data_mut(feed_address);
        feed_data_mut.arbitrum_gas_per_l2_tx = gas_per_l2_tx;
        feed_data_mut.arbitrum_gas_per_l1_calldata_byte = gas_per_l1_calldata_byte;
    }

    /// Sets the native token price in USD for the feed denominated in `denominator` precision
    public entry fun set_native_token_price_usd(
        updater: &signer,
        feed_address: address,
        native_token_price_usd: u128,
    ) acquires Feed {
        let updater = address_of(move updater);
        assert_valid_fee_updater(updater, feed_address);

        feed_data_mut(feed_address).native_token_price_usd = native_token_price_usd;
    }

    // ===================================================== View =====================================================

    #[view]
    /// Gets the denominator used for price ratios for the feed
    public fun get_price_ratio_denominator(feed_address: address): u128 acquires Feed {
        feed_data(feed_address).denominator
    }

    #[view]
    /// Checks if a feed updater has the permission to write to a feed
    public fun is_price_updater(updater: address, feed: address): bool acquires Feed {
        table::contains(feed_updaters(feed), updater)
    }

    #[view]
    /// Gets the native token price in USD for the feed (denominated in `denominator` precision)
    public fun get_native_token_price_usd(feed_address: address): u128 acquires Feed {
        feed_data(feed_address).native_token_price_usd
    }

    #[view]
    /// Gets the arbitrum compression percent (base 100) for the feed
    public fun get_arbitrum_compression_percent(feed_address: address): u64 acquires Feed {
        feed_data(feed_address).arbitrum_compression_percent
    }

    #[view]
    /// Gets the arbitrum traits for the feed
    /// @return (gas per L2 transaction, gas per L1 calldata byte)
    public fun get_arbitrum_price_traits(feed_address: address): (u128, u128) acquires Feed {
        let feed = feed_data(feed_address);
        (feed.arbitrum_gas_per_l2_tx, feed.arbitrum_gas_per_l1_calldata_byte)
    }

    #[view]
    /// Gets the price data for a given destination EID
    /// @return (price ratio, gas price in unit, gas price per byte)
    public fun get_price(feed_address: address, _dst_eid: u32): (u128, u64, u32) acquires Feed {
        let prices = &feed_data(feed_address).prices;

        assert!(table::contains(prices, _dst_eid), EEID_DOES_NOT_EXIST);
        let eid_price = table::borrow(prices, _dst_eid);
        (price::get_price_ratio(eid_price), price::get_gas_price_in_unit(eid_price), price::get_gas_per_byte(eid_price))
    }

    // ================================================ Fee Estimation ================================================

    #[view]
    /// Estimates the fee for a send transaction, considering the eid, gas, and call data size
    /// This selects the appropriate model and prices inputs based on the destination EID
    /// @return (fee, price ratio, denominator, native token price in USD)
    public fun estimate_fee_on_send(
        feed_address: address,
        dst_eid: u32,
        call_data_size: u64,
        gas: u128,
    ): (u128, u128, u128, u128) acquires Feed {
        // v2 EIDs are the v1 EIDs + 30,000
        // We anticipate that each subsequent eid will be 30,000 more than the prior (but on the same chain)
        let dst_eid_mod = dst_eid % 30_000;

        let feed = feed_data(feed_address);
        let denominator = feed.denominator;
        let native_token_price_usd = feed.native_token_price_usd;

        let type = table::borrow_with_default(&feed.model_type, dst_eid_mod, &DEFAULT_MODEL_TYPE());
        assert!(table::contains(&feed.prices, dst_eid_mod), EPRICE_FEED_NOT_CONFIGURED_FOR_EID);
        let dst_pricing = table::borrow(&feed.prices, dst_eid_mod);

        let fee = if (dst_eid_mod == 110 || dst_eid_mod == 10143 || dst_eid_mod == 20143 || type == &ARBITRUM_MODEL_TYPE(
        )) {
            // Arbitrum Type
            estimate_fee_with_arbitrum_model(
                call_data_size,
                gas,
                dst_pricing,
                feed.denominator,
                feed.arbitrum_compression_percent,
                feed.arbitrum_gas_per_l1_calldata_byte,
                feed.arbitrum_gas_per_l2_tx,
            )
        } else if (dst_eid_mod == 111 || dst_eid_mod == 10132 || dst_eid_mod == 20132 || type == &OPTIMISM_MODEL_TYPE(
        )) {
            // Optimism Type
            let ethereum_id = get_l1_lookup_id_for_optimism_model(dst_eid_mod);
            assert!(table::contains(&feed.prices, ethereum_id), EPRICE_FEED_NOT_CONFIGURED_FOR_EID_ETH_L1);
            let ethereum_pricing = table::borrow(&feed.prices, ethereum_id);
            estimate_fee_with_optimism_model(
                call_data_size,
                gas,
                ethereum_pricing,
                dst_pricing,
                feed.denominator,
            )
        } else {
            // Default
            estimate_fee_with_default_model(call_data_size, gas, dst_pricing, feed.denominator)
        };

        let price_ratio = price::get_price_ratio(dst_pricing);
        (fee, price_ratio, denominator, native_token_price_usd)
    }

    /// Estimates the fee for a send transaction using the default model
    public(friend) fun estimate_fee_with_default_model(
        call_data_size: u64,
        gas: u128,
        dst_pricing: &Price,
        denominator: u128,
    ): u128 {
        let gas_per_byte = price::get_gas_per_byte_u128(dst_pricing);
        let gas_price_in_unit = price::get_gas_price_in_unit_u128(dst_pricing);
        let gas_for_call_data = (call_data_size as u128) * gas_per_byte;
        let remote_fee = (gas_for_call_data + gas) * gas_price_in_unit;

        let fee = (remote_fee * price::get_price_ratio(dst_pricing)) / denominator;
        fee
    }

    /// Estimates the fee for a send transaction using the arbitrum model
    public(friend) fun estimate_fee_with_arbitrum_model(
        call_data_size: u64,
        gas: u128,
        dst_pricing: &Price,
        denominator: u128,
        arbitrum_compression_percent: u64,
        arbitrum_gas_per_l1_call_data_byte: u128,
        arbitrum_gas_per_l2_tx: u128,
    ): u128 {
        let arbitrum_gas_per_byte = price::get_gas_per_byte_u128(dst_pricing);
        let gas_price_in_unit = price::get_gas_price_in_unit_u128(dst_pricing);
        let price_ratio = price::get_price_ratio(dst_pricing);

        let gas_for_l1_call_data = ((call_data_size as u128) * (arbitrum_compression_percent as u128) / 100)
            * arbitrum_gas_per_l1_call_data_byte;
        let gas_for_l2_call_data = (call_data_size as u128) * arbitrum_gas_per_byte;
        let gas_fee = (gas
            + arbitrum_gas_per_l2_tx
            + gas_for_l1_call_data + gas_for_l2_call_data)
            * gas_price_in_unit;

        gas_fee * price_ratio / denominator
    }

    /// Estimates the fee for a send transaction using the optimism model
    public(friend) fun estimate_fee_with_optimism_model(
        call_data_size: u64,
        gas: u128,
        ethereum_pricing: &Price,
        optimism_pricing: &Price,
        denominator: u128,
    ): u128 {
        // L1 Fee
        let gas_per_byte_eth = price::get_gas_per_byte_u128(ethereum_pricing);
        let gas_price_in_unit_eth = price::get_gas_price_in_unit_u128(ethereum_pricing);
        let gas_for_l1_call_data = (call_data_size as u128) * gas_per_byte_eth + 3188;
        let l1_fee = gas_for_l1_call_data * gas_price_in_unit_eth;

        // L2 Fee
        let gas_per_byte_opt = price::get_gas_per_byte_u128(optimism_pricing);
        let gas_price_in_unit_opt = price::get_gas_price_in_unit_u128(optimism_pricing);
        let gas_for_l2_call_data = (call_data_size as u128) * gas_per_byte_opt;
        let l2_fee = (gas_for_l2_call_data + gas) * gas_price_in_unit_opt;

        let gas_price_ratio_eth = price::get_price_ratio(ethereum_pricing);
        let gas_price_ratio_opt = price::get_price_ratio(optimism_pricing);
        let l1_fee_in_src_price = (l1_fee * gas_price_ratio_eth) / denominator;
        let l2_fee_in_src_price = (l2_fee * gas_price_ratio_opt) / denominator;

        l1_fee_in_src_price + l2_fee_in_src_price
    }

    /// Gets the L1 lookup ID for the optimism model
    /// This is a hardcoded lookup for the L1 chain for the optimism model and it differs based on network
    public(friend) fun get_l1_lookup_id_for_optimism_model(l2_eid: u32): u32 {
        if (l2_eid < 10_000) {
            101
        } else if (l2_eid < 20_000) {
            if (l2_eid == 10132) {
                10121  // ethereum-goerli
            } else {
                10161  // ethereum-sepolia
            }
        } else {
            20121 // ethereum-goerli
        }
    }

    // ==================================================== Helpers ===================================================

    /// Asserts that a feed exists
    inline fun assert_feed_exists(feed: address) { assert!(exists<Feed>(feed), EFEED_DOES_NOT_EXIST); }

    /// Borrow the feed data for a single feed
    inline fun feed_data(feed: address): &Feed {
        assert_feed_exists(feed);
        borrow_global(feed)
    }

    /// Borrow the feed data for a single feed mutably
    inline fun feed_data_mut(feed: address): &mut Feed {
        assert_feed_exists(feed);
        borrow_global_mut(feed)
    }

    /// Borrow the updaters for a single feed
    inline fun feed_updaters(feed: address): &Table<address, bool> {
        assert_feed_exists(feed);
        &feed_data(feed).updaters
    }

    /// Borrow the updaters for a single feed mutably
    inline fun feed_updaters_mut(feed: address): &mut Table<address, bool> {
        assert_feed_exists(feed);
        &mut feed_data_mut(feed).updaters
    }

    // ==================================================== Events ====================================================

    #[event]
    struct FeedUpdaterSet has drop, store {
        feed_address: address,
        updater: address,
        enabled: bool,
    }

    #[test_only]
    public fun feed_updater_set_event(feed_address: address, updater: address, enabled: bool): FeedUpdaterSet {
        FeedUpdaterSet {
            feed_address,
            updater,
            enabled,
        }
    }

    // ================================================== Error Codes =================================================

    const EEID_DOES_NOT_EXIST: u64 = 1;
    const EFEED_DOES_NOT_EXIST: u64 = 2;
    const EINVALID_DENOMNIATOR: u64 = 3;
    const EINVALID_MODEL_TYPE: u64 = 4;
    const EPRICE_FEED_NOT_CONFIGURED_FOR_EID: u64 = 5;
    const EPRICE_FEED_NOT_CONFIGURED_FOR_EID_ETH_L1: u64 = 6;
    const EUNAUTHORIZED_UPDATER: u64 = 7;
}