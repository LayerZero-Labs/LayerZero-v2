use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: LzComposeAlertParams)]
pub struct LzComposeAlert<'info> {
    pub executor: Signer<'info>,
}

impl LzComposeAlert<'_> {
    pub fn apply(ctx: &mut Context<LzComposeAlert>, params: &LzComposeAlertParams) -> Result<()> {
        emit_cpi!(LzComposeAlertEvent {
            executor: ctx.accounts.executor.key(),
            from: params.from,
            to: params.to,
            guid: params.guid,
            index: params.index,
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
pub struct LzComposeAlertParams {
    pub from: Pubkey,
    pub to: Pubkey,
    pub guid: [u8; 32],
    pub index: u16,
    pub compute_units: u64,
    pub value: u64,
    pub message: Vec<u8>,
    pub extra_data: Vec<u8>,
    pub reason: Vec<u8>,
}
