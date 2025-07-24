use crate::*;

#[derive(Accounts)]
#[instruction(params: InitSendLibraryParams)]
pub struct InitSendLibrary<'info> {
    /// only the delegate can initialize the send_library_config
    #[account(mut)]
    pub delegate: Signer<'info>,
    #[account(
        seeds = [OAPP_SEED, params.sender.as_ref()],
        bump = oapp_registry.bump,
        has_one = delegate
    )]
    pub oapp_registry: Account<'info, OAppRegistry>,
    #[account(
        init,
        payer = delegate,
        space = 8 + SendLibraryConfig::INIT_SPACE,
        seeds = [SEND_LIBRARY_CONFIG_SEED, &params.sender.to_bytes(), &params.eid.to_be_bytes()],
        bump
    )]
    pub send_library_config: Account<'info, SendLibraryConfig>,
    pub system_program: Program<'info, System>,
}



#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitSendLibraryParams {
    pub sender: Pubkey,
    pub eid: u32,
}
