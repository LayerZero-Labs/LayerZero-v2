#[test_only]
module endpoint_v2_common::config_eid_tagged_tests {
    #[test]
    fun test_tag_with_eid() {
        let tagged = endpoint_v2_common::config_eid_tagged::tag_with_eid(1, 2);
        let (eid, config) = endpoint_v2_common::config_eid_tagged::get_eid_and_config(tagged);
        assert!(eid == 1, 0);
        assert!(config == 2, 0);
    }
}