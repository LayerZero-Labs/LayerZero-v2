/// View functions for the ULN-302 module
module uln_302::msglib {
    use std::event::emit;
    use std::option::Option;
    use std::signer::address_of;

    use endpoint_v2_common::bytes32;
    use endpoint_v2_common::packet_raw::bytes_to_raw_packet;
    use endpoint_v2_common::packet_v1_codec::{Self, is_receive_header_valid};
    use endpoint_v2_common::universal_config;
    use msglib_types::configs_executor::ExecutorConfig;
    use msglib_types::configs_uln::UlnConfig;
    use uln_302::configuration;
    use uln_302::uln_302_store;
    use uln_302::verification;

    #[test_only]
    /// Initializes the uln for testing
    public fun initialize_for_test() {
        uln_302_store::init_module_for_test();
    }

    #[view]
    /// Checks that a packet is verifiable and has received verification of the required confirmations from the needed
    /// set of DVNs
    public fun verifiable(
        packet_header_bytes: vector<u8>,
        payload_hash: vector<u8>,
    ): bool {
        let packet_header = bytes_to_raw_packet(packet_header_bytes);
        let src_eid = packet_v1_codec::get_src_eid(&packet_header);
        let receiver = bytes32::to_address(
            packet_v1_codec::get_receiver(&packet_header)
        );

        is_receive_header_valid(&packet_header, universal_config::eid()) &&
            verification::check_verifiable(
                &configuration::get_receive_uln_config(receiver, src_eid),
                bytes32::keccak256(packet_header_bytes),
                bytes32::to_bytes32(payload_hash)
            )
    }

    #[view]
    /// Gets the treasury address
    public fun get_treasury(): address {
        @treasury
    }

    #[view]
    /// Gets the default send ULN config for an EID
    ///
    /// This will return option::none() if it is not set.
    public fun get_default_uln_send_config(eid: u32): Option<UlnConfig> {
        uln_302_store::get_default_send_uln_config(eid)
    }

    #[view]
    /// Gets the default receive ULN config for an EID
    ///
    /// This will return option::none() if it is not set.
    public fun get_default_uln_receive_config(eid: u32): Option<UlnConfig> {
        uln_302_store::get_default_receive_uln_config(eid)
    }

    #[view]
    /// Gets the default executor config for an EID
    ///
    /// This will return option::none() if it is not set.
    public fun get_default_executor_config(eid: u32): Option<ExecutorConfig> {
        uln_302_store::get_default_executor_config(eid)
    }

    #[view]
    /// Gets the send ULN config for an OApp and EID
    ///
    /// This will return option::none() if it is not set.
    public fun get_app_send_config(oapp: address, eid: u32): Option<UlnConfig> {
        uln_302_store::get_send_uln_config(oapp, eid)
    }

    #[view]
    /// Gets the receive ULN config for an OApp and EID
    ///
    /// This will return option::none() if it is not set.
    public fun get_app_receive_config(oapp: address, eid: u32): Option<UlnConfig> {
        uln_302_store::get_receive_uln_config(oapp, eid)
    }

    #[view]
    /// Gets the executor config for an OApp and EID
    ///
    /// This will return option::none() if it is not set.
    public fun get_app_executor_config(oapp: address, eid: u32): Option<ExecutorConfig> {
        uln_302_store::get_executor_config(oapp, eid)
    }

    #[view]
    public fun get_verification_confirmations(
        header_hash: vector<u8>,
        payload_hash: vector<u8>,
        dvn_address: address,
    ): u64 {
        let header_hash_bytes = bytes32::to_bytes32(header_hash);
        let payload_hash_bytes = bytes32::to_bytes32(payload_hash);

        if (uln_302_store::has_verification_confirmations(header_hash_bytes, payload_hash_bytes, dvn_address)) {
            uln_302_store::get_verification_confirmations(header_hash_bytes, payload_hash_bytes, dvn_address)
        } else 0
    }

    /// Setter for a worker to opt in (true) or out (false) of using the worker_common::worker_config module to store
    /// their fee library configuration
    public entry fun set_worker_config_for_fee_lib_routing_opt_in(worker: &signer, opt_in: bool) {
        let worker_address = address_of(move worker);
        // Emit an event only if there is a change
        if (uln_302_store::get_worker_config_for_fee_lib_routing_opt_in(worker_address) != opt_in) {
            emit(WorkerConfigForFeeLibRoutingOptIn { worker: worker_address, opt_in })
        };

        uln_302_store::set_worker_config_for_fee_lib_routing_opt_in(worker_address, opt_in);
    }

    #[view]
    /// Gets the opt in/out status of a worker
    public fun worker_config_for_fee_lib_routing_opt_in(worker: address): bool {
        uln_302_store::get_worker_config_for_fee_lib_routing_opt_in(worker)
    }

    // ==================================================== Events ====================================================

    #[event]
    struct WorkerConfigForFeeLibRoutingOptIn has drop, store {
        worker: address,
        opt_in: bool,
    }

    #[test_only]
    public fun worker_config_for_fee_lib_routing_opt_in_event(
        worker: address,
        opt_in: bool,
    ): WorkerConfigForFeeLibRoutingOptIn {
        WorkerConfigForFeeLibRoutingOptIn { worker, opt_in }
    }
}
