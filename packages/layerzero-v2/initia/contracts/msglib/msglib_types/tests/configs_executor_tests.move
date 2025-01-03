#[test_only]
module msglib_types::configs_executor_tests {
    use endpoint_v2_common::config_eid_tagged::{get_eid_and_config, tag_with_eid};
    use msglib_types::configs_executor::{append_executor_config_with_eid,
        extract_executor_config_with_eid, new_executor_config };

    #[test]
    fun test_configs_executor_serialization_deserialization() {
        let config = new_executor_config(1000, @0x1);
        let tagged_config = tag_with_eid(5, config);

        let bytes = vector[];
        append_executor_config_with_eid(&mut bytes, tagged_config);

        let extracted_tagged_config = extract_executor_config_with_eid(&bytes, &mut 0);
        let (extracted_eid, extracted_config) = get_eid_and_config(extracted_tagged_config);
        assert!(extracted_eid == 5, 0);
        assert!(config == extracted_config, 0);
    }
}
