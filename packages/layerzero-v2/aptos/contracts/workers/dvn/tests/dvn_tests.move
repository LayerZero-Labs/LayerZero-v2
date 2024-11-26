#[test_only]
module dvn::dvn_tests {
    use std::account::{create_account_for_test, create_signer_for_test};
    use std::event::was_event_emitted;

    use dvn::dvn::{
        get_fee_lib, get_quorum, init_module_for_test, initialize, is_admin, is_dvn_signer, is_paused,
        quorum_change_admin, set_admin, set_allowlist, set_denylist, set_deposit_address, set_dst_config,
        set_dvn_signer, set_fee_lib, set_pause, set_quorum, set_supported_msglibs, verify,
    };
    use dvn::hashes::create_verify_hash;
    use endpoint_v2_common::bytes32::{Self, from_bytes32};
    use endpoint_v2_common::contract_identity::make_call_ref_for_test;
    use endpoint_v2_common::guid::compute_guid;
    use endpoint_v2_common::packet_raw::get_packet_bytes;
    use endpoint_v2_common::packet_v1_codec;
    use endpoint_v2_common::serde::flatten;
    use endpoint_v2_common::universal_config;
    use worker_common::worker_config;

    const VID: u32 = 1;
    const EXPIRATION: u64 = 2000;

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config_store::EWORKER_ALREADY_INITIALIZED)]
    fun test_register_and_configure_dvn_cannot_initialize_twice() {
        let pub_key_1: vector<u8> = x"3bd5f17b6bc7a9022402246dd8e1530f0acd1d6439089b4f3bd8868250c1656c08a9fc2e4bff170ed023fbf77e6645020a77eba9c7c03390ed1b316af1ab6f0c";
        universal_config::init_module_for_test(VID);
        init_module_for_test();

        let dvn = &create_account_for_test(@dvn);
        initialize(
            dvn,
            @dvn,
            vector[@1234],
            vector[pub_key_1],
            1,
            vector[@0xaaaa],
            @dvn_fee_lib_router_0,
        );
        initialize(
            dvn,
            @dvn,
            vector[@1234],
            vector[pub_key_1],
            1,
            vector[@0xaaaa],
            @dvn_fee_lib_router_0,
        )
    }

    #[test]
    fun test_initialization() {
        let pub_key_1: vector<u8> = x"3bd5f17b6bc7a9022402246dd8e1530f0acd1d6439089b4f3bd8868250c1656c08a9fc2e4bff170ed023fbf77e6645020a77eba9c7c03390ed1b316af1ab6f0c";
        let pub_key_2: vector<u8> = x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d";
        let pub_key_3: vector<u8> = x"37bdab42a45e9d6cc56f7d0cc7897e871a0357bce3f0f4c99c93c54291b259a29a92111167a25ae188ef49b2f3df880d8aae8522e29cb6c299745258a200cfff";
        universal_config::init_module_for_test(VID);
        init_module_for_test();
        let dvn = &create_account_for_test(@dvn);
        initialize(
            dvn,
            @dvn,
            vector[@1234, @2234, @3234],
            vector[pub_key_1, pub_key_2],
            1,
            vector[@0xaaaa],
            @dvn_fee_lib_router_0,
        );
        assert!(get_quorum() == 1, 0);
        assert!(is_dvn_signer(pub_key_1), 1);
        assert!(is_dvn_signer(pub_key_2), 2);
        assert!(!is_dvn_signer(pub_key_3), 3);
        assert!(is_admin(@1234), 4);
        assert!(is_admin(@2234), 5);
        assert!(is_admin(@3234), 6);
        assert!(!is_admin(@9876), 7);
    }

    #[test]
    fun test_set_dvn_signer() {
        let pub_key_1: vector<u8> = x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a";
        let pub_key_2: vector<u8> = x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d";
        universal_config::init_module_for_test(VID);
        init_module_for_test();
        let dvn = &create_account_for_test(@dvn);
        initialize(
            dvn,
            @dvn,
            vector[@1234, @2234, @3234],
            vector[pub_key_1],
            1,
            vector[@0xaaaa],
            @dvn_fee_lib_router_0,
        );

        let signature_1 = x"a13c94e82fc009f71f152f137bed7fb799fa7d75a91a0e3a4ed2000fd408ba052743f3b91ee00cf6a5e98cd4d12b3b2e4984213c0c1c5a251b4e98eeec54f7a800";

        let native_framework = &create_signer_for_test(@std);
        std::timestamp::set_time_has_started_for_testing(native_framework);
        std::timestamp::update_global_time_for_test_secs(1000);

        let admin_1 = &create_signer_for_test(@1234);
        set_dvn_signer(
            admin_1,
            pub_key_2,
            true,
            EXPIRATION,
            signature_1,
        );

        assert!(is_dvn_signer(pub_key_2), 0);
    }

    #[test]
    fun test_set_dst_config() {
        let pub_key_1: vector<u8> = x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a";
        universal_config::init_module_for_test(VID);
        init_module_for_test();
        let dvn = &create_account_for_test(@dvn);
        let dvn_address = std::signer::address_of(dvn);
        initialize(
            dvn,
            @dvn,
            vector[dvn_address],
            vector[pub_key_1],
            1,
            vector[@0xaaaa],
            @dvn_fee_lib_router_0,
        );

        set_dst_config(dvn, 101, 77000, 12000, 1);

        let (gas, multiplier_bps, floor_margin_usd) = worker_config::get_dvn_dst_config_values(
            std::signer::address_of(dvn),
            101,
        );
        assert!(gas == 77000, 0);
        assert!(multiplier_bps == 12000, 1);
        assert!(floor_margin_usd == 1, 2);
    }

    #[test]
    fun test_set_quorum() {
        let pub_key_1: vector<u8> = x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a";
        let pub_key_2: vector<u8> = x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d";
        universal_config::init_module_for_test(VID);
        init_module_for_test();
        let dvn = &create_account_for_test(@dvn);
        initialize(
            dvn,
            @dvn,
            vector[@1234, @2234, @3234],
            vector[pub_key_1, pub_key_2],
            1,
            vector[@0xaaaa],
            @dvn_fee_lib_router_0,
        );

        let signature_1 = x"456e6b632d0958e6dc3d2fff9998e9c4be8023884e4a7f05d63bfd55f0178c743902b838114150a715597c808832c6bc61215ddc5133beac665861d9c2d0e26800";

        let native_framework = &create_signer_for_test(@std);
        std::timestamp::set_time_has_started_for_testing(native_framework);
        std::timestamp::update_global_time_for_test_secs(1000);

        let admin_1 = &create_signer_for_test(@1234);
        set_quorum(
            admin_1,
            2,
            EXPIRATION,
            signature_1,
        );

        assert!(get_quorum() == 2, 0);
    }

    #[test]
    fun test_set_allowlist() {
        let pub_key_1: vector<u8> = x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a";
        let pub_key_2: vector<u8> = x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d";
        universal_config::init_module_for_test(VID);
        init_module_for_test();

        let dvn = &create_account_for_test(@dvn);
        initialize(
            dvn,
            @dvn,
            vector[@1234, @2234, @3234],
            vector[pub_key_1, pub_key_2],
            1,
            vector[@simple_msglib],
            @dvn_fee_lib_router_0,
        );

        let signature_1_1 = x"d9a9aa95f0e21102aa8d05f2ada4261bc887b16f85d669df700c01ed985439187a278239f70567bcb879b1b5109d2f6fd4fa551535421188450e6cb1c74df7f200";

        let native_framework = &create_signer_for_test(@std);
        std::timestamp::set_time_has_started_for_testing(native_framework);
        std::timestamp::update_global_time_for_test_secs(1000);

        let admin_1 = &create_signer_for_test(@1234);

        set_allowlist(admin_1, @9988, true, EXPIRATION, signature_1_1); // pubkey 1 adds oapp to allowlist
        assert!(worker_config::allowlist_contains(@dvn, @9988), 0);
        assert!(worker_config::is_allowed(@dvn, @9988), 1);

        let signature_1_2 = x"504be072fd7ca14b3ef724d4dcfe2eb24ed121651b9f293b56c1df3a0e3e5e17437308c3d0aff27f7a9608003447d11d1f8f2f5c521ba77abb751d6fa225693001";
        set_allowlist(admin_1, @9988, false, EXPIRATION, signature_1_2); // pubkey 1 removes oapp to allowlist
        assert!(!worker_config::allowlist_contains(@dvn, @9988), 2);
    }

    #[test]
    fun test_set_denylist() {
        let pub_key_1: vector<u8> = x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a";
        let pub_key_2: vector<u8> = x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d";
        universal_config::init_module_for_test(VID);
        init_module_for_test();

        let dvn = &create_account_for_test(@dvn);
        initialize(
            dvn,
            @dvn,
            vector[@1234, @2234, @3234],
            vector[pub_key_1, pub_key_2],
            1,
            vector[@simple_msglib],
            @dvn_fee_lib_router_0,
        );

        let signature_1_1 = x"afbb4ac1ed62b3c63ee2ae9b9b5272f5fb7296990da96a29029e75bb6b97b3fc6471ad3ac62e897ab7681bf7dc4dd10f8b33325e391155d8d02d7c3ad455eaf001";

        let native_framework = &create_signer_for_test(@std);
        std::timestamp::set_time_has_started_for_testing(native_framework);
        std::timestamp::update_global_time_for_test_secs(1000);

        let admin_1 = &create_signer_for_test(@1234);

        set_denylist(admin_1, @9988, true, EXPIRATION, signature_1_1); // pubkey 1 adds oapp to denylist
        assert!(worker_config::denylist_contains(@dvn, @9988), 0);
        assert!(!worker_config::is_allowed(@dvn, @9988), 1);

        let signature_1_2 = x"64526a94655175cb1553d36615b2cbae8c7df8465719e1508ea1905d47b833fe44aea8d6aebf48a1cb70f6d93ba92215b70a311b18dd468d290d02404c15b63e01";
        set_denylist(admin_1, @9988, false, EXPIRATION, signature_1_2); // pubkey 1 removes oapp to denylist
        assert!(!worker_config::denylist_contains(@dvn, @9988), 2);
        assert!(worker_config::is_allowed(@dvn, @9988), 3);
    }

    #[test]
    fun test_set_fee_lib() {
        let pub_key_1: vector<u8> = x"1656867692ee1158567ecf944ea0755eff7d804b72fb3bdd7dda07758296cf14df3a10d6632e17023a4ed2aa47f6adf83b7aa6b0be4100efbcb7654cc40bcede";
        universal_config::init_module_for_test(VID);
        init_module_for_test();

        let dvn = &create_account_for_test(@dvn);
        initialize(
            dvn,
            @dvn,
            vector[@1234, @2234, @3234],
            vector[pub_key_1],
            1,
            vector[@simple_msglib],
            @0xfee11b001,
        );

        let fee_lib_from_worker_config = worker_config::get_worker_fee_lib(@dvn);
        assert!(fee_lib_from_worker_config == @0xfee11b001, 0);
        let fee_lib_from_dvn = get_fee_lib();
        assert!(fee_lib_from_dvn == @0xfee11b001, 1);

        let signature_1 = x"8675d9d20931230c405c6a756d7d9e9f6c2bc9770e2e7d52a1d31b5a7a5fedd80f5e60a0af97ef2ee5a7063ebbf285f34c2de07630a5bc07bac24da80d0a055e00";

        let native_framework = &create_signer_for_test(@std);
        std::timestamp::set_time_has_started_for_testing(native_framework);
        std::timestamp::update_global_time_for_test_secs(1000);

        let admin_1 = &create_signer_for_test(@1234);
        set_fee_lib(
            admin_1,
            @0xfee11b002,
            EXPIRATION,
            signature_1,
        );
        assert!(was_event_emitted(&worker_config::worker_fee_lib_updated_event(@dvn, @0xfee11b002)), 2);

        let fee_lib_from_worker_config = worker_config::get_worker_fee_lib(@dvn);
        assert!(fee_lib_from_worker_config == @0xfee11b002, 0);
        let fee_lib_from_dvn = get_fee_lib();
        assert!(fee_lib_from_dvn == @0xfee11b002, 1);
    }

    #[test]
    fun test_set_pause() {
        let pub_key_1: vector<u8> = x"2f68cff6060b082c04370615bbd5097d2f55f6d4ec9e3ed6156db64095b43efe0894d94399cc394394cdfb1075515877049959398ef042fca64e03443f9e8a41";
        universal_config::init_module_for_test(VID);
        init_module_for_test();

        let dvn = &create_account_for_test(@dvn);
        initialize(
            dvn,
            @dvn,
            vector[@1234, @2234, @3234],
            vector[pub_key_1],
            1,
            vector[@simple_msglib],
            @0xfee11b001,
        );

        let signature_1 = x"8675d9d20931230c405c6a756d7d9e9f6c2bc9770e2e7d52a1d31b5a7a5fedd80f5e60a0af97ef2ee5a7063ebbf285f34c2de07630a5bc07bac24da80d0a055e00";

        let native_framework = &create_signer_for_test(@std);
        std::timestamp::set_time_has_started_for_testing(native_framework);
        std::timestamp::update_global_time_for_test_secs(1000);

        assert!(!is_paused(), 0);
        let admin_1 = &create_signer_for_test(@1234);
        set_pause(admin_1, true, EXPIRATION, signature_1);
        assert!(was_event_emitted(&worker_config::paused_event(@dvn)), 2);
        assert!(is_paused(), 0);
    }

    #[test]
    fun test_set_unpause() {
        let pub_key_1: vector<u8> = x"7dd96c8221160d75f6ea7b11382755a907e80a90d03275f360f1febd21d8454819abbefaed3080505f6e3c2d5b33cf04e019cb8cfd90440c7715663ee4fe5483";
        universal_config::init_module_for_test(VID);
        init_module_for_test();

        let dvn = &create_account_for_test(@dvn);
        initialize(
            dvn,
            @dvn,
            vector[@1234, @2234, @3234],
            vector[pub_key_1],
            1,
            vector[@simple_msglib],
            @0xfee11b001,
        );

        let signature_1 = x"8675d9d20931230c405c6a756d7d9e9f6c2bc9770e2e7d52a1d31b5a7a5fedd80f5e60a0af97ef2ee5a7063ebbf285f34c2de07630a5bc07bac24da80d0a055e00";

        let native_framework = &create_signer_for_test(@std);
        std::timestamp::set_time_has_started_for_testing(native_framework);
        std::timestamp::update_global_time_for_test_secs(1000);
        assert!(!is_paused(), 0);
        worker_config::set_worker_pause(&make_call_ref_for_test(@dvn), true);
        assert!(is_paused(), 0);

        let admin_1 = &create_signer_for_test(@1234);
        set_pause(admin_1, false, EXPIRATION, signature_1);
        assert!(was_event_emitted(&worker_config::unpaused_event(@dvn)), 2);
        assert!(!is_paused(), 0);
    }

    #[test]
    fun test_quorum_change_admin() {
        let pub_key_1: vector<u8> = x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a";
        let pub_key_2: vector<u8> = x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d";
        universal_config::init_module_for_test(VID);
        init_module_for_test();

        let dvn = &create_account_for_test(@dvn);
        initialize(
            dvn,
            @dvn,
            vector[@1234, @2234, @3234],
            vector[pub_key_1, pub_key_2],
            1,
            vector[@simple_msglib],
            @dvn_fee_lib_router_0,
        );

        let signature_1 = x"8675d9d20931230c405c6a756d7d9e9f6c2bc9770e2e7d52a1d31b5a7a5fedd80f5e60a0af97ef2ee5a7063ebbf285f34c2de07630a5bc07bac24da80d0a055e00";
        let signature_2 = x"6525f9282e67057649022911b539663b92b9ba06b3b1a797c052499b61cf4e404f1aba7379fb1f75a7a891ce890ffa866c38704b0f978f8c76721ab2dcff437d01";

        let native_framework = &create_signer_for_test(@std);
        std::timestamp::set_time_has_started_for_testing(native_framework);
        std::timestamp::update_global_time_for_test_secs(1000);

        assert!(!is_admin(@9988), 0);
        quorum_change_admin(
            @9988,
            true,
            EXPIRATION,
            flatten(vector[signature_1, signature_2]),
        );
        assert!(is_admin(@9988), 1);
    }

    #[test]
    fun test_set_supported_msglibs() {
        let pub_key_1: vector<u8> = x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a";
        universal_config::init_module_for_test(VID);
        init_module_for_test();

        let dvn = &create_account_for_test(@dvn);
        initialize(
            dvn,
            @dvn,
            vector[@1234, @2234, @3234],
            vector[pub_key_1],
            1,
            vector[@simple_msglib],
            @dvn_fee_lib_router_0,
        );

        let signature_1 = x"e7b2bfe8c1f079ea3aa1923ba76e3f15ae30fab716941352514b34656c6cd9b96c5a0ee0a5e4f579dcff9a8a339dcd44c53b7f56068fb7c97c7c589d2e4518a601";

        let native_framework = &create_signer_for_test(@std);
        std::timestamp::set_time_has_started_for_testing(native_framework);
        std::timestamp::update_global_time_for_test_secs(1000);

        let admin_1 = &create_signer_for_test(@1234);

        assert!(!std::vector::contains(&worker_config::get_supported_msglibs(@dvn), &@2345), 1);
        set_supported_msglibs(
            admin_1,
            vector[@1234, @2345],
            EXPIRATION,
            flatten(vector[signature_1]),
        );
        assert!(std::vector::contains(&worker_config::get_supported_msglibs(@dvn), &@2345), 1);
    }

    #[test]
    fun test_verify() {
        let pub_key_1: vector<u8> = x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a";
        let pub_key_2: vector<u8> = x"505d1d231bb110780d1190b0a2ce9f2770350b295cbe970f127c4bc399cc406bb8c85d26b5afdbdc7316a065e4d4a3e4f27182310bf0d7c16da4b65ae787435d";

        universal_config::init_module_for_test(VID);
        uln_302::msglib::initialize_for_test();
        init_module_for_test();

        let dvn = &create_account_for_test(@dvn);
        initialize(
            dvn,
            @dvn,
            vector[@1234, @2234, @3234],
            vector[pub_key_1, pub_key_2],
            1,
            vector[@simple_msglib, @uln_302],
            @dvn_fee_lib_router_0,
        );

        let signature_1 = x"0fdeda25570d3cb243b39764a167558e4445786c54b180afe8ed36ab87b95a9f04c26107fb149be923d0f82d54d064a2dfc18edaa9c3f00f572c20240a51064700";
        let signature_2 = x"344aa33801eab51e48fa0b1112f1cb3227316a6640a0d05dc9e1f9cf1c62494a69fe521a2fca7cdfa70271bf3126b7d4fa10696ad648a17c1c32e3e3c678eb0d00";

        let native_framework = &create_signer_for_test(@std);
        std::timestamp::set_time_has_started_for_testing(native_framework);
        std::timestamp::update_global_time_for_test_secs(1000);

        // params to use for test
        let src_eid = 1;
        let sender = bytes32::from_address(@9999);
        let dst_eid = 1;
        let receiver = bytes32::from_address(@9999);
        let nonce = 1;
        let message = vector<u8>[1, 2, 3, 4];
        let guid = compute_guid(nonce, src_eid, sender, dst_eid, receiver);
        let packet = endpoint_v2_common::packet_v1_codec::new_packet_v1(
            src_eid,
            sender,
            dst_eid,
            receiver,
            nonce,
            guid,
            message,
        );
        let packet_header = packet_v1_codec::extract_header(&packet);
        let packet_header_bytes = get_packet_bytes(packet_header);
        let payload_hash = endpoint_v2_common::packet_v1_codec::get_payload_hash(&packet);

        let admin = &create_signer_for_test(@1234);

        verify(
            admin,
            packet_header_bytes,
            bytes32::from_bytes32(payload_hash),
            10,
            @uln_302,
            EXPIRATION,
            flatten(vector[signature_1, signature_2]),
        );

        let expected_used_hash = create_verify_hash(
            packet_header_bytes,
            bytes32::from_bytes32(payload_hash),
            10,
            @uln_302,
            dst_eid,
            EXPIRATION,
        );
        assert!(worker_common::multisig::was_hash_used(@dvn, from_bytes32(expected_used_hash)), 0)
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EUNAUTHORIZED)]
    fun test_set_admin_fails_if_not_admin() {
        let pub_key_1: vector<u8> = x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a";
        universal_config::init_module_for_test(VID);
        init_module_for_test();

        let dvn = &create_account_for_test(@dvn);
        initialize(
            dvn,
            @dvn,
            vector[@1234, @2234, @3234],
            vector[pub_key_1],
            1,
            vector[@simple_msglib],
            @dvn_fee_lib_router_0,
        );
        let admin = &create_signer_for_test(@3333);
        set_admin(admin, @8888, true);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EUNAUTHORIZED)]
    fun test_set_deposit_address_fails_if_not_admin() {
        let pub_key_1: vector<u8> = x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a";
        universal_config::init_module_for_test(VID);
        init_module_for_test();

        let dvn = &create_account_for_test(@dvn);
        initialize(
            dvn,
            @dvn,
            vector[@1234, @2234, @3234],
            vector[pub_key_1],
            1,
            vector[@simple_msglib],
            @dvn_fee_lib_router_0,
        );
        let admin = &create_signer_for_test(@1111);
        set_deposit_address(admin, @8888);
    }

    #[test]
    #[expected_failure(abort_code = worker_common::worker_config::EUNAUTHORIZED)]
    fun test_set_dst_config_fails_if_not_admin() {
        let pub_key_1: vector<u8> = x"e1b271a7296266189d300d37814581a695ec1da2e8ffbbeb9b89d754ac88d7bbecbff48968853fb6bf19251a0265df162fd436b8308a5ca6db97ee3e8f6e541a";
        universal_config::init_module_for_test(VID);
        init_module_for_test();

        let dvn = &create_account_for_test(@dvn);
        initialize(
            dvn,
            @dvn,
            vector[@1234, @2234, @3234],
            vector[pub_key_1],
            1,
            vector[@simple_msglib],
            @dvn_fee_lib_router_0,
        );
        let admin = &create_signer_for_test(@1111);
        set_dst_config(admin, 101, 77000, 12000, 1);
    }
}
