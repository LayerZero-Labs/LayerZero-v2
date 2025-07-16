use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: ClearComposeParams)]
pub struct ClearCompose<'info> {
    pub to: Signer<'info>,
    pub compose_message: UncheckedAccount<'info>,
}

impl ClearCompose<'_> {
    pub fn apply(_ctx: &mut Context<ClearCompose>, _params: &ClearComposeParams) -> Result<()> {
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct ClearComposeParams {
    pub from: Pubkey,
    pub guid: [u8; 32],
    pub index: u16,
    pub message: Vec<u8>,
}
