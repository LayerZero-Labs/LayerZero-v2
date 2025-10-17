#[test_only]
module counter::uln302_quote_test;

use counter::{
    options_builder,
    uln302_test_common::{
        setup_test_environment,
        quote,
        clean,
        VANILLA_TYPE,
        COMPOSE_TYPE,
        ABA_TYPE,
        ABA_COMPOSE_TYPE,
        default_config
    }
};

#[test]
fun test_quote_with_zro_fee_enabled() {
    let config = default_config();
    let (mut scenario, test_clock, deployments) = setup_test_environment(
        &config,
        vector[config.src_eid(), config.dst_eid()],
        true,
    );
    // Get messaging fee
    scenario.next_tx(config.user());
    // Standard executor options: 200,000 gas, no additional value
    let mut builder = options_builder::new_builder();
    let options = builder.add_executor_lz_receive_option(200000, 0).build();

    // Quote with native fee (pay_in_zro = false)
    let messaging_fee = quote(
        &config,
        &mut scenario,
        &deployments,
        config.src_eid(),
        config.dst_eid(),
        VANILLA_TYPE!(),
        options,
        true,
    );

    assert!(messaging_fee.native_fee() > 0, 0);
    assert!(messaging_fee.zro_fee() > 0, 0);

    clean(scenario, test_clock, deployments);
}

#[test]
fun test_quote_with_zro_fee_disabled() {
    let config = default_config();
    let (mut scenario, test_clock, deployments) = setup_test_environment(
        &config,
        vector[config.src_eid(), config.dst_eid()],
        false,
    );
    // Get messaging fee
    scenario.next_tx(config.user());
    // Standard executor options: 200,000 gas, no additional value
    let mut builder = options_builder::new_builder();
    let options = builder.add_executor_lz_receive_option(200000, 0).build();

    // Quote with native fee (pay_in_zro = false)
    let messaging_fee = quote(
        &config,
        &mut scenario,
        &deployments,
        config.src_eid(),
        config.dst_eid(),
        VANILLA_TYPE!(),
        options,
        false,
    );

    assert!(messaging_fee.native_fee() > 0, 0);
    assert!(messaging_fee.zro_fee() == 0, 0);

    clean(scenario, test_clock, deployments);
}

#[test]
fun test_quote_allowed_msg_type() {
    let config = default_config();
    let allowed_msg_types = vector[VANILLA_TYPE!(), COMPOSE_TYPE!(), ABA_TYPE!(), ABA_COMPOSE_TYPE!()];
    let zro_fee_status = vector[true, false];
    let (mut scenario, test_clock, deployments) = setup_test_environment(
        &config,
        vector[config.src_eid(), config.dst_eid()],
        true,
    );

    allowed_msg_types.do!(|msg_type| {
        zro_fee_status.do!(|zro_fee| {
            // Advance transaction context for each iteration
            scenario.next_tx(config.user());
            let options = options_builder::new_builder().add_executor_lz_receive_option(200000, 0).build();
            let messaging_fee = quote(
                &config,
                &mut scenario,
                &deployments,
                config.src_eid(),
                config.dst_eid(),
                msg_type,
                options,
                zro_fee,
            );
            assert!(messaging_fee.native_fee() > 0, 0);
            if (zro_fee) {
                assert!(messaging_fee.zro_fee() > 0, 0);
            } else {
                assert!(messaging_fee.zro_fee() == 0, 0);
            }
        });
    });

    clean(scenario, test_clock, deployments);
}

#[test, expected_failure(abort_code = treasury::treasury::EZroNotEnabled)]
fun test_quote_with_zro_while_zro_fee_disabled() {
    let config = default_config();
    let (mut scenario, test_clock, deployments) = setup_test_environment(
        &config,
        vector[config.src_eid(), config.dst_eid()],
        false,
    );
    // Get messaging fee
    scenario.next_tx(config.user());
    // Standard executor options: 200,000 gas, no additional value
    let mut builder = options_builder::new_builder();
    let options = builder.add_executor_lz_receive_option(200000, 0).build();

    // Quote with native fee (pay_in_zro = false)
    let _messaging_fee = quote(
        &config,
        &mut scenario,
        &deployments,
        config.src_eid(),
        config.dst_eid(),
        VANILLA_TYPE!(),
        options,
        true,
    );

    clean(scenario, test_clock, deployments);
}
