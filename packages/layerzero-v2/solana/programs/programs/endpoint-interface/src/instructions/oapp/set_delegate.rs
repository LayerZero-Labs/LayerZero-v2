use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: RegisterOAppParams)]
pub struct SetDelegate<'info> {
    /// The PDA of the OApp
    pub oapp: Signer<'info>,
    pub oapp_registry: UncheckedAccount<'info>,
}

impl SetDelegate<'_> {
    pub fn apply(ctx: &mut Context<SetDelegate>, params: &SetDelegateParams) -> Result<()> {
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetDelegateParams {
    pub delegate: Pubkey,
}
