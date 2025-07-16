use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: SetSendLibraryParams)]
pub struct SetSendLibrary<'info> {
    /// The PDA of the OApp or delegate
    pub signer: Signer<'info>,
    pub oapp_registry: UncheckedAccount<'info>,
    pub send_library_config: UncheckedAccount<'info>,
    pub message_lib_info: UncheckedAccount<'info>,
}

impl SetSendLibrary<'_> {
    pub fn apply(_ctx: &mut Context<SetSendLibrary>, _params: &SetSendLibraryParams) -> Result<()> {
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetSendLibraryParams {
    pub sender: Pubkey,
    pub eid: u32,
    pub new_lib: Pubkey,
}
