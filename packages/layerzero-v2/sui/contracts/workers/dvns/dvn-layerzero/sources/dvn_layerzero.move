module dvn_layerzero::dvn_layerzero;

use call::call_cap::{Self, CallCap};
use dvn::dvn;
use utils::package;

const EWorkerCapNotFromPackage: u64 = 1;

/// One time witness for the dvn layerzero package
public struct DVN_LAYERZERO has drop {}

fun init(witness: DVN_LAYERZERO, ctx: &mut TxContext) {
    transfer::public_transfer(
        call_cap::new_package_cap(&witness, ctx),
        ctx.sender(),
    );
}

#[allow(lint(share_owned))]
public fun init_dvn(
    worker_cap: CallCap,
    vid: u32,
    deposit_address: address,
    price_feed: address,
    worker_fee_lib: address,
    default_multiplier_bps: u16,
    admins: vector<address>,
    signers: vector<vector<u8>>,
    quorum: u64,
    ctx: &mut TxContext,
) {
    assert!(worker_cap.id() == package::original_package_of_type<DVN_LAYERZERO>(), EWorkerCapNotFromPackage);
    let dvn = dvn::create_dvn(
        worker_cap,
        vid,
        deposit_address,
        price_feed,
        worker_fee_lib,
        default_multiplier_bps,
        admins,
        signers,
        quorum,
        ctx,
    );

    transfer::public_share_object(dvn);
}
