// Multi-DVN Testing Helper Module
#[test_only]
module counter::multi_dvn_helper;

use utils::buffer_writer;

// === Structs ===

/// Configuration for a single DVN
#[allow(unused_field)]
public struct DVNConfig has copy, drop, store {
    index: u64, // Index of this DVN (0, 1, 2, ...)
    vid: u32, // DVN ID
    quorum: u64, // Number of signers required
    gas: u256, // Gas configuration
    multiplier_bps: u16, // Multiplier in basis points
    floor_margin_usd: u128, // Floor margin in USD
}

// === Constants ===

const EXECUTOR_WORKER_ID: u8 = 1;
const DVN_WORKER_ID: u8 = 2;
const EXECUTOR_OPTION_TYPE_LZ_RECEIVE: u8 = 1;
const OPTIONS_TYPE_3: u16 = 3;

// === Public Functions ===

/// Construct Type 3 options from executor and DVN configurations
/// @param execution_gas Gas limit for execution
/// @param dvn_count Number of DVNs (determines DVN indices in options)
/// @param include_dvn_options Whether to include DVN-specific options
/// @return Properly formatted Type 3 options
public fun construct_options(execution_gas: u128, dvn_count: u8, include_dvn_options: bool): vector<u8> {
    let mut writer = buffer_writer::new();

    // Write option type (Type 3)
    writer.write_u16(OPTIONS_TYPE_3);

    // Write executor options
    writer
        .write_u8(EXECUTOR_WORKER_ID) // worker_id
        .write_u16(17) // option_size: 1 (type) + 16 (gas)
        .write_u8(EXECUTOR_OPTION_TYPE_LZ_RECEIVE) // option_type
        .write_u128(execution_gas); // execution gas

    // Optionally write DVN options
    if (include_dvn_options) {
        let mut dvn_idx = 0;
        while (dvn_idx < dvn_count) {
            // Each DVN can have custom options
            // For now, we'll add a simple confirmation option
            writer
                .write_u8(DVN_WORKER_ID) // worker_id
                .write_u16(5) // option_size: 1 (dvn_idx) + 4 (custom data)
                .write_u8(dvn_idx) // dvn_idx
                .write_u32(1000); // custom DVN data (e.g., confirmation delay)

            dvn_idx = dvn_idx + 1;
        };
    };

    writer.to_bytes()
}

/// Construct options with specific DVN indices
/// @param execution_gas Gas limit for execution
/// @param dvn_indices Specific DVN indices to include in options
/// @return Properly formatted Type 3 options
public fun construct_options_with_dvn_indices(
    execution_gas: u128,
    dvn_indices: vector<u8>,
    dvn_custom_data: vector<u32>,
): vector<u8> {
    let mut writer = buffer_writer::new();

    // Write option type (Type 3)
    writer.write_u16(OPTIONS_TYPE_3);

    // Write executor options
    writer
        .write_u8(EXECUTOR_WORKER_ID)
        .write_u16(17)
        .write_u8(EXECUTOR_OPTION_TYPE_LZ_RECEIVE)
        .write_u128(execution_gas);

    // Write DVN options for specified indices
    let mut i = 0;
    while (i < dvn_indices.length()) {
        writer
            .write_u8(DVN_WORKER_ID)
            .write_u16(5)
            .write_u8(dvn_indices[i])
            .write_u32(if (i < dvn_custom_data.length()) {
                dvn_custom_data[i]
            } else {
                1000 // default value
            });

        i = i + 1;
    };

    writer.to_bytes()
}
