/// Executor Get Fee Module
///
/// This module defines parameters for querying executor fees. It provides the data
/// structure needed to request fee calculations from executors for cross-chain
/// message execution.
module uln_common::executor_get_fee;

// === Structs ===

/// Parameters for executor fee calculation requests.
public struct GetFeeParam has copy, drop, store {
    // Destination endpoint ID where the message will be executed
    dst_eid: u32,
    // Address of the message sender on the source chain
    sender: address,
    // Size of the calldata that will be executed (in bytes)
    calldata_size: u64,
    // Execution options (e.g. lz_receive_option)
    options: vector<u8>,
}

// === Creation ===

/// Creates a new GetFeeParam with the specified parameters.
public fun create_param(dst_eid: u32, sender: address, calldata_size: u64, options: vector<u8>): GetFeeParam {
    GetFeeParam { dst_eid, sender, calldata_size, options }
}

// === Getters ===

/// Returns the destination endpoint ID.
public fun dst_eid(self: &GetFeeParam): u32 {
    self.dst_eid
}

/// Returns the sender address.
public fun sender(self: &GetFeeParam): address {
    self.sender
}

/// Returns the calldata size in bytes.
public fun calldata_size(self: &GetFeeParam): u64 {
    self.calldata_size
}

/// Returns a reference to the execution options.
public fun options(self: &GetFeeParam): &vector<u8> {
    &self.options
}
