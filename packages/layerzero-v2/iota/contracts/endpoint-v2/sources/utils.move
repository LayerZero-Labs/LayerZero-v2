/// Utility functions for endpoint v2 operations.
module endpoint_v2::utils;

use iota::coin::Coin;
use utils::{buffer_writer, bytes32::Bytes32, hash};

/// Computes a globally unique identifier (GUID) for cross-chain messages.
public fun compute_guid(nonce: u64, src_eid: u32, sender: Bytes32, dst_eid: u32, receiver: Bytes32): Bytes32 {
    let mut writer = buffer_writer::new();
    writer.write_u64(nonce).write_u32(src_eid).write_bytes32(sender).write_u32(dst_eid).write_bytes32(receiver);
    hash::keccak256!(&writer.to_bytes())
}

/// Builds the message payload by concatenating the GUID with the message.
public fun build_payload(guid: Bytes32, message: vector<u8>): vector<u8> {
    let mut writer = buffer_writer::new();
    writer.write_bytes32(guid).write_bytes(message);
    writer.to_bytes()
}

/// Transfers a coin to a recipient, handling zero-value coins gracefully.
/// Zero-value coins are destroyed rather than transferred to avoid unnecessary transactions.
public fun transfer_coin<T>(coin: Coin<T>, recipient: address) {
    if (coin.value() > 0) {
        transfer::public_transfer(coin, recipient);
    } else {
        coin.destroy_zero();
    }
}

/// Transfers an optional coin to a recipient, handling both Some and None cases.
/// If the option contains a coin, it is transferred to the recipient.
/// If the option is None, it is properly destroyed to clean up resources.
public fun transfer_coin_option<T>(coin: Option<Coin<T>>, recipient: address) {
    if (coin.is_some()) {
        transfer_coin(coin.destroy_some(), recipient);
    } else {
        coin.destroy_none();
    }
}
