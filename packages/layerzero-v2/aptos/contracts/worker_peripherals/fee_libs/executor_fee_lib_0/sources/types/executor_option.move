module executor_fee_lib_0::executor_option {
    use std::vector;

    use endpoint_v2_common::bytes32::Bytes32;
    use endpoint_v2_common::serde;
    use msglib_types::worker_options::EXECUTOR_WORKER_ID;

    const OPTION_TYPE_LZ_RECEIVE: u8 = 1;
    const OPTION_TYPE_NATIVE_DROP: u8 = 2;
    const OPTION_TYPE_LZ_COMPOSE: u8 = 3;
    const OPTION_TYPE_ORDERED_EXECUTION: u8 = 4;


    /// ExecutorOptions is used to specify the options for an executor
    struct ExecutorOptions has drop, copy, store {
        // The gas and value delivered via the LZ Receive operation
        lz_receive_options: vector<LzReceiveOption>,
        // The amount and receiver for the Native Drop operation
        native_drop_options: vector<NativeDropOption>,
        // The gas and value for each LZ Compose operation
        lz_compose_options: vector<LzComposeOption>,
        // Whether or not the execution will require ordered execution
        ordered_execution_option: bool,
    }

    /// The gas and value for the LZ Receive operation
    struct LzReceiveOption has drop, copy, store {
        gas: u128,
        value: u128,
    }

    /// The amount and receiver for the Native Drop operation
    struct NativeDropOption has drop, copy, store {
        amount: u128,
        receiver: Bytes32,
    }

    /// The gas, value, and index of a specific LZ Compose operation
    struct LzComposeOption has drop, copy, store {
        index: u16,
        gas: u128,
        value: u128,
    }

    /// Unpacks ExecutorOptions into its components
    public fun unpack_options(
        options: ExecutorOptions,
    ): (vector<LzReceiveOption>, vector<NativeDropOption>, vector<LzComposeOption>, bool) {
        let ExecutorOptions {
            lz_receive_options,
            native_drop_options,
            lz_compose_options,
            ordered_execution_option,
        } = options;
        (lz_receive_options, native_drop_options, lz_compose_options, ordered_execution_option)
    }

    /// Unpacks LzReceiveOption into its components
    /// @return (gas, value)
    public fun unpack_lz_receive_option(option: LzReceiveOption): (u128, u128) {
        let LzReceiveOption { gas, value } = option;
        (gas, value)
    }

    /// Unpacks NativeDropOption into its components
    /// @return (amount, receiver)
    public fun unpack_native_drop_option(option: NativeDropOption): (u128, Bytes32) {
        let NativeDropOption { amount, receiver } = option;
        (amount, receiver)
    }

    /// Unpacks LzComposeOption into its components
    /// @return (compose index, gas, value)
    public fun unpack_lz_compose_option(option: LzComposeOption): (u16, u128, u128) {
        let LzComposeOption { index, gas, value } = option;
        (index, gas, value)
    }

    /// Creates a new ExecutorOptions from its components
    public fun new_executor_options(
        lz_receive_options: vector<LzReceiveOption>,
        native_drop_options: vector<NativeDropOption>,
        lz_compose_options: vector<LzComposeOption>,
        ordered_execution_option: bool,
    ): ExecutorOptions {
        ExecutorOptions { lz_receive_options, native_drop_options, lz_compose_options, ordered_execution_option }
    }

    /// Creates a new LzReceiveOption from its components
    public fun new_lz_receive_option(gas: u128, value: u128): LzReceiveOption {
        LzReceiveOption { gas, value }
    }

    /// Creates a new NativeDropOption from its components
    public fun new_native_drop_option(amount: u128, receiver: Bytes32): NativeDropOption {
        NativeDropOption { amount, receiver }
    }

    /// Creates a new LzComposeOption from its components
    public fun new_lz_compose_option(index: u16, gas: u128, value: u128): LzComposeOption {
        LzComposeOption { index, gas, value }
    }

    /// Extracts an ExecutorOptions from a byte buffer
    public fun extract_executor_options(buf: &vector<u8>, pos: &mut u64): ExecutorOptions {
        let options = ExecutorOptions {
            lz_receive_options: vector[],
            native_drop_options: vector[],
            lz_compose_options: vector[],
            ordered_execution_option: false,
        };
        let len = vector::length(buf);
        while (*pos < len) {
            let _worker_id = serde::extract_u8(buf, pos);
            // The serialized option_size includes 1 byte for the option_type. Subtracting 1 byte is the number of bytes
            // that should be read after reading the option type
            let option_size = serde::extract_u16(buf, pos) - 1;
            let option_type = serde::extract_u8(buf, pos);

            if (option_type == OPTION_TYPE_LZ_RECEIVE) {
                // LZ Receive
                let option = extract_lz_receive_option(buf, option_size, pos);
                vector::push_back(&mut options.lz_receive_options, option)
            } else if (option_type == OPTION_TYPE_NATIVE_DROP) {
                // Native Drop
                let option = extract_native_drop_option(buf, option_size, pos);
                vector::push_back(&mut options.native_drop_options, option)
            } else if (option_type == OPTION_TYPE_LZ_COMPOSE) {
                // LZ Compose
                let option = extract_lz_compose_option(buf, option_size, pos);
                vector::push_back(&mut options.lz_compose_options, option)
            } else if (option_type == OPTION_TYPE_ORDERED_EXECUTION) {
                // Ordered Execution
                assert!(option_size == 0, EINVALID_ORDERED_EXECUTION_OPTION_LENGTH);
                options.ordered_execution_option = true;
                // Nothing else to read - continue to next
            } else {
                abort EUNSUPPORTED_OPTION
            }
        };
        options
    }

    /// Appends an ExecutorOptions to a byte buffer
    public fun append_executor_options(buf: &mut vector<u8>, options: &ExecutorOptions) {
        vector::for_each_ref(&options.lz_receive_options, |option| {
            serde::append_u8(buf, EXECUTOR_WORKER_ID());
            append_lz_receive_option(buf, option)
        });
        vector::for_each_ref(&options.native_drop_options, |option| {
            serde::append_u8(buf, EXECUTOR_WORKER_ID());
            append_native_drop_option(buf, option)
        });
        vector::for_each_ref(&options.lz_compose_options, |option| {
            serde::append_u8(buf, EXECUTOR_WORKER_ID());
            append_lz_compose_option(buf, option)
        });
        if (options.ordered_execution_option) {
            serde::append_u8(buf, EXECUTOR_WORKER_ID());
            append_ordered_execution_option(buf);
        }
    }

    /// Extracts a LzReceiveOption from a buffer and updates position to the end of the read
    fun extract_lz_receive_option(option: &vector<u8>, size: u16, pos: &mut u64): LzReceiveOption {
        let gas = serde::extract_u128(option, pos);
        let value = if (size == 32) {
            serde::extract_u128(option, pos)
        } else if (size == 16) {
            0
        } else {
            abort EINVALID_LZ_RECEIVE_OPTION_LENGTH
        };
        LzReceiveOption { gas, value }
    }

    /// Serializes a LzReceiveOption to the end of a buffer
    fun append_lz_receive_option(output: &mut vector<u8>, lz_receive_option: &LzReceiveOption) {
        let size = if (lz_receive_option.value == 0) { 17 } else { 33 };
        serde::append_u16(output, size);
        serde::append_u8(output, OPTION_TYPE_LZ_RECEIVE);
        serde::append_u128(output, lz_receive_option.gas);
        if (lz_receive_option.value != 0) {
            serde::append_u128(output, lz_receive_option.value);
        }
    }

    /// Extracts a NativeDropOption from a buffer and updates position to the end of the read
    fun extract_native_drop_option(option: &vector<u8>, size: u16, pos: &mut u64): NativeDropOption {
        assert!(size == 48, EINVALID_NATIVE_DROP_OPTION_LENGTH);
        let amount = serde::extract_u128(option, pos);
        let receiver = serde::extract_bytes32(option, pos);
        NativeDropOption { amount, receiver }
    }

    /// Serializes a NativeDropOption to the end of a buffer
    fun append_native_drop_option(output: &mut vector<u8>, native_drop_option: &NativeDropOption) {
        serde::append_u16(output, 49);
        serde::append_u8(output, OPTION_TYPE_NATIVE_DROP);
        serde::append_u128(output, native_drop_option.amount);
        serde::append_bytes32(output, native_drop_option.receiver);
    }

    /// Extracts a LzComposeOption from a buffer
    fun extract_lz_compose_option(option: &vector<u8>, size: u16, pos: &mut u64): LzComposeOption {
        let index = serde::extract_u16(option, pos);
        let gas = serde::extract_u128(option, pos);
        let value = if (size == 34) {
            serde::extract_u128(option, pos)
        } else if (size == 18) {
            0
        } else {
            abort EINVALID_LZ_COMPOSE_OPTION_LENGTH
        };
        LzComposeOption { index, gas, value }
    }

    /// Serializes a LzComposeOption to the end of a buffer
    fun append_lz_compose_option(output: &mut vector<u8>, lz_compose_option: &LzComposeOption) {
        let size = if (lz_compose_option.value == 0) { 19 } else { 35 };
        serde::append_u16(output, size);
        serde::append_u8(output, OPTION_TYPE_LZ_COMPOSE);
        serde::append_u16(output, lz_compose_option.index);
        serde::append_u128(output, lz_compose_option.gas);
        if (lz_compose_option.value != 0) {
            serde::append_u128(output, lz_compose_option.value);
        }
    }

    /// Serializes an ordered execution option into a buffer
    fun append_ordered_execution_option(output: &mut vector<u8>) {
        serde::append_u16(output, 1);  // size = 1
        serde::append_u8(output, OPTION_TYPE_ORDERED_EXECUTION);
    }

    // ================================================== Error Codes =================================================

    const EINVALID_LZ_COMPOSE_OPTION_LENGTH: u64 = 1;
    const EINVALID_LZ_RECEIVE_OPTION_LENGTH: u64 = 2;
    const EINVALID_NATIVE_DROP_OPTION_LENGTH: u64 = 3;
    const EINVALID_ORDERED_EXECUTION_OPTION_LENGTH: u64 = 4;
    const EUNSUPPORTED_OPTION: u64 = 5;
}
