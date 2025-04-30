use crate::*;
use pricefeed::instructions::GetFeeParams;
use std::collections::HashMap;
use utils::sorted_list_helper;
use worker_interface::{worker_utils, QuoteExecutorParams};

#[derive(Accounts)]
#[instruction(params: QuoteExecutorParams)]
pub struct Quote<'info> {
    #[account(seeds = [EXECUTOR_CONFIG_SEED], bump = executor_config.bump)]
    pub executor_config: Account<'info, ExecutorConfig>,
    #[account(address = price_feed_config.owner.clone())]
    pub price_feed_program: AccountInfo<'info>,
    #[account(address = executor_config.price_feed)]
    pub price_feed_config: AccountInfo<'info>,
}

impl Quote<'_> {
    pub fn apply(ctx: &Context<Quote>, params: &QuoteExecutorParams) -> Result<u64> {
        require!(!ctx.accounts.executor_config.paused, ExecutorError::Paused);
        let config = &ctx.accounts.executor_config;

        config.acl.assert_permission(&params.sender)?;
        if config.msglibs.len() > 0 {
            require!(
                config.msglibs.binary_search(&params.msglib).is_ok(),
                ExecutorError::MsgLibNotAllowed
            );
        }

        let dst_config =
            sorted_list_helper::get_from_sorted_list_by_eid(&config.dst_configs, params.dst_eid)?;
        require!(dst_config.lz_receive_base_gas > 0, ExecutorError::EidNotSupported);

        let mut total_dst_amount: u128 = 0;
        let mut ordered = false;

        let mut unique_lz_compose_idx = Vec::new();
        let mut total_lz_compose_gas: HashMap<u16, u128> = HashMap::new();
        let mut total_lz_receive_gas: u128 = 0;
        for option in params.options.clone() {
            match option.option_type {
                OPTION_TYPE_LZRECEIVE => {
                    let (gas, value) = decode_lz_receive_params(&option.params)?;
                    total_dst_amount += value;
                    total_lz_receive_gas += gas;
                },
                OPTION_TYPE_NATIVE_DROP => {
                    let (amount, _) = decode_native_drop_params(&option.params)?;
                    total_dst_amount += amount;
                },
                OPTION_TYPE_LZCOMPOSE => {
                    let (index, gas, value) = decode_lz_compose_params(&option.params)?;

                    total_dst_amount += value;
                    // update lz compose gas by index
                    if let Some(lz_compose_gas) = total_lz_compose_gas.get(&index) {
                        total_lz_compose_gas.insert(index, lz_compose_gas + gas);
                    } else {
                        total_lz_compose_gas.insert(index, gas);
                        unique_lz_compose_idx.push(index);
                    }
                },
                OPTION_TYPE_ORDERED_EXECUTION => {
                    ordered = true;
                },
                _ => return Err(ExecutorError::UnsupportedOptionType.into()),
            }
        }

        require!(
            total_dst_amount <= dst_config.native_drop_cap,
            ExecutorError::NativeAmountExceedsCap
        );

        // validate lzComposeGas and lzReceiveGas
        require!(total_lz_receive_gas > 0, ExecutorError::ZeroLzReceiveGasProvided);
        let mut total_gas = dst_config.lz_receive_base_gas as u128 + total_lz_receive_gas;

        for idx in unique_lz_compose_idx {
            let lz_compose_gas = total_lz_compose_gas.get(&idx).unwrap();
            require!(*lz_compose_gas > 0, ExecutorError::ZeroLzComposeGasProvided);
            total_gas += dst_config.lz_compose_base_gas as u128 + *lz_compose_gas;
        }

        if ordered {
            total_gas = total_gas * 102 / 100; // 2% extra gas for ordered
        }

        let get_fee_params = GetFeeParams {
            dst_eid: params.dst_eid,
            calldata_size: params.calldata_size,
            total_gas,
        };
        let cpi_ctx = CpiContext::new(
            ctx.accounts.price_feed_program.to_account_info(),
            pricefeed::cpi::accounts::GetFee {
                price_feed: ctx.accounts.price_feed_config.to_account_info(),
            },
        );
        let (mut fee_for_gas, price_ratio, price_ration_denominator, native_token_price_usd) =
            pricefeed::cpi::get_fee(cpi_ctx, get_fee_params)?.get();

        let multiplier_bps = if let Some(multiplier_bps) = dst_config.multiplier_bps {
            multiplier_bps as u128
        } else {
            config.default_multiplier_bps as u128
        };

        fee_for_gas = worker_utils::increase_fee_with_multiplier_or_floor_margin(
            fee_for_gas,
            multiplier_bps,
            dst_config.floor_margin_usd,
            native_token_price_usd,
        );

        let fee_for_amount =
            total_dst_amount * price_ratio * multiplier_bps / price_ration_denominator / 10000;

        let total_fee = fee_for_gas + fee_for_amount;
        Ok(worker_utils::safe_convert_u128_to_u64(total_fee)?)
    }
}
