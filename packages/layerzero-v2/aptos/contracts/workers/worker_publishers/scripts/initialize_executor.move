script {
    use std::vector;
    use std::from_bcs::to_address;

    const ADDRESS_SIZE: u64 = 32;

    fun initialize_executor(
        publisher: &signer,
        executor_address: address,
        deposit_address: address,
        role_admin: address,
        admins_concatenated: vector<u8>,
        supported_msglibs_concatenated: vector<u8>,
        fee_lib: address,
    ) {
        let executor_signer = &deployer::object_code_deployment::get_code_object_signer(publisher, executor_address);


        // == Admin Addresses (32 bytes each) ==
        let length = vector::length(&admins_concatenated);
        assert!(length % ADDRESS_SIZE == 0, 1);

        let admins = vector[];
        for (i in 0..(length / ADDRESS_SIZE)) {
            let start = i * ADDRESS_SIZE;
            let admin = vector::slice(&admins_concatenated, start, start + ADDRESS_SIZE);
            vector::push_back(&mut admins, to_address(admin));
        };

        // == Supported Msglib Addresses (32 bytes each) ==
        let length = vector::length(&supported_msglibs_concatenated);
        assert!(length % ADDRESS_SIZE == 0, 1);

        let supported_msglibs = vector[];
        for (i in 0..(length / ADDRESS_SIZE)) {
            let start = i * ADDRESS_SIZE;
            let supported_msglib = vector::slice(&supported_msglibs_concatenated, start, start + ADDRESS_SIZE);
            vector::push_back(&mut supported_msglibs, to_address(supported_msglib));
        };


        executor::executor::initialize(
            executor_signer,
            deposit_address,
            role_admin,
            admins,
            supported_msglibs,
            fee_lib,
        );

        uln_302::msglib::set_worker_config_for_fee_lib_routing_opt_in(executor_signer, true);
    }
}