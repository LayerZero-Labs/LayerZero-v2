use crate::*;

#[derive(Accounts)]
#[instruction(params: CloseExecuteParams)]
pub struct CloseExecute<'info> {
    pub admin: Signer<'info>,
    #[account(
        mut,
        seeds = [DVN_CONFIG_SEED],
        bump = config.bump,
        constraint = config.admins.contains(admin.key) @DvnError::NotAdmin
    )]
    pub config: Account<'info, DvnConfig>,
    #[account(
        mut,
        seeds = [EXECUTE_HASH_SEED, &params.digest_hash],
        bump = execute_hash.bump,
        constraint = execute_hash.expiration <= Clock::get()?.unix_timestamp @DvnError::UnexpiredExecuteHash,
        close = config
    )]
    pub execute_hash: Account<'info, ExecuteHash>,
}

impl CloseExecute<'_> {
    pub fn apply(_ctx: &mut Context<CloseExecute>, _params: &CloseExecuteParams) -> Result<()> {
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct CloseExecuteParams {
    pub digest_hash: [u8; 32],
}
