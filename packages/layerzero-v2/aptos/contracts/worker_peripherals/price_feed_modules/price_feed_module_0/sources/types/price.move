module price_feed_module_0::price {
    use std::vector;

    use endpoint_v2_common::config_eid_tagged::{borrow_config, EidTagged, get_eid, tag_with_eid};
    use endpoint_v2_common::serde;

    /// This struct carries the EID specific price and gas information required to calculate gas for a given chain and
    /// convert gas, value, and fees to the current chain's native token.
    /// The price_ratio is relative to a DENOMINATOR that is defined in the price feed module
    struct Price has copy, drop, store {
        price_ratio: u128,
        gas_price_in_unit: u64,
        gas_per_byte: u32,
    }

    // Creates a new price struct
    public fun new_price(price_ratio: u128, gas_price_in_unit: u64, gas_per_byte: u32): Price {
        Price {
            price_ratio,
            gas_price_in_unit,
            gas_per_byte,
        }
    }

    // Gets the price ratio
    public fun get_price_ratio(price: &Price): u128 { price.price_ratio }

    // Gets the gas price in unit
    public fun get_gas_price_in_unit(price: &Price): u64 { price.gas_price_in_unit }

    // Gets the gas price in unit as a u128 (for use in arithmetic)
    public fun get_gas_price_in_unit_u128(price: &Price): u128 { (price.gas_price_in_unit as u128) }

    // Gets the gas price per byte in the native token
    public fun get_gas_per_byte(price: &Price): u32 { price.gas_per_byte }

    /// Gets the gas price per byte in the native token as a u128 (for use in arithmetic)
    public fun get_gas_per_byte_u128(price: &Price): u128 { (price.gas_per_byte as u128) }

    // Append Price to the end of a byte buffer
    public fun append_price(buf: &mut vector<u8>, price: &Price) {
        serde::append_u128(buf, price.price_ratio);
        serde::append_u64(buf, price.gas_price_in_unit);
        serde::append_u32(buf, price.gas_per_byte);
    }

    /// Append an Eid-tagged Price to the end of a byte buffer
    public fun append_eid_tagged_price(buf: &mut vector<u8>, price: &EidTagged<Price>) {
        serde::append_u32(buf, get_eid(price));
        append_price(buf, borrow_config(price));
    }

    /// Serialize a list of Eid-tagged Prices into a byte vector
    /// This will be a series of Eid-tagged Prices serialized one after the other
    public fun serialize_eid_tagged_price_list(prices: &vector<EidTagged<Price>>): vector<u8> {
        let buf = vector<u8>[];
        for (i in 0..vector::length(prices)) {
            append_eid_tagged_price(&mut buf, vector::borrow(prices, i));
        };
        buf
    }

    /// Extract a Price from a byte buffer at a given position
    /// The position to be updated to the next position after the deserialized Price
    public fun extract_price(buf: &vector<u8>, position: &mut u64): Price {
        let price_ratio = serde::extract_u128(buf, position);
        let gas_price_in_unit = serde::extract_u64(buf, position);
        let gas_per_byte = serde::extract_u32(buf, position);
        Price {
            price_ratio,
            gas_price_in_unit,
            gas_per_byte,
        }
    }

    /// Extract an Eid-tagged Price from a byte buffer at a given position
    /// The position to be updated to the next position after the deserialized Eid-tagged Price
    public fun extract_eid_tagged_price(buf: &vector<u8>, position: &mut u64): EidTagged<Price> {
        let eid = serde::extract_u32(buf, position);
        tag_with_eid(eid, extract_price(buf, position))
    }

    /// Deserialize a list of Eid-tagged Prices from a byte buffer
    /// This will extract a series of one-after-another Eid-tagged Prices from the buffer
    public fun deserialize_eid_tagged_price_list(buf: &vector<u8>): vector<EidTagged<Price>> {
        let result = vector<EidTagged<Price>>[];
        let position = 0;
        while (position < vector::length(buf)) {
            vector::push_back(&mut result, extract_eid_tagged_price(buf, &mut position));
        };
        result
    }
}
