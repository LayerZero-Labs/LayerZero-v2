use crate::*;

#[event_cpi]
#[derive(Accounts)]
pub struct TransferAdmin<'info> {
    pub admin: Signer<'info>,
    #[account(mut, has_one = admin, seeds = [ULN_SEED], bump = uln.bump)]
    pub uln: Account<'info, UlnSettings>,
}

impl TransferAdmin<'_> {
    pub fn apply(ctx: &mut Context<TransferAdmin>, params: &TransferAdminParams) -> Result<()> {
        ctx.accounts.uln.admin = params.admin;
        emit_cpi!(AdminTransferredEvent { new_admin: params.admin });
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct TransferAdminParams {
    pub admin: Pubkey,
}
