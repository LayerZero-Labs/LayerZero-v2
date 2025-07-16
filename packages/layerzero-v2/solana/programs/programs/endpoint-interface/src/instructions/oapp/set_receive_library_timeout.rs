use crate::*;
use cpi_helper::CpiContext;

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: SetReceiveLibraryTimeoutParams)]
pub struct SetReceiveLibraryTimeout<'info> {
    /// The PDA of the OApp or delegate
    pub signer: Signer<'info>,
    pub oapp_registry: UncheckedAccount<'info>,
    pub receive_library_config: UncheckedAccount<'info>,
    pub message_lib_info: UncheckedAccount<'info>,
}

impl SetReceiveLibraryTimeout<'_> {
    pub fn apply(
        _ctx: &mut Context<SetReceiveLibraryTimeout>,
        _params: &SetReceiveLibraryTimeoutParams,
    ) -> Result<()> {
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetReceiveLibraryTimeoutParams {
    pub receiver: Pubkey,
    pub eid: u32,
    pub lib: Pubkey,
    pub expiry: u64,
}
