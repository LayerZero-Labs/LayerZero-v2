module endpoint_v2_common::assert_no_duplicates {
    use std::vector;

    /// Assert that there are no duplicate addresses in the given vector.
    public fun assert_no_duplicates<T>(items: &vector<T>) {
        for (i in 0..vector::length(items)) {
            for (j in 0..i) {
                if (vector::borrow(items, i) == vector::borrow(items, j)) {
                    abort EDUPLICATE_ITEM
                }
            }
        }
    }


    // ================================================== Error Codes =================================================

    const EDUPLICATE_ITEM: u64 = 1;
}