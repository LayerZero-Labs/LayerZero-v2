module counter::msg_codec {
    use std::option::{Self, Option};
    use std::vector;

    use endpoint_v2_common::serde;

    public inline fun VANILLA_TYPE(): u8 { 1 }

    public inline fun COMPOSED_TYPE(): u8 { 2 }

    public inline fun ABA_TYPE(): u8 { 3 }

    public inline fun COMPOSED_ABA_TYPE(): u8 { 4 }

    const MSG_TYPE_OFFSET: u64 = 0;
    const SRC_EID_OFFSET: u64 = 1;
    const VALUE_OFFSET: u64 = 5;

    public fun encode_msg_type(type: u8, src_eid: u32, value: Option<u128>): vector<u8> {
        let payload = vector[];
        serde::append_u8(&mut payload, type);
        serde::append_u32(&mut payload, src_eid);
        if (option::is_some(&value)) {
            serde::append_u128(&mut payload, *option::borrow(&value));
        };
        payload
    }

    public fun get_msg_type(payload: &vector<u8>): u8 {
        serde::extract_u8(payload, &mut MSG_TYPE_OFFSET)
    }

    public fun get_src_eid(payload: &vector<u8>): u32 {
        serde::extract_u32(payload, &mut SRC_EID_OFFSET)
    }

    public fun get_value(payload: &vector<u8>): Option<u128> {
        if (vector::length(payload) > (VALUE_OFFSET as u64)) {
            let value = serde::extract_u128(payload, &mut VALUE_OFFSET);
            option::some(value)
        } else {
            option::none()
        }
    }
}