use crate::*;
use cpi_helper::CpiContext;

#[derive(CpiContext, Accounts)]
#[instruction(params: InitNonceParams)]
pub struct InitNonce<'info> {
    /// only the delegate can initialize the nonce accounts
    #[account(mut)]
    pub delegate: Signer<'info>,
    pub oapp_registry: UncheckedAccount<'info>,
    pub nonce: UncheckedAccount<'info>,
    pub pending_inbound_nonce: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
}

impl InitNonce<'_> {
    pub fn apply(_ctx: &mut Context<InitNonce>, _params: &InitNonceParams) -> Result<()> {
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitNonceParams {
    local_oapp: Pubkey, // the PDA of the OApp
    remote_eid: u32,
    remote_oapp: [u8; 32],
}
