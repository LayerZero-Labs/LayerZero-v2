/// Entrypoint for administrative functions for the ULN 302 module. The functions in this module can only be called by
/// ULN administrators
module uln_302::admin {
    use std::signer::address_of;

    use endpoint_v2_common::universal_config::assert_layerzero_admin;
    use msglib_types::configs_executor::new_executor_config;
    use msglib_types::configs_uln::new_uln_config;
    use uln_302::configuration;

    /// Sets the default send config for an EID
    public entry fun set_default_uln_send_config(
        account: &signer,
        dst_eid: u32,
        confirmations: u64,
        optional_dvn_threshold: u8,
        required_dvns: vector<address>,
        optional_dvns: vector<address>,
    ) {
        assert_layerzero_admin(address_of(move account));
        configuration::set_default_send_uln_config(
            dst_eid,
            new_uln_config(
                confirmations,
                optional_dvn_threshold,
                required_dvns,
                optional_dvns,
                false,
                false,
                false,
            )
        )
    }

    /// Sets the default receive config for an EID
    public entry fun set_default_uln_receive_config(
        account: &signer,
        src_eid: u32,
        confirmations: u64,
        optional_dvn_threshold: u8,
        required_dvns: vector<address>,
        optional_dvns: vector<address>,
    ) {
        assert_layerzero_admin(address_of(move account));
        configuration::set_default_receive_uln_config(
            src_eid,
            new_uln_config(
                confirmations,
                optional_dvn_threshold,
                required_dvns,
                optional_dvns,
                false,
                false,
                false,
            )
        )
    }

    /// Sets the default executor config for an EID
    public entry fun set_default_executor_config(
        account: &signer,
        eid: u32,
        max_message_size: u32,
        executor_address: address,
    ) {
        assert_layerzero_admin(address_of(move account));
        let config = new_executor_config(max_message_size, executor_address);
        configuration::set_default_executor_config(eid, config)
    }

    // ================================================== Error Codes =================================================

    const ENOT_AUTHORIZED: u64 = 1;
}
