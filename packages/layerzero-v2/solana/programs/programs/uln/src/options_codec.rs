use crate::*;
use messagelib_helper::utils::bytes_lib::BytesUtils;
use std::collections::HashMap;
use worker_interface::LzOption;

pub type DVNOptions = HashMap<u8, Vec<LzOption>>; // dvn_idx -> options

pub const TYPE_1: u16 = 1;
pub const TYPE_2: u16 = 2;
pub const TYPE_3: u16 = 3;

pub const EXECUTOR_WORKER_ID: u8 = 1;
pub const DVN_WORKER_ID: u8 = 2;

pub const EXECUTOR_OPTION_TYPE_LZRECEIVE: u8 = 1;
pub const EXECUTOR_OPTION_TYPE_NATIVE_DROP: u8 = 2;

pub fn decode_options(options: &[u8]) -> Result<(Vec<LzOption>, DVNOptions)> {
    let mut executor_options = Vec::new();
    let mut dvn_options = DVNOptions::new();

    // the first 2 bytes is the format type
    let format_type = options.to_u16(0);
    if format_type < TYPE_3 {
        executor_options = convert_legacy_options(format_type, &options)?;
        Ok((executor_options, dvn_options))
    } else if format_type == TYPE_3 {
        // type3 options: [worker_option][worker_option]...
        // worker_option: [worker_id][option_size][option]
        // option: [option_type][params]
        // worker_id: uint8, option_size: uint16, option: bytes, option_type: uint8, params: bytes
        let mut cursor = 2;
        while cursor < options.len() {
            let worker_id = options.to_u8(cursor);
            cursor += 1;
            let option_size = options.to_u16(cursor) as usize;
            cursor += 2;

            match worker_id {
                EXECUTOR_WORKER_ID => {
                    let option_type = options.to_u8(cursor);
                    let option_params = &options[cursor + 1..cursor + option_size];
                    cursor += option_size;
                    executor_options.push(LzOption { option_type, params: option_params.to_vec() })
                },
                DVN_WORKER_ID => {
                    let idx = options.to_u8(cursor);
                    let option_type = options.to_u8(cursor + 1);
                    let option_params = &options[cursor + 2..cursor + option_size];
                    cursor += option_size;

                    if let Some(options) = dvn_options.get_mut(&idx) {
                        options.push(LzOption { option_type, params: option_params.to_vec() });
                    } else {
                        dvn_options.insert(
                            idx,
                            vec![LzOption { option_type, params: option_params.to_vec() }],
                        );
                    }
                },
                _ => return Err(UlnError::InvalidWorkerId.into()),
            }
        }
        Ok((executor_options, dvn_options))
    } else {
        Err(UlnError::InvalidOptionType.into())
    }
}

// executor only
// legacy type 1
// bytes  [32      ]
// fields [extraGas]
// legacy type 2
// bytes  [32        32            bytes[]         ]
// fields [extraGas  dstNativeAmt  dstNativeAddress]
fn convert_legacy_options(format_type: u16, options: &[u8]) -> Result<Vec<LzOption>> {
    match format_type {
        TYPE_1 => {
            require!(options.len() == 34, UlnError::InvalidType1Size);
            require!(options.to_u128(2) == 0, UlnError::ExceededU128); // the gas amount should be <= u128::MAX
            let execution_gas = options.to_u128(18);
            Ok(vec![LzOption {
                option_type: EXECUTOR_OPTION_TYPE_LZRECEIVE,
                params: execution_gas.to_be_bytes().to_vec(),
            }])
        },
        TYPE_2 => {
            require!(options.len() > 66 && options.len() <= 98, UlnError::InvalidType2Size);
            require!(options.to_u128(2) == 0, UlnError::ExceededU128); // the gas amount should be <= u128::MAX
            let execution_gas = options.to_u128(18);
            require!(options.to_u128(34) == 0, UlnError::ExceededU128); // the native drop amount should be <= u128::MAX
            let native_drop_amount = options.to_u128(50);
            let receiver_bytes = &options[66..];

            // convert receiver to [0;32]
            let mut native_drop_params = Vec::with_capacity(48); // 16 + 32
            native_drop_params.extend_from_slice(&native_drop_amount.to_be_bytes());
            native_drop_params.extend_from_slice(&receiver_bytes[..32]);

            Ok(vec![
                LzOption {
                    option_type: EXECUTOR_OPTION_TYPE_LZRECEIVE,
                    params: execution_gas.to_be_bytes().to_vec(),
                },
                LzOption {
                    option_type: EXECUTOR_OPTION_TYPE_NATIVE_DROP,
                    params: native_drop_params,
                },
            ])
        },
        _ => return Err(UlnError::InvalidOptionType.into()),
    }
}
