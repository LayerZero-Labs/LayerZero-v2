use crate::*;

#[derive(Accounts)]
#[instruction(params: TransferAdminParams)]
pub struct TransferAdmin<'info> {
    pub admin: Signer<'info>,
    #[account(
        mut,
        seeds = [PRICE_FEED_SEED],
        bump = price_feed.bump,
        has_one = admin,
    )]
    pub price_feed: Account<'info, PriceFeed>,
}

impl TransferAdmin<'_> {
    pub fn apply(ctx: &mut Context<TransferAdmin>, params: &TransferAdminParams) -> Result<()> {
        let price_feed = &mut ctx.accounts.price_feed;
        price_feed.admin = params.admin;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct TransferAdminParams {
    pub admin: Pubkey,
}
