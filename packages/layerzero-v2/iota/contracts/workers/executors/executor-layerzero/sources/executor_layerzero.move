module executor_layerzero::executor_layerzero;

use call::call_cap::{Self, CallCap};
use executor::executor_worker;
use utils::package;
use worker_registry::worker_registry::WorkerRegistry;

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
    supported_message_libs: vector<address>,
    price_feed: address,
    worker_fee_lib: address,
    default_multiplier_bps: u16,
    owner: address,
    admins: vector<address>,
    worker_registry: &mut WorkerRegistry,
    ctx: &mut TxContext,
) {
    assert!(worker_cap.id() == package::original_package_of_type<EXECUTOR_LAYERZERO>(), EWorkerCapNotFromPackage);
    executor_worker::create_executor(
        worker_cap,
        deposit_address,
        supported_message_libs,
        price_feed,
        worker_fee_lib,
        default_multiplier_bps,
        owner,
        admins,
        worker_registry,
        ctx,
    );
}
