use crate::*;
use cpi_helper::CpiContext;

/// to initialize the configuration of an oapp in a certain message library
#[derive(CpiContext, Accounts)]
#[instruction(params: InitConfigParams)]
pub struct InitConfig<'info> {
    /// only the delegate can initialize the config accounts
    pub delegate: Signer<'info>,
    pub oapp_registry: UncheckedAccount<'info>,
    /// The PDA signer to the message lib when the endpoint calls the message lib program.
    pub message_lib_info: UncheckedAccount<'info>,
    /// the pda of the message_lib_program
    pub message_lib: UncheckedAccount<'info>,
    /// CHECK: already checked with the message_lib account
    pub message_lib_program: UncheckedAccount<'info>,
}

impl InitConfig<'_> {
    pub fn apply(_ctx: &mut Context<InitConfig>, _params: &InitConfigParams) -> Result<()> {
        Ok(())
    }
}
