module endpoint_v2::store {
    use std::math64::min;
    use std::string::{Self, String};
    use std::table::{Self, Table};
    use std::vector;

    use endpoint_v2::timeout::Timeout;
    use endpoint_v2_common::bytes32::Bytes32;
    use endpoint_v2_common::contract_identity::{Self, ContractSigner, DynamicCallRef};

    friend endpoint_v2::channels;
    friend endpoint_v2::messaging_composer;
    friend endpoint_v2::msglib_manager;
    friend endpoint_v2::registration;

    #[test_only]
    friend endpoint_v2::admin;
    #[test_only]
    friend endpoint_v2::endpoint_tests;
    #[test_only]
    friend endpoint_v2::channels_tests;
    #[test_only]
    friend endpoint_v2::msglib_manager_tests;
    #[test_only]
    friend endpoint_v2::messaging_composer_tests;
    #[test_only]
    friend endpoint_v2::registration_tests;

    struct EndpointStore has key {
        contract_signer: ContractSigner,
        oapps: Table<address, OAppStore>,
        composers: Table<address, ComposerStore>,
        msglibs: Table<u64, address>,
        msglib_count: u64,
        msglibs_registered: Table<address, bool>,
        msglibs_default_send_libs: Table<u32, address>,
        msglibs_default_receive_libs: Table<u32, address>,
        msglibs_default_receive_lib_timeout_configs: Table<u32, Timeout>,
    }

    struct OAppStore has store {
        lz_receive_module: String,
        channels: Table<ChannelKey, Channel>,
        msglibs_send_libs: Table<u32, address>,
        msglibs_receive_libs: Table<u32, address>,
        msglibs_receive_lib_timeout_configs: Table<u32, Timeout>,
    }

    struct ComposerStore has store {
        lz_compose_module: String,
        compose_message_hashes: Table<ComposeKey, Bytes32>,
    }

    struct Channel has store {
        outbound_nonce: u64,
        inbound_pathway_registered: bool,
        inbound_lazy_nonce: u64,
        inbound_hashes: Table<u64, Bytes32>,
    }

    struct ChannelKey has store, drop, copy { remote_eid: u32, remote_address: Bytes32 }

    struct ComposeKey has store, drop, copy { from: address, guid: Bytes32, index: u16 }

    fun init_module(account: &signer) {
        move_to(account, EndpointStore {
            contract_signer: contract_identity::create_contract_signer(account),
            oapps: table::new(),
            composers: table::new(),
            msglibs: table::new(),
            msglib_count: 0,
            msglibs_registered: table::new(),
            msglibs_default_send_libs: table::new(),
            msglibs_default_receive_libs: table::new(),
            msglibs_default_receive_lib_timeout_configs: table::new(),
        })
    }

    #[test_only]
    public fun init_module_for_test() {
        let account = &std::account::create_signer_for_test(@endpoint_v2);
        init_module(account);
    }

    // ==================================================== General ===================================================

    public(friend) fun make_dynamic_call_ref(
        target_contract: address,
        authorization: vector<u8>,
    ): DynamicCallRef acquires EndpointStore {
        contract_identity::make_dynamic_call_ref(&store().contract_signer, target_contract, authorization)
    }

    // OApp - Helpers
    inline fun store(): &EndpointStore { borrow_global(@endpoint_v2) }

    inline fun store_mut(): &mut EndpointStore { borrow_global_mut(@endpoint_v2) }

    inline fun oapps(): &Table<address, OAppStore> { &store().oapps }

    inline fun oapps_mut(): &mut Table<address, OAppStore> { &mut store_mut().oapps }

    inline fun composers(): &Table<address, ComposerStore> { &store().composers }

    inline fun composers_mut(): &mut Table<address, ComposerStore> { &mut store_mut().composers }

    inline fun oapp_store(oapp: address): &OAppStore {
        assert!(table::contains(oapps(), oapp), EUNREGISTERED_OAPP);
        table::borrow(oapps(), oapp)
    }

    inline fun oapp_store_mut(oapp: address): &mut OAppStore {
        assert!(table::contains(oapps(), oapp), EUNREGISTERED_OAPP);
        table::borrow_mut(oapps_mut(), oapp)
    }

    inline fun composer_store(composer: address): &ComposerStore {
        assert!(table::contains(composers(), composer), EUNREGISTERED_COMPOSER);
        table::borrow(composers(), composer)
    }

    inline fun composer_store_mut(composer: address): &mut ComposerStore {
        assert!(table::contains(composers(), composer), EUNREGISTERED_COMPOSER);
        table::borrow_mut(composers_mut(), composer)
    }

    inline fun has_channel(oapp: address, remote_eid: u32, remote_address: Bytes32): bool {
        table::contains(&oapp_store(oapp).channels, ChannelKey { remote_eid, remote_address })
    }

    inline fun create_channel(oapp: address, remote_eid: u32, remote_address: Bytes32) acquires EndpointStore {
        table::add(&mut oapp_store_mut(oapp).channels, ChannelKey { remote_eid, remote_address }, Channel {
            outbound_nonce: 0,
            inbound_pathway_registered: false,
            inbound_lazy_nonce: 0,
            inbound_hashes: table::new(),
        });
    }

    /// Get a reference to an OApp channel. The initialization of a channel should be implicit and transparent to the
    /// user.
    /// Therefore caller should generally check that the channel exists before calling this function; if it doesn't
    /// exist, it should return the value that is consistent with the initial state of a channel
    inline fun channel(oapp: address, remote_eid: u32, remote_address: Bytes32): &Channel {
        let channel_key = ChannelKey { remote_eid, remote_address };
        table::borrow(&oapp_store(oapp).channels, channel_key)
    }

    /// Get a mutable reference to an OApp channel. If the channel doesn't exist, create it
    inline fun channel_mut(oapp: address, remote_eid: u32, remote_address: Bytes32): &mut Channel {
        let channel_key = ChannelKey { remote_eid, remote_address };
        if (!table::contains(&oapp_store(oapp).channels, channel_key)) {
            create_channel(oapp, remote_eid, remote_address);
        };
        table::borrow_mut(&mut oapp_store_mut(oapp).channels, channel_key)
    }

    // ================================================= OApp General =================================================

    public(friend) fun register_oapp(oapp: address, lz_receive_module: String) acquires EndpointStore {
        assert!(!string::is_empty(&lz_receive_module), EEMPTY_MODULE_NAME);
        table::add(oapps_mut(), oapp, OAppStore {
            channels: table::new(),
            lz_receive_module,
            msglibs_send_libs: table::new(),
            msglibs_receive_libs: table::new(),
            msglibs_receive_lib_timeout_configs: table::new(),
        });
    }

    public(friend) fun is_registered_oapp(oapp: address): bool acquires EndpointStore {
        table::contains(oapps(), oapp)
    }

    public(friend) fun lz_receive_module(receiver: address): String acquires EndpointStore {
        oapp_store(receiver).lz_receive_module
    }

    // ================================================= OApp Outbound ================================================

    public(friend) fun outbound_nonce(sender: address, dst_eid: u32, receiver: Bytes32): u64 acquires EndpointStore {
        if (has_channel(sender, dst_eid, receiver)) {
            channel(sender, dst_eid, receiver).outbound_nonce
        } else {
            0
        }
    }

    public(friend) fun increment_outbound_nonce(
        sender: address,
        dst_eid: u32,
        receiver: Bytes32,
    ): u64 acquires EndpointStore {
        let outbound_nonce = &mut channel_mut(sender, dst_eid, receiver).outbound_nonce;
        *outbound_nonce = *outbound_nonce + 1;
        *outbound_nonce
    }

    // ================================================= OApp Inbound =================================================

    public(friend) fun receive_pathway_registered(
        receiver: address,
        src_eid: u32,
        sender: Bytes32,
    ): bool acquires EndpointStore {
        if (is_registered_oapp(receiver) && has_channel(receiver, src_eid, sender)) {
            channel(receiver, src_eid, sender).inbound_pathway_registered
        } else {
            false
        }
    }

    public(friend) fun register_receive_pathway(
        receiver: address,
        src_eid: u32,
        sender: Bytes32,
    ) acquires EndpointStore {
        if (!has_channel(receiver, src_eid, sender)) { create_channel(receiver, src_eid, sender) };
        let channel = channel_mut(receiver, src_eid, sender);
        channel.inbound_pathway_registered = true;
    }

    public(friend) fun assert_receive_pathway_registered(
        receiver: address,
        src_eid: u32,
        sender: Bytes32,
    ) acquires EndpointStore {
        assert!(receive_pathway_registered(receiver, src_eid, sender), EUNREGISTERED_PATHWAY);
    }

    public(friend) fun lazy_inbound_nonce(
        receiver: address,
        src_eid: u32,
        sender: Bytes32,
    ): u64 acquires EndpointStore {
        if (has_channel(receiver, src_eid, sender)) {
            channel(receiver, src_eid, sender).inbound_lazy_nonce
        } else {
            0
        }
    }

    public(friend) fun set_lazy_inbound_nonce(
        receiver: address,
        src_eid: u32,
        sender: Bytes32,
        nonce: u64,
    ) acquires EndpointStore {
        channel_mut(receiver, src_eid, sender).inbound_lazy_nonce = nonce;
    }

    public(friend) fun has_payload_hash(
        receiver: address,
        src_eid: u32,
        sender: Bytes32,
        nonce: u64,
    ): bool acquires EndpointStore {
        if (has_channel(receiver, src_eid, sender)) {
            table::contains(&channel(receiver, src_eid, sender).inbound_hashes, nonce)
        } else {
            false
        }
    }

    public(friend) fun get_payload_hash(
        receiver: address,
        src_eid: u32,
        sender: Bytes32,
        nonce: u64,
    ): Bytes32 acquires EndpointStore {
        assert!(has_channel(receiver, src_eid, sender), EUNREGISTERED_PATHWAY);
        let hashes = &channel(receiver, src_eid, sender).inbound_hashes;
        assert!(table::contains(hashes, nonce), ENO_PAYLOAD_HASH);
        *table::borrow(hashes, nonce)
    }

    public(friend) fun set_payload_hash(
        receiver: address,
        src_eid: u32,
        sender: Bytes32,
        nonce: u64,
        hash: Bytes32,
    ) acquires EndpointStore {
        table::upsert(&mut channel_mut(receiver, src_eid, sender).inbound_hashes, nonce, hash);
    }

    public(friend) fun remove_payload_hash(
        receiver: address,
        src_eid: u32,
        sender: Bytes32,
        nonce: u64,
    ): Bytes32 acquires EndpointStore {
        let hashes = &mut channel_mut(receiver, src_eid, sender).inbound_hashes;
        assert!(table::contains(hashes, nonce), ENO_PAYLOAD_HASH);
        table::remove(hashes, nonce)
    }

    // ==================================================== Compose ===================================================

    public(friend) fun register_composer(composer: address, lz_compose_module: String) acquires EndpointStore {
        assert!(!string::is_empty(&lz_compose_module), EEMPTY_MODULE_NAME);
        table::add(composers_mut(), composer, ComposerStore {
            lz_compose_module,
            compose_message_hashes: table::new(),
        });
    }

    public(friend) fun is_registered_composer(composer: address): bool acquires EndpointStore {
        table::contains(composers(), composer)
    }

    public(friend) fun lz_compose_module(composer: address): String acquires EndpointStore {
        composer_store(composer).lz_compose_module
    }

    public(friend) fun has_compose_message_hash(
        from: address,
        to: address,
        guid: Bytes32,
        index: u16,
    ): bool acquires EndpointStore {
        let compose_key = ComposeKey { from, guid, index };
        table::contains(&composer_store(to).compose_message_hashes, compose_key)
    }

    public(friend) fun get_compose_message_hash(
        from: address,
        to: address,
        guid: Bytes32,
        index: u16,
    ): Bytes32 acquires EndpointStore {
        let compose_key = ComposeKey { from, guid, index };
        *table::borrow(&composer_store(to).compose_message_hashes, compose_key)
    }

    public(friend) fun set_compose_message_hash(
        from: address,
        to: address,
        guid: Bytes32,
        index: u16,
        hash: Bytes32,
    ) acquires EndpointStore {
        let compose_key = ComposeKey { from, guid, index };
        table::upsert(&mut composer_store_mut(to).compose_message_hashes, compose_key, hash);
    }

    // =============================================== Message Libraries ==============================================

    public(friend) fun registered_msglibs(start: u64, max_count: u64): vector<address> acquires EndpointStore {
        let msglibs = &store().msglibs;
        let end = min(start + max_count, store().msglib_count);
        if (start >= end) { return vector[] };

        let result = vector[];
        for (i in start..end) {
            let lib = *table::borrow(msglibs, i);
            vector::push_back(&mut result, lib);
        };
        result
    }

    public(friend) fun add_msglib(lib: address) acquires EndpointStore {
        let count = store().msglib_count;
        table::add(&mut store_mut().msglibs, count, lib);
        store_mut().msglib_count = count + 1;

        table::add(&mut store_mut().msglibs_registered, lib, true);
    }

    public(friend) fun is_registered_msglib(lib: address): bool acquires EndpointStore {
        table::contains(&store().msglibs_registered, lib)
    }

    public(friend) fun has_default_send_library(dst_eid: u32): bool acquires EndpointStore {
        table::contains(&store().msglibs_default_send_libs, dst_eid)
    }

    public(friend) fun get_default_send_library(dst_eid: u32): address acquires EndpointStore {
        let default_send_libs = &store().msglibs_default_send_libs;
        assert!(table::contains(default_send_libs, dst_eid), EUNSUPPORTED_DST_EID);
        *table::borrow(default_send_libs, dst_eid)
    }

    public(friend) fun set_default_send_library(dst_eid: u32, lib: address) acquires EndpointStore {
        table::upsert(&mut store_mut().msglibs_default_send_libs, dst_eid, lib);
    }

    public(friend) fun has_default_receive_library(src_eid: u32): bool acquires EndpointStore {
        table::contains(&store().msglibs_default_receive_libs, src_eid)
    }

    public(friend) fun get_default_receive_library(src_eid: u32): address acquires EndpointStore {
        let default_receive_libs = &store().msglibs_default_receive_libs;
        assert!(table::contains(default_receive_libs, src_eid), EUNSUPPORTED_SRC_EID);
        *table::borrow(default_receive_libs, src_eid)
    }

    public(friend) fun set_default_receive_library(src_eid: u32, lib: address) acquires EndpointStore {
        table::upsert(&mut store_mut().msglibs_default_receive_libs, src_eid, lib);
    }

    public(friend) fun has_default_receive_library_timeout(src_eid: u32): bool acquires EndpointStore {
        table::contains(&store().msglibs_default_receive_lib_timeout_configs, src_eid)
    }

    public(friend) fun get_default_receive_library_timeout(
        src_eid: u32,
    ): Timeout acquires EndpointStore {
        *table::borrow(&store().msglibs_default_receive_lib_timeout_configs, src_eid)
    }

    public(friend) fun set_default_receive_library_timeout(
        src_eid: u32,
        config: Timeout,
    ) acquires EndpointStore {
        table::upsert(&mut store_mut().msglibs_default_receive_lib_timeout_configs, src_eid, config);
    }

    public(friend) fun unset_default_receive_library_timeout(
        src_eid: u32,
    ): Timeout acquires EndpointStore {
        table::remove(&mut store_mut().msglibs_default_receive_lib_timeout_configs, src_eid)
    }

    public(friend) fun has_send_library(sender: address, dst_eid: u32): bool acquires EndpointStore {
        table::contains(&oapp_store(sender).msglibs_send_libs, dst_eid)
    }

    public(friend) fun get_send_library(sender: address, dst_eid: u32): address acquires EndpointStore {
        *table::borrow(&oapp_store(sender).msglibs_send_libs, dst_eid)
    }

    public(friend) fun set_send_library(sender: address, dst_eid: u32, lib: address) acquires EndpointStore {
        table::upsert(&mut oapp_store_mut(sender).msglibs_send_libs, dst_eid, lib);
    }

    public(friend) fun unset_send_library(sender: address, dst_eid: u32): address acquires EndpointStore {
        table::remove(&mut oapp_store_mut(sender).msglibs_send_libs, dst_eid)
    }

    public(friend) fun has_receive_library(receiver: address, src_eid: u32): bool acquires EndpointStore {
        table::contains(&oapp_store(receiver).msglibs_receive_libs, src_eid)
    }

    public(friend) fun get_receive_library(receiver: address, src_eid: u32): address acquires EndpointStore {
        *table::borrow(&oapp_store(receiver).msglibs_receive_libs, src_eid)
    }

    public(friend) fun set_receive_library(
        receiver: address,
        src_eid: u32,
        lib: address,
    ) acquires EndpointStore {
        table::upsert(&mut oapp_store_mut(receiver).msglibs_receive_libs, src_eid, lib);
    }

    public(friend) fun unset_receive_library(receiver: address, src_eid: u32): address acquires EndpointStore {
        table::remove(&mut oapp_store_mut(receiver).msglibs_receive_libs, src_eid)
    }

    public(friend) fun has_receive_library_timeout(receiver: address, src_eid: u32): bool acquires EndpointStore {
        table::contains(&oapp_store(receiver).msglibs_receive_lib_timeout_configs, src_eid)
    }

    public(friend) fun get_receive_library_timeout(receiver: address, src_eid: u32): Timeout acquires EndpointStore {
        *table::borrow(&oapp_store(receiver).msglibs_receive_lib_timeout_configs, src_eid)
    }

    public(friend) fun set_receive_library_timeout(
        receiver: address,
        src_eid: u32,
        config: Timeout,
    ) acquires EndpointStore {
        table::upsert(&mut oapp_store_mut(receiver).msglibs_receive_lib_timeout_configs, src_eid, config);
    }

    public(friend) fun unset_receive_library_timeout(
        receiver: address,
        src_eid: u32,
    ): Timeout acquires EndpointStore {
        table::remove(&mut oapp_store_mut(receiver).msglibs_receive_lib_timeout_configs, src_eid)
    }

    // ================================================== Error Codes =================================================

    const EEMPTY_MODULE_NAME: u64 = 1;
    const ENO_PAYLOAD_HASH: u64 = 2;
    const EUNREGISTERED_OAPP: u64 = 3;
    const EUNREGISTERED_COMPOSER: u64 = 4;
    const EUNREGISTERED_PATHWAY: u64 = 5;
    const EUNSUPPORTED_DST_EID: u64 = 6;
    const EUNSUPPORTED_SRC_EID: u64 = 7;
}
