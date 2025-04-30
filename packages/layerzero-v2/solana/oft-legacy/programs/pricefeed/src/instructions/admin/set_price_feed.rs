use crate::*;

#[derive(Accounts)]
#[instruction(params: SetPriceFeedParams)]
pub struct SetPriceFeed<'info> {
    #[account(mut)]
    pub admin: Signer<'info>,
    #[account(
        mut,
        seeds = [PRICE_FEED_SEED],
        bump = price_feed.bump,
        has_one = admin,
    )]
    pub price_feed: Account<'info, PriceFeed>,
}

impl SetPriceFeed<'_> {
    pub fn apply(ctx: &mut Context<SetPriceFeed>, params: &SetPriceFeedParams) -> Result<()> {
        let price_feed = &mut ctx.accounts.price_feed;

        require!(params.updaters.len() <= UPDATERS_MAX_LEN, PriceFeedError::TooManyUpdaters);
        price_feed.updaters = params.updaters.clone();
        price_feed.price_ratio_denominator = params.price_ratio_denominator;
        price_feed.arbitrum_compression_percent = params.arbitrum_compression_percent;

        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetPriceFeedParams {
    pub updaters: Vec<Pubkey>,
    pub price_ratio_denominator: u128,
    pub arbitrum_compression_percent: u128,
}
