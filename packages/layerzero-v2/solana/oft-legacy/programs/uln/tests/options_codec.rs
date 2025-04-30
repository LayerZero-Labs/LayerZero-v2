mod utils;

#[cfg(test)]
mod test_options_codec {
    use crate::utils::options_util::{OptionsUtil, DVN_OPTION_TYPE_PRECRIME};
    use primitive_types::U256;
    use uln::options_codec;

    #[test]
    fn test_decode_type1() {
        let execution_gas: u128 = 20000;
        let legacy_options = OptionsUtil::encode_legacy_options_type1(U256::from(execution_gas));

        let (executor_options, _) = options_codec::decode_options(&legacy_options).unwrap();
        assert_eq!(executor_options.len(), 1);
        assert_eq!(executor_options[0].option_type, options_codec::EXECUTOR_OPTION_TYPE_LZRECEIVE);
        assert_eq!(
            executor_options[0].params,
            OptionsUtil::executor_encode_lz_receive_option(execution_gas, 0)
        );
    }

    #[test]
    fn test_decode_type2() {
        let execution_gas: u128 = 20000;
        let amount: u128 = 10000;
        let receiver = [1u8; 32];
        let legacy_options = OptionsUtil::encode_legacy_options_type2(
            U256::from(execution_gas),
            U256::from(amount),
            receiver,
        );

        let (executor_options, _) = options_codec::decode_options(&legacy_options).unwrap();
        assert_eq!(executor_options.len(), 2);
        assert_eq!(executor_options[0].option_type, options_codec::EXECUTOR_OPTION_TYPE_LZRECEIVE);
        assert_eq!(
            executor_options[0].params,
            OptionsUtil::executor_encode_lz_receive_option(execution_gas, 0)
        );
        assert_eq!(
            executor_options[1].option_type,
            options_codec::EXECUTOR_OPTION_TYPE_NATIVE_DROP
        );
        assert_eq!(
            executor_options[1].params,
            OptionsUtil::executor_encode_native_drop_option(amount, receiver)
        );
    }

    #[test]
    fn test_decode_type3_executor_with_1_option() {
        let execution_gas: u128 = 20000;
        let mut t3_option = OptionsUtil::new_options();
        t3_option.add_executor_lz_receive_option(execution_gas, 0);

        let (executor_options, _) = options_codec::decode_options(&t3_option.value).unwrap();
        assert_eq!(executor_options.len(), 1);
        assert_eq!(executor_options[0].option_type, options_codec::EXECUTOR_OPTION_TYPE_LZRECEIVE);
        assert_eq!(
            executor_options[0].params,
            OptionsUtil::executor_encode_lz_receive_option(execution_gas, 0)
        );
    }

    #[test]
    fn test_decode_type3_executor_with_n_option() {
        let execution_gas: u128 = 20000;
        let amount: u128 = 10000;
        let receiver = [1u8; 32];
        let mut t3_option = OptionsUtil::new_options();
        t3_option.add_executor_lz_receive_option(execution_gas, 0);
        t3_option.add_executor_native_drop_option(amount, receiver);

        let (executor_options, _) = options_codec::decode_options(&t3_option.value).unwrap();
        assert_eq!(executor_options.len(), 2);
        assert_eq!(executor_options[0].option_type, options_codec::EXECUTOR_OPTION_TYPE_LZRECEIVE);
        assert_eq!(
            executor_options[0].params,
            OptionsUtil::executor_encode_lz_receive_option(execution_gas, 0)
        );
        assert_eq!(
            executor_options[1].option_type,
            options_codec::EXECUTOR_OPTION_TYPE_NATIVE_DROP
        );
        assert_eq!(
            executor_options[1].params,
            OptionsUtil::executor_encode_native_drop_option(amount, receiver)
        );
    }

    #[test]
    fn test_decode_type3_dvn_with_1_option() {
        let mut t3_option = OptionsUtil::new_options();
        t3_option.add_dvn_precrime_option(1);

        let (_, dvn_options) = options_codec::decode_options(&t3_option.value).unwrap();
        let dvn_idx1_options = dvn_options.get(&1).unwrap();
        assert_eq!(dvn_idx1_options.len(), 1);
        assert_eq!(dvn_idx1_options[0].option_type, DVN_OPTION_TYPE_PRECRIME);
        assert_eq!(dvn_idx1_options[0].params.len(), 0);
    }

    #[test]
    fn test_decode_type3_dvn_with_n_option() {
        let mut t3_option = OptionsUtil::new_options();
        t3_option.add_dvn_precrime_option(1);
        t3_option.add_dvn_precrime_option(2);
        t3_option.add_dvn_precrime_option(3);
        t3_option.add_dvn_precrime_option(4);

        let (_, dvn_options) = options_codec::decode_options(&t3_option.value).unwrap();
        for i in 1..5 {
            println!("i: {}", i);
            let dvn_idx_options = dvn_options.get(&i).unwrap();
            assert_eq!(dvn_idx_options.len(), 1);
            assert_eq!(dvn_idx_options[0].option_type, DVN_OPTION_TYPE_PRECRIME);
            assert_eq!(dvn_idx_options[0].params.len(), 0);
        }
    }

    #[test]
    fn test_decode_type3_dvn_with_n_option_and_executor_with_n_option() {
        let execution_gas: u128 = 20000;
        let amount: u128 = 10000;
        let receiver = [1u8; 32];
        let mut t3_option = OptionsUtil::new_options();
        t3_option.add_dvn_precrime_option(1);
        t3_option.add_executor_lz_receive_option(execution_gas, 0);
        t3_option.add_dvn_precrime_option(2);
        t3_option.add_executor_native_drop_option(amount, receiver);
        t3_option.add_dvn_precrime_option(3);
        t3_option.add_dvn_precrime_option(4);

        let (executor_options, dvn_options) =
            options_codec::decode_options(&t3_option.value).unwrap();

        assert_eq!(executor_options.len(), 2);
        assert_eq!(executor_options[0].option_type, options_codec::EXECUTOR_OPTION_TYPE_LZRECEIVE);
        assert_eq!(
            executor_options[0].params,
            OptionsUtil::executor_encode_lz_receive_option(execution_gas, 0)
        );
        assert_eq!(
            executor_options[1].option_type,
            options_codec::EXECUTOR_OPTION_TYPE_NATIVE_DROP
        );
        assert_eq!(
            executor_options[1].params,
            OptionsUtil::executor_encode_native_drop_option(amount, receiver)
        );

        for i in 1..5 {
            let dvn_idx_options = dvn_options.get(&i).unwrap();
            assert_eq!(dvn_idx_options.len(), 1);
            assert_eq!(dvn_idx_options[0].option_type, DVN_OPTION_TYPE_PRECRIME);
            assert_eq!(dvn_idx_options[0].params.len(), 0);
        }
    }

    #[test]
    #[should_panic]
    fn test_decode_type3_options_invalid_size_longer() {
        // case 1: add one more byte to make it invalid
        let mut t3_option = OptionsUtil::new_options();
        t3_option.add_executor_lz_receive_option(20000, 0);
        t3_option.value.push(1);
        t3_option.value.push(2);
        assert!(options_codec::decode_options(&t3_option.value).is_err());
    }

    #[test]
    #[should_panic]
    fn test_decode_type3_options_invalid_size_shorter() {
        // case 2: remove the last byte to make it invalid
        let mut t3_option = OptionsUtil::new_options();
        t3_option.add_executor_lz_receive_option(20000, 0);
        t3_option.value.pop();
        assert!(options_codec::decode_options(&t3_option.value).is_err());
    }

    #[test]
    fn test_decode_type3_options_invalid_worker_id() {
        let worker_id = 0;
        let option_type = 1;

        let mut t3_option = OptionsUtil::new_options();
        t3_option.add_option(worker_id, option_type, vec![1, 2, 3, 4]);

        let result = options_codec::decode_options(&t3_option.value);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("InvalidWorkerId"));
    }

    #[test]
    fn test_decode_invalid_type() {
        let result = options_codec::decode_options(&vec![0, 4]); // type 4 is invalid
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("InvalidOptionType"));
    }
}
