pub mod worker_utils;

use anchor_lang::prelude::*;

declare_id!("2iENutMTfTfxdFEjEQSbFCBstZqakXFZQCLZLLk4Ti58");

#[program]
pub mod worker_interface {
    use super::*;

    pub fn quote_executor(_ctx: Context<Quote>, _params: QuoteExecutorParams) -> Result<u64> {
        Ok(0)
    }

    pub fn quote_dvn(_ctx: Context<Quote>, _params: QuoteDvnParams) -> Result<u64> {
        Ok(0)
    }
}

#[derive(Accounts)]
pub struct Quote<'info> {
    pub worker_config: UncheckedAccount<'info>,
    pub price_feed_program: UncheckedAccount<'info>,
    pub price_feed_config: UncheckedAccount<'info>,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct QuoteExecutorParams {
    pub msglib: Pubkey,
    pub dst_eid: u32,
    pub sender: Pubkey,
    pub calldata_size: u64,
    pub options: Vec<LzOption>,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct QuoteDvnParams {
    pub msglib: Pubkey,
    pub dst_eid: u32,
    pub sender: Pubkey,
    pub packet_header: Vec<u8>,
    pub payload_hash: [u8; 32],
    pub confirmations: u64,
    pub options: Vec<LzOption>,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize, Debug)]
pub struct LzOption {
    pub option_type: u8,
    pub params: Vec<u8>,
}

#[error_code]
pub enum WorkerError {
    PermissionDenied,
    InvalidSize,
}
