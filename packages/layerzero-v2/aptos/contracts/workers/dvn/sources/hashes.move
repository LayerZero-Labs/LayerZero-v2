/// These functions are used to generate hashes against which signatures are created and verified
module dvn::hashes {
    use std::aptos_hash;
    use std::vector;

    use endpoint_v2_common::bytes32::{Bytes32, keccak256};
    use endpoint_v2_common::serde;

    // ================================================ Hash Generation ===============================================

    // These hashes are used by the DVN Multisig as an input to signature generation

    #[view]
    /// Get a 4-byte hash that represents a given function name
    public fun get_function_signature(function_name: vector<u8>): vector<u8> {
        vector::slice(&aptos_hash::keccak256(std::bcs::to_bytes(&function_name)), 0, 4)
    }

    #[view]
    /// Create a hash for a verify function call
    public fun create_verify_hash(
        packet_header: vector<u8>,
        payload_hash: vector<u8>,
        confirmations: u64,
        target: address,
        vid: u32,
        expiration: u64,
    ): Bytes32 {
        keccak256(build_verify_payload(packet_header, payload_hash, confirmations, target, vid, expiration))
    }

    #[view]
    /// Create a hash for a set_quorum function call
    public fun create_set_quorum_hash(quorum: u64, vid: u32, expiration: u64): Bytes32 {
        keccak256(build_set_quorum_payload(quorum, vid, expiration))
    }

    #[view]
    /// Create a hash for a set_dvn_signer function call
    public fun create_set_dvn_signer_hash(dvn_signer: vector<u8>, active: bool, vid: u32, expiration: u64): Bytes32 {
        keccak256(build_set_dvn_signer_payload(dvn_signer, active, vid, expiration))
    }

    #[view]
    /// Create a hash for a set_allowlist function call
    public fun create_set_allowlist_hash(sender: address, allowed: bool, vid: u32, expiration: u64): Bytes32 {
        keccak256(build_set_allowlist_payload(sender, allowed, vid, expiration))
    }

    #[view]
    /// Create a hash for a set_denylist function call
    public fun create_set_denylist_hash(sender: address, denied: bool, vid: u32, expiration: u64): Bytes32 {
        keccak256(build_set_denylist_payload(sender, denied, vid, expiration))
    }

    #[view]
    /// Create a hash for a quorum_change_admin function call
    public fun create_quorum_change_admin_hash(
        admin: address,
        active: bool,
        vid: u32,
        expiration: u64,
    ): Bytes32 {
        keccak256(build_quorum_change_admin_payload(admin, active, vid, expiration))
    }

    #[view]
    /// Create a hash for a set_msglibs function call
    public fun create_set_msglibs_hash(msglibs: vector<address>, vid: u32, expiration: u64): Bytes32 {
        keccak256(build_set_msglibs_payload(msglibs, vid, expiration))
    }

    #[view]
    public fun create_set_fee_lib_hash(fee_lib: address, vid: u32, expiration: u64): Bytes32 {
        keccak256(build_set_fee_lib_payload(fee_lib, vid, expiration))
    }

    #[view]
    public fun create_set_pause_hash(pause: bool, vid: u32, expiration: u64): Bytes32 {
        keccak256(build_set_pause_payload(pause, vid, expiration))
    }

    // ============================================== Payload Generation ==============================================

    // Payloads are serialized data that are hashed to create a hash that can be signed by a worker

    #[view]
    /// Build the serialized payload for a verify function call (for procuring a hash)
    public fun build_verify_payload(
        packet_header: vector<u8>,
        payload_hash: vector<u8>,
        confirmations: u64,
        target: address,
        vid: u32,
        expiration: u64,
    ): vector<u8> {
        let payload = vector[];
        serde::append_bytes(&mut payload, get_function_signature(b"verify"));
        serde::append_bytes(&mut payload, packet_header);
        serde::append_bytes(&mut payload, payload_hash);
        serde::append_u64(&mut payload, confirmations);
        serde::append_bytes(&mut payload, std::bcs::to_bytes(&target));
        serde::append_u32(&mut payload, vid);
        serde::append_u64(&mut payload, expiration);
        payload
    }

    #[view]
    /// Build the serialized payload for a set_quorum function call (for procuring a hash)
    public fun build_set_quorum_payload(quorum: u64, vid: u32, expiration: u64): vector<u8> {
        let payload = vector[];
        serde::append_bytes(&mut payload, get_function_signature(b"set_quorum"));
        serde::append_u64(&mut payload, quorum);
        serde::append_u32(&mut payload, vid);
        serde::append_u64(&mut payload, expiration);
        payload
    }

    #[view]
    /// Build the serialized payload for a set_dvn_signer function call (for procuring a hash)
    public fun build_set_dvn_signer_payload(
        dvn_signer: vector<u8>,
        active: bool,
        vid: u32,
        expiration: u64,
    ): vector<u8> {
        let active_value: u8 = if (active) 1 else 0;
        let payload = vector[];
        serde::append_bytes(&mut payload, get_function_signature(b"set_dvn_signer"));
        serde::append_bytes(&mut payload, dvn_signer);
        serde::append_u8(&mut payload, active_value);
        serde::append_u32(&mut payload, vid);
        serde::append_u64(&mut payload, expiration);
        payload
    }

    #[view]
    /// Build the serialized payload for a set_allowlist function call (for procuring a hash)
    public fun build_set_allowlist_payload(sender: address, allowed: bool, vid: u32, expiration: u64): vector<u8> {
        let allowed_value: u8 = if (allowed) 1 else 0;
        let payload = vector[];
        serde::append_bytes(&mut payload, get_function_signature(b"set_allowlist"));
        serde::append_bytes(&mut payload, std::bcs::to_bytes(&sender));
        serde::append_u8(&mut payload, allowed_value);
        serde::append_u32(&mut payload, vid);
        serde::append_u64(&mut payload, expiration);
        payload
    }

    #[view]
    /// Build the serialized payload for a set_denylist function call (for procuring a hash)
    public fun build_set_denylist_payload(sender: address, denied: bool, vid: u32, expiration: u64): vector<u8> {
        let denied_value: u8 = if (denied) 1 else 0;
        let payload = vector[];
        serde::append_bytes(&mut payload, get_function_signature(b"set_denylist"));
        serde::append_bytes(&mut payload, std::bcs::to_bytes(&sender));
        serde::append_u8(&mut payload, denied_value);
        serde::append_u32(&mut payload, vid);
        serde::append_u64(&mut payload, expiration);
        payload
    }

    #[view]
    /// Build the serialized payload for a quorum_change_admin function call (for procuring a hash)
    public fun build_quorum_change_admin_payload(
        admin: address,
        active: bool,
        vid: u32,
        expiration: u64,
    ): vector<u8> {
        let active_value: u8 = if (active) 1 else 0;
        let payload = vector[];
        serde::append_bytes(&mut payload, get_function_signature(b"quorum_change_admin"));
        serde::append_bytes(&mut payload, std::bcs::to_bytes(&admin));
        serde::append_u8(&mut payload, active_value);
        serde::append_u32(&mut payload, vid);
        serde::append_u64(&mut payload, expiration);
        payload
    }

    #[view]
    /// Build the serialized payload for a set_msglibs function call (for procuring a hash)
    public fun build_set_msglibs_payload(msglibs: vector<address>, vid: u32, expiration: u64): vector<u8> {
        let payload = vector[];
        serde::append_bytes(&mut payload, get_function_signature(b"set_msglibs"));
        for (i in 0..vector::length(&msglibs)) {
            let msglib = *vector::borrow(&msglibs, i);
            serde::append_address(&mut payload, msglib);
        };
        serde::append_u32(&mut payload, vid);
        serde::append_u64(&mut payload, expiration);
        payload
    }

    #[view]
    public fun build_set_fee_lib_payload(fee_lib: address, vid: u32, expiration: u64): vector<u8> {
        let payload = vector[];
        serde::append_bytes(&mut payload, get_function_signature(b"set_fee_lib"));
        serde::append_address(&mut payload, fee_lib);
        serde::append_u32(&mut payload, vid);
        serde::append_u64(&mut payload, expiration);
        payload
    }

    #[view]
    public fun build_set_pause_payload(pause: bool, vid: u32, expiration: u64): vector<u8> {
        let payload = vector[];
        serde::append_bytes(&mut payload, get_function_signature(b"set_pause"));
        serde::append_u8(&mut payload, if (pause) 1 else 0);
        serde::append_u32(&mut payload, vid);
        serde::append_u64(&mut payload, expiration);
        payload
    }
}
