use crate::*;

#[derive(Accounts)]
#[instruction(params: InitPriceFeedParams)]
pub struct InitPriceFeed<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(
        init,
        payer = payer,
        space = 8 + PriceFeed::INIT_SPACE,
        seeds = [PRICE_FEED_SEED],
        bump
    )]
    pub price_feed: Account<'info, PriceFeed>,
    pub system_program: Program<'info, System>,
}

impl InitPriceFeed<'_> {
    pub fn apply(ctx: &mut Context<InitPriceFeed>, params: &InitPriceFeedParams) -> Result<()> {
        let price_feed = &mut ctx.accounts.price_feed;

        price_feed.admin = params.admin;
        require!(params.updaters.len() <= UPDATERS_MAX_LEN, PriceFeedError::TooManyUpdaters);
        price_feed.updaters = params.updaters.clone();
        price_feed.price_ratio_denominator = u128::pow(10, 20); // 1e20
        price_feed.arbitrum_compression_percent = 47;
        price_feed.native_token_price_usd = None;
        price_feed.bump = ctx.bumps.price_feed;

        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitPriceFeedParams {
    pub admin: Pubkey,
    pub updaters: Vec<Pubkey>,
}
