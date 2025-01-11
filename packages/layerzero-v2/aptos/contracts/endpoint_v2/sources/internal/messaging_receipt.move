/// Messaging Receipt is returned upon endpoint::send and provides proof of the message being sent and fees paid
module endpoint_v2::messaging_receipt {
    use endpoint_v2_common::bytes32::Bytes32;

    friend endpoint_v2::channels;

    #[test_only]
    friend endpoint_v2::messaging_receipt_tests;

    // For indirect dependency: `channels_tests` calls friend functions via inline functions in `endpoint_v2::channels`
    #[test_only]
    friend endpoint_v2::channels_tests;

    /// Messaging receipt is returned from endpoint::send and provides proof of the message being sent and fees paid
    struct MessagingReceipt has store, drop {
        guid: Bytes32,
        nonce: u64,
        native_fee: u64,
        zro_fee: u64,
    }

    /// Constructs a new messaging receipt
    /// This is a friend-only function so that the Messaging Receipt cannot be forged by a 3rd party
    public(friend) fun new_messaging_receipt(
        guid: Bytes32,
        nonce: u64,
        native_fee: u64,
        zro_fee: u64,
    ): MessagingReceipt {
        MessagingReceipt { guid, nonce, native_fee, zro_fee }
    }

    #[test_only]
    public fun new_messaging_receipt_for_test(
        guid: Bytes32,
        nonce: u64,
        native_fee: u64,
        zro_fee: u64,
    ): MessagingReceipt {
        MessagingReceipt { guid, nonce, native_fee, zro_fee }
    }

    /// Get the guid of a MessagingReceipt in the format of a bytes array
    public fun get_guid(self: &MessagingReceipt): Bytes32 {
        self.guid
    }

    /// Gets the nonce of a MessagingReceipt
    public fun get_nonce(self: &MessagingReceipt): u64 {
        self.nonce
    }

    /// Gets the native fee of a MessagingReceipt
    public fun get_native_fee(self: &MessagingReceipt): u64 {
        self.native_fee
    }

    /// Gets the zro fee of a MessagingReceipt
    public fun get_zro_fee(self: &MessagingReceipt): u64 {
        self.zro_fee
    }

    /// Unpacks the fields of a MessagingReceipt
    /// @return (guid, nonce, native_fee, zro_fee)
    public fun unpack_messaging_receipt(receipt: MessagingReceipt): (Bytes32, u64, u64, u64) {
        let MessagingReceipt {
            guid,
            nonce,
            native_fee,
            zro_fee,
        } = receipt;
        (guid, nonce, native_fee, zro_fee)
    }
}