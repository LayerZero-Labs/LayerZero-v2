use crate::*;

#[derive(Accounts)]
pub struct SetSolPrice<'info> {
    pub updater: Signer<'info>,
    #[account(
        mut,
        seeds = [PRICE_FEED_SEED],
        bump = price_feed.bump,
        constraint = price_feed.updaters.contains(&updater.key()) @PriceFeedError::InvalidUpdater
    )]
    pub price_feed: Account<'info, PriceFeed>,
}

impl SetSolPrice<'_> {
    pub fn apply(ctx: &mut Context<SetSolPrice>, params: SetSolPriceParams) -> Result<()> {
        let price = &mut ctx.accounts.price_feed;
        price.native_token_price_usd = params.native_token_price_usd;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetSolPriceParams {
    pub native_token_price_usd: Option<u128>,
}
