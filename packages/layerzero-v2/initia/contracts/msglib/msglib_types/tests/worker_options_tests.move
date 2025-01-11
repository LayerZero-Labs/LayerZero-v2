#[test_only]
module msglib_types::worker_options_tests {
    use std::vector;

    use endpoint_v2_common::serde;
    use msglib_types::worker_options;
    use msglib_types::worker_options::unpack_index_option_pair;

    #[test]
    fun test_extract_and_split_options_dvn_only() {
        let option_type = x"0003";
        let dvn_options_raw = x"020002000102000302ff0102000200010200020101";
        let options = serde::flatten(vector[
            option_type,
            dvn_options_raw,
        ]);
        let (executor_options, dvn_options) = worker_options::extract_and_split_options(
            &options,
        );

        assert!(executor_options == x"", 0);
        assert!(dvn_options == dvn_options_raw, 1);
    }

    #[test]
    fun test_extract_and_split_options_executor_only() {
        let option_type = x"0003";
        let executor_options_raw = x"0100110100000000000000000000000000009470010011010000000000000000000000000000ea60";
        let options = serde::flatten(vector[
            option_type,
            executor_options_raw,
        ]);
        let (executor_options, dvn_options) = worker_options::extract_and_split_options(
            &options,
        );

        assert!(executor_options == executor_options_raw, 0);
        assert!(dvn_options == x"", 1);
    }

    #[test]
    fun test_extract_and_split_options() {
        let option_type = x"0003";
        let executor_options_raw = x"0100110100000000000000000000000000009470010011010000000000000000000000000000ea60";
        let dvn_options_raw = x"020002000102000302ff0102000200010200020101";
        let options = serde::flatten(vector[
            option_type,
            executor_options_raw,
            dvn_options_raw,
        ]);

        let (executor_options, dvn_options) = worker_options::extract_and_split_options(
            &options,
        );

        assert!(executor_options == executor_options_raw, 0);
        assert!(dvn_options == dvn_options_raw, 1);
    }

    #[test]
    fun test_decode_legacy_options_type_1() {
        let option_type = 1;
        let legacy_options = x"00010000000000000000000000000000000000000000000000000000000000030d40";
        let expected_options = x"0100110100000000000000000000000000030d40";

        let (executor_options, _) = worker_options::extract_legacy_options(option_type, &legacy_options);
        // assert that the new executor option follows: [worker_id][option_size][option_type][option]
        assert!(executor_options == expected_options, 0);
        let pos = &mut 0;
        assert!(serde::extract_u8(&executor_options, pos) == 1, 1); // worker_id
        assert!(serde::extract_u16(&executor_options, pos) == 17, 2); // option_size
        assert!(serde::extract_u8(&executor_options, pos) == 1, 3); // option_type
        assert!(serde::extract_u128(&executor_options, pos) == 200000, 4); // option value (execution gas)
    }

    #[test]
    fun test_decode_legacy_options_type_2() {
        let option_type = 2;
        let legacy_options = x"00020000000000000000000000000000000000000000000000000000000000030d400000000000000000000000000000000000000000000000000000000000989680f39fd6e51aad88f6f4ce6ab8827279cfffb92266";
        let expected_options = x"0100110100000000000000000000000000030d400100310200000000000000000000000000989680000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266";
        let (executor_options, _) = worker_options::extract_legacy_options(option_type, &legacy_options);

        // adapter params type 2 includes both 1 and 2
        assert!(executor_options == expected_options, 0);
        let pos = &mut 0;
        // adapter params type 1
        assert!(serde::extract_u8(&executor_options, pos) == 1, 1); // worker_id
        assert!(serde::extract_u16(&executor_options, pos) == 17, 2); // option_size
        assert!(serde::extract_u8(&executor_options, pos) == 1, 3); // option_type
        assert!(serde::extract_u128(&executor_options, pos) == 200000, 4); // option value (execution gas)
        // adapter params type 2
        assert!(serde::extract_u8(&executor_options, pos) == 1, 5); // worker_id
        assert!(serde::extract_u16(&executor_options, pos) == 49, 6); // option_size
        assert!(serde::extract_u8(&executor_options, pos) == 2, 7); // option_type
        assert!(serde::extract_u128(&executor_options, pos) == 10000000, 8); // option value (amount)
        let expected_receiver = endpoint_v2_common::bytes32::to_bytes32(
            x"000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266"
        );
        assert!(serde::extract_bytes32(&executor_options, pos) == expected_receiver, 9); // option value (receiver)
    }

    #[test]
    fun test_extract_and_split_options_using_legacy_option() {
        let legacy_options = x"00020000000000000000000000000000000000000000000000000000000000030d400000000000000000000000000000000000000000000000000000000000989680f39fd6e51aad88f6f4ce6ab8827279cfffb92266";
        let expected_options = x"0100110100000000000000000000000000030d400100310200000000000000000000000000989680000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266";
        let (executor_options, _) = worker_options::extract_and_split_options(&legacy_options);

        // adapter params type 2 includes both 1 and 2
        assert!(executor_options == expected_options, 0);
        let pos = &mut 0;
        // adapter params type 1
        assert!(serde::extract_u8(&executor_options, pos) == 1, 1); // worker_id
        assert!(serde::extract_u16(&executor_options, pos) == 17, 2); // option_size
        assert!(serde::extract_u8(&executor_options, pos) == 1, 3); // option_type
        assert!(serde::extract_u128(&executor_options, pos) == 200000, 4); // option value (execution gas)
        // adapter params type 2
        assert!(serde::extract_u8(&executor_options, pos) == 1, 5); // worker_id
        assert!(serde::extract_u16(&executor_options, pos) == 49, 6); // option_size
        assert!(serde::extract_u8(&executor_options, pos) == 2, 7); // option_type
        assert!(serde::extract_u128(&executor_options, pos) == 10000000, 8); // option value (amount)
        let expected_receiver = endpoint_v2_common::bytes32::to_bytes32(
            x"000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266"
        );
        assert!(serde::extract_bytes32(&executor_options, pos) == expected_receiver, 9); // option value (receiver)
    }

    #[test]
    fun test_group_dvn_options_by_index() {
        let dvn_option_bytes = x"020002000102000302ff0102000200010200020101";
        let expected_dvn_0_options = x"02000200010200020001";
        let expected_dvn_1_options = x"0200020101";
        let expected_dvn_2_options = x"02000302ff01";

        let pairs = worker_options::group_dvn_options_by_index(&dvn_option_bytes);


        let found_0 = false;
        let found_1 = false;
        let found_2 = false;

        // get_all_dvn_fee logic check
        for (i in 0..vector::length(&pairs)) {
            let (index, option) = unpack_index_option_pair(*vector::borrow(&pairs, i));
            if (index == 0) {
                found_0 = true;
                assert!(option == expected_dvn_0_options, 0);
            };
            if (index == 1) {
                found_1 = true;
                assert!(option == expected_dvn_1_options, 1);
            };
            if (index == 2) {
                found_2 = true;
                assert!(option == expected_dvn_2_options, 2);
            };
        };
        assert!(found_0 && found_1 && found_2, 3);
    }
}
