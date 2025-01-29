#[test_only]
module endpoint_v2::messaging_composer_tests {
    use std::string;

    use endpoint_v2::messaging_composer::{clear_compose, send_compose};
    use endpoint_v2::store;
    use endpoint_v2_common::bytes32;

    #[test]
    fun test_send_compose_and_clear() {
        let oapp: address = @0x1;
        let to = @0x2;
        let index = 0;
        let guid = bytes32::to_bytes32(b"................................");
        let message = b"message";
        store::init_module_for_test();
        store::register_composer(to, string::utf8(b"test"));

        send_compose(oapp, to, index, guid, message);
        clear_compose(oapp, to, guid, index, message);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::messaging_composer::ECOMPOSE_NOT_FOUND)]
    fun test_cannot_clear_before_send_compose() {
        let oapp: address = @0x1;
        let to = @0x2;
        let index = 0;
        let guid = bytes32::to_bytes32(b"................................");
        let message = b"message";
        store::init_module_for_test();
        store::register_composer(to, string::utf8(b"test"));

        clear_compose(oapp, to, guid, index, message);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2::messaging_composer::ECOMPOSE_ALREADY_CLEARED)]
    fun test_cannot_clear_same_message_twice() {
        let oapp: address = @0x1;
        let to = @0x2;
        let index = 0;
        let guid = bytes32::to_bytes32(b"................................");
        let message = b"message";
        store::init_module_for_test();
        store::register_composer(to, string::utf8(b"test"));

        send_compose(oapp, to, index, guid, message);
        clear_compose(oapp, to, guid, index, message);
        clear_compose(oapp, to, guid, index, message);
    }
}
