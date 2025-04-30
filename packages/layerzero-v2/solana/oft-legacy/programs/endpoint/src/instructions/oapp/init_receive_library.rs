use crate::*;

#[derive(Accounts)]
#[instruction(params: InitReceiveLibraryParams)]
pub struct InitReceiveLibrary<'info> {
    /// only the delegate can initialize the send_library_config
    #[account(mut)]
    pub delegate: Signer<'info>,
    #[account(
        seeds = [OAPP_SEED, params.receiver.as_ref()],
        bump = oapp_registry.bump,
        has_one = delegate
    )]
    pub oapp_registry: Account<'info, OAppRegistry>,
    #[account(
        init,
        payer = delegate,
        space = 8 + ReceiveLibraryConfig::INIT_SPACE,
        seeds = [RECEIVE_LIBRARY_CONFIG_SEED, &params.receiver.to_bytes(), &params.eid.to_be_bytes()],
        bump
    )]
    pub receive_library_config: Account<'info, ReceiveLibraryConfig>,
    pub system_program: Program<'info, System>,
}

impl InitReceiveLibrary<'_> {
    pub fn apply(
        ctx: &mut Context<InitReceiveLibrary>,
        _params: &InitReceiveLibraryParams,
    ) -> Result<()> {
        ctx.accounts.receive_library_config.message_lib = DEFAULT_MESSAGE_LIB;
        ctx.accounts.receive_library_config.timeout = None;
        ctx.accounts.receive_library_config.bump = ctx.bumps.receive_library_config;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitReceiveLibraryParams {
    pub receiver: Pubkey,
    pub eid: u32,
}
