use crate::*;
use cpi_helper::CpiContext;

#[derive(CpiContext, Accounts)]
#[instruction(params: InitSendLibraryParams)]
pub struct InitSendLibrary<'info> {
    /// only the delegate can initialize the send_library_config
    #[account(mut)]
    pub delegate: Signer<'info>, 
    pub oapp_registry: UncheckedAccount<'info>,
    pub send_library_config: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
}

impl InitSendLibrary<'_> {
    pub fn apply(
        ctx: &mut Context<InitSendLibrary>,
        _params: &InitSendLibraryParams,
    ) -> Result<()> {
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitSendLibraryParams {
    pub sender: Pubkey,
    pub eid: u32,
}
