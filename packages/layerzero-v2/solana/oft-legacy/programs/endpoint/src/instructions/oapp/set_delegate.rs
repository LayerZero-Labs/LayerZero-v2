use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: RegisterOAppParams)]
pub struct SetDelegate<'info> {
    /// The PDA of the OApp
    pub oapp: Signer<'info>,
    #[account(
        mut,
        seeds = [OAPP_SEED, oapp.key.as_ref()],
        bump = oapp_registry.bump
    )]
    pub oapp_registry: Account<'info, OAppRegistry>,
}

impl SetDelegate<'_> {
    pub fn apply(ctx: &mut Context<SetDelegate>, params: &SetDelegateParams) -> Result<()> {
        ctx.accounts.oapp_registry.delegate = params.delegate;
        emit_cpi!(DelegateSetEvent { new_delegate: params.delegate });
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetDelegateParams {
    pub delegate: Pubkey,
}
