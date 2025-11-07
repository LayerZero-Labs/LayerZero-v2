module worker_common::worker_info_v1;

use iota::bcs;
use utils::{buffer_reader, buffer_writer};

// === Constants ===

const WORKER_INFO_VERSION: u16 = 1;

// === Errors ===

const EInvalidData: u64 = 1;
const EInvalidVersion: u64 = 2;

// === Structs ===

public struct WorkerInfoV1 has copy, drop, store {
    worker_id: u8,
    worker_info: vector<u8>,
}

// === Creation Functions ===

/// Create a new worker info with the given worker type and worker payload
///
/// **Parameters**:
/// - `worker_id`: the type of worker
/// - `worker_info`: the information of the worker
///
/// **Returns**: a new worker info v1 instance
public fun create(worker_id: u8, worker_info: vector<u8>): WorkerInfoV1 {
    WorkerInfoV1 { worker_id, worker_info }
}

// === View Functions ===

/// Returns the type of worker
public fun worker_id(self: &WorkerInfoV1): u8 {
    self.worker_id
}

/// Returns the payload of the worker
public fun worker_info(self: &WorkerInfoV1): &vector<u8> {
    &self.worker_info
}

// === Serialization Functions ===

/// Encodes the worker info into a versioned byte vector for storage or transmission
public fun encode(self: &WorkerInfoV1): vector<u8> {
    let mut writer = buffer_writer::new();
    writer.write_u16(WORKER_INFO_VERSION).write_bytes(bcs::to_bytes(self));
    writer.to_bytes()
}

/// Decodes a byte vector back into a worker info v1 instance
public fun decode(worker_info: vector<u8>): WorkerInfoV1 {
    let mut reader = buffer_reader::create(worker_info);
    let version = reader.read_u16();
    assert!(version == WORKER_INFO_VERSION, EInvalidVersion);
    let worker_info_bytes = reader.read_bytes_until_end();
    let mut bcs_reader = bcs::new(worker_info_bytes);
    let worker_id = bcs_reader.peel_u8();
    let worker_info = bcs_reader.peel_vec_u8();
    assert!(bcs_reader.into_remainder_bytes().is_empty(), EInvalidData);
    WorkerInfoV1 { worker_id, worker_info }
}
