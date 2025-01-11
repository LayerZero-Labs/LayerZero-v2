#[test_only]
module endpoint_v2::test_helpers {
    use std::account::create_signer_for_test;
    use std::signer::address_of;
    use std::timestamp;

    use endpoint_v2::admin;
    use endpoint_v2_common::contract_identity::make_call_ref_for_test;
    use endpoint_v2_common::native_token_test_helpers::initialize_native_token_for_test;
    use msglib_types::worker_options::EXECUTOR_WORKER_ID;
    use price_feed_module_0::price;
    use price_feed_module_0::price::tag_price_with_eid;
    use treasury::treasury;
    use worker_common::worker_config;

    public fun setup_layerzero_for_test(
        msglib_addr: address, // should be the address of whatever msglib we are trying to test
        local_eid: u32,
        remote_eid: u32,
    ) {
        let native_framework = &create_signer_for_test(@std);
        let layerzero_admin = &create_signer_for_test(@layerzero_admin);

        // set global time
        timestamp::set_time_has_started_for_testing(native_framework);

        // init
        endpoint_v2_common::universal_config::init_module_for_test(local_eid);
        admin::initialize_endpoint_for_test();
        simple_msglib::msglib::initialize_for_test();

        // config/wire
        endpoint_v2::msglib_manager::register_library(msglib_addr);

        // defaults
        endpoint_v2::admin::set_default_send_library(
            layerzero_admin,
            remote_eid,
            msglib_addr,
        );
        endpoint_v2::admin::set_default_receive_library(
            layerzero_admin,
            remote_eid,
            msglib_addr,
            0,
        );
    }

    public fun setup_layerzero_for_test_uln(local_eid: u32, remote_eid: u32) {
        initialize_native_token_for_test();
        let native_framework = &create_signer_for_test(@std);
        let layerzero_admin = &create_signer_for_test(@layerzero_admin);

        // set global time
        timestamp::set_time_has_started_for_testing(native_framework);

        // init
        endpoint_v2_common::universal_config::init_module_for_test(local_eid);
        admin::initialize_endpoint_for_test();
        uln_302::msglib::initialize_for_test();

        // config/wire
        endpoint_v2::msglib_manager::register_library(@uln_302);

        // uln
        uln_302::configuration_tests::enable_send_eid_for_test(remote_eid);
        uln_302::configuration_tests::enable_receive_eid_for_test(local_eid);

        // defaults
        endpoint_v2::admin::set_default_send_library(
            layerzero_admin,
            remote_eid,
            @uln_302,
        );
        endpoint_v2::admin::set_default_receive_library(
            layerzero_admin,
            local_eid,
            @uln_302,
            0,
        );

        let executor = @3002;
        uln_302::admin::set_default_executor_config(
            layerzero_admin,
            remote_eid,
            100000,
            executor,
        );

        // Executor config
        worker_config::initialize_for_worker_test_only(
            executor,
            EXECUTOR_WORKER_ID(),
            executor,
            @13002,
            vector[executor],
            vector[@uln_302],
            @executor_fee_lib_0,
        );
        worker_config::set_executor_dst_config(
            &make_call_ref_for_test(executor),
            remote_eid,
            1000,
            1000,
            1000,
            1000,
            1000,
        );
        // opt into using worker config for feelib routing
        uln_302::msglib::set_worker_config_for_fee_lib_routing_opt_in(&create_signer_for_test(executor), true);
        let feed_address = @1234;
        worker_config::set_price_feed(
            &make_call_ref_for_test(executor),
            @price_feed_module_0,
            feed_address,
        );

        // Treasury
        treasury::init_module_for_test();

        // Price feed
        let feed_updater = &create_signer_for_test(@555);
        price_feed_module_0::feeds::initialize(&create_signer_for_test(feed_address));
        price_feed_module_0::feeds::enable_feed_updater(
            &create_signer_for_test(feed_address),
            address_of(feed_updater)
        );
        price_feed_module_0::feeds::set_price(
            feed_updater,
            feed_address,
            price::serialize_eid_tagged_price_list(&vector[
                tag_price_with_eid(
                    remote_eid,
                    price::new_price(1, 1, 1),
                ),
                tag_price_with_eid(
                    local_eid,
                    price::new_price(1, 1, 1),
                ),
            ]),
        )
    }
}
