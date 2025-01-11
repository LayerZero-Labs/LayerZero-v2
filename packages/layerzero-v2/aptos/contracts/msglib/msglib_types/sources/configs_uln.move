/// This module contains the serialization and deserialization logic for handling Send and Receive ULN configurations
module msglib_types::configs_uln {
    use std::vector;

    use endpoint_v2_common::serde::{
        append_address, append_u64, append_u8, extract_address, extract_u64, extract_u8, map_count,
    };

    struct UlnConfig has drop, copy, store {
        confirmations: u64,
        optional_dvn_threshold: u8,
        required_dvns: vector<address>,
        optional_dvns: vector<address>,
        use_default_for_confirmations: bool,
        use_default_for_required_dvns: bool,
        use_default_for_optional_dvns: bool,
    }

    public fun new_uln_config(
        confirmations: u64,
        optional_dvn_threshold: u8,
        required_dvns: vector<address>,
        optional_dvns: vector<address>,
        use_default_for_confirmations: bool,
        use_default_for_required_dvns: bool,
        use_default_for_optional_dvns: bool,
    ): UlnConfig {
        UlnConfig {
            confirmations,
            optional_dvn_threshold,
            required_dvns,
            optional_dvns,
            use_default_for_confirmations,
            use_default_for_required_dvns,
            use_default_for_optional_dvns,
        }
    }

    // ================================================ Field Accessors ===============================================

    public fun unpack_uln_config(config: UlnConfig): (u64, u8, vector<address>, vector<address>, bool, bool, bool) {
        let UlnConfig {
            confirmations,
            optional_dvn_threshold,
            required_dvns,
            optional_dvns,
            use_default_for_confirmations,
            use_default_for_required_dvns,
            use_default_for_optional_dvns,
        } = config;
        (
            confirmations, optional_dvn_threshold, required_dvns, optional_dvns, use_default_for_confirmations,
            use_default_for_required_dvns, use_default_for_optional_dvns,
        )
    }

    public fun get_confirmations(self: &UlnConfig): u64 { self.confirmations }

    public fun get_required_dvn_count(self: &UlnConfig): u64 { vector::length(&self.required_dvns) }

    public fun get_optional_dvn_count(self: &UlnConfig): u64 { vector::length(&self.optional_dvns) }

    public fun get_optional_dvn_threshold(self: &UlnConfig): u8 { self.optional_dvn_threshold }

    public fun get_required_dvns(self: &UlnConfig): vector<address> { self.required_dvns }

    public fun borrow_required_dvns(self: &UlnConfig): &vector<address> { &self.required_dvns }

    public fun get_optional_dvns(self: &UlnConfig): vector<address> { self.optional_dvns }

    public fun borrow_optional_dvns(self: &UlnConfig): &vector<address> { &self.optional_dvns }

    public fun get_use_default_for_confirmations(self: &UlnConfig): bool { self.use_default_for_confirmations }

    public fun get_use_default_for_required_dvns(self: &UlnConfig): bool { self.use_default_for_required_dvns }

    public fun get_use_default_for_optional_dvns(self: &UlnConfig): bool { self.use_default_for_optional_dvns }


    // ======================================== Serialization / Deserialization =======================================

    public fun append_uln_config(target: &mut vector<u8>, config: UlnConfig) {
        append_u64(target, config.confirmations);
        append_u8(target, config.optional_dvn_threshold);
        append_u8(target, (vector::length(&config.required_dvns) as u8));
        vector::for_each(config.required_dvns, |address| append_address(target, address));
        append_u8(target, (vector::length(&config.optional_dvns) as u8));
        vector::for_each(config.optional_dvns, |address| append_address(target, address));
        append_u8(target, from_bool(config.use_default_for_confirmations));
        append_u8(target, from_bool(config.use_default_for_required_dvns));
        append_u8(target, from_bool(config.use_default_for_optional_dvns));
    }

    public fun extract_uln_config(input: &vector<u8>, position: &mut u64): UlnConfig {
        let confirmations = extract_u64(input, position);
        let optional_dvn_threshold = extract_u8(input, position);
        let required_dvns_count = extract_u8(input, position);
        let required_dvns = map_count((required_dvns_count as u64), |_i| extract_address(input, position));
        let optional_dvns_count = extract_u8(input, position);
        let optional_dvns = map_count((optional_dvns_count as u64), |_i| extract_address(input, position));
        let use_default_for_confirmations = to_bool(extract_u8(input, position));
        let use_default_for_required_dvns = to_bool(extract_u8(input, position));
        let use_default_for_optional_dvns = to_bool(extract_u8(input, position));

        UlnConfig {
            confirmations,
            optional_dvn_threshold,
            required_dvns,
            optional_dvns,
            use_default_for_confirmations,
            use_default_for_required_dvns,
            use_default_for_optional_dvns,
        }
    }

    fun to_bool(uint: u8): bool {
        if (uint == 1) { true } else if (uint == 0) { false } else { abort EINVALID_BOOLEAN }
    }

    fun from_bool(bool: bool): u8 {
        if (bool) { 1 } else { 0 }
    }

    // ================================================== Error Codes =================================================

    const EINVALID_BOOLEAN: u64 = 1;
}