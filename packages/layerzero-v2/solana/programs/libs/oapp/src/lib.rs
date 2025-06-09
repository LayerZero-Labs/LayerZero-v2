use anchor_lang::prelude::*;

pub mod endpoint_cpi;
pub mod lz_receive_v2;
pub mod options;

pub use endpoint;

pub const LZ_RECEIVE_TYPES_SEED: &[u8] = b"LzReceiveTypes";

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct LzReceiveParams {
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub nonce: u64,
    pub guid: [u8; 32],
    pub message: Vec<u8>,
    pub extra_data: Vec<u8>,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct LzComposeParams {
    pub from: Pubkey,
    pub to: Pubkey,
    pub guid: [u8; 32],
    pub index: u16,
    pub message: Vec<u8>,
    pub extra_data: Vec<u8>,
}

#[error_code]
pub enum ErrorCode {
    #[msg("Invalid address lookup table data")]
    InvalidAddressLookupTable,
}

pub type AltIndex = (u8, u8); // (alt_index, address_index_within_alt)
