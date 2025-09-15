/// Worker Options Module
///
/// This module provides utilities for parsing and processing LayerZero worker options.
/// Worker options contain requirements for executors and DVNs that handle cross-chain
/// message processing.
///
/// Option Formats:
/// The module supports three option formats:
/// - **Legacy Type 1**: Simple execution gas specification (32 bytes)
/// - **Legacy Type 2**: Execution gas + native drop (64-96 bytes)
/// - **Type 3**: Modern flexible format with multiple worker options
///
/// Type 3 Format Structure:
/// ```
/// [option_type: u16][worker_option][worker_option]...
/// ```
///
/// Worker Option:
/// ```
/// [worker_id: u8][option_size: u16][option_data: bytes]
/// ```
module message_lib_common::worker_options;

use utils::{buffer_reader::{Self, Reader}, buffer_writer::{Self, Writer}, bytes32::{Self, Bytes32}};

// === Constants ===

/// Legacy option format version 1: Contains only execution gas (32 bytes u256).
const LEGACY_OPTIONS_TYPE_1: u16 = 1;
/// Legacy option format version 2: Contains execution gas + native drop amount + receiver (total 64-96 bytes).
const LEGACY_OPTIONS_TYPE_2: u16 = 2;
/// Modern option format version 3: Flexible format supporting multiple workers and option types.
const OPTIONS_TYPE_3: u16 = 3;

/// Worker identifier for Executor and DVN.
const EXECUTOR_WORKER_ID: u8 = 1;
const DVN_WORKER_ID: u8 = 2;

/// Executor option type for LzReceive operation.
const EXECUTOR_OPTION_TYPE_LZ_RECEIVE: u8 = 1;
/// Executor option type for native token drop operation.
const EXECUTOR_OPTION_TYPE_NATIVE_DROP: u8 = 2;

// === Errors ===

const EInvalidLegacyOptionsType1: u64 = 1;
const EInvalidLegacyOptionsType2: u64 = 2;
const EInvalidOptions: u64 = 3;
const EInvalidOptionType: u64 = 4;
const EInvalidWorkerId: u64 = 5;

// === Structs ===

/// Container for DVN-specific options with associated index.
///
/// This structure binds a DVN index to its serialized options, allowing
/// efficient lookup and processing of DVN-specific configuration.
public struct DVNOptions has copy, drop, store {
    /// Serialized options data for this DVN
    options: vector<u8>,
    /// Index identifier for the DVN
    dvn_idx: u8,
}

/// Unpacks a DVNOptions struct into its constituent parts.
public fun unpack(pair: DVNOptions): (u8, vector<u8>) {
    (pair.dvn_idx, pair.options)
}

// === Public Functions ===

/// Retrieves the concatenated options for a specific DVN index.
///
/// Searches through a vector of DVNOptions and returns the serialized options
/// that match the given DVN index. Returns an empty vector if no match is found.
public fun get_matching_options(dvn_options: &vector<DVNOptions>, dvn_index: u8): vector<u8> {
    let index = dvn_options.find_index!(|pair| pair.dvn_idx == dvn_index);
    if (index.is_some()) {
        dvn_options[index.destroy_some()].options
    } else {
        vector[]
    }
}

/// Splits worker options into separate executor and DVN option collections.
///
/// This is the main entry point for processing worker options. It automatically
/// detects the option format version and delegates to the appropriate parser.
///
/// Format detection:
/// - Type 3: Modern flexible format with multiple worker types
/// - Type 1 & 2: Legacy formats (executor options only, no DVN options)
public fun split_worker_options(options: &vector<u8>): (vector<u8>, vector<DVNOptions>) {
    // Options must contain at least 2 bytes (the u16 "option type") to be considered valid
    assert!(options.length() >= 2, EInvalidOptions);
    let mut reader = buffer_reader::create(*options);
    let options_type = reader.read_u16();
    if (options_type == OPTIONS_TYPE_3) {
        extract_type_3_options(&mut reader)
    } else {
        (convert_legacy_options(&mut reader, options_type), vector[])
    }
}

/// Extracts options from the modern Type 3 format.
///
/// Type 3 format supports multiple workers (executors and DVNs) with flexible
/// option structures. Each worker option includes its own size header.
///
/// Format Structure:
/// ```
/// [worker_option][worker_option][worker_option]...
///
/// Worker Option:
/// [worker_id: u8][option_size: u16][option_data: bytes(option_size)]
/// ```
public fun extract_type_3_options(options_reader: &mut Reader): (vector<u8>, vector<DVNOptions>) {
    let mut executor_options = buffer_writer::new();
    let mut dvn_options = vector<DVNOptions>[];

    while (options_reader.remaining_length() > 0) {
        let worker_id = options_reader.read_u8();
        let option_size = options_reader.read_u16() as u64;

        // Rewind to the start of the current option and read the complete option bytes
        // 3 bytes for worker_id (1) + option_size (2)
        let current_options = options_reader.rewind(3).read_fixed_len_bytes(3 + option_size);

        if (worker_id == EXECUTOR_WORKER_ID) {
            executor_options.write_bytes(current_options);
        } else if (worker_id == DVN_WORKER_ID) {
            append_dvn_option(&mut dvn_options, current_options);
        } else {
            abort EInvalidWorkerId
        };
    };

    (executor_options.to_bytes(), dvn_options)
}

// === Legacy Format Processing ===

/// Converts legacy option formats (Type 1 and Type 2) to executor options in Type 3 format.
/// Legacy formats only supported executor options and did not include DVN options.
///
/// Legacy Format Details:
/// - **Type 1**: [execution_gas: u256] (32 bytes total)
/// - **Type 2**: [execution_gas: u256][amount: u256][receiver: bytes(0-32)] (64-96 bytes total)
///
/// Note: Legacy formats use u256 for gas/amounts, but Type 3 uses u128.
/// The conversion will abort if values exceed u128 range.
public fun convert_legacy_options(options_reader: &mut Reader, option_type: u16): vector<u8> {
    let mut executor_options = buffer_writer::new();
    let options_size = options_reader.remaining_length();

    if (option_type == LEGACY_OPTIONS_TYPE_1) {
        // Type 1: Only execution gas
        assert!(options_size == 32, EInvalidLegacyOptionsType1);
        let execution_gas = options_reader.read_u256() as u128;
        append_lz_receive_option(&mut executor_options, execution_gas);
    } else if (option_type == LEGACY_OPTIONS_TYPE_2) {
        // Type 2: Execution gas + native drop configuration
        assert!(options_size > 64 && options_size <= 96, EInvalidLegacyOptionsType2);
        let execution_gas = options_reader.read_u256() as u128;
        let amount = options_reader.read_u256() as u128;
        // Receiver address can be any length up to 32 bytes
        let receiver = bytes32::from_bytes_left_padded(options_reader.read_bytes_until_end());
        append_lz_receive_option(&mut executor_options, execution_gas);
        append_native_drop_option(&mut executor_options, amount, receiver);
    } else {
        abort EInvalidOptionType
    };

    // Ensure all bytes were consumed
    assert!(options_reader.remaining_length() == 0, EInvalidOptions);
    executor_options.to_bytes()
}

// === Internal Helper Functions ===

/// Appends a LzReceive option to the executor options buffer.
/// Format: [worker_id][option_size][option_type][execution_gas]
fun append_lz_receive_option(buf: &mut Writer, execution_gas: u128) {
    buf
        .write_u8(EXECUTOR_WORKER_ID) // worker_id (1 byte)
        .write_u16(17) // option_size: option_type(1) + data(16) = 17 bytes
        .write_u8(EXECUTOR_OPTION_TYPE_LZ_RECEIVE) // option_type (1 byte)
        .write_u128(execution_gas); // execution gas data (16 bytes)
}

/// Appends a native drop option to the executor options buffer.
/// Format: [worker_id][option_size][option_type][amount][receiver]
fun append_native_drop_option(buf: &mut Writer, amount: u128, receiver: Bytes32) {
    buf
        .write_u8(EXECUTOR_WORKER_ID) // worker_id (1 byte)
        .write_u16(49) // option_size: option_type(1) + amount(16) + receiver(32) = 49 bytes
        .write_u8(EXECUTOR_OPTION_TYPE_NATIVE_DROP) // option_type (1 byte)
        .write_u128(amount) // drop amount (16 bytes)
        .write_bytes32(receiver); // receiver address (32 bytes)
}

/// Efficiently groups DVN options by index.
///
/// Searches for existing DVN options with the same index and concatenates them,
/// or creates a new entry if this is the first option for this DVN index.
fun append_dvn_option(dvn_options: &mut vector<DVNOptions>, option_bytes: vector<u8>) {
    let dvn_idx = option_bytes[3]; // Extract DVN index from option bytes
    let index = dvn_options.find_index!(|pair| pair.dvn_idx == dvn_idx);

    if (index.is_some()) {
        // Append to existing DVN options
        dvn_options[index.destroy_some()].options.append(option_bytes);
    } else {
        // Create new DVN options entry
        dvn_options.push_back(DVNOptions { options: option_bytes, dvn_idx });
    };
}
