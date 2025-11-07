/// Native drop type definitions for Executor
module executor::native_drop_type;

/// Native drop parameters
public struct NativeDropParams has copy, drop, store {
    receiver: address,
    amount: u64,
}

// === Constructor Functions ===

/// Create a new NativeDropParams
public fun new_native_drop_params(receiver: address, amount: u64): NativeDropParams {
    NativeDropParams {
        receiver,
        amount,
    }
}

// === Getter Functions ===

public use fun native_drop_params_receiver as NativeDropParams.receiver;

/// Get receiver from NativeDropParams
public fun native_drop_params_receiver(params: &NativeDropParams): address {
    params.receiver
}

public use fun native_drop_params_amount as NativeDropParams.amount;

/// Get amount from NativeDropParams
public fun native_drop_params_amount(params: &NativeDropParams): u64 {
    params.amount
}

// === Unpack Functions ===

/// Unpack NativeDropParams
public fun unpack_native_drop_params(params: NativeDropParams): (address, u64) {
    let NativeDropParams { receiver, amount } = params;
    (receiver, amount)
}
