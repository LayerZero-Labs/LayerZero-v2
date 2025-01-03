#[test_only]
module endpoint_v2::messaging_receipt_tests {
    use endpoint_v2_common::bytes32;

    #[test]
    fun test_messaging_receipt() {
        let guid = bytes32::from_address(@0x12345678);
        let nonce = 12;
        let native_fee = 100;
        let zro_fee = 10;

        let receipt = endpoint_v2::messaging_receipt::new_messaging_receipt(guid, nonce, native_fee, zro_fee);

        // check getters
        assert!(endpoint_v2::messaging_receipt::get_guid(&receipt) == guid, 0);
        assert!(endpoint_v2::messaging_receipt::get_nonce(&receipt) == nonce, 0);
        assert!(endpoint_v2::messaging_receipt::get_native_fee(&receipt) == native_fee, 0);
        assert!(endpoint_v2::messaging_receipt::get_zro_fee(&receipt) == zro_fee, 0);

        // check unpacked
        let (guid_, nonce_, native_fee_, zro_fee_) = endpoint_v2::messaging_receipt::unpack_messaging_receipt(receipt);
        assert!(guid_ == guid, 0);
        assert!(nonce_ == nonce, 0);
        assert!(native_fee_ == native_fee, 0);
        assert!(zro_fee_ == zro_fee, 0);
    }
}
