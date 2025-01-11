/// This module provides the function to compute the GUID for a message
module endpoint_v2_common::guid {
    use endpoint_v2_common::bytes32::{Self, Bytes32};
    use endpoint_v2_common::serde;

    public fun compute_guid(nonce: u64, src_eid: u32, sender: Bytes32, dst_eid: u32, receiver: Bytes32): Bytes32 {
        let guid_bytes = vector[];
        serde::append_u64(&mut guid_bytes, nonce);
        serde::append_u32(&mut guid_bytes, src_eid);
        serde::append_bytes32(&mut guid_bytes, sender);
        serde::append_u32(&mut guid_bytes, dst_eid);
        serde::append_bytes32(&mut guid_bytes, receiver);
        bytes32::keccak256(guid_bytes)
    }
}
