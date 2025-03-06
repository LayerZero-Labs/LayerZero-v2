#[test_only]
module price_feed_module_0::eid_model_pair_tests {
    use std::vector;

    use price_feed_module_0::eid_model_pair::{
        append_eid_model_pair, deserialize_eid_model_pair_list, EidModelPair, extract_eid_model_pair,
        get_dst_eid, get_model_type, new_eid_model_pair, serialize_eid_model_pair_list,
    };

    #[test]
    fun test_eid_to_model() {
        let obj = new_eid_model_pair(123, 456);
        let buf = vector<u8>[];
        append_eid_model_pair(&mut buf, &obj);
        let pos = 0;
        let obj2 = extract_eid_model_pair(&buf, &mut pos);

        // test getters
        assert!(get_dst_eid(&obj) == get_dst_eid(&obj2), 0);
        assert!(get_model_type(&obj) == get_model_type(&obj2), 1);

        // test object
        assert!(obj == obj2, 3);
    }

    #[test]
    fun test_eid_to_model_list() {
        let objs = vector<EidModelPair>[];
        vector::push_back(&mut objs, new_eid_model_pair(123, 456));
        vector::push_back(&mut objs, new_eid_model_pair(789, 1));

        let buf = serialize_eid_model_pair_list(&objs);
        let objs2 = deserialize_eid_model_pair_list(&buf);

        // test object
        assert!(objs == objs2, 1);
    }
}
