use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: LzReceiveAlertParams)]
pub struct LzReceiveAlert<'info> {
    pub executor: Signer<'info>,
}

impl LzReceiveAlert<'_> {
    pub fn apply(ctx: &mut Context<LzReceiveAlert>, params: &LzReceiveAlertParams) -> Result<()> {
        emit_cpi!(LzReceiveAlertEvent {
            receiver: params.receiver,
            executor: ctx.accounts.executor.key(),
            src_eid: params.src_eid,
            sender: params.sender,
            nonce: params.nonce,
            guid: params.guid,
            compute_units: params.compute_units,
            value: params.value,
            message: params.message.clone(),
            extra_data: params.extra_data.clone(),
            reason: params.reason.clone()
        });
        Ok(())
    }
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
