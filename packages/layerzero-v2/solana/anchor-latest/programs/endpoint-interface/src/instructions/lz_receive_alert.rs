use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: LzReceiveAlertParams)]
pub struct LzReceiveAlert<'info> {
    pub executor: Signer<'info>,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct LzReceiveAlertParams {
    pub receiver: Pubkey,
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub nonce: u64,
    pub guid: [u8; 32],
    pub compute_units: u64,
    pub value: u64,
    pub message: Vec<u8>,
    pub extra_data: Vec<u8>,
    pub reason: Vec<u8>,
}
