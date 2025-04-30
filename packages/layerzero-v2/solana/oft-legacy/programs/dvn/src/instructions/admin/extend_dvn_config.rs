use crate::*;

#[derive(Accounts)]
pub struct ExtendDVNConfig<'info> {
    #[account(mut)]
    pub admin: Signer<'info>,
    #[account(
        mut,
        seeds = [DVN_CONFIG_SEED],
        bump = config.bump,
        realloc = 8 + DvnConfig::INIT_SPACE + DstConfig::INIT_SPACE * (DST_CONFIG_MAX_LEN - DST_CONFIG_DEFAULT_LEN),
        realloc::payer = admin,
        realloc::zero = false,
        constraint = config.admins.contains(admin.key) @DvnError::NotAdmin
    )]
    pub config: Account<'info, DvnConfig>,
    pub system_program: Program<'info, System>,
}

impl ExtendDVNConfig<'_> {
    pub fn apply(_ctx: &mut Context<ExtendDVNConfig>) -> Result<()> {
        Ok(())
    }
}
