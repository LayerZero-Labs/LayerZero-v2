#[test_only]
module msglib_types::configs_uln_tests {
    use endpoint_v2_common::config_eid_tagged::{get_eid_and_config, tag_with_eid};
    use msglib_types::configs_uln::{append_uln_config_with_eid, extract_uln_config_with_eid, new_uln_config, };

    #[test]
    fun test_configs_uln_serialization_deserialization() {
        let config = new_uln_config(1000, 1, vector[@123, @456, @789], vector[@222, @333], false, false, false);
        let tagged_config = tag_with_eid(12, config);

        let bytes = vector[];
        append_uln_config_with_eid(&mut bytes, tagged_config);

        let extracted_tagged_config = extract_uln_config_with_eid(&bytes, &mut 0);
        let (extracted_eid, extracted_config) = get_eid_and_config(extracted_tagged_config);
        assert!(extracted_eid == 12, 0);
        assert!(config == extracted_config, 0);
    }
}
