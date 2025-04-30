use crate::*;
use pricefeed::instructions::GetFeeParams;
use utils::sorted_list_helper;
use worker_interface::worker_utils;

#[derive(Accounts)]
#[instruction(params: QuoteDvnParams)]
pub struct Quote<'info> {
    #[account(seeds = [DVN_CONFIG_SEED], bump = dvn_config.bump)]
    pub dvn_config: Account<'info, DvnConfig>,
    #[account(address = price_feed_config.owner.clone())]
    pub price_feed_program: AccountInfo<'info>,
    #[account(address = dvn_config.price_feed)]
    pub price_feed_config: AccountInfo<'info>,
}

impl Quote<'_> {
    pub fn apply(ctx: &Context<Quote>, params: &QuoteDvnParams) -> Result<u64> {
        let config = &ctx.accounts.dvn_config;
        require!(!config.paused, DvnError::Paused);

        config.acl.assert_permission(&params.sender)?;
        if config.msglibs.len() > 0 {
            require!(
                config.msglibs.binary_search(&params.msglib).is_ok(),
                DvnError::MsgLibNotAllowed
            );
        }

        let total_signature_bytes = config.multisig.quorum as u64 * SIGNATURE_RAW_BYTES as u64;
        let total_signature_bytes_padded = if total_signature_bytes % 32 == 0 {
            total_signature_bytes
        } else {
            total_signature_bytes + 32 - (total_signature_bytes % 32)
        };

        // getFee should charge on execute(updateHash)
        // totalSignatureBytesPadded also has 64 overhead for bytes
        let calldata_size = EXECUTE_FIXED_BYTES + VERIFY_BYTES + total_signature_bytes_padded + 64;

        let dst_config =
            sorted_list_helper::get_from_sorted_list_by_eid(&config.dst_configs, params.dst_eid)?;
        require!(dst_config.dst_gas > 0, DvnError::EidNotSupported);

        let get_fee_params = GetFeeParams {
            dst_eid: params.dst_eid,
            calldata_size,
            total_gas: dst_config.dst_gas as u128,
        };
        let cpi_ctx = CpiContext::new(
            ctx.accounts.price_feed_program.to_account_info(),
            pricefeed::cpi::accounts::GetFee {
                price_feed: ctx.accounts.price_feed_config.to_account_info(),
            },
        );
        let (fee, _, _, native_token_price_usd) =
            pricefeed::cpi::get_fee(cpi_ctx, get_fee_params)?.get();

        let multiplier_bps = if let Some(multiplier_bps) = dst_config.multiplier_bps {
            multiplier_bps
        } else {
            config.default_multiplier_bps
        };

        let fee = worker_utils::increase_fee_with_multiplier_or_floor_margin(
            fee,
            multiplier_bps as u128,
            dst_config.floor_margin_usd,
            native_token_price_usd,
        );

        Ok(worker_utils::safe_convert_u128_to_u64(fee)?)
    }
}
