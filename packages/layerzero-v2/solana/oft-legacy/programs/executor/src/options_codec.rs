use crate::*;
use utils::bytes_lib::BytesUtils;

pub const OPTION_TYPE_LZRECEIVE: u8 = 1;
pub const OPTION_TYPE_NATIVE_DROP: u8 = 2;
pub const OPTION_TYPE_LZCOMPOSE: u8 = 3;
pub const OPTION_TYPE_ORDERED_EXECUTION: u8 = 4;

pub fn decode_lz_receive_params(params: &[u8]) -> Result<(u128, u128)> {
    require!(params.len() == 16 || params.len() == 32, ExecutorError::InvalidSize);
    let gas = params.to_u128(0);
    let value = if params.len() == 32 { params.to_u128(16) } else { 0 };
    Ok((gas, value))
}

pub fn decode_native_drop_params(params: &[u8]) -> Result<(u128, [u8; 32])> {
    require!(params.len() == 48, ExecutorError::InvalidSize);
    let amount = params.to_u128(0);
    let receiver = params.to_byte_array(16);
    Ok((amount, receiver))
}

pub fn decode_lz_compose_params(params: &[u8]) -> Result<(u16, u128, u128)> {
    require!(params.len() == 18 || params.len() == 34, ExecutorError::InvalidSize);
    let index = params.to_u16(0);
    let gas = params.to_u128(2);
    let value = if params.len() == 34 { params.to_u128(18) } else { 0 };
    Ok((index, gas, value))
}
