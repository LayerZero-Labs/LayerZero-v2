script {
    use std::vector;
    use std::from_bcs::to_address;

    const ADDRESS_SIZE: u64 = 32;
    const PUBKEY_SIZE: u64 = 64;

    /// Publish a DVN with the given code and metadata.
    fun initialize_dvn(
        publisher: &signer,
        dvn_address: address,
        deposit_address: address,
        admins_concatenated: vector<u8>,
        dvn_signers_concatenated: vector<u8>,
        quorum: u64,
        supported_msglibs_concatenated: vector<u8>,
        fee_lib: address,
    ) {
        let dvn_signer = &deployer::object_code_deployment::get_code_object_signer(publisher, dvn_address);


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


        // == DVN Signers (64 bytes each) ==
        let length = vector::length(&dvn_signers_concatenated);
        assert!(length % PUBKEY_SIZE == 0, 1);

        let dvn_signers = vector[];
        for (i in 0..(length / PUBKEY_SIZE)) {
            let start = i * PUBKEY_SIZE;
            let dvn_signer = vector::slice(&dvn_signers_concatenated, start, start + PUBKEY_SIZE);
            vector::push_back(&mut dvn_signers, dvn_signer);
        };

        dvn::dvn::initialize(
            dvn_signer,
            deposit_address,
            admins,
            dvn_signers,
            quorum,
            supported_msglibs,
            fee_lib,
        );

        uln_302::msglib::set_worker_config_for_fee_lib_routing_opt_in(dvn_signer, true);
    }
}