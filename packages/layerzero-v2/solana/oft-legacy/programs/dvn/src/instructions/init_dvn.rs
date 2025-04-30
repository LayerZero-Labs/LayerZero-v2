use crate::*;

#[derive(Accounts)]
pub struct InitDvn<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(
        init,
        payer = payer,
        space = 8 + DvnConfig::INIT_SPACE,
        seeds = [DVN_CONFIG_SEED],
        bump
    )]
    pub config: Account<'info, DvnConfig>,
    pub system_program: Program<'info, System>,
}

impl InitDvn<'_> {
    pub fn apply(ctx: &mut Context<InitDvn>, params: &InitDvnParams) -> Result<()> {
        ctx.accounts.config.vid = params.vid;
        ctx.accounts.config.bump = ctx.bumps.config;

        // set quorum and signers
        ctx.accounts
            .config
            .set_multisig(Multisig { signers: params.signers.clone(), quorum: params.quorum })?;

        ctx.accounts.config.set_admins(params.admins.clone())?;
        ctx.accounts.config.set_msglibs(params.msglibs.clone())?;
        ctx.accounts.config.price_feed = params.price_feed;
        ctx.accounts.config.default_multiplier_bps = 12000; // 1.2x
        ctx.accounts.config.paused = false;

        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitDvnParams {
    vid: u32,
    msglibs: Vec<Pubkey>,
    price_feed: Pubkey,
    signers: Vec<[u8; 64]>,
    quorum: u8,
    admins: Vec<Pubkey>,
}
