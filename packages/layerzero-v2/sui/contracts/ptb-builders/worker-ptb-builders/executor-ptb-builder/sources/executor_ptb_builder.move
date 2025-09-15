module executor_ptb_builder::executor_ptb_builder;

use executor::executor_worker::Executor;
use executor_fee_lib::executor_fee_lib::ExecutorFeeLib;
use price_feed::price_feed::PriceFeed;
use ptb_move_call::{
    argument::{Self, Argument},
    move_call::{Self, MoveCall},
    move_calls_builder::{Self, MoveCallsBuilder}
};
use uln_302_ptb_builder::uln_302_ptb_builder;
use utils::package;

public fun build_executor_ptb(
    executor: &Executor,
    feelib: &ExecutorFeeLib,
    price_feed: &PriceFeed,
): (vector<MoveCall>, vector<MoveCall>) {
    let get_fee_ptb = build_get_fee_ptb(executor, feelib, price_feed);
    let assign_job_ptb = build_assign_job_ptb(executor, feelib, price_feed);
    (get_fee_ptb, assign_job_ptb)
}

public fun build_get_fee_ptb(executor: &Executor, feelib: &ExecutorFeeLib, price_feed: &PriceFeed): vector<MoveCall> {
    let executor_package = package::package_of_type<Executor>();
    let mut move_calls_builder = move_calls_builder::new();
    // executor::get_fee(executor, call) -> Call<FeelibGetFeeParam, u64>
    let feelib_call = move_calls_builder
        .add(
            move_call::create(
                executor_package,
                b"executor_worker".to_ascii_string(),
                b"get_fee".to_ascii_string(),
                vector[
                    argument::create_object(object::id_address(executor)),
                    argument::create_id(uln_302_ptb_builder::executor_get_fee_call_id()),
                ],
                vector[],
                false,
                vector[],
            ),
        )
        .to_nested_result_arg(0);
    // append fee lib calls
    append_get_fee_move_calls(&mut move_calls_builder, feelib, price_feed, feelib_call);
    // executor::confirm_get_fee(executor, executor_call, feelib_call)
    move_calls_builder.add(
        move_call::create(
            executor_package,
            b"executor_worker".to_ascii_string(),
            b"confirm_get_fee".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(executor)),
                argument::create_id(uln_302_ptb_builder::executor_get_fee_call_id()),
                feelib_call,
            ],
            vector[],
            false,
            vector[],
        ),
    );
    move_calls_builder.build()
}

public fun build_assign_job_ptb(
    executor: &Executor,
    feelib: &ExecutorFeeLib,
    price_feed: &PriceFeed,
): vector<MoveCall> {
    let executor_package = package::package_of_type<Executor>();
    let mut move_calls_builder = move_calls_builder::new();
    // executor::assign_job(executor, call) -> Call<FeelibGetFeeParam, u64>
    let feelib_call = move_calls_builder
        .add(
            move_call::create(
                executor_package,
                b"executor_worker".to_ascii_string(),
                b"assign_job".to_ascii_string(),
                vector[
                    argument::create_object(object::id_address(executor)),
                    argument::create_id(uln_302_ptb_builder::executor_assign_job_call_id()),
                ],
                vector[],
                false,
                vector[],
            ),
        )
        .to_nested_result_arg(0);
    // append fee lib calls
    append_get_fee_move_calls(&mut move_calls_builder, feelib, price_feed, feelib_call);
    // executor::confirm_assign_job(executor, executor_call, feelib_call)
    move_calls_builder.add(
        move_call::create(
            executor_package,
            b"executor_worker".to_ascii_string(),
            b"confirm_assign_job".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(executor)),
                argument::create_id(uln_302_ptb_builder::executor_assign_job_call_id()),
                feelib_call,
            ],
            vector[],
            false,
            vector[],
        ),
    );
    move_calls_builder.build()
}

// === Internal Functions ===

fun append_get_fee_move_calls(
    builder: &mut MoveCallsBuilder,
    feelib: &ExecutorFeeLib,
    price_feed: &PriceFeed,
    feelib_call: Argument,
) {
    let feelib_package = package::package_of_type<ExecutorFeeLib>();
    let price_feed_package = package::package_of_type<PriceFeed>();

    // feelib::get_fee(feelib, call) -> Call<EstimateFeeParam, EstimateFeeResult>
    let price_feed_call = builder
        .add(
            move_call::create(
                feelib_package,
                b"executor_fee_lib".to_ascii_string(),
                b"get_fee".to_ascii_string(),
                vector[argument::create_object(object::id_address(feelib)), feelib_call],
                vector[],
                false,
                vector[],
            ),
        )
        .to_nested_result_arg(0);
    // price_feed::estimate_fee_by_eid(price_feed, call)
    builder.add(
        move_call::create(
            price_feed_package,
            b"price_feed".to_ascii_string(),
            b"estimate_fee_by_eid".to_ascii_string(),
            vector[argument::create_object(object::id_address(price_feed)), price_feed_call],
            vector[],
            false,
            vector[],
        ),
    );
    // feelib::confirm_get_fee(feelib, feelib_call, price_feed_call)
    builder.add(
        move_call::create(
            feelib_package,
            b"executor_fee_lib".to_ascii_string(),
            b"confirm_get_fee".to_ascii_string(),
            vector[argument::create_object(object::id_address(feelib)), feelib_call, price_feed_call],
            vector[],
            false,
            vector[],
        ),
    );
}
