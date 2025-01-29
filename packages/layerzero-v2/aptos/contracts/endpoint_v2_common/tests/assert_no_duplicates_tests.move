#[test_only]
module endpoint_v2_common::assert_no_duplicates_tests {
    use endpoint_v2_common::assert_no_duplicates::assert_no_duplicates;

    #[test]
    fun does_not_abort_if_no_duplicate_addresses() {
        let addresses = vector<address>[@1, @2, @3, @4];
        assert_no_duplicates(&addresses);
    }

    #[test]
    #[expected_failure(abort_code = endpoint_v2_common::assert_no_duplicates::EDUPLICATE_ITEM)]
    fun aborts_if_duplicate_addresses() {
        let addresses = vector<address>[@1, @2, @3, @1, @5, @6];
        assert_no_duplicates(&addresses);
    }
}
