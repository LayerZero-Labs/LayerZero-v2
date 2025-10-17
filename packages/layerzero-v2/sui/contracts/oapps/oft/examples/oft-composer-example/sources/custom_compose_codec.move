// This module is for tutorial purpose for how composing works in SUI OFT
module oft_composer_example::custom_compose_codec;

use sui::address;
use utils::{buffer_reader, buffer_writer};

public fun encode(recipient: address): vector<u8> {
    let mut writer = buffer_writer::new();
    writer.write_bytes(recipient.to_bytes());
    writer.to_bytes()
}

public fun decode(msg: &vector<u8>): address {
    let mut reader = buffer_reader::create(*msg);
    let recipient = reader.read_bytes32();
    address::from_bytes(recipient.to_bytes())
}
