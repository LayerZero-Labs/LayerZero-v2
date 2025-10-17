module counter::msg_codec;

use utils::{buffer_reader, buffer_writer};

const MSG_TYPE_OFFSET: u64 = 0;
const SRC_EID_OFFSET: u64 = 1;
const VALUE_OFFSET: u64 = 5;

public fun encode_msg(msg_type: u8, src_eid: u32, value: u256): vector<u8> {
    let mut writer = buffer_writer::new();
    writer.write_u8(msg_type).write_u32(src_eid);
    if (value > 0) {
        writer.write_u256(value);
    };
    writer.to_bytes()
}

#[allow(implicit_const_copy)]
public fun get_msg_type(payload: &vector<u8>): u8 {
    buffer_reader::create(*payload).skip(MSG_TYPE_OFFSET).read_u8()
}

#[allow(implicit_const_copy)]
public fun get_src_eid(payload: &vector<u8>): u32 {
    buffer_reader::create(*payload).skip(SRC_EID_OFFSET).read_u32()
}

#[allow(implicit_const_copy)]
public fun get_value(payload: &vector<u8>): u256 {
    if (payload.length() > (VALUE_OFFSET as u64)) {
        let reader = buffer_reader::create(*payload).skip(VALUE_OFFSET);
        reader.read_u256()
    } else {
        0
    }
}
