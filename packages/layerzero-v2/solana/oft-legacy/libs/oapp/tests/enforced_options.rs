#[cfg(test)]
mod test_enforced_options {
    use oapp::options::{assert_type_3, combine_options};

    #[test]
    fn test_assert_type_3_revert() {
        let options = vec![0, 1, 2, 3];
        let result = assert_type_3(&options);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("InvalidOptions"));
    }

    #[test]
    fn test_assert_type_3() {
        let options = vec![0, 3, 1, 2, 3];
        let result = assert_type_3(&options);
        assert!(result.is_ok());
    }

    #[test]
    fn test_combine_options_revert_if_not_type_3() {
        let enforced_options: Vec<u8> = vec![0, 3, 1, 2, 3];
        let extra_options = vec![0, 1, 7, 8, 9];
        let result = combine_options(enforced_options, &extra_options);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("InvalidOptions"));
    }

    #[test]
    fn test_combine_options() {
        let enforced_options: Vec<u8> = vec![0, 3, 1, 2, 3];
        let extra_options = vec![0, 3, 7, 8, 9];

        let result = combine_options(enforced_options, &extra_options);
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), vec![0, 3, 1, 2, 3, 7, 8, 9]);
    }
}
