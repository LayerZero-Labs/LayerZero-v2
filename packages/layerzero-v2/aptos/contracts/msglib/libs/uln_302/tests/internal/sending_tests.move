#[test_only]
module uln_302::sending_tests {
    use std::event::was_event_emitted;
    use std::fungible_asset::FungibleAsset;
    use std::option::{Self, destroy_none};
    use std::vector;

    use endpoint_v2_common::bytes32;
    use endpoint_v2_common::guid;
    use endpoint_v2_common::native_token_test_helpers::{burn_token_for_test, mint_native_token_for_test};
    use endpoint_v2_common::packet_raw;
    use endpoint_v2_common::packet_v1_codec;
    use endpoint_v2_common::send_packet;
    use endpoint_v2_common::serde::flatten;
    use msglib_types::configs_executor::new_executor_config;
    use msglib_types::configs_uln::new_uln_config;
    use msglib_types::worker_options::{
        append_dvn_option,
        append_generic_type_3_executor_option,
        new_empty_type_3_options,
    };
    use treasury::treasury;
    use uln_302::configuration;
    use uln_302::sending::{dvn_fee_paid_event, executor_fee_paid_event, quote_internal, send_internal};
    use uln_302::uln_302_store;

    #[test]
    fun test_send_internal() {
        uln_302_store::init_module_for_test();
        treasury::init_module_for_test();
        configuration::set_default_send_uln_config(103, new_uln_config(
            5,
            1,
            vector[@10001],
            vector[@10002, @10003],
            false,
            false,
            false,
        ));
        configuration::set_default_executor_config(103, new_executor_config(
            10000,
            @10100,
        ));

        let native_token = mint_native_token_for_test(10000);
        let zro_token = option::none<FungibleAsset>();

        let send_packet = send_packet::new_send_packet(
            1,
            102,
            bytes32::from_address(@1234),
            103,
            bytes32::from_address(@5678),
            b"payload",
        );

        let worker_options = new_empty_type_3_options();
        append_dvn_option(&mut worker_options,
            0,
            9,
            x"aa00",
        );
        append_dvn_option(&mut worker_options,
            2,
            9,
            x"aa20",
        );
        append_dvn_option(&mut worker_options,
            2,
            5,
            x"aa21",
        );
        append_generic_type_3_executor_option(&mut worker_options, b"777");

        let get_executor_fee_call_count = 0;
        let get_dvn_fee_call_count = 0;
        let called_dvns = vector<address>[];

        // needed to prevent the compiler warning
        assert!(get_executor_fee_call_count == 0, 0);
        assert!(get_dvn_fee_call_count == 0, 0);
        assert!(vector::length(&called_dvns) == 0, 0);

        let expected_packet_header = packet_v1_codec::new_packet_v1_header_only(
            102,
            bytes32::from_address(@1234),
            103,
            bytes32::from_address(@5678),
            1,
        );
        let guid = bytes32::from_bytes32(guid::compute_guid(
            1,
            102,
            bytes32::from_address(@1234),
            103,
            bytes32::from_address(@5678),
        ));

        let expected_payload_hash = bytes32::keccak256(flatten(vector[guid, b"payload"]));

        let (native_fee, zro_fee, encoded_packet) = send_internal(
            send_packet,
            worker_options,
            &mut native_token,
            &mut zro_token,
            |executor_address, executor_options| {
                get_executor_fee_call_count = get_executor_fee_call_count + 1;
                assert!(executor_address == @10100, 101);
                let expected_option = flatten(vector[
                    x"01", // executor option
                    x"0003", // length = 3
                    b"777"  // option
                ]);
                assert!(executor_options == expected_option, 102);
                (101, @555)
            },
            |dvn_address, confirmations, dvn_options, packet_header, payload_hash| {
                assert!(packet_header == expected_packet_header, 0);
                assert!(payload_hash == expected_payload_hash, 0);
                get_dvn_fee_call_count = get_dvn_fee_call_count + 1;
                vector::push_back(&mut called_dvns, dvn_address);
                assert!(confirmations == 5, 0);
                if (dvn_address == @10001) {
                    let expected_option = flatten(vector[
                        x"02", // dvn option
                        x"0004", // length = 4
                        x"00", // dvn index
                        x"09", // option type
                        x"aa00", // option
                    ]);
                    assert!(dvn_options == expected_option, 0);
                    (203, @777)
                } else if (dvn_address == @10002) {
                    let expected_option = x""; // empty
                    assert!(dvn_options == expected_option, 0);

                    (204, @778)
                } else if (dvn_address == @10003) {
                    let expected_option = flatten(vector[
                        // first option
                        x"02", // dvn option
                        x"0004", // length = 4
                        x"02", // dvn index
                        x"09", // option type
                        x"aa20", // option
                        // second option
                        x"02", // dvn option
                        x"0004", // length = 4
                        x"02", // dvn index
                        x"05", // option type
                        x"aa21", // option
                    ]);
                    assert!(dvn_options == expected_option, 0);
                    (205, @779)
                } else {
                    (1, @111)
                }
            },
        );

        // (203 + 204 + 205) + 101 = 713
        assert!(native_fee == 713, 0);
        assert!(zro_fee == 0, 0);

        let expected_encoded_packet = flatten(vector[
            packet_raw::get_packet_bytes(expected_packet_header),
            guid,
            b"payload",
        ]);
        assert!(packet_raw::get_packet_bytes(encoded_packet) == expected_encoded_packet, 0);

        assert!(get_executor_fee_call_count == 1, 1);
        assert!(get_dvn_fee_call_count == 3, 1);
        assert!(vector::contains(&called_dvns, &@10001), 0);
        assert!(vector::contains(&called_dvns, &@10002), 0);
        assert!(vector::contains(&called_dvns, &@10003), 0);

        assert!(was_event_emitted(&executor_fee_paid_event(
            @10100,
            @555,
            101,
        )), 0);

        assert!(was_event_emitted(&dvn_fee_paid_event(
            vector[@10001],
            vector[@10002, @10003],
            vector[203, 204, 205],
            vector[@777, @778, @779],
        )), 0);
        burn_token_for_test(native_token);
        destroy_none(zro_token);
    }

    #[test]
    fun test_quote_internal() {
        uln_302_store::init_module_for_test();
        treasury::init_module_for_test();
        configuration::set_default_send_uln_config(103, new_uln_config(
            5,
            1,
            vector[@10001],
            vector[@10002, @10003],
            false,
            false,
            false,
        ));
        configuration::set_default_executor_config(103, new_executor_config(
            10000,
            @10100,
        ));

        let send_packet = send_packet::new_send_packet(
            1,
            102,
            bytes32::from_address(@1234),
            103,
            bytes32::from_address(@5678),
            b"payload",
        );

        let worker_options = new_empty_type_3_options();
        append_dvn_option(&mut worker_options,
            0,
            9,
            x"aa00",
        );
        append_dvn_option(&mut worker_options,
            2,
            9,
            x"aa20",
        );
        append_dvn_option(&mut worker_options,
            2,
            5,
            x"aa21",
        );
        append_generic_type_3_executor_option(&mut worker_options, b"777");

        let get_executor_fee_call_count = 0;
        let get_dvn_fee_call_count = 0;

        // needed to prevent the compiler warning
        assert!(get_executor_fee_call_count == 0, 0);
        assert!(get_dvn_fee_call_count == 0, 0);

        let expected_packet_header = packet_v1_codec::new_packet_v1_header_only(
            102,
            bytes32::from_address(@1234),
            103,
            bytes32::from_address(@5678),
            1,
        );
        let guid = bytes32::from_bytes32(guid::compute_guid(
            1,
            102,
            bytes32::from_address(@1234),
            103,
            bytes32::from_address(@5678),
        ));

        let expected_payload_hash = bytes32::keccak256(flatten(vector[guid, b"payload"]));
        let called_dvns = vector<address>[];
        assert!(vector::length(&called_dvns) == 0, 0);

        let (native_fee, zro_fee) = quote_internal(
            send_packet,
            worker_options,
            false,
            |executor_address, executor_options| {
                get_executor_fee_call_count = get_executor_fee_call_count + 1;
                assert!(executor_address == @10100, 101);
                let expected_option = flatten(vector[
                    x"01", // executor option
                    x"0003", // length = 3
                    b"777"  // option
                ]);
                assert!(executor_options == expected_option, 102);
                (101, @555)
            },
            |dvn_address, confirmations, dvn_options, packet_header, payload_hash| {
                assert!(packet_header == expected_packet_header, 0);
                assert!(payload_hash == expected_payload_hash, 0);
                get_dvn_fee_call_count = get_dvn_fee_call_count + 1;
                vector::push_back(&mut called_dvns, dvn_address);
                assert!(confirmations == 5, 0);
                if (dvn_address == @10001) {
                    let expected_option = flatten(vector[
                        x"02", // dvn option
                        x"0004", // length = 4
                        x"00", // dvn index
                        x"09", // option type
                        x"aa00", // option
                    ]);
                    assert!(dvn_options == expected_option, 0);
                };
                if (dvn_address == @10002) {
                    let expected_option = x""; // empty
                    assert!(dvn_options == expected_option, 0);
                };
                if (dvn_address == @10003) {
                    let expected_option = flatten(vector[
                        // first option
                        x"02", // dvn option
                        x"0004", // length = 4
                        x"02", // dvn index
                        x"09", // option type
                        x"aa20", // option
                        // second option
                        x"02", // dvn option
                        x"0004", // length = 4
                        x"02", // dvn index
                        x"05", // option type
                        x"aa21", // option
                    ]);
                    assert!(dvn_options == expected_option, 0);
                };
                (203, @777)
            },
        );

        // 203 * 3 + 101 = 710
        assert!(native_fee == 710, 0);
        assert!(zro_fee == 0, 0);

        assert!(get_executor_fee_call_count == 1, 1);
        assert!(get_dvn_fee_call_count == 3, 1);
        assert!(vector::contains(&called_dvns, &@10001), 0);
        assert!(vector::contains(&called_dvns, &@10002), 0);
        assert!(vector::contains(&called_dvns, &@10003), 0);
    }
}
