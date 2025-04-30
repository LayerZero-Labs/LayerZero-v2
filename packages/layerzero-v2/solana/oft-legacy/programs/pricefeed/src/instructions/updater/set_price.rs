use crate::*;
use utils::sorted_list_helper;

#[derive(Accounts)]
#[instruction(params: SetPriceParams)]
pub struct SetPrice<'info> {
    pub updater: Signer<'info>,
    #[account(
        mut,
        seeds = [PRICE_FEED_SEED],
        bump = price_feed.bump,
        constraint = price_feed.updaters.contains(&updater.key()) @PriceFeedError::InvalidUpdater
    )]
    pub price_feed: Account<'info, PriceFeed>,
}

impl SetPrice<'_> {
    pub fn apply(ctx: &mut Context<SetPrice>, params: SetPriceParams) -> Result<()> {
        if let Some(price_params) = params.params {
            let price = Price {
                eid: params.dst_eid,
                price_ratio: price_params.price_ratio,
                gas_price_in_unit: price_params.gas_price_in_unit,
                gas_per_byte: price_params.gas_per_byte,
                model_type: price_params.model_type,
            };
            let account_size = ctx.accounts.price_feed.to_account_info().data_len();
            let max_len = if account_size > (PriceFeed::INIT_SPACE + 8) {
                PRICES_MAX_LEN
            } else {
                PRICES_DEFAULT_LEN
            };
            sorted_list_helper::insert_or_update_sorted_list_by_eid(
                &mut ctx.accounts.price_feed.prices,
                price,
                max_len,
            )
        } else {
            sorted_list_helper::remove_from_sorted_list_by_eid(
                &mut ctx.accounts.price_feed.prices,
                params.dst_eid,
            )
        }
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetPriceParams {
    pub dst_eid: u32,
    pub params: Option<PriceParams>,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct PriceParams {
    pub price_ratio: u128,
    pub gas_price_in_unit: u64,
    pub gas_per_byte: u32,
    pub model_type: Option<ModelType>,
}
