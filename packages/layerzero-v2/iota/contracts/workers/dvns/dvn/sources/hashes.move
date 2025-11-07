/// These functions are used to generate hashes against which signatures are created and verified
module dvn::hashes;

use ptb_move_call::move_call::MoveCall;
use iota::bcs;
use utils::{buffer_writer, bytes32::Bytes32, hash};

// ================================================ Hash Generation ===============================================

// These hashes are used by the DVN Multisig as an input to signature generation

/// Get a 4-byte function signature hash for a given function name
public fun get_function_signature(function_name: vector<u8>): vector<u8> {
    let full_hash_bytes = hash::keccak256!(&bcs::to_bytes(&function_name)).to_bytes();
    vector::tabulate!(4, |i| full_hash_bytes[i])
}

/// Create a hash for a verify function call
public fun create_verify_hash(
    packet_header: vector<u8>,
    payload_hash: vector<u8>,
    confirmations: u64,
    target: address,
    vid: u32,
    expiration: u64,
): Bytes32 {
    let payload = build_verify_payload(packet_header, payload_hash, confirmations, target, vid, expiration);
    hash::keccak256!(&payload)
}

/// Create a hash for a set_dvn_signer function call
public fun create_set_dvn_signer_hash(signer: vector<u8>, active: bool, vid: u32, expiration: u64): Bytes32 {
    let payload = build_set_dvn_signer_payload(signer, active, vid, expiration);
    hash::keccak256!(&payload)
}

/// Create a hash for a set_quorum function call
public fun create_set_quorum_hash(quorum: u64, vid: u32, expiration: u64): Bytes32 {
    let payload = build_set_quorum_payload(quorum, vid, expiration);
    hash::keccak256!(&payload)
}

/// Create a hash for a quorum_change_admin function call
public fun create_quorum_change_admin_hash(admin: address, active: bool, vid: u32, expiration: u64): Bytes32 {
    let payload = build_quorum_change_admin_payload(admin, active, vid, expiration);
    hash::keccak256!(&payload)
}

/// Create a hash for a set_supported_message_lib function call
public fun create_set_supported_message_lib_hash(
    message_lib: address,
    supported: bool,
    vid: u32,
    expiration: u64,
): Bytes32 {
    let payload = build_set_supported_message_lib_payload(message_lib, supported, vid, expiration);
    hash::keccak256!(&payload)
}

/// Create a hash for a set_allowlist function call
public fun create_set_allowlist_hash(oapp: address, allowed: bool, vid: u32, expiration: u64): Bytes32 {
    let payload = build_set_allowlist_payload(oapp, allowed, vid, expiration);
    hash::keccak256!(&payload)
}

/// Create a hash for a set_denylist function call
public fun create_set_denylist_hash(oapp: address, denied: bool, vid: u32, expiration: u64): Bytes32 {
    let payload = build_set_denylist_payload(oapp, denied, vid, expiration);
    hash::keccak256!(&payload)
}

/// Create a hash for a set_pause function call
public fun create_set_pause_hash(paused: bool, vid: u32, expiration: u64): Bytes32 {
    let payload = build_set_pause_payload(paused, vid, expiration);
    hash::keccak256!(&payload)
}

/// Create a hash for a set_ptb_builder_move_calls function call
public fun create_set_ptb_builder_move_calls_hash(
    target_ptb_builder: address,
    get_fee_move_calls: vector<MoveCall>,
    assign_job_move_calls: vector<MoveCall>,
    vid: u32,
    expiration: u64,
): Bytes32 {
    let payload = build_set_ptb_builder_move_calls_payload(
        target_ptb_builder,
        get_fee_move_calls,
        assign_job_move_calls,
        vid,
        expiration,
    );
    hash::keccak256!(&payload)
}

/// Create a hash for a set_worker_info function call
public fun create_set_worker_info_hash(worker_info: vector<u8>, vid: u32, expiration: u64): Bytes32 {
    let payload = build_set_worker_info_payload(worker_info, vid, expiration);
    hash::keccak256!(&payload)
}

// ============================================== Payload Generation ==============================================

// Payloads are serialized data that are hashed to create a hash that can be signed by a worker

/// Build the serialized payload for a verify function call (for procuring a hash)
public fun build_verify_payload(
    packet_header: vector<u8>,
    payload_hash: vector<u8>,
    confirmations: u64,
    target: address,
    vid: u32,
    expiration: u64,
): vector<u8> {
    let mut writer = buffer_writer::new();
    writer
        .write_bytes(get_function_signature(b"verify"))
        .write_bytes(packet_header)
        .write_bytes(payload_hash)
        .write_u64(confirmations)
        .write_address(target)
        .write_u32(vid)
        .write_u64(expiration);
    writer.to_bytes()
}

/// Build the serialized payload for a set_dvn_signer function call (for procuring a hash)
public fun build_set_dvn_signer_payload(signer: vector<u8>, active: bool, vid: u32, expiration: u64): vector<u8> {
    let mut writer = buffer_writer::new();
    writer
        .write_bytes(get_function_signature(b"set_dvn_signer"))
        .write_bytes(signer)
        .write_bool(active)
        .write_u32(vid)
        .write_u64(expiration);
    writer.to_bytes()
}

/// Build the serialized payload for a set_quorum function call (for procuring a hash)
public fun build_set_quorum_payload(quorum: u64, vid: u32, expiration: u64): vector<u8> {
    let mut writer = buffer_writer::new();
    writer.write_bytes(get_function_signature(b"set_quorum")).write_u64(quorum).write_u32(vid).write_u64(expiration);
    writer.to_bytes()
}

/// Build the serialized payload for a quorum_change_admin function call (for procuring a hash)
public fun build_quorum_change_admin_payload(admin: address, active: bool, vid: u32, expiration: u64): vector<u8> {
    let mut writer = buffer_writer::new();
    writer
        .write_bytes(get_function_signature(b"quorum_change_admin"))
        .write_address(admin)
        .write_bool(active)
        .write_u32(vid)
        .write_u64(expiration);
    writer.to_bytes()
}

/// Build the serialized payload for a set_supported_message_lib function call (for procuring a hash)
public fun build_set_supported_message_lib_payload(
    message_lib: address,
    supported: bool,
    vid: u32,
    expiration: u64,
): vector<u8> {
    let mut writer = buffer_writer::new();
    writer
        .write_bytes(get_function_signature(b"set_supported_message_lib"))
        .write_address(message_lib)
        .write_bool(supported)
        .write_u32(vid)
        .write_u64(expiration);
    writer.to_bytes()
}

/// Build the serialized payload for a set_allowlist function call (for procuring a hash)
public fun build_set_allowlist_payload(oapp: address, allowed: bool, vid: u32, expiration: u64): vector<u8> {
    let mut writer = buffer_writer::new();
    writer
        .write_bytes(get_function_signature(b"set_allowlist"))
        .write_address(oapp)
        .write_bool(allowed)
        .write_u32(vid)
        .write_u64(expiration);
    writer.to_bytes()
}

/// Build the serialized payload for a set_denylist function call (for procuring a hash)
public fun build_set_denylist_payload(oapp: address, denied: bool, vid: u32, expiration: u64): vector<u8> {
    let mut writer = buffer_writer::new();
    writer
        .write_bytes(get_function_signature(b"set_denylist"))
        .write_address(oapp)
        .write_bool(denied)
        .write_u32(vid)
        .write_u64(expiration);
    writer.to_bytes()
}

/// Build the serialized payload for a set_pause function call (for procuring a hash)
public fun build_set_pause_payload(paused: bool, vid: u32, expiration: u64): vector<u8> {
    let mut writer = buffer_writer::new();
    writer.write_bytes(get_function_signature(b"set_pause")).write_bool(paused).write_u32(vid).write_u64(expiration);
    writer.to_bytes()
}

/// Build the serialized payload for a set_ptb_builder_move_calls function call (for procuring a hash)
public fun build_set_ptb_builder_move_calls_payload(
    target_ptb_builder: address,
    get_fee_move_calls: vector<MoveCall>,
    assign_job_move_calls: vector<MoveCall>,
    vid: u32,
    expiration: u64,
): vector<u8> {
    let mut writer = buffer_writer::new();
    writer
        .write_bytes(get_function_signature(b"set_ptb_builder_move_calls"))
        .write_address(target_ptb_builder)
        .write_bytes(hash::keccak256!(&bcs::to_bytes(&get_fee_move_calls)).to_bytes())
        .write_bytes(hash::keccak256!(&bcs::to_bytes(&assign_job_move_calls)).to_bytes())
        .write_u32(vid)
        .write_u64(expiration);
    writer.to_bytes()
}

/// Build the serialized payload for a set_worker_info function call (for procuring a hash)
public fun build_set_worker_info_payload(worker_info: vector<u8>, vid: u32, expiration: u64): vector<u8> {
    let mut writer = buffer_writer::new();
    writer
        .write_bytes(get_function_signature(b"set_worker_info"))
        .write_bytes(hash::keccak256!(&worker_info).to_bytes())
        .write_u32(vid)
        .write_u64(expiration);
    writer.to_bytes()
}
