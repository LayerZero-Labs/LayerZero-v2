module executor_layerzero::executor_layerzero;

use call::call_cap::{Self, CallCap};
use executor::executor_worker;
use utils::package;

const EWorkerCapNotFromPackage: u64 = 1;

/// One time witness for the executor layerzero package
public struct EXECUTOR_LAYERZERO has drop {}

fun init(otw: EXECUTOR_LAYERZERO, ctx: &mut TxContext) {
    transfer::public_transfer(
        call_cap::new_package_cap(&otw, ctx),
        ctx.sender(),
    );
}

#[allow(lint(share_owned))]
public fun init_executor(
    worker_cap: CallCap,
    deposit_address: address,
    price_feed: address,
    worker_fee_lib: address,
    default_multiplier_bps: u16,
    owner: address,
    admins: vector<address>,
    ctx: &mut TxContext,
) {
    assert!(worker_cap.id() == package::original_package_of_type<EXECUTOR_LAYERZERO>(), EWorkerCapNotFromPackage);
    let executor = executor_worker::create_executor(
        worker_cap,
        deposit_address,
        price_feed,
        worker_fee_lib,
        default_multiplier_bps,
        owner,
        admins,
        ctx,
    );

    transfer::public_share_object(executor);
}
