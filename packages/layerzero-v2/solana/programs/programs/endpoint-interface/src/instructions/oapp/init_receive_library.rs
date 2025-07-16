use crate::*;
use cpi_helper::CpiContext;

#[derive(CpiContext, Accounts)]
#[instruction(params: InitReceiveLibraryParams)]
pub struct InitReceiveLibrary<'info> {
    /// only the delegate can initialize the send_library_config
    #[account(mut)]
    pub delegate: Signer<'info>,
    pub oapp_registry: UncheckedAccount<'info>,
    pub receive_library_config: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
}

impl InitReceiveLibrary<'_> {
    pub fn apply(
        ctx: &mut Context<InitReceiveLibrary>,
        _params: &InitReceiveLibraryParams,
    ) -> Result<()> {
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitReceiveLibraryParams {
    pub receiver: Pubkey,
    pub eid: u32,
}
