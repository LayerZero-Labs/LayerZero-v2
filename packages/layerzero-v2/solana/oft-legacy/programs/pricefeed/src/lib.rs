use anchor_lang::prelude::*;
pub mod errors;
pub mod instructions;
pub mod state;

use errors::*;
use instructions::*;
use solana_helper::program_id_from_env;
pub use state::*;

declare_id!(Pubkey::new_from_array(program_id_from_env!(
    "PRICEFEED_ID",
    "8ahPGPjEbpgGaZx2NV1iG5Shj7TDwvsjkEDcGWjt94TP"
)));

pub const PRICE_FEED_SEED: &[u8] = b"PriceFeed";
pub const PRICE_SEED: &[u8] = b"Price";

#[program]
pub mod pricefeed {
    use super::*;

    /// --------------------------- Admin Instructions ---------------------------
    pub fn init_price_feed(
        mut ctx: Context<InitPriceFeed>,
        params: InitPriceFeedParams,
    ) -> Result<()> {
        InitPriceFeed::apply(&mut ctx, &params)
    }

    pub fn extend_price_feed(mut ctx: Context<ExtendPriceFeed>) -> Result<()> {
        ExtendPriceFeed::apply(&mut ctx)
    }

    pub fn set_price_feed(
        mut ctx: Context<SetPriceFeed>,
        params: SetPriceFeedParams,
    ) -> Result<()> {
        SetPriceFeed::apply(&mut ctx, &params)
    }

    pub fn transfer_admin(
        mut ctx: Context<TransferAdmin>,
        params: TransferAdminParams,
    ) -> Result<()> {
        TransferAdmin::apply(&mut ctx, &params)
    }

    /// --------------------------- Updater Instructions --------------------------
    pub fn set_price(mut ctx: Context<SetPrice>, params: SetPriceParams) -> Result<()> {
        SetPrice::apply(&mut ctx, params)
    }
    pub fn set_sol_price(mut ctx: Context<SetSolPrice>, params: SetSolPriceParams) -> Result<()> {
        SetSolPrice::apply(&mut ctx, params)
    }

    /// --------------------------- Getter Instructions ---------------------------
    pub fn get_fee(
        ctx: Context<GetFee>,
        params: GetFeeParams,
    ) -> Result<(u128, u128, u128, Option<u128>)> {
        GetFee::apply(&ctx, params)
    }
}
