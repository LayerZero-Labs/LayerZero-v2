module executor::native_drop_params {
    use std::vector;

    use endpoint_v2_common::serde;

    struct NativeDropParams has copy, store, drop {
        receiver: address,
        amount: u64,
    }

    public fun new_native_drop_params(receiver: address, amount: u64): NativeDropParams {
        NativeDropParams { receiver, amount }
    }

    public fun unpack_native_drop_params(params: NativeDropParams): (address, u64) {
        let NativeDropParams { receiver, amount } = params;
        (receiver, amount)
    }

    public fun deserialize_native_drop_params(params_serialized: &vector<u8>): vector<NativeDropParams> {
        let params = vector[];
        let pos = 0;
        let len = vector::length(params_serialized);
        while (pos < len) {
            let receiver = serde::extract_address(params_serialized, &mut pos);
            let amount = serde::extract_u64(params_serialized, &mut pos);
            vector::push_back(&mut params, new_native_drop_params(receiver, amount));
        };
        params
    }

    public fun serialize_native_drop_params(params: vector<NativeDropParams>): vector<u8> {
        let params_serialized = vector[];
        for (i in 0..vector::length(&params)) {
            let item = vector::borrow(&params, i);
            let receiver = item.receiver;
            let amount = item.amount;
            serde::append_address(&mut params_serialized, receiver);
            serde::append_u64(&mut params_serialized, amount);
        };
        params_serialized
    }

    public fun calculate_total_amount(params: vector<NativeDropParams>): u64 {
        let total_amount = 0;
        for (i in 0..vector::length(&params)) {
            let item = vector::borrow(&params, i);
            total_amount = total_amount + item.amount;
        };
        total_amount
    }
}
