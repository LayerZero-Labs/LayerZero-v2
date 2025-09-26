#[test_only]
module message_lib_common::worker_options_test;

use message_lib_common::worker_options;
use utils::{buffer_reader, bytes32};

#[test]
fun test_split_worker_options_dvn_only() {
    let option_type = x"0003";
    let dvn_options_raw = x"020002000102000302ff0102000200010200020101";
    let options = vector::flatten(vector[option_type, dvn_options_raw]);
    let (executor_options, dvn_options) = worker_options::split_worker_options(&options);

    assert!(executor_options == x"", 0);
    assert!(dvn_options.length() == 3, 1);

    // Check DVN options are grouped correctly by index
    let dvn_0_options = worker_options::get_matching_options(&dvn_options, 0);
    let dvn_1_options = worker_options::get_matching_options(&dvn_options, 1);
    let dvn_2_options = worker_options::get_matching_options(&dvn_options, 2);

    assert!(dvn_0_options == x"02000200010200020001", 2);
    assert!(dvn_1_options == x"0200020101", 3);
    assert!(dvn_2_options == x"02000302ff01", 4);
}

#[test]
fun test_split_worker_options_executor_only() {
    let option_type = x"0003";
    let executor_options_raw = x"0100110100000000000000000000000000009470010011010000000000000000000000000000ea60";
    let options = vector::flatten(vector[option_type, executor_options_raw]);
    let (executor_options, dvn_options) = worker_options::split_worker_options(&options);

    assert!(executor_options == executor_options_raw, 0);
    assert!(dvn_options.length() == 0, 1);
}

#[test]
fun test_split_worker_options_options() {
    let option_type = x"0003";
    let executor_options_raw = x"0100110100000000000000000000000000009470010011010000000000000000000000000000ea60";
    let dvn_options_raw = x"020002000102000302ff0102000200010200020101";
    let options = vector::flatten(vector[option_type, executor_options_raw, dvn_options_raw]);
    let (executor_options, dvn_options) = worker_options::split_worker_options(&options);

    assert!(executor_options == executor_options_raw, 0);
    assert!(dvn_options.length() == 3, 1);

    // Check DVN options are grouped correctly by index
    let dvn_0_options = worker_options::get_matching_options(&dvn_options, 0);
    let dvn_1_options = worker_options::get_matching_options(&dvn_options, 1);
    let dvn_2_options = worker_options::get_matching_options(&dvn_options, 2);

    assert!(dvn_0_options == x"02000200010200020001", 2);
    assert!(dvn_1_options == x"0200020101", 3);
    assert!(dvn_2_options == x"02000302ff01", 4);
}

#[test]
fun test_decode_legacy_options_type_1() {
    let option_type = 1;
    let legacy_options = x"0000000000000000000000000000000000000000000000000000000000030d40";
    let expected_options = x"0100110100000000000000000000000000030d40";

    let executor_options = worker_options::convert_legacy_options(
        &mut buffer_reader::create(legacy_options),
        option_type,
    );
    // assert that the new executor option follows: [worker_id][option_size][option_type][option]
    assert!(executor_options == expected_options, 0);

    let mut reader = buffer_reader::create(executor_options);
    assert!(reader.read_u8() == 1, 1); // worker_id
    assert!(reader.read_u16() == 17, 2); // option_size
    assert!(reader.read_u8() == 1, 3); // option_type
    assert!(reader.read_u128() == 200000, 4); // option value (execution gas)
}

#[test]
fun test_decode_legacy_options_type_2() {
    let option_type = 2;
    let legacy_options =
        x"0000000000000000000000000000000000000000000000000000000000030d400000000000000000000000000000000000000000000000000000000000989680f39fd6e51aad88f6f4ce6ab8827279cfffb92266";
    let expected_options =
        x"0100110100000000000000000000000000030d400100310200000000000000000000000000989680000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266";
    let executor_options = worker_options::convert_legacy_options(
        &mut buffer_reader::create(legacy_options),
        option_type,
    );

    // adapter params type 2 includes both 1 and 2
    assert!(executor_options == expected_options, 0);

    let mut reader = buffer_reader::create(executor_options);
    // adapter params type 1
    assert!(reader.read_u8() == 1, 1); // worker_id
    assert!(reader.read_u16() == 17, 2); // option_size
    assert!(reader.read_u8() == 1, 3); // option_type
    assert!(reader.read_u128() == 200000, 4); // option value (execution gas)
    // adapter params type 2
    assert!(reader.read_u8() == 1, 5); // worker_id
    assert!(reader.read_u16() == 49, 6); // option_size
    assert!(reader.read_u8() == 2, 7); // option_type
    assert!(reader.read_u128() == 10000000, 8); // option value (amount)
    let expected_receiver = bytes32::from_bytes(x"000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266");
    assert!(reader.read_bytes32() == expected_receiver, 9); // option value (receiver)
}

#[test]
fun test_split_worker_options_using_legacy_option() {
    let legacy_options =
        x"00020000000000000000000000000000000000000000000000000000000000030d400000000000000000000000000000000000000000000000000000000000989680f39fd6e51aad88f6f4ce6ab8827279cfffb92266";
    let expected_options =
        x"0100110100000000000000000000000000030d400100310200000000000000000000000000989680000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266";
    let (executor_options, _) = worker_options::split_worker_options(&legacy_options);

    // adapter params type 2 includes both 1 and 2
    assert!(executor_options == expected_options, 0);

    let mut reader = buffer_reader::create(executor_options);
    // adapter params type 1
    assert!(reader.read_u8() == 1, 1); // worker_id
    assert!(reader.read_u16() == 17, 2); // option_size
    assert!(reader.read_u8() == 1, 3); // option_type
    assert!(reader.read_u128() == 200000, 4); // option value (execution gas)
    // adapter params type 2
    assert!(reader.read_u8() == 1, 5); // worker_id
    assert!(reader.read_u16() == 49, 6); // option_size
    assert!(reader.read_u8() == 2, 7); // option_type
    assert!(reader.read_u128() == 10000000, 8); // option value (amount)
    let expected_receiver = bytes32::from_bytes(x"000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266");
    assert!(reader.read_bytes32() == expected_receiver, 9); // option value (receiver)
}

#[test]
fun test_group_dvn_options_by_index() {
    let option_type = x"0003";
    let dvn_option_bytes = x"020002000102000302ff0102000200010200020101";
    let options = vector::flatten(vector[option_type, dvn_option_bytes]);
    let (_, dvn_options) = worker_options::split_worker_options(&options);

    let expected_dvn_0_options = x"02000200010200020001"; // 2 DVN options, id = 0
    let expected_dvn_1_options = x"0200020101"; // 1 DVN option, id = 1
    let expected_dvn_2_options = x"02000302ff01"; // 1 DVN option, id = 2

    let mut found_0 = false;
    let mut found_1 = false;
    let mut found_2 = false;

    // Check that DVN options are grouped correctly by index
    let mut i = 0;
    while (i < dvn_options.length()) {
        let (index, option) = worker_options::unpack(dvn_options[i]);
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

        i = i + 1;
    };
    assert!(found_0 && found_1 && found_2, 3);
}

#[test]
fun test_get_matching_options() {
    let option_type = x"0003";
    let dvn_option_bytes = x"020002000102000302ff0102000200010200020101";
    let options = vector::flatten(vector[option_type, dvn_option_bytes]);
    let (_, dvn_options) = worker_options::split_worker_options(&options);

    let expected_dvn_0_options = x"02000200010200020001"; // 2 DVN options, id = 0
    let expected_dvn_1_options = x"0200020101"; // 1 DVN option, id = 1
    let expected_dvn_2_options = x"02000302ff01"; // 1 DVN option, id = 2

    let dvn_0_options = worker_options::get_matching_options(&dvn_options, 0);
    assert!(dvn_0_options == expected_dvn_0_options, 0);
    let dvn_1_options = worker_options::get_matching_options(&dvn_options, 1);
    assert!(dvn_1_options == expected_dvn_1_options, 1);
    let dvn_2_options = worker_options::get_matching_options(&dvn_options, 2);
    assert!(dvn_2_options == expected_dvn_2_options, 2);
}
