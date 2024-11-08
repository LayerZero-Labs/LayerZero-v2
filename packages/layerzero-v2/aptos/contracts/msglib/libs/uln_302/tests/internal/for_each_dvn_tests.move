#[test_only]
module uln_302::for_each_dvn_tests {
    use std::vector;

    use uln_302::for_each_dvn::for_each_dvn;

    #[test]
    fun test_for_each_dvn() {
        let required_dvns = vector[@1, @2, @3];
        let optional_dvns = vector[@4, @5, @6];
        let expected_dvns = vector[@1, @2, @3, @4, @5, @6];

        for_each_dvn(&required_dvns, &optional_dvns, |dvn, idx| {
            let expected_dvn = *vector::borrow(&expected_dvns, idx);
            assert!(dvn == expected_dvn, 1);
        });
    }
}
