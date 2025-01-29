module counter::counter {
    use std::fungible_asset::FungibleAsset;
    use std::option;
    use std::option::Option;
    use std::primary_fungible_store;
    use std::signer::address_of;
    use std::table::{Self, Table};

    use counter::msg_codec;
    use counter::msg_codec::{ABA_TYPE, COMPOSED_ABA_TYPE, COMPOSED_TYPE, VANILLA_TYPE};
    use counter::oapp_core::{
        assert_admin, get_admin, lz_quote, lz_send, lz_send_compose, refund_fees, skip,
    };
    use endpoint_v2_common::bytes32::{Bytes32, to_bytes32};
    use endpoint_v2_common::native_token;
    use executor_fee_lib_0::executor_option::{append_executor_options, new_executor_options, new_lz_receive_option};
    use msglib_types::worker_options::new_empty_type_3_options;

    friend counter::oapp_receive;
    friend counter::oapp_compose;

    struct Counter has key {
        outbound_count: Table<u32, u64>,
        inbound_count: Table<u32, u64>,
        total_inbound_count: u64,
        compose_count: u64,
        ordered_nonce: bool,
        max_received_nonce: Table<ReceivePathway, u64>,
    }

    struct ReceivePathway has drop, copy, store { src_eid: u32, sender: Bytes32 }

    // ===================================================== Quote ====================================================

    public fun quote(dst_eid: u32, type: u8, options: vector<u8>, pay_in_zro: bool): (u64, u64) {
        let message = counter::msg_codec::encode_msg_type(type, dst_eid, option::none());
        lz_quote(dst_eid, message, options, pay_in_zro)
    }

    // ===================================================== Send =====================================================

    public entry fun send(
        account: &signer,
        dst_eid: u32,
        type: u8,
        options: vector<u8>,
        fee_in_native: u64,
    ) acquires Counter {
        let native_fee = native_token::withdraw(account, fee_in_native);
        let zro_fee = option::none<FungibleAsset>();
        let sender = address_of(move account);

        // i dont see it done in evm but i think that's how it's intended to be used
        let message = msg_codec::encode_msg_type(type, dst_eid, option::none());
        lz_send(
            dst_eid,
            message,
            options,
            &mut native_fee,
            &mut zro_fee,
        );

        refund_fees(sender, native_fee, zro_fee);
        increment_outbound_count(dst_eid);
    }

    // ==================================================== Receive ===================================================

    public(friend) fun lz_receive_impl(
        src_eid: u32,
        sender: Bytes32,
        nonce: u64,
        guid: Bytes32,
        message: vector<u8>,
        _extra_data: vector<u8>,
        receive_value: Option<FungibleAsset>,
    ) acquires Counter {
        accept_nonce(src_eid, sender, nonce);

        let msg_type = msg_codec::get_msg_type(&message);
        if (msg_type == VANILLA_TYPE()) {
            increment_inbound_count(src_eid);
        } else if (msg_type == COMPOSED_TYPE() || msg_type == COMPOSED_ABA_TYPE()) {
            increment_inbound_count(src_eid);
            lz_send_compose(@counter, 0, guid, message);
        } else if (msg_type == ABA_TYPE()) {
            increment_inbound_count(src_eid);
            let options = new_empty_type_3_options();
            append_executor_options(&mut options, &new_executor_options(
                vector[
                    new_lz_receive_option(200000, 100),
                ],
                vector[],
                vector[],
                false,
            ));
            assert!(option::is_some(&receive_value), EABA_REQUIRES_RECEIVE_VALUE);
            increment_outbound_count(src_eid);
            let b_message = msg_codec::encode_msg_type(msg_codec::VANILLA_TYPE(), src_eid, option::some(10));
            let zro_fee = option::none();
            lz_send(src_eid, b_message, options, option::borrow_mut(&mut receive_value), &mut zro_fee);
            option::destroy_none(zro_fee);
        } else {
            abort ECOUNTER_INVALID_MSG_TYPE
        };

        if (option::is_some(&receive_value)) {
            primary_fungible_store::deposit(@counter, option::destroy_some(receive_value));
        } else {
            option::destroy_none(receive_value);
        }
    }

    public(friend) fun lz_compose_impl(
        _from: address,
        _guid: Bytes32,
        _index: u16,
        message: vector<u8>,
        _extra_data: vector<u8>,
        compose_value: Option<FungibleAsset>,
    ) acquires Counter {
        let message_type = msg_codec::get_msg_type(&message);
        if (message_type == COMPOSED_TYPE()) {
            increment_compose_count();
            // We don't need compose value here, so just deposit it to the admin if it exists
            option::destroy(compose_value, |fa| {
                primary_fungible_store::deposit(get_admin(), fa);
            });
        } else if (message_type == COMPOSED_ABA_TYPE()) {
            let src_eid = msg_codec::get_src_eid(&message);
            let b_message = msg_codec::encode_msg_type(msg_codec::VANILLA_TYPE(), src_eid, option::some(10));
            let zro_fee = option::none<FungibleAsset>();
            lz_send(
                src_eid,
                b_message,
                new_empty_type_3_options(),
                option::borrow_mut(&mut compose_value),
                &mut zro_fee,
            );
            option::destroy_none(zro_fee);
            primary_fungible_store::deposit(@counter, option::destroy_some(compose_value));
        } else {
            option::destroy(compose_value, |fa| {
                primary_fungible_store::deposit(get_admin(), fa);
            });
            abort ECOUNTER_INVALID_MSG_TYPE
        };
    }

    // ================================================= Ordered OApp =================================================

    public entry fun set_ordered_nonce(account: &signer, ordered_nonce: bool) acquires Counter {
        assert_admin(address_of(move account));
        counter_mut().ordered_nonce = ordered_nonce;
    }

    public(friend) fun next_nonce_impl(src_eid: u32, sender: Bytes32): u64 acquires Counter {
        *table::borrow_with_default(&counter().max_received_nonce, ReceivePathway { src_eid, sender }, &0) + 1
    }

    fun accept_nonce(src_eid: u32, sender: Bytes32, nonce: u64) acquires Counter {
        if (counter().ordered_nonce) {
            assert!(nonce == next_nonce_impl(src_eid, sender), 0);
        };
        let pathway = ReceivePathway { src_eid, sender };
        let max_received_nonce = table::borrow_mut_with_default(&mut counter_mut().max_received_nonce, pathway, 0);
        if (nonce > *max_received_nonce) {
            *max_received_nonce = nonce;
        }
    }

    public entry fun skip_inbound_nonce(
        account: &signer,
        src_eid: u32,
        sender: vector<u8>,
        nonce: u64,
    ) acquires Counter {
        skip(account, src_eid, sender, nonce);
        if (counter().ordered_nonce) {
            let pathway = ReceivePathway { src_eid, sender: to_bytes32(sender) };
            let max_received_nonce = table::borrow_mut_with_default(&mut counter_mut().max_received_nonce, pathway, 0);
            *max_received_nonce = *max_received_nonce + 1;
        }
    }

    // ============================================== Internal Functions ==============================================

    inline fun counter(): &Counter acquires Counter { borrow_global(@counter) }

    inline fun counter_mut(): &mut Counter acquires Counter { borrow_global_mut(@counter) }

    fun increment_outbound_count(dst_eid: u32) acquires Counter {
        let count = table::borrow_mut_with_default(&mut counter_mut().outbound_count, dst_eid, 0);
        *count = *count + 1;
    }

    public(friend) fun increment_inbound_count(src_eid: u32) acquires Counter {
        let count = table::borrow_mut_with_default(&mut counter_mut().inbound_count, src_eid, 0);
        *count = *count + 1;

        let total_count = &mut counter_mut().total_inbound_count;
        *total_count = *total_count + 1;
    }

    public(friend) fun increment_compose_count() acquires Counter {
        let compose_count = &mut counter_mut().compose_count;
        *compose_count = *compose_count + 1;
    }

    // ================================================ View Functions ================================================

    // Read the value in the `Counter` resource stored at `addr`
    #[view]
    public fun get_outbound_count(dst_eid: u32): u64 acquires Counter {
        *table::borrow_with_default(&counter().outbound_count, dst_eid, &0)
    }

    #[view]
    public fun get_inbound_count(src_eid: u32): u64 acquires Counter {
        *table::borrow_with_default(&counter().inbound_count, src_eid, &0)
    }

    #[view]
    public fun get_total_inbound_count(): u64 acquires Counter { counter().total_inbound_count }

    #[view]
    public fun get_compose_count(): u64 acquires Counter { counter().compose_count }

    // ================================================ Initialization ================================================

    fun init_module(account: &signer) {
        move_to(account, Counter {
            outbound_count: table::new(),
            inbound_count: table::new(),
            total_inbound_count: 0,
            compose_count: 0,
            ordered_nonce: false,
            max_received_nonce: table::new(),
        });
    }


    #[test_only]
    public fun init_module_for_test() {
        init_module(&std::account::create_signer_for_test(counter::oapp_store::OAPP_ADDRESS()));
    }

    // ================================================== Error Codes =================================================

    const ECOUNTER_INVALID_MSG_TYPE: u64 = 1;
    const EABA_REQUIRES_RECEIVE_VALUE: u64 = 2;
}
