use crate::*;

#[derive(Accounts)]
pub struct ExtendExecutorConfig<'info> {
    #[account(mut)]
    pub admin: Signer<'info>,
    #[account(
        mut,
        seeds = [EXECUTOR_CONFIG_SEED],
        bump = config.bump,
		realloc = 8 + ExecutorConfig::INIT_SPACE + DstConfig::INIT_SPACE * (DST_CONFIG_MAX_LEN - DST_CONFIG_DEFAULT_LEN),
        realloc::payer = admin,
        realloc::zero = false,
        constraint = config.admins.contains(admin.key) @ExecutorError::NotAdmin
    )]
    pub config: Account<'info, ExecutorConfig>,
    pub system_program: Program<'info, System>,
}

impl ExtendExecutorConfig<'_> {
    pub fn apply(_ctx: &mut Context<ExtendExecutorConfig>) -> Result<()> {
        Ok(())
    }
}
