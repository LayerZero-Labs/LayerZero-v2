module executor_fee_lib::executor_option;

use utils::{buffer_reader::{Self, Reader}, bytes32::Bytes32};

// === Constants ===

// Option types
const OPTION_TYPE_LZRECEIVE: u8 = 1;
const OPTION_TYPE_NATIVE_DROP: u8 = 2;
const OPTION_TYPE_LZCOMPOSE: u8 = 3;
const OPTION_TYPE_ORDERED_EXECUTION: u8 = 4;

// === Errors ===

const ENoOptions: u64 = 1;
const EUnsupportedOptionType: u64 = 2;
const EZeroLzReceiveGasProvided: u64 = 3;
const EZeroLzComposeGasProvided: u64 = 4;
const ENativeAmountExceedsCap: u64 = 5;
const EInvalidLzReceiveOption: u64 = 6;
const EInvalidNativeDropOption: u64 = 7;
const EInvalidLzComposeOption: u64 = 8;

// === Structs ===

// Aggregated executor options
public struct ExecutorOptionsAgg has copy, drop {
    total_value: u128,
    total_gas: u128,
    ordered: bool,
    num_lz_compose: u64,
}

// Individual option structs
public struct LzReceiveOption has copy, drop {
    gas: u128,
    value: u128,
}

public struct NativeDropOption has copy, drop {
    amount: u128,
    receiver: Bytes32,
}

public struct LzComposeOption has copy, drop {
    index: u16,
    gas: u128,
    value: u128,
}

// === Main Functions ===

public fun parse_executor_options(options: vector<u8>, is_v1_eid: bool, native_cap: u128): ExecutorOptionsAgg {
    assert!(!options.is_empty(), ENoOptions);
    let mut options_reader = buffer_reader::create(options);

    let mut agg_options = ExecutorOptionsAgg {
        total_value: 0,
        total_gas: 0,
        ordered: false,
        num_lz_compose: 0,
    };

    let mut lz_receive_gas = 0u128;
    while (options_reader.remaining_length() > 0) {
        let (option_type, option_data) = next_executor_option(&mut options_reader);

        if (option_type == OPTION_TYPE_LZRECEIVE) {
            let lz_receive_option = decode_lz_receive_option(option_data);

            // endpoint v1 does not support lzReceive with value
            assert!(!(is_v1_eid && lz_receive_option.value > 0), EUnsupportedOptionType);

            agg_options.total_value = agg_options.total_value + lz_receive_option.value;
            lz_receive_gas = lz_receive_gas + lz_receive_option.gas;
        } else if (option_type == OPTION_TYPE_NATIVE_DROP) {
            let native_drop_option = decode_native_drop_option(option_data);
            agg_options.total_value = agg_options.total_value + native_drop_option.amount;
        } else if (option_type == OPTION_TYPE_LZCOMPOSE) {
            // endpoint v1 does not support lzCompose
            assert!(!is_v1_eid, EUnsupportedOptionType);

            let lz_compose_option = decode_lz_compose_option(option_data);
            assert!(lz_compose_option.gas != 0, EZeroLzComposeGasProvided);

            agg_options.total_value = agg_options.total_value + lz_compose_option.value;
            agg_options.total_gas = agg_options.total_gas + lz_compose_option.gas;
            agg_options.num_lz_compose = agg_options.num_lz_compose + 1;
        } else if (option_type == OPTION_TYPE_ORDERED_EXECUTION) {
            agg_options.ordered = true;
        } else {
            abort EUnsupportedOptionType
        };
    };

    assert!(agg_options.total_value <= native_cap, ENativeAmountExceedsCap);
    assert!(lz_receive_gas != 0, EZeroLzReceiveGasProvided);

    agg_options.total_gas = agg_options.total_gas + lz_receive_gas;
    agg_options
}

/// Extract next executor option from options byte array
public fun next_executor_option(options_reader: &mut Reader): (u8, vector<u8>) {
    // Skip worker id
    options_reader.skip(1);
    // Read option size (2 bytes)
    let size = options_reader.read_u16();

    // Read option type
    let option_type = options_reader.read_u8();
    // Extract option data (size includes option type, so read size - 1)
    let option_data = options_reader.read_fixed_len_bytes((size - 1) as u64);

    (option_type, option_data)
}

// === Option Decoding Functions ===

/// Decode LZ receive option
public fun decode_lz_receive_option(option: vector<u8>): LzReceiveOption {
    let len = option.length();
    assert!(len == 16 || len == 32, EInvalidLzReceiveOption);

    let mut reader = buffer_reader::create(option);
    let gas = reader.read_u128();
    let value = if (len == 32) reader.read_u128() else 0;

    LzReceiveOption { gas, value }
}

/// Decode native drop option
public fun decode_native_drop_option(option: vector<u8>): NativeDropOption {
    assert!(option.length() == 48, EInvalidNativeDropOption);

    let mut reader = buffer_reader::create(option);
    let amount = reader.read_u128();
    let receiver = reader.read_bytes32();

    NativeDropOption { amount, receiver }
}

/// Decode LZ compose option
public fun decode_lz_compose_option(option: vector<u8>): LzComposeOption {
    let len = option.length();
    assert!(len == 18 || len == 34, EInvalidLzComposeOption);

    let mut reader = buffer_reader::create(option);
    let index = reader.read_u16();
    let gas = reader.read_u128();
    let value = if (len == 34) reader.read_u128() else 0;

    LzComposeOption { index, gas, value }
}

// === Getter Functions ===

/// Get total value from ExecutorOptionsAgg
public fun total_value(agg: &ExecutorOptionsAgg): u128 {
    agg.total_value
}

/// Get total gas from ExecutorOptionsAgg
public fun total_gas(agg: &ExecutorOptionsAgg): u128 {
    agg.total_gas
}

/// Check if ordered execution is required
public fun is_ordered(agg: &ExecutorOptionsAgg): bool {
    agg.ordered
}

/// Get number of LZ compose operations
public fun num_lz_compose(agg: &ExecutorOptionsAgg): u64 {
    agg.num_lz_compose
}

public fun ordered(agg: &ExecutorOptionsAgg): bool {
    agg.ordered
}
