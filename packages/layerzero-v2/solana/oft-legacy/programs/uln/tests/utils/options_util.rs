use primitive_types::U256;
use uln::options_codec;
use uln::options_codec::{DVN_WORKER_ID, EXECUTOR_OPTION_TYPE_LZRECEIVE, EXECUTOR_WORKER_ID};

pub const DVN_OPTION_TYPE_PRECRIME: u8 = 1;

pub struct OptionsUtil {
    pub value: Vec<u8>,
}

impl OptionsUtil {
    pub fn new_options() -> OptionsUtil {
        OptionsUtil { value: options_codec::TYPE_3.to_be_bytes().to_vec() }
    }

    pub fn add_executor_lz_receive_option(&mut self, gas: u128, value: u128) {
        self.add_executor_option(
            EXECUTOR_OPTION_TYPE_LZRECEIVE,
            Self::executor_encode_lz_receive_option(gas, value),
        );
    }

    pub fn add_executor_native_drop_option(&mut self, amount: u128, receiver: [u8; 32]) {
        self.add_executor_option(
            options_codec::EXECUTOR_OPTION_TYPE_NATIVE_DROP,
            Self::executor_encode_native_drop_option(amount, receiver),
        );
    }

    pub fn add_dvn_precrime_option(&mut self, dvn_idx: u8) {
        self.add_dvn_option(dvn_idx, DVN_OPTION_TYPE_PRECRIME, vec![]);
    }

    pub fn executor_encode_lz_receive_option(gas: u128, value: u128) -> Vec<u8> {
        if value == 0 {
            gas.to_be_bytes().to_vec()
        } else {
            [gas.to_be_bytes().to_vec(), value.to_be_bytes().to_vec()].concat()
        }
    }

    pub fn executor_encode_native_drop_option(amount: u128, receiver: [u8; 32]) -> Vec<u8> {
        [amount.to_be_bytes().to_vec(), receiver.to_vec()].concat()
    }

    pub fn add_option(&mut self, worker_id: u8, option_type: u8, option: Vec<u8>) {
        let bytes = [
            self.value.clone(),
            worker_id.to_be_bytes().to_vec(),
            ((option.len() as u16) + 1).to_be_bytes().to_vec(), // +1 for option_type
            option_type.to_be_bytes().to_vec(),
            option,
        ]
        .concat();
        self.value = bytes;
    }

    fn add_executor_option(&mut self, option_type: u8, option: Vec<u8>) {
        self.add_option(EXECUTOR_WORKER_ID, option_type, option);
    }

    fn add_dvn_option(&mut self, dvn_idx: u8, option_type: u8, option: Vec<u8>) {
        let bytes = [
            self.value.clone(),
            DVN_WORKER_ID.to_be_bytes().to_vec(),
            ((option.len() as u16) + 2).to_be_bytes().to_vec(), // +2 for option_type and dvn_idx
            dvn_idx.to_be_bytes().to_vec(),
            option_type.to_be_bytes().to_vec(),
            option,
        ]
        .concat();
        self.value = bytes;
    }

    pub fn encode_legacy_options_type1(execution_gas: U256) -> Vec<u8> {
        let mut bytes = vec![0u8; 32]; // U256 is always 32 bytes
        execution_gas.to_big_endian(&mut bytes);

        let t = options_codec::TYPE_1.to_be_bytes().to_vec();
        [t, bytes].concat()
    }

    pub fn encode_legacy_options_type2(
        execution_gas: U256,
        value: U256,
        receiver: [u8; 32],
    ) -> Vec<u8> {
        let mut bytes = vec![0u8; 32]; // U256 is always 32 bytes
        execution_gas.to_big_endian(&mut bytes);
        let mut bytes2 = vec![0u8; 32]; // U256 is always 32 bytes
        value.to_big_endian(&mut bytes2);

        let t = options_codec::TYPE_2.to_be_bytes().to_vec();
        [t, bytes, bytes2, receiver.to_vec()].concat()
    }
}
