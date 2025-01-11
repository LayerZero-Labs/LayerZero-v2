module uln_302::verification {
    use std::event::emit;
    use std::vector;

    use endpoint_v2_common::bytes32::{Self, Bytes32, from_bytes32};
    use endpoint_v2_common::packet_raw::{get_packet_bytes, RawPacket};
    use endpoint_v2_common::packet_v1_codec::{Self, assert_receive_header};
    use endpoint_v2_common::universal_config;
    use msglib_types::configs_uln::{Self, UlnConfig};
    use uln_302::configuration;
    use uln_302::for_each_dvn::for_each_dvn;
    use uln_302::uln_302_store;

    friend uln_302::msglib;
    friend uln_302::router_calls;

    #[test_only]
    friend uln_302::verification_tests;

    // ================================================= Verification =================================================

    /// Initiated from the DVN to give their verification of a payload as well as the number of confirmations
    public(friend) fun verify(
        dvn_address: address,
        packet_header: RawPacket,
        payload_hash: Bytes32,
        confirmations: u64,
    ) {
        let packet_header_bytes = get_packet_bytes(packet_header);
        let header_hash = bytes32::keccak256(packet_header_bytes);
        uln_302_store::set_verification_confirmations(header_hash, payload_hash, dvn_address, confirmations);
        emit(PayloadVerified {
            dvn: dvn_address,
            header: packet_header_bytes,
            confirmations,
            proof_hash: from_bytes32(payload_hash),
        });
    }

    /// This checks if a message is verifiable by a sufficient group of DVNs to meet the requirements
    public(friend) fun check_verifiable(config: &UlnConfig, header_hash: Bytes32, payload_hash: Bytes32): bool {
        let required_dvn_count = configs_uln::get_required_dvn_count(config);
        let optional_dvn_count = configs_uln::get_optional_dvn_count(config);
        let optional_dvn_threshold = configs_uln::get_optional_dvn_threshold(config);
        let required_confirmations = configs_uln::get_confirmations(config);

        if (required_dvn_count > 0) {
            let required_dvns = configs_uln::get_required_dvns(config);
            for (i in 0..required_dvn_count) {
                let dvn = vector::borrow(&required_dvns, i);
                if (!is_verified(*dvn, header_hash, payload_hash, required_confirmations)) {
                    return false
                };
            };
            if (optional_dvn_threshold == 0) {
                return true
            };
        };

        let count_optional_dvns_verified = 0;
        let optional_dvns = configs_uln::get_optional_dvns(config);
        for (i in 0..optional_dvn_count) {
            let dvn = vector::borrow(&optional_dvns, i);
            if (is_verified(*dvn, header_hash, payload_hash, required_confirmations)) {
                count_optional_dvns_verified = count_optional_dvns_verified + 1;
                if (count_optional_dvns_verified >= optional_dvn_threshold) {
                    return true
                };
            };
        };

        return false
    }

    /// This checks if a DVN has verified a message with at least the required number of confirmations
    public(friend) fun is_verified(
        dvn_address: address,
        header_hash: Bytes32,
        payload_hash: Bytes32,
        required_confirmations: u64,
    ): bool {
        if (!uln_302_store::has_verification_confirmations(header_hash, payload_hash, dvn_address)) { return false };
        let confirmations = uln_302_store::get_verification_confirmations(header_hash, payload_hash, dvn_address);
        confirmations >= required_confirmations
    }


    /// Commits the verification of a payload
    /// This uses the contents of a serialized packet header to then assert the complete verification of a payload and
    /// then clear the storage related to it
    public(friend) fun commit_verification(
        packet_header: RawPacket,
        payload_hash: Bytes32,
    ): (address, u32, Bytes32, u64) {
        assert_receive_header(&packet_header, universal_config::eid());
        verify_and_reclaim_storage(
            &get_receive_uln_config_from_packet_header(&packet_header),
            bytes32::keccak256(get_packet_bytes(packet_header)),
            payload_hash,
        );

        // decode the header
        let receiver = bytes32::to_address(packet_v1_codec::get_receiver(&packet_header));
        let src_eid = packet_v1_codec::get_src_eid(&packet_header);
        let sender = packet_v1_codec::get_sender(&packet_header);
        let nonce = packet_v1_codec::get_nonce(&packet_header);
        (receiver, src_eid, sender, nonce)
    }

    public(friend) fun get_receive_uln_config_from_packet_header(packet_header: &RawPacket): UlnConfig {
        let src_eid = packet_v1_codec::get_src_eid(packet_header);
        let oapp_address = bytes32::to_address(packet_v1_codec::get_receiver(packet_header));
        configuration::get_receive_uln_config(oapp_address, src_eid)
    }

    /// If the message is verifiable, this function will remove the confirmations from the store
    /// It will abort if the message is not verifiable
    public(friend) fun verify_and_reclaim_storage(config: &UlnConfig, header_hash: Bytes32, payload_hash: Bytes32) {
        assert!(check_verifiable(config, header_hash, payload_hash), ENOT_VERIFIABLE);

        reclaim_storage(
            &configs_uln::get_required_dvns(config),
            &configs_uln::get_optional_dvns(config),
            header_hash,
            payload_hash,
        );
    }


    /// Loop through the DVN addresses and clear confirmations for the given header and payload hash
    public(friend) fun reclaim_storage(
        required_dvns: &vector<address>,
        optional_dvns: &vector<address>,
        header_hash: Bytes32,
        payload_hash: Bytes32,
    ) {
        for_each_dvn(required_dvns, optional_dvns, |dvn, _idx| {
            if (uln_302_store::has_verification_confirmations(header_hash, payload_hash, dvn)) {
                uln_302_store::remove_verification_confirmations(header_hash, payload_hash, dvn);
            };
        });
    }

    // ==================================================== Events ====================================================

    #[event]
    struct PayloadVerified has drop, copy, store {
        dvn: address,
        header: vector<u8>,
        confirmations: u64,
        proof_hash: vector<u8>,
    }

    #[test_only]
    public fun payload_verified_event(
        dvn: address,
        header: vector<u8>,
        confirmations: u64,
        proof_hash: vector<u8>,
    ): PayloadVerified {
        PayloadVerified { dvn, header, confirmations, proof_hash }
    }

    // ================================================== Error Codes =================================================

    const ENO_DVNS: u64 = 1;
    const ENOT_VERIFIABLE: u64 = 2;
}
