module executor_fee_lib::executor_fee_lib;

use call::{call::Call, call_cap::{Self, CallCap}};
use executor_call_type::executor_feelib_get_fee::FeelibGetFeeParam;
use executor_fee_lib::executor_option;
use price_feed_call_types::estimate_fee::{Self, EstimateFeeParam, EstimateFeeResult};
use worker_common::worker_common;

// === Constants ===

const V1_EID_THRESHOLD: u32 = 30000;
const BPS_BASE: u128 = 10000;

// === Errors ===

const EEidNotSupported: u64 = 1;

// === Structs ===

/// One time witness for the executor fee lib package
public struct EXECUTOR_FEE_LIB has drop {}

public struct ExecutorFeeLib has key {
    id: UID,
    call_cap: CallCap,
}

// === Initialization ===

fun init(otw: EXECUTOR_FEE_LIB, ctx: &mut TxContext) {
    transfer::share_object(ExecutorFeeLib {
        id: object::new(ctx),
        call_cap: call_cap::new_package_cap(&otw, ctx),
    });
}

// === Main Fee Functions ===

public fun get_fee(
    self: &ExecutorFeeLib,
    call: &mut Call<FeelibGetFeeParam, u64>,
    ctx: &mut TxContext,
): Call<EstimateFeeParam, EstimateFeeResult> {
    let params = call.param();
    assert!(params.lz_receive_base_gas() != 0, EEidNotSupported);

    let (_, total_gas) = decode_executor_options(
        *params.options(),
        params.dst_eid(),
        params.lz_receive_base_gas(),
        params.lz_compose_base_gas(),
        params.native_cap(),
    );
    let estimate_fee_param = estimate_fee::create_param(
        params.dst_eid(),
        params.call_data_size(),
        total_gas as u256,
    );
    call.create_single_child(&self.call_cap, params.price_feed(), estimate_fee_param, ctx)
}

public fun confirm_get_fee(
    self: &ExecutorFeeLib,
    feelib_call: &mut Call<FeelibGetFeeParam, u64>,
    price_feed_call: Call<EstimateFeeParam, EstimateFeeResult>,
) {
    let (_, _, result) = feelib_call.destroy_child(&self.call_cap, price_feed_call);

    let feelib_param = feelib_call.param();
    let (total_value, _) = decode_executor_options(
        *feelib_param.options(),
        feelib_param.dst_eid(),
        feelib_param.lz_receive_base_gas(),
        feelib_param.lz_compose_base_gas(),
        feelib_param.native_cap(),
    );

    let multiplier_bps = if (feelib_param.multiplier_bps() == 0) {
        feelib_param.default_multiplier_bps()
    } else {
        feelib_param.multiplier_bps()
    };

    let gas_fee = apply_premium_to_gas(
        result.fee(),
        multiplier_bps,
        feelib_param.floor_margin_usd(),
        result.native_price_usd(),
    );
    let value_fee = convert_and_apply_premium_to_value(
        total_value,
        result.price_ratio(),
        result.price_ratio_denominator(),
        multiplier_bps,
    );
    let fee = gas_fee + value_fee;
    feelib_call.complete(&self.call_cap, fee as u64);
}

// === Fee Calculation Helper Functions ===

fun apply_premium_to_gas(fee: u128, multiplier_bps: u16, margin_usd: u128, native_price_usd: u128): u128 {
    let fee_with_multiplier = (fee * (multiplier_bps as u128)) / BPS_BASE;
    if (native_price_usd == 0 || margin_usd == 0) return fee_with_multiplier;

    let native_decimals_rate = worker_common::get_native_decimals_rate() as u128;
    let fee_with_margin = (margin_usd * native_decimals_rate / native_price_usd) + fee;
    if (fee_with_margin > fee_with_multiplier) fee_with_margin else fee_with_multiplier
}

fun convert_and_apply_premium_to_value(value: u128, ratio: u128, denom: u128, multiplier_bps: u16): u128 {
    let final_value = if (value > 0) {
        value * ratio / denom * (multiplier_bps as u128) / BPS_BASE
    } else {
        0
    };
    final_value as u128
}

/// Decode executor options and return aggregated values and gas
fun decode_executor_options(
    options: vector<u8>,
    dst_eid: u32,
    lz_receive_base_gas: u64,
    lz_compose_base_gas: u64,
    native_cap: u128,
): (u128, u128) {
    let agg_options = executor_option::parse_executor_options(options, is_v1_eid(dst_eid), native_cap);

    // Calculate total gas
    let total_gas =
        (lz_receive_base_gas as u128) + agg_options.total_gas() + 
                   (lz_compose_base_gas as u128) * (agg_options.num_lz_compose() as u128);

    // Apply ordered execution premium
    let final_total_gas = if (agg_options.ordered()) (total_gas * 102) / 100 else total_gas;

    (agg_options.total_value(), final_total_gas)
}

/// Check if EID is V1
fun is_v1_eid(eid: u32): bool {
    eid < V1_EID_THRESHOLD
}

// === Test Functions ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    init(EXECUTOR_FEE_LIB {}, ctx);
}

#[test_only]
public fun get_call_cap(self: &ExecutorFeeLib): &CallCap {
    &self.call_cap
}

#[test_only]
public(package) fun test_apply_premium_to_gas(
    fee: u128,
    multiplier_bps: u16,
    margin_usd: u128,
    native_price_usd: u128,
): u128 {
    apply_premium_to_gas(fee, multiplier_bps, margin_usd, native_price_usd)
}

#[test_only]
public(package) fun test_convert_and_apply_premium_to_value(
    value: u128,
    ratio: u128,
    denom: u128,
    multiplier_bps: u16,
): u128 {
    convert_and_apply_premium_to_value(value, ratio, denom, multiplier_bps)
}
