#[test_only]
module executor_fee_lib_0::executor_option_tests {
    use endpoint_v2_common::bytes32;
    use endpoint_v2_common::serde::{Self, flatten};
    use executor_fee_lib_0::executor_option::{
        append_executor_options, extract_executor_options, new_executor_options, new_lz_compose_option,
        new_lz_receive_option, new_native_drop_option, unpack_options,
    };

    #[test]
    fun serializes_and_deserializes_to_the_same_input() {
        let options = new_executor_options(
            vector[
                new_lz_receive_option(333, 200), // serializes to a 32 length option
                new_lz_receive_option(222, 0), // serializes to a 16 length option
            ],
            vector[
                new_native_drop_option(111, bytes32::from_address(@0x123456)),
                new_native_drop_option(222, bytes32::from_address(@0x654321)),
            ],
            vector[
                new_lz_compose_option(1, 444, 1234), // serializes to a 34 length option
                new_lz_compose_option(1, 555, 0), // serializes to a 18 length option
            ],
            true,
        );

        let serialized = serde::bytes_of(|buf| append_executor_options(buf, &options));

        let deserialized = extract_executor_options(&serialized, &mut 0);
        let (
            lz_receive_options,
            native_drop_options,
            lz_compose_options,
            ordered_execution_option,
        ) = unpack_options(deserialized);

        assert!(lz_receive_options == vector[
            new_lz_receive_option(333, 200),
            new_lz_receive_option(222, 0),
        ], 1);

        assert!(native_drop_options == vector[
            new_native_drop_option(111, bytes32::from_address(@0x123456)),
            new_native_drop_option(222, bytes32::from_address(@0x654321)),
        ], 2);

        assert!(lz_compose_options == vector[
            new_lz_compose_option(1, 444, 1234),
            new_lz_compose_option(1, 555, 0),
        ], 3);

        assert!(ordered_execution_option == true, 4);


        // test having ordered_execution_option as false
        let options = new_executor_options(
            vector[],
            vector[],
            vector[],
            false,
        );

        let serialized = serde::bytes_of(|buf| append_executor_options(buf, &options));
        let deserialized = extract_executor_options(&serialized, &mut 0);
        let (
            _lz_receive_options,
            _native_drop_options,
            _lz_compose_options,
            ordered_execution_option,
        ) = unpack_options(deserialized);

        assert!(ordered_execution_option == false, 5);
    }

    #[test]
    #[expected_failure(abort_code = executor_fee_lib_0::executor_option::EUNSUPPORTED_OPTION)]
    fun test_deserialize_executor_options_will_fail_if_provided_unsupported_option() {
        let options = new_executor_options(
            vector[
                new_lz_receive_option(333, 200),
                new_lz_receive_option(222, 0),
            ],
            vector[
                new_native_drop_option(111, bytes32::from_address(@0x123456)),
                new_native_drop_option(222, bytes32::from_address(@0x654321)),
            ],
            vector[
                new_lz_compose_option(1, 444, 1234),
                new_lz_compose_option(1, 555, 0),
            ],
            true,
        );
        let serialized = serde::bytes_of(|buf| append_executor_options(buf, &options));
        serialized = flatten(vector[
            serialized,
            x"01", // worker_id = 1
            x"0001", // option_size = 1
            x"05", // option_type = 5 (invalid option type)
        ]);

        extract_executor_options(&serialized, &mut 0);
    }

    #[test]
    #[expected_failure(abort_code = executor_fee_lib_0::executor_option::EINVALID_ORDERED_EXECUTION_OPTION_LENGTH)]
    fun test_deserialize_executor_options_will_fail_if_provided_invalid_ordered_execution_option() {
        let serialized = flatten(vector[
            x"04", // worker_id = 1
            x"0002", // option_size = 2  (should be 1)
            x"04", // option_type = 4 (ordered execution option)
            x"12", // option body
        ]);

        extract_executor_options(&serialized, &mut 0);
    }

    #[test]
    #[expected_failure(abort_code = executor_fee_lib_0::executor_option::EINVALID_LZ_RECEIVE_OPTION_LENGTH)]
    fun test_deserialize_executor_options_will_fail_if_provided_invalid_lz_receive_option() {
        let serialized = flatten(vector[
            x"01", // worker_id = 1
            x"0015", // option_size = 21  (should be 17 or 33)
            x"01", // option_type = 1 (lz receive option)
            x"0101010101010101010101010101010101010101", // lz receive option
        ]);

        extract_executor_options(&serialized, &mut 0);
    }

    #[test]
    #[expected_failure(abort_code = executor_fee_lib_0::executor_option::EINVALID_NATIVE_DROP_OPTION_LENGTH)]
    fun test_deserialize_executor_options_will_fail_if_provided_invalid_native_drop_option() {
        let serialized = flatten(vector[
            x"01", // worker_id = 1
            x"0011", // option_size = 17  (should be 49)
            x"02", // option_type = 2 (native drop option)
            x"01010101010101010101010101010101", // native drop option
        ]);

        extract_executor_options(&serialized, &mut 0);
    }

    #[test]
    #[expected_failure(abort_code = executor_fee_lib_0::executor_option::EINVALID_LZ_COMPOSE_OPTION_LENGTH)]
    fun test_deserialize_executor_options_will_fail_if_provided_invalid_lz_compose_option() {
        let serialized = flatten(vector[
            x"01", // worker_id = 1
            x"0015", // option_size = 21  (should be 19 or 35)
            x"03", // option_type = 3 (lz compose option)
            x"0101010101010101010101010101010101010101", // lz compose option
        ]);

        extract_executor_options(&serialized, &mut 0);
    }
}
