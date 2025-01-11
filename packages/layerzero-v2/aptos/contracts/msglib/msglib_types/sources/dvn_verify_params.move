/// These DVN Verify Params are used to verify the DVN packet for ULN302.
/// The format of this may change in future Message Libraries, so is sent through the Message Library router as an
/// `Any` type to ensure the format can be upgraded for future Message Libraries.
module msglib_types::dvn_verify_params {
    use std::any::{Self, Any};

    use endpoint_v2_common::bytes32::Bytes32;
    use endpoint_v2_common::packet_raw::RawPacket;

    struct DvnVerifyParams has drop, store {
        packet_header: RawPacket,
        payload_hash: Bytes32,
        confirmations: u64,
    }

    public fun pack_dvn_verify_params(
        packet_header: RawPacket,
        payload_hash: Bytes32,
        confirmations: u64,
    ): Any {
        any::pack(DvnVerifyParams { packet_header, payload_hash, confirmations })
    }

    public fun unpack_dvn_verify_params(params: Any): (RawPacket, Bytes32, u64) {
        let params = any::unpack<DvnVerifyParams>(params);
        let DvnVerifyParams { packet_header, payload_hash, confirmations } = params;
        (packet_header, payload_hash, confirmations)
    }
}
