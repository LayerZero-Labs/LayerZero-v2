use crate::*;
use utils::sorted_list_helper;

#[derive(Accounts)]
#[instruction(params: GetFeeParams)]
pub struct GetFee<'info> {
    #[account(seeds = [PRICE_FEED_SEED], bump = price_feed.bump)]
    pub price_feed: Account<'info, PriceFeed>,
}

impl GetFee<'_> {
    pub fn apply(
        ctx: &Context<GetFee>,
        params: GetFeeParams,
    ) -> Result<(u128, u128, u128, Option<u128>)> {
        let price_feed = &ctx.accounts.price_feed;

        let price = sorted_list_helper::get_from_sorted_list_by_eid(
            &price_feed.prices,
            params.dst_eid % EID_MODULUS,
        )?;
        let fee = match price.model_type {
            None => price_feed.estimate_fee_with_default_model(
                price,
                params.calldata_size,
                params.total_gas,
            ),
            Some(ModelType::Arbitrum { gas_per_l2_tx, gas_per_l1_calldata_byte }) => price_feed
                .estimate_fee_with_arbitrum_model(
                    price,
                    params.calldata_size,
                    params.total_gas,
                    gas_per_l2_tx,
                    gas_per_l1_calldata_byte,
                )?,
            Some(ModelType::Optimism { l1_eid }) => {
                let l1_price = sorted_list_helper::get_from_sorted_list_by_eid(
                    &price_feed.prices,
                    l1_eid % EID_MODULUS,
                )?;
                price_feed.estimate_fee_with_optimism_model(
                    price,
                    params.calldata_size,
                    params.total_gas,
                    l1_price,
                )?
            },
        };
        Ok((
            fee,
            price.price_ratio,
            price_feed.price_ratio_denominator,
            price_feed.native_token_price_usd,
        ))
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct GetFeeParams {
    pub dst_eid: u32,
    pub calldata_size: u64,
    pub total_gas: u128,
}

impl PriceFeed {
    fn estimate_fee_with_default_model(
        &self,
        price: &Price,
        calldata_size: u64,
        gas: u128,
    ) -> u128 {
        let gas_for_calldata = calldata_size * price.gas_per_byte as u64;
        return (gas + gas_for_calldata as u128)
            * price.gas_price_in_unit as u128
            * price.price_ratio
            / self.price_ratio_denominator;
    }

    fn estimate_fee_with_optimism_model(
        &self,
        price: &Price,
        calldata_size: u64,
        gas: u128,
        l1_price: &Price,
    ) -> Result<u128> {
        // L1 fee
        let gas_for_l1_calldata = calldata_size * l1_price.gas_per_byte as u64 + 3188; // 2100 + 68 * 16
        let l1_fee = gas_for_l1_calldata * l1_price.gas_price_in_unit;
        let l1_fee = l1_fee as u128 * l1_price.price_ratio / self.price_ratio_denominator;

        // L2 fee
        let gas_for_l2_calldata = calldata_size * price.gas_per_byte as u64;
        let l2_fee = (gas + gas_for_l2_calldata as u128)
            * price.gas_price_in_unit as u128
            * price.price_ratio
            / self.price_ratio_denominator;

        Ok(l2_fee + l1_fee)
    }

    fn estimate_fee_with_arbitrum_model(
        &self,
        price: &Price,
        calldata_size: u64,
        gas: u128,
        gas_per_l2_tx: u64,
        gas_per_l1_calldata_byte: u32,
    ) -> Result<u128> {
        // L1 fee
        let gas_for_l1_calldata = calldata_size * gas_per_l1_calldata_byte as u64;

        // L2 fee
        let gas_for_l2_calldata = calldata_size * price.gas_per_byte as u64;

        let total_gas =
            gas + gas_per_l2_tx as u128 + gas_for_l1_calldata as u128 + gas_for_l2_calldata as u128;
        let total_fee = total_gas * price.gas_price_in_unit as u128 * price.price_ratio
            / self.price_ratio_denominator;

        Ok(total_fee)
    }
}
