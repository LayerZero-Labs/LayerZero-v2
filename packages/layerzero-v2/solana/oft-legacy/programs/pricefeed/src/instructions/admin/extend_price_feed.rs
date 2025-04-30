use crate::*;

#[derive(Accounts)]
pub struct ExtendPriceFeed<'info> {
    #[account(mut)]
    pub admin: Signer<'info>,
    #[account(
        mut,
        realloc = 8 + PriceFeed::INIT_SPACE + Price::INIT_SPACE * (PRICES_MAX_LEN - PRICES_DEFAULT_LEN),
        realloc::payer = admin,
        realloc::zero = false,
        has_one = admin,
    )]
    pub price_feed: Account<'info, PriceFeed>,
    pub system_program: Program<'info, System>,
}

impl ExtendPriceFeed<'_> {
    pub fn apply(_ctx: &mut Context<ExtendPriceFeed>) -> Result<()> {
        Ok(())
    }
}
