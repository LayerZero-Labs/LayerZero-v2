module dvn_fee_lib::dvn_fee_lib;

use call::{call::Call, call_cap::{Self, CallCap}};
use dvn_call_type::dvn_feelib_get_fee::FeelibGetFeeParam;
use price_feed_call_types::estimate_fee::{Self, EstimateFeeParam, EstimateFeeResult};
use worker_common::worker_common;

// === Constants ===

const BPS_BASE: u128 = 10000;
const EXECUTE_FIXED_BYTES: u64 = 260;
const SIGNATURE_RAW_BYTES: u64 = 65;
const VERIFY_BYTES: u64 = 288;

// === Errors ===

const EEidNotSupported: u64 = 1;
const EInvalidDVNOptions: u64 = 2;

// === Structs ===

/// One time witness for the dvn fee lib package
public struct DVN_FEE_LIB has drop {}

public struct DvnFeeLib has key {
    id: UID,
    call_cap: CallCap,
}

// === Initialization ===

fun init(witness: DVN_FEE_LIB, ctx: &mut TxContext) {
    transfer::share_object(DvnFeeLib {
        id: object::new(ctx),
        call_cap: call_cap::new_package_cap(&witness, ctx),
    });
}

// === Main Fee Functions ===

/// Get fee view function
/// Matches: getFee(FeeParams calldata _params, IDVN.DstConfig calldata _dstConfig, bytes calldata _options)
public fun get_fee(
    self: &DvnFeeLib,
    call: &mut Call<FeelibGetFeeParam, u64>,
    ctx: &mut TxContext,
): Call<EstimateFeeParam, EstimateFeeResult> {
    let param = call.param();
    assert!(param.gas() != 0, EEidNotSupported);
    assert!(param.options().is_empty(), EInvalidDVNOptions); // validate options

    let call_data_size = get_call_data_size(param.quorum());
    let estimate_fee_param = estimate_fee::create_param(
        param.dst_eid(),
        call_data_size,
        param.gas(),
    );
    call.create_single_child(&self.call_cap, param.price_feed(), estimate_fee_param, ctx)
}

public fun confirm_get_fee(
    self: &DvnFeeLib,
    feelib_call: &mut Call<FeelibGetFeeParam, u64>,
    price_feed_call: Call<EstimateFeeParam, EstimateFeeResult>,
) {
    let (_, _, result) = feelib_call.destroy_child(&self.call_cap, price_feed_call);

    let feelib_param = feelib_call.param();
    let final_fee = apply_premium(
        result.fee(),
        feelib_param.multiplier_bps(),
        feelib_param.default_multiplier_bps(),
        feelib_param.floor_margin_usd(),
        result.native_price_usd(),
    );
    feelib_call.complete(&self.call_cap, final_fee as u64);
}

// === Internal Functions ===

/// Apply premium using the higher of multiplier or floor margin
fun apply_premium(
    fee: u128,
    multiplier_bps: u16,
    default_multiplier_bps: u16,
    floor_margin_usd: u128,
    native_price_usd: u128,
): u128 {
    let effective_multiplier_bps = if (multiplier_bps == 0) default_multiplier_bps else multiplier_bps;
    let fee_with_multiplier = fee * (effective_multiplier_bps as u128) / BPS_BASE;
    if (native_price_usd == 0 || floor_margin_usd == 0) return fee_with_multiplier;

    let native_decimals_rate = worker_common::get_native_decimals_rate() as u128;
    let fee_with_floor_margin = floor_margin_usd * native_decimals_rate / native_price_usd + fee;
    if (fee_with_floor_margin > fee_with_multiplier) fee_with_floor_margin else fee_with_multiplier
}

/// Calculate call data size based on quorum size (calculated based on evm standard)
fun get_call_data_size(quorum: u64): u64 {
    let mut total_signature_bytes = quorum * SIGNATURE_RAW_BYTES;

    if (total_signature_bytes % 32 != 0) {
        total_signature_bytes = total_signature_bytes - (total_signature_bytes % 32) + 32;
    };

    EXECUTE_FIXED_BYTES + VERIFY_BYTES + total_signature_bytes + 32
}

// === Test Functions ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    init(DVN_FEE_LIB {}, ctx);
}

#[test_only]
public fun get_call_cap(self: &DvnFeeLib): &CallCap {
    &self.call_cap
}

#[test_only]
public(package) fun test_apply_premium(
    fee: u128,
    multiplier_bps: u16,
    default_multiplier_bps: u16,
    floor_margin_usd: u128,
    native_price_usd: u128,
): u128 {
    apply_premium(fee, multiplier_bps, default_multiplier_bps, floor_margin_usd, native_price_usd)
}
