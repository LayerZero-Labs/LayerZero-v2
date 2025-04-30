pub mod errors;
pub mod events;
pub mod instructions;
pub mod state;

use anchor_lang::prelude::*;
use errors::*;
use events::*;
use instructions::*;
use solana_helper::program_id_from_env;
use state::*;
use worker_interface::QuoteDvnParams;

declare_id!(Pubkey::new_from_array(program_id_from_env!(
    "DVN_ID",
    "HtEYV4xB4wvsj5fgTkcfuChYpvGYzgzwvNhgDZQNh7wW"
)));

pub const DVN_CONFIG_SEED: &[u8] = b"DvnConfig";
pub const EXECUTE_HASH_SEED: &[u8] = b"ExecuteHash";

#[program]
pub mod dvn {
    use super::*;

    pub fn init_dvn(mut ctx: Context<InitDvn>, params: InitDvnParams) -> Result<()> {
        InitDvn::apply(&mut ctx, &params)
    }

    /// --------------------------- Admin Instructions ---------------------------
    pub fn set_config(mut ctx: Context<SetConfig>, params: SetConfigParams) -> Result<()> {
        SetConfig::apply(&mut ctx, &params)
    }

    pub fn extend_dvn_config(mut ctx: Context<ExtendDVNConfig>) -> Result<()> {
        ExtendDVNConfig::apply(&mut ctx)
    }

    pub fn invoke(mut ctx: Context<Invoke>, params: InvokeParams) -> Result<()> {
        Invoke::apply(&mut ctx, &params)
    }

    pub fn close_execute(mut ctx: Context<CloseExecute>, params: CloseExecuteParams) -> Result<()> {
        CloseExecute::apply(&mut ctx, &params)
    }

    pub fn withdraw_fee(mut ctx: Context<WithdrawFee>, params: WithdrawFeeParams) -> Result<()> {
        WithdrawFee::apply(&mut ctx, &params)
    }

    /// --------------------------- MsgLib Instructions ---------------------------
    pub fn quote_dvn(ctx: Context<Quote>, params: QuoteDvnParams) -> Result<u64> {
        Quote::apply(&ctx, &params)
    }

    pub fn verifiable(
        ctx: Context<Verifiable>,
        params: VerifiableParams,
    ) -> Result<VerificationState> {
        Verifiable::apply(&ctx, &params)
    }
}
