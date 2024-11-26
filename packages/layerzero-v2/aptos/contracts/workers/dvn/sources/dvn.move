module dvn::dvn {
    use std::signer::address_of;
    use std::vector;

    use dvn::hashes::{
        create_quorum_change_admin_hash,
        create_set_allowlist_hash,
        create_set_denylist_hash,
        create_set_dvn_signer_hash,
        create_set_fee_lib_hash,
        create_set_msglibs_hash,
        create_set_pause_hash,
        create_set_quorum_hash,
        create_verify_hash,
    };
    use endpoint_v2_common::bytes32;
    use endpoint_v2_common::contract_identity::{Self, CallRef, ContractSigner, DynamicCallRef, make_call_ref};
    use endpoint_v2_common::packet_raw;
    use endpoint_v2_common::universal_config;
    use msglib_types::worker_options::DVN_WORKER_ID;
    use router_node_0::router_node;
    use worker_common::multisig::{Self, assert_all_and_add_to_history};
    use worker_common::worker_config;

    #[test_only]
    friend dvn::dvn_tests;

    struct DvnStore has key {
        contract_signer: ContractSigner,
    }

    /// Initialize the DVN Store
    fun init_module(account: &signer) {
        move_to(account, DvnStore { contract_signer: contract_identity::create_contract_signer(account) });
    }

    #[test_only]
    /// Initialize the DVN Store for testing
    public fun init_module_for_test() {
        init_module(&std::account::create_signer_for_test(@dvn));
    }

    /// Worker-only function to register and configure the DVN. This can only be called once, and should be called with
    /// the contract (@dvn) as the signer.
    public entry fun initialize(
        account: &signer,
        deposit_address: address,
        admins: vector<address>,
        dvn_signers: vector<vector<u8>>,
        quorum: u64,
        supported_msglibs: vector<address>,
        fee_lib: address,
    ) {
        assert!(address_of(account) == @dvn, EUNAUTHORIZED);
        assert!(vector::length(&supported_msglibs) > 0, EDVN_MSGLIB_LESS_THAN_ONE);

        worker_config::initialize_for_worker(
            account,
            DVN_WORKER_ID(),
            deposit_address,
            // Instead of a role admin, this DVN allows regular admins or signers (quorum_change_admin()) to add or
            // remove admins
            @0x0,
            admins,
            supported_msglibs,
            fee_lib,
        );
        multisig::initialize_for_worker(move account, quorum, dvn_signers);
    }

    // ================================== Protocol: DVN Verify (Admin /w Signatures) ==================================

    /// DVNs call dvn_verify() in uln_302/router_calls.move to verify a packet
    /// Only admins can call this function and it requires a quorum of dvn_signer signatures to succeed
    public entry fun verify(
        account: &signer,
        packet_header: vector<u8>,
        payload_hash: vector<u8>,
        confirmations: u64,
        msglib: address,
        expiration: u64,
        signatures: vector<u8>,
    ) acquires DvnStore {
        assert_admin(address_of(move account));
        let packet_header_raw = packet_raw::bytes_to_raw_packet(packet_header);
        let hash = create_verify_hash(
            packet_header,
            payload_hash,
            confirmations,
            msglib,
            get_vid(),
            expiration,
        );
        assert_all_and_add_to_history(call_ref(), &signatures, expiration, hash);
        let dvn_verify_params = msglib_types::dvn_verify_params::pack_dvn_verify_params(
            packet_header_raw,
            bytes32::to_bytes32(payload_hash),
            confirmations,
        );
        router_node::dvn_verify(msglib, dynamic_call_ref(msglib, b"dvn_verify"), dvn_verify_params);
    }

    // ================================================== Admin Only ==================================================

    /// Add or remove an admin. `active` is true to add, false to remove.
    /// Admins are required to call the majority of DVN non-view actions, including verifying messages.
    public entry fun set_admin(account: &signer, admin: address, active: bool) acquires DvnStore {
        assert_admin(address_of(move account));
        worker_config::set_worker_admin(call_ref(), admin, active);
    }


    /// Set the deposit address for the DVN (must be real account)
    /// The message library is instructed to send DVN fees to this address
    public entry fun set_deposit_address(account: &signer, deposit_address: address) acquires DvnStore {
        assert_admin(address_of(move account));
        worker_config::set_deposit_address(call_ref(), deposit_address);
    }

    /// Set the configuration for a specific destination EID
    public entry fun set_dst_config(
        account: &signer,
        remote_eid: u32,
        gas: u64,
        multiplier_bps: u16,
        floor_margin_usd: u128,
    ) acquires DvnStore {
        assert_admin(address_of(move account));
        worker_config::set_dvn_dst_config(call_ref(), remote_eid, gas, multiplier_bps, floor_margin_usd);
    }

    /// Sets the price feed module address and the feed address for the dvn
    public entry fun set_price_feed(
        account: &signer,
        price_feed: address,
        feed_address: address,
    ) acquires DvnStore {
        assert_admin(address_of(move account));
        worker_config::set_price_feed(call_ref(), price_feed, feed_address);
    }

    // =========================================== Admin /w Signatures Only ===========================================

    /// Add or remove a dvn signer (public key)
    /// This will abort if it results in fewer signers than the quorum
    public entry fun set_dvn_signer(
        account: &signer,
        dvn_signer: vector<u8>,
        active: bool,
        expiration: u64,
        signatures: vector<u8>,
    ) acquires DvnStore {
        assert_admin(address_of(move account));
        let hash = create_set_dvn_signer_hash(dvn_signer, active, get_vid(), expiration);
        assert_all_and_add_to_history(call_ref(), &signatures, expiration, hash);
        multisig::set_signer(call_ref(), dvn_signer, active);
    }

    /// Update the quorum threshold
    /// This will abort if the new quorum is greater than the number of registered dvn signers
    public entry fun set_quorum(
        account: &signer,
        quorum: u64,
        expiration: u64,
        signatures: vector<u8>,
    ) acquires DvnStore {
        assert_admin(address_of(move account));
        let hash = create_set_quorum_hash(quorum, get_vid(), expiration);
        assert_all_and_add_to_history(call_ref(), &signatures, expiration, hash);
        multisig::set_quorum(call_ref(), quorum);
    }

    /// Add or remove a sender address from the allowlist
    /// When the allowlist has as least one entry, only senders on the allowlist can send messages to the DVN
    /// When the allowlist is empty, only denylist senders will be rejected
    /// The allowlist and the denylist are enforced upon get fee
    public entry fun set_allowlist(
        account: &signer,
        oapp: address,
        allowed: bool,
        expiration: u64,
        signatures: vector<u8>,
    ) acquires DvnStore {
        assert_admin(address_of(move account));
        let hash = create_set_allowlist_hash(oapp, allowed, get_vid(), expiration);
        assert_all_and_add_to_history(call_ref(), &signatures, expiration, hash);
        worker_config::set_allowlist(call_ref(), oapp, allowed);
    }

    /// Add or remove an oapp sender address from the denylist
    /// A denylisted sender will be rejected by the DVN regardless of the allowlist status
    /// The allowlist and the denylist are enforced upon get fee
    public entry fun set_denylist(
        account: &signer,
        oapp: address,
        denied: bool,
        expiration: u64,
        signatures: vector<u8>,
    ) acquires DvnStore {
        assert_admin(address_of(move account));
        let hash = create_set_denylist_hash(oapp, denied, get_vid(), expiration);
        assert_all_and_add_to_history(call_ref(), &signatures, expiration, hash);
        worker_config::set_denylist(call_ref(), oapp, denied);
    }

    /// Set the supported message libraries for the DVN
    /// The list provided will completely replace the existing list
    public entry fun set_supported_msglibs(
        account: &signer,
        msglibs: vector<address>,
        expiration: u64,
        signatures: vector<u8>,
    ) acquires DvnStore {
        assert_admin(address_of(move account));
        let hash = create_set_msglibs_hash(msglibs, get_vid(), expiration);
        assert_all_and_add_to_history(call_ref(), &signatures, expiration, hash);
        worker_config::set_supported_msglibs(call_ref(), msglibs);
    }

    /// Set the fee lib for the DVN
    /// The fee lib will be used by the Message Library to route the call to the correct DVN Fee Lib
    public entry fun set_fee_lib(
        account: &signer,
        fee_lib: address,
        expiration: u64,
        signatures: vector<u8>,
    ) acquires DvnStore {
        assert_admin(address_of(move account));
        let hash = create_set_fee_lib_hash(fee_lib, get_vid(), expiration);
        assert_all_and_add_to_history(call_ref(), &signatures, expiration, hash);
        worker_config::set_worker_fee_lib(call_ref(), fee_lib);
    }

    // Pause or unpause the DVN
    public entry fun set_pause(
        account: &signer,
        pause: bool,
        expiration: u64,
        signatures: vector<u8>,
    ) acquires DvnStore {
        assert_admin(address_of(move account));
        let hash = create_set_pause_hash(pause, get_vid(), expiration);
        assert_all_and_add_to_history(call_ref(), &signatures, expiration, hash);
        worker_config::set_worker_pause(call_ref(), pause);
    }

    // ================================================= Signers Only =================================================

    /// Add or remove an admin using a quorum of dvn signers
    public entry fun quorum_change_admin(
        admin: address,
        active: bool,
        expiration: u64,
        signatures: vector<u8>,
    ) acquires DvnStore {
        let hash = create_quorum_change_admin_hash(admin, active, get_vid(), expiration);
        assert_all_and_add_to_history(call_ref(), &signatures, expiration, hash);
        worker_config::set_worker_admin(call_ref(), admin, active);
    }

    // ================================================ View Functions ================================================

    #[view]
    /// Returns the admins of the DVN
    public fun get_admins(): vector<address> {
        worker_config::get_worker_admins(@dvn)
    }

    #[view]
    /// Returns whether the account is an admin of the DVN
    public fun is_admin(account: address): bool { worker_config::is_worker_admin(@dvn, account) }

    #[view]
    /// Returns whether the worker is paused
    public fun is_paused(): bool { worker_config::is_worker_paused(@dvn) }

    #[view]
    /// Returns the deposit address for the DVN. The message library will send fees to this address
    public fun get_deposit_address(): address {
        worker_config::get_deposit_address(@dvn)
    }

    #[view]
    /// Returns whether a particular signer (public key) is one of the DVN signers
    public fun is_dvn_signer(signer: vector<u8>): bool { multisig::is_signer(@dvn, signer) }

    #[view]
    /// Returns the fee library selected for this DVN
    public fun get_fee_lib(): address {
        worker_config::get_worker_fee_lib(@dvn)
    }

    #[view]
    /// Returns the quorum count required by this DVN
    public fun get_quorum(): u64 { multisig::get_quorum(@dvn) }

    #[view]
    /// Returns the list of supported message libraries for the DVN
    public fun get_supported_msglibs(): vector<address> { worker_config::get_supported_msglibs(@dvn) }

    #[view]
    /// Returns the fee lib for the DVN
    public fun get_worker_fee_lib(): address {
        let fee_lib = worker_config::get_worker_fee_lib(@dvn);
        fee_lib
    }

    #[view]
    /// Returns the default multiplier bps for the premium calculation
    public fun get_default_multiplier_bps(): u16 {
        worker_config::get_default_multiplier_bps(@dvn)
    }

    #[view]
    /// Returns the supported option types for the DVN
    public fun get_supported_option_types(): vector<u8> {
        worker_config::get_supported_option_types(@dvn)
    }

    #[view]
    /// Returns whether a particular sender is on the allowlist
    public fun allowlist_contains(sender: address): bool { worker_config::allowlist_contains(@dvn, sender) }

    #[view]
    /// Returns whether a particular sender is on the denylist
    public fun denylist_contains(sender: address): bool { worker_config::denylist_contains(@dvn, sender) }

    #[view]
    /// Returns whether the sender is allowed to send messages to the DVN based on allowlist and denylist
    public fun is_allowed(sender: address): bool { worker_config::is_allowed(@dvn, sender) }

    #[view]
    /// Returns the DVN config values for the destination EID
    /// @returns (gas, multiplier_bps, floor_margin_usd)
    public fun get_dst_config(dst_eid: u32): (u64, u16, u128) {
        worker_config::get_dvn_dst_config_values(@dvn, dst_eid)
    }

    #[view]
    /// Returns the VID for the DVN
    public fun get_vid(): u32 {
        universal_config::eid() % 30_000
    }

    #[view]
    /// Get the number of other workers that are currently delegating to this dvn's price feed configuration
    public fun get_count_price_feed_delegate_dependents(): u64 {
        worker_config::get_count_price_feed_delegate_dependents(@dvn)
    }

    // ==================================================== Helpers ===================================================

    /// Derive a call ref for the DVN worker for a given target contract
    inline fun dynamic_call_ref(target_contract: address, authorization: vector<u8>): &DynamicCallRef {
        &contract_identity::make_dynamic_call_ref(&store().contract_signer, target_contract, authorization)
    }

    /// Get a Call Ref directed at the worker common contract
    inline fun call_ref<Target>(): &CallRef<Target> {
        &make_call_ref(&store().contract_signer)
    }

    /// Borrow the DVN Store
    inline fun store(): &DvnStore { borrow_global(@dvn) }

    /// Borrow a mutable DVN store
    inline fun store_mut(): &mut DvnStore { borrow_global_mut(@dvn) }

    // ==================================================== Internal ===================================================

    /// Assert that the caller is an admin
    inline fun assert_admin(admin: address) {
        worker_config::assert_worker_admin(@dvn, admin);
    }

    /// Assert that the VID for the DVN is the expected VID for this chain
    /// VID is a endpoint v1-v2 compatible eid e.g. 30101 -> 101
    inline fun assert_vid(vid: u32) {
        assert!(get_vid() == vid, EDVN_INVALID_VID);
    }

    // ================================================== Error Codes =================================================

    const EDVN_INVALID_VID: u64 = 2;
    const EDVN_MSGLIB_LESS_THAN_ONE: u64 = 3;
    const EUNAUTHORIZED: u64 = 4;
}
