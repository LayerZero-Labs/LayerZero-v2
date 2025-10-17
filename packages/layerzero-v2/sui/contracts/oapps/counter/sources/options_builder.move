/// OptionsBuilder module for building and encoding various message options.
/// This is the Sui Move equivalent of the EVM OptionsBuilder.sol library.
///
/// Usage example:
/// ```
/// // Type 3 options (modern)
/// let options = options_builder::new_builder()
///     .add_executor_lz_receive_option(200000, 1000000)
///     .add_executor_native_drop_option(500000, receiver_address)
///     .build();
///
/// // Legacy options
/// let legacy_options = options_builder::encode_legacy_options_type1(200000);
/// ```
module counter::options_builder;

use std::u128;
use utils::{buffer_reader, buffer_writer, bytes32::Bytes32};

// === Constants ===

// Option types
const TYPE_1: u16 = 1; // legacy options type 1
const TYPE_2: u16 = 2; // legacy options type 2
const TYPE_3: u16 = 3; // modern options type 3

// Worker IDs
const EXECUTOR_WORKER_ID: u8 = 1;
const DVN_WORKER_ID: u8 = 2;

// Executor option types
const EXECUTOR_OPTION_TYPE_LZRECEIVE: u8 = 1;
const EXECUTOR_OPTION_TYPE_NATIVE_DROP: u8 = 2;
const EXECUTOR_OPTION_TYPE_LZCOMPOSE: u8 = 3;
const EXECUTOR_OPTION_TYPE_ORDERED_EXECUTION: u8 = 4;
const EXECUTOR_OPTION_TYPE_LZREAD: u8 = 5;

// DVN option types
const DVN_OPTION_TYPE_PRECRIME: u8 = 1;

// === Errors ===

const EInvalidOptionsType: u64 = 1;
const EInvalidSize: u64 = 2;

// === Structs ===

/// OptionsBuilder struct for fluent API pattern
public struct OptionsBuilder has drop {
    options: vector<u8>,
}

// =========================================================================
// === BUILDER PATTERN API ===
// =========================================================================

/// Creates a new OptionsBuilder with TYPE_3 options.
/// @return OptionsBuilder A new builder instance ready for chaining.
public fun new_builder(): OptionsBuilder {
    let mut writer = buffer_writer::new();
    writer.write_u16(TYPE_3);

    OptionsBuilder {
        options: writer.to_bytes(),
    }
}

/// Creates a new OptionsBuilder from existing options.
/// @param options The existing options.
/// @return OptionsBuilder A new builder instance ready for chaining.
public fun new_from_options(options: vector<u8>): OptionsBuilder {
    // assert that the options are of type 3
    let mut reader = buffer_reader::create(options);
    let option_type = reader.read_u16();
    assert!(option_type == TYPE_3, EInvalidOptionsType);
    OptionsBuilder {
        options,
    }
}

// === Constant Access Functions ===

/// Returns the Type 1 option constant.
/// @return u16 The Type 1 option value.
public fun type_1(): u16 { TYPE_1 }

/// Returns the Type 2 option constant.
/// @return u16 The Type 2 option value.
public fun type_2(): u16 { TYPE_2 }

/// Returns the Type 3 option constant.
/// @return u16 The Type 3 option value.
public fun type_3(): u16 { TYPE_3 }

/// Finalizes the builder and returns the encoded options.
/// @param self The OptionsBuilder instance.
/// @return vector<u8> The final encoded options.
public fun build(self: &OptionsBuilder): vector<u8> {
    self.options
}

// =========================================================================
// === OPTIONSBUILDER.SOL FUNCTIONS (BUILDER PATTERN) ===
// === Functions directly defined in OptionsBuilder.sol ===
// =========================================================================

/// Adds an executor LZ receive option to the existing options.
/// @param self The OptionsBuilder instance.
/// @param gas The gasLimit used on the lzReceive() function in the OApp.
/// @param value The msg.value passed to the lzReceive() function in the OApp.
/// @return &mut OptionsBuilder Self reference for method chaining.
///
/// @dev When multiples of this option are added, they are summed by the executor
/// eg. if (gas: 200k, and value: 1 ether) AND (gas: 100k, value: 0.5 ether) are sent in an option to the
/// LayerZeroEndpoint,
/// that becomes (300k, 1.5 ether) when the message is executed on the remote lzReceive() function.
public fun add_executor_lz_receive_option(self: &mut OptionsBuilder, gas: u128, value: u128): &mut OptionsBuilder {
    let option = encode_lz_receive_option(gas, value);
    add_executor_option(self, EXECUTOR_OPTION_TYPE_LZRECEIVE, option);
    self
}

/// Adds an executor LZ read option to the existing options.
/// @param self The OptionsBuilder instance.
/// @param gas The gas limit used for the lzReceive() function in the ReadOApp.
/// @param calldata_size The size of the payload for lzReceive() function in the ReadOApp.
/// @param value The msg.value passed to the lzReceive() function in the ReadOApp.
/// @return &mut OptionsBuilder Self reference for method chaining.
public fun add_executor_lz_read_option(
    self: &mut OptionsBuilder,
    gas: u128,
    calldata_size: u32,
    value: u128,
): &mut OptionsBuilder {
    let option = encode_lz_read_option(gas, calldata_size, value);
    add_executor_option(self, EXECUTOR_OPTION_TYPE_LZREAD, option);
    self
}

/// Adds an executor native drop option to the existing options.
/// @param self The OptionsBuilder instance.
/// @param amount The amount for the native value that is airdropped to the 'receiver'.
/// @param receiver The receiver address for the native drop option.
/// @return &mut OptionsBuilder Self reference for method chaining.
///
/// @dev When multiples of this option are added, they are summed by the executor on the remote chain.
public fun add_executor_native_drop_option(
    self: &mut OptionsBuilder,
    amount: u128,
    receiver: Bytes32,
): &mut OptionsBuilder {
    let option = encode_native_drop_option(amount, receiver);
    add_executor_option(self, EXECUTOR_OPTION_TYPE_NATIVE_DROP, option);
    self
}

/// Adds an executor LZ compose option to the existing options.
/// @param self The OptionsBuilder instance.
/// @param index The index for the lzCompose() function call.
/// @param gas The gasLimit for the lzCompose() function call.
/// @param value The msg.value for the lzCompose() function call.
/// @return &mut OptionsBuilder Self reference for method chaining.
///
/// @dev When multiples of this option are added, they are summed PER index by the executor on the remote chain.
/// @dev If the OApp sends N lzCompose calls on the remote, you must provide N incremented indexes starting with 0.
/// ie. When your remote OApp composes (N = 3) messages, you must set this option for index 0,1,2
public fun add_executor_lz_compose_option(
    self: &mut OptionsBuilder,
    index: u16,
    gas: u128,
    value: u128,
): &mut OptionsBuilder {
    let option = encode_lz_compose_option(index, gas, value);
    add_executor_option(self, EXECUTOR_OPTION_TYPE_LZCOMPOSE, option);
    self
}

/// Adds an executor ordered execution option to the existing options.
/// @param self The OptionsBuilder instance.
/// @return &mut OptionsBuilder Self reference for method chaining.
public fun add_executor_ordered_execution_option(self: &mut OptionsBuilder): &mut OptionsBuilder {
    add_executor_option(self, EXECUTOR_OPTION_TYPE_ORDERED_EXECUTION, vector[]);
    self
}

/// Adds a DVN pre-crime option to the existing options.
/// @param self The OptionsBuilder instance.
/// @param dvn_idx The DVN index for the pre-crime option.
/// @return &mut OptionsBuilder Self reference for method chaining.
public fun add_dvn_pre_crime_option(self: &mut OptionsBuilder, dvn_idx: u8): &mut OptionsBuilder {
    add_dvn_option(self, dvn_idx, DVN_OPTION_TYPE_PRECRIME, vector[]);
    self
}

/// Adds an executor option to the existing options.
/// @param self The OptionsBuilder instance.
/// @param option_type The type of the executor option.
/// @param option The encoded data for the executor option.
fun add_executor_option(self: &mut OptionsBuilder, option_type: u8, option: vector<u8>) {
    let mut writer = buffer_writer::create(self.options);
    writer
        .write_u8(EXECUTOR_WORKER_ID)
        .write_u16((option.length() as u16) + 1) // +1 for option_type
        .write_u8(option_type)
        .write_bytes(option);

    self.options = writer.to_bytes();
}

/// Adds a DVN option to the existing options.
/// @param self The OptionsBuilder instance.
/// @param dvn_idx The DVN index for the DVN option.
/// @param option_type The type of the DVN option.
/// @param option The encoded data for the DVN option.
public fun add_dvn_option(
    self: &mut OptionsBuilder,
    dvn_idx: u8,
    option_type: u8,
    option: vector<u8>,
): &mut OptionsBuilder {
    let mut writer = buffer_writer::create(self.options);
    writer
        .write_u8(DVN_WORKER_ID)
        .write_u16((option.length() as u16) + 2) // +2 for option_type and dvn_idx
        .write_u8(dvn_idx)
        .write_u8(option_type)
        .write_bytes(option);

    self.options = writer.to_bytes();
    self
}

/// Encodes legacy options of type 1.
/// @param execution_gas The gasLimit value passed to lzReceive().
/// @return legacy_options The encoded legacy options.
public fun encode_legacy_options_type1(execution_gas: u256): vector<u8> {
    assert!(execution_gas < u128::max_value!() as u256, EInvalidSize);

    let mut writer = buffer_writer::new();
    writer.write_u16(TYPE_1).write_u256(execution_gas);

    writer.to_bytes()
}

/// Encodes legacy options of type 2.
/// @param execution_gas The gasLimit value passed to lzReceive().
/// @param native_for_dst The amount of native air dropped to the receiver.
/// @param receiver The native_for_dst receiver address.
/// @return legacy_options The encoded legacy options of type 2.
public fun encode_legacy_options_type2(
    execution_gas: u256,
    native_for_dst: u256,
    receiver: vector<u8>, // Use bytes instead of bytes32 in legacy type 2 for receiver.
): vector<u8> {
    assert!(execution_gas < u128::max_value!() as u256, EInvalidSize);
    assert!(native_for_dst < u128::max_value!() as u256, EInvalidSize);
    assert!(receiver.length() <= 32, EInvalidSize);

    let mut writer = buffer_writer::new();
    writer.write_u16(TYPE_2).write_u256(execution_gas).write_u256(native_for_dst).write_bytes(receiver);

    writer.to_bytes()
}

// =========================================================================
// === EXECUTOROPTIONS.SOL FUNCTIONS ===
// === Equivalent to functions from ExecutorOptions.sol ===
// =========================================================================

/// Encodes LZ receive option data.
/// Equivalent to ExecutorOptions.encodeLzReceiveOption()
/// @param gas Gas limit for lzReceive.
/// @param value Value to pass to lzReceive.
/// @return encoded option data.
public fun encode_lz_receive_option(gas: u128, value: u128): vector<u8> {
    let mut writer = buffer_writer::new();
    writer.write_u128(gas);

    if (value > 0) {
        writer.write_u128(value);
    };

    writer.to_bytes()
}

/// Encodes LZ read option data.
/// Equivalent to ExecutorOptions.encodeLzReadOption()
/// @param gas Gas limit for lzReceive.
/// @param calldata_size Size of the calldata.
/// @param value Value to pass to lzReceive.
/// @return encoded option data.
public fun encode_lz_read_option(gas: u128, calldata_size: u32, value: u128): vector<u8> {
    let mut writer = buffer_writer::new();
    writer.write_u128(gas).write_u32(calldata_size);

    if (value > 0) {
        writer.write_u128(value);
    };

    writer.to_bytes()
}

/// Encodes native drop option data.
/// Equivalent to ExecutorOptions.encodeNativeDropOption()
/// @param amount Amount to airdrop.
/// @param receiver Receiver address.
/// @return encoded option data.
public fun encode_native_drop_option(amount: u128, receiver: Bytes32): vector<u8> {
    let mut writer = buffer_writer::new();
    writer.write_u128(amount).write_bytes32(receiver);

    writer.to_bytes()
}

/// Encodes LZ compose option data.
/// Equivalent to ExecutorOptions.encodeLzComposeOption()
/// @param index Compose index.
/// @param gas Gas limit for lzCompose.
/// @param value Value to pass to lzCompose.
/// @return encoded option data.
public fun encode_lz_compose_option(index: u16, gas: u128, value: u128): vector<u8> {
    let mut writer = buffer_writer::new();
    writer.write_u16(index).write_u128(gas);

    if (value > 0) {
        writer.write_u128(value);
    };

    writer.to_bytes()
}
