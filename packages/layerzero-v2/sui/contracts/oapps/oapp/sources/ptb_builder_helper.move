module oapp::ptb_builder_helper;

use call::call::{Call, Void};
use endpoint_v2::{lz_compose::LzComposeParam, lz_receive::LzReceiveParam};
use std::type_name;
use utils::{bytes32::Bytes32, hash};

/// Generate deterministic call ID for endpoint lz_receive calls
/// Used to create consistent call object references across PTBs
public fun lz_receive_call_id(): Bytes32 {
    hash::keccak256!(type_name::get_with_original_ids<Call<LzReceiveParam, Void>>().into_string().as_bytes())
}

/// Generate deterministic call ID for endpoint lz_compose calls
/// Used to create consistent call object references across PTBs
public fun lz_compose_call_id(): Bytes32 {
    hash::keccak256!(type_name::get_with_original_ids<Call<LzComposeParam, Void>>().into_string().as_bytes())
}
