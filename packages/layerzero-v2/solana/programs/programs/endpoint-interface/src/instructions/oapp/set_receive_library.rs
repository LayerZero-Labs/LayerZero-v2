use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: SetReceiveLibraryParams)]
pub struct SetReceiveLibrary<'info> {
    /// The PDA of the OApp or delegate
    pub signer: Signer<'info>,
    pub oapp_registry: UncheckedAccount<'info>,
    pub receive_library_config: UncheckedAccount<'info>,
    pub message_lib_info: UncheckedAccount<'info>,
}

impl SetReceiveLibrary<'_> {
    pub fn apply(
        _ctx: &mut Context<SetReceiveLibrary>,
        _params: &SetReceiveLibraryParams,
    ) -> Result<()> {
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetReceiveLibraryParams {
    pub receiver: Pubkey,
    pub eid: u32,
    pub new_lib: Pubkey,
    pub grace_period: u64,
}
