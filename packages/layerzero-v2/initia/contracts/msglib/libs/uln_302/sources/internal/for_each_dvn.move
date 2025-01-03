module uln_302::for_each_dvn {
    use std::vector;

    friend uln_302::verification;
    friend uln_302::sending;

    #[test_only]
    friend uln_302::for_each_dvn_tests;

    /// Loop through each dvn and provide the dvn and the dvn index
    /// If a required dvn is duplicated as an optional dvn, it will be called twice
    public(friend) inline fun for_each_dvn(
        required_dvns: &vector<address>,
        optional_dvns: &vector<address>,
        f: |address, u64|(),
    ) {
        let count_required = vector::length(required_dvns);
        let count_optional = vector::length(optional_dvns);

        for (i in 0..(count_required + count_optional)) {
            let dvn = if (i < count_required) {
                vector::borrow(required_dvns, i)
            } else {
                vector::borrow(optional_dvns, i - count_required)
            };

            f(*dvn, i)
        }
    }
}
