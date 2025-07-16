use crate::*;
use cpi_helper::CpiContext;

#[derive(CpiContext, Accounts)]
#[instruction(params: SetConfigParams)]
pub struct SetConfig<'info> {
    /// The PDA of the OApp or delegate
    pub signer: Signer<'info>,
    pub oapp_registry: UncheckedAccount<'info>,
    /// The PDA signer to the message lib when the endpoint calls the message lib program
    pub message_lib_info: UncheckedAccount<'info>,
    /// the pda of the message_lib_program
    pub message_lib: UncheckedAccount<'info>,
    /// CHECK: already checked with the message_lib account
    pub message_lib_program: UncheckedAccount<'info>,
}

impl SetConfig<'_> {
    pub fn apply(_ctx: &mut Context<SetConfig>, _params: &SetConfigParams) -> Result<()> {
        Ok(())
    }
}
