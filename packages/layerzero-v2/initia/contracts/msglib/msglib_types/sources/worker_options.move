module msglib_types::worker_options {
    use std::vector;

    use endpoint_v2_common::serde;

    public inline fun EXECUTOR_WORKER_ID(): u8 { 1 }

    public inline fun DVN_WORKER_ID(): u8 { 2 }

    const EXECUTOR_OPTION_TYPE_LZ_RECEIVE: u8 = 1;
    const EXECUTOR_OPTION_TYPE_NATIVE_DROP: u8 = 2;

    /// Convenience structure to bind the DVN index and the serialized (concatted) options for that DVN index
    struct IndexOptionsPair has copy, drop, store {
        options: vector<u8>,
        dvn_idx: u8,
    }

    /// Unpacks the DVN index and the serialized (concatted) options for that DVN index
    public fun unpack_index_option_pair(pair: IndexOptionsPair): (u8, vector<u8>) {
        let IndexOptionsPair { options, dvn_idx } = pair;
        (dvn_idx, options)
    }

    /// Searches a vector of IndexOptionsPair and returns the concatinated options that matches the given DVN index
    /// This returns an empty vector if no match is found
    public fun get_matching_options(index_option_pairs: &vector<IndexOptionsPair>, dvn_index: u8): vector<u8> {
        for (i in 0..vector::length(index_option_pairs)) {
            let pair = vector::borrow(index_option_pairs, i);
            if (pair.dvn_idx == dvn_index) {
                return pair.options
            }
        };
        vector[]
    }

    // ============================================== Process DNV Options =============================================

    /// Split Options into Executor and DVN Options
    /// @return (executor_options, dvn_options)
    public fun extract_and_split_options(
        options: &vector<u8>,
    ): (vector<u8>, vector<u8>) {
        // Options must contain at least 2 bytes (the u16 "option type") to be considered valid
        assert!(vector::length(options) >= 2, EINVALID_OPTIONS);

        let uln_options_type = serde::extract_u16(options, &mut 0);

        if (uln_options_type == 3) {
            extract_type_3_options(options)
        } else {
            extract_legacy_options(uln_options_type, options)
        }
    }

    /// Extracts the current type 3 option format
    /// Format: [worker_option][worker_option][worker_option]...
    /// Worker Option Format: [worker_id: u8][option_size: u16][option: bytes(option_size)]
    /// @return (executor_options, dvn_options)
    public fun extract_type_3_options(
        options: &vector<u8>,
    ): (vector<u8>, vector<u8>) {
        // start after the u16 option type
        let position: u64 = 2;

        let executor_options = vector[];
        let dvn_options = vector[];

        // serde extract methods will move the position cursor according to the size of the extracted value
        let len = vector::length(options);
        while (position < len) {
            let internal_cursor = position;
            let worker_id = serde::extract_u8(options, &mut internal_cursor);
            let option_size = serde::extract_u16(options, &mut internal_cursor);
            let total_option_size = (option_size as u64) + 3; // 1 byte for worker_id, 2 bytes for option_size
            let option_bytes = serde::extract_fixed_len_bytes(options, &mut position, total_option_size);
            if (worker_id == EXECUTOR_WORKER_ID()) {
                vector::append(&mut executor_options, option_bytes);
            } else if (worker_id == DVN_WORKER_ID()) {
                vector::append(&mut dvn_options, option_bytes);
            } else {
                abort EINVALID_WORKER_ID
            };
        };

        (executor_options, dvn_options)
    }

    /// This creates a stem for type 3 options after which a series of executor and/or DVN options can be appended
    public fun new_empty_type_3_options(): vector<u8> {
        x"0003" // type 3
    }

    #[test_only]
    /// Test only function to append an executor option to a buffer. This is only for testing the general behavior
    /// when the options don't matter. Please use the method provided by the executor fee lib to append fee-lib-specific
    /// executor options when not testing
    public fun append_generic_type_3_executor_option(
        buf: &mut vector<u8>,
        option: vector<u8>,
    ) {
        serde::append_u8(buf, EXECUTOR_WORKER_ID());
        serde::append_u16(buf, (vector::length(&option) as u16));
        serde::append_bytes(buf, option);
    }

    // ============================================ Process Legacy Options ============================================

    /// Extracts options in legacy formats
    /// @return (executor_options, dvn_options)
    public fun extract_legacy_options(option_type: u16, options: &vector<u8>): (vector<u8>, vector<u8>) {
        // start after the u16 option type
        let position: u64 = 2; // skip the option type
        let total_options_size = vector::length(options);
        let executor_options = vector[];

        // type 1 and 2 lzReceive options use u256 but type 3 uses u128
        // casting operation is safe: will abort if too large
        if (option_type == 1) {
            assert!(total_options_size == 34, EINVALID_LEGACY_OPTIONS_TYPE_1);
            let execution_gas = (serde::extract_u256(options, &mut position) as u128);
            append_legacy_option_lz_receive(&mut executor_options, execution_gas);
        } else if (option_type == 2) {
            assert!(total_options_size > 66 && total_options_size <= 98, EINVALID_LEGACY_OPTIONS_TYPE_2);
            let execution_gas = (serde::extract_u256(options, &mut position) as u128);

            // native_drop (amount + receiver)
            let amount = (serde::extract_u256(options, &mut position) as u128);
            // receiver addresses are not necessarily bytes32
            let receiver = serde::extract_bytes_until_end(options, &mut position);
            receiver = serde::pad_zero_left(receiver, 32);

            append_legacy_option_lz_receive(&mut executor_options, execution_gas);
            append_legacy_option_native_drop(&mut executor_options, amount, receiver);
        } else {
            abort EINVALID_OPTION_TYPE
        };
        (executor_options, vector[])
    }

    fun append_legacy_option_lz_receive(buf: &mut vector<u8>, execution_gas: u128) {
        serde::append_u8(buf, EXECUTOR_WORKER_ID());
        serde::append_u16(buf, 17); // 16 + 1, 16 for option_length, + 1 for option_type
        serde::append_u8(buf, EXECUTOR_OPTION_TYPE_LZ_RECEIVE);
        serde::append_u128(buf, execution_gas);
    }

    fun append_legacy_option_native_drop(buf: &mut vector<u8>, amount: u128, receiver: vector<u8>) {
        serde::append_u8(buf, EXECUTOR_WORKER_ID());
        serde::append_u16(buf, 49); // 48 + 1, 32 + 16 for option_length, + 1 for option_type
        serde::append_u8(buf, EXECUTOR_OPTION_TYPE_NATIVE_DROP);
        serde::append_u128(buf, amount);
        serde::append_bytes(buf, receiver);
    }

    // ====================================== Prepare DVN Options for Fee Library =====================================

    /// Group DVN Options into IndexOptionsPairs, such that each element has a DVN index and a concatted vector of
    /// serialized options
    /// serialized options
    /// Format: { dvn_idx: u8, options: [dvn_option][dvn_option][dvn_option]...
    /// DVN Option format: [worker_id][option_size][dvn_idx][option_type][option]
    public fun group_dvn_options_by_index(dvn_options_bytes: &vector<u8>): vector<IndexOptionsPair> {
        let index_option_pairs = vector<IndexOptionsPair>[];
        let position: u64 = 0;
        let len = vector::length(dvn_options_bytes);
        while (position < len) {
            let internal_cursor = position;
            internal_cursor = internal_cursor + 1; // skip worker_id
            let option_size = serde::extract_u16(dvn_options_bytes, &mut internal_cursor);
            let dvn_idx = serde::extract_u8(dvn_options_bytes, &mut internal_cursor);
            let total_option_size = (option_size as u64) + 3; // 1 byte for worker_id, 2 bytes for option_size

            let option = serde::extract_fixed_len_bytes(dvn_options_bytes, &mut position, total_option_size);

            assert!(option_size >= 2, EINVALID_OPTION_LENGTH);
            assert!(dvn_idx != 255, EINVALID_DVN_IDX);
            insert_dvn_option(&mut index_option_pairs, dvn_idx, option);
        };

        index_option_pairs
    }

    /// Inserts a new DVN option into the vector of IndexOptionsPair, appending to the existing options of the DVN index
    /// or creating a new entry if the DVN index does not exist
    fun insert_dvn_option(
        index_option_pairs: &mut vector<IndexOptionsPair>,
        dvn_idx: u8,
        new_options: vector<u8>,
    ) {
        // If the dvn_idx already exists, append the new options to the existing options
        let count = vector::length(index_option_pairs);
        for (ii in 0..count) {
            // Reverse the scan, to save gas when options are appended in ordered groups
            let i = count - ii - 1;
            let pair = vector::borrow(index_option_pairs, i);
            if (pair.dvn_idx == dvn_idx) {
                let existing_option = vector::borrow_mut(index_option_pairs, i);
                vector::append(&mut existing_option.options, new_options);
                return
            }
        };
        // Otherwise, create a new entry
        vector::push_back(index_option_pairs, IndexOptionsPair { options: new_options, dvn_idx });
    }

    // This appends a dvn_option to the buffer
    public fun append_dvn_option(buf: &mut vector<u8>, dvn_idx: u8, option_type: u8, option: vector<u8>) {
        serde::append_u8(buf, DVN_WORKER_ID());
        let length = vector::length(&option) + 2; // 2 for option_type and dvn_idx
        serde::append_u16(buf, (length as u16));
        serde::append_u8(buf, dvn_idx);
        serde::append_u8(buf, option_type);
        serde::append_bytes(buf, option);
    }

    // ================================================== Error Codes =================================================

    const EINVALID_DVN_IDX: u64 = 1;
    const EINVALID_LEGACY_OPTIONS_TYPE_1: u64 = 2;
    const EINVALID_LEGACY_OPTIONS_TYPE_2: u64 = 3;
    const EINVALID_OPTIONS: u64 = 4;
    const EINVALID_OPTION_LENGTH: u64 = 5;
    const EINVALID_OPTION_TYPE: u64 = 6;
    const EINVALID_WORKER_ID: u64 = 7;
}