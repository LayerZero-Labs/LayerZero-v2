mod errors;
mod instructions;
mod revert_call_test;
mod state;

use anchor_lang::prelude::*;
use errors::*;
use instructions::*;
use messagelib_helper::messagelib_interface::{
    InitConfigParams, MessagingFee, QuoteParams, SendParams, SendWithLzTokenParams,
    SetConfigParams, Version,
};
use revert_call_test::*;
use solana_helper::program_id_from_env;
use state::*;

declare_id!(Pubkey::new_from_array(program_id_from_env!(
    "SIMPLE_MESSAGELIB_ID",
    "6GsmxMTHAAiFKfemuM4zBjumTjNSX5CAiw4xSSXM2Toy"
)));

pub const MESSAGE_LIB_SEED: &[u8] = messagelib_helper::MESSAGE_LIB_SEED;
pub const SEND_CONFIG_SEED: &[u8] = b"SendConfig";
pub const RECEIVE_CONFIG_SEED: &[u8] = b"ReceiveConfig";

#[program]
pub mod simple_messagelib {
    use super::*;

    pub fn version(_ctx: Context<GetVersion>) -> Result<Version> {
        Ok(Version { major: 0, minor: 0, endpoint_version: 2 })
    }

    pub fn init_message_lib(
        mut ctx: Context<InitMessageLib>,
        params: InitMessageLibParams,
    ) -> Result<()> {
        InitMessageLib::apply(&mut ctx, &params)
    }

    /// --------------------------- Admin Instructions ---------------------------
    pub fn transfer_admin(
        mut ctx: Context<TransferAdmin>,
        params: TransferAdminParams,
    ) -> Result<()> {
        TransferAdmin::apply(&mut ctx, &params)
    }

    pub fn set_wl_caller(mut ctx: Context<SetWlCaller>, params: SetWlCallerParams) -> Result<()> {
        SetWlCaller::apply(&mut ctx, &params)
    }

    pub fn set_fee(mut ctx: Context<SetFee>, params: SetFeeParams) -> Result<()> {
        SetFee::apply(&mut ctx, &params)
    }

    pub fn withdraw_fees(mut ctx: Context<WithdrawFees>, params: WithdrawFeesParams) -> Result<()> {
        WithdrawFees::apply(&mut ctx, &params)
    }

    pub fn init_default_config(
        mut ctx: Context<InitDefaultConfig>,
        params: InitDefaultConfigParams,
    ) -> Result<()> {
        InitDefaultConfig::apply(&mut ctx, &params)
    }

    pub fn set_default_config(
        mut ctx: Context<SetDefaultConfig>,
        params: SetDefaultConfigParams,
    ) -> Result<()> {
        SetDefaultConfig::apply(&mut ctx, &params)
    }

    /// --------------------------- WhitelistedCaller Instructions ---------------------------
    pub fn validate_packet(
        mut ctx: Context<ValidatePacket>,
        params: ValidatePacketParams,
    ) -> Result<()> {
        ValidatePacket::apply(&mut ctx, &params)
    }

    /// --------------------------- Endpoint Instructions ---------------------------
    pub fn send(mut ctx: Context<Send>, params: SendParams) -> Result<(MessagingFee, Vec<u8>)> {
        Send::apply(&mut ctx, &params)
    }
    pub fn send_with_lz_token(
        mut ctx: Context<SendWithLzToken>,
        params: SendWithLzTokenParams,
    ) -> Result<(MessagingFee, Vec<u8>)> {
        SendWithLzToken::apply(&mut ctx, &params)
    }

    pub fn quote(ctx: Context<Quote>, params: QuoteParams) -> Result<MessagingFee> {
        Quote::apply(&ctx, &params)
    }

    /// --------------------------- Endpoint Instructions ---------------------------
    pub fn init_config(mut ctx: Context<InitConfig>, params: InitConfigParams) -> Result<()> {
        InitConfig::apply(&mut ctx, &params)
    }

    pub fn set_config(mut ctx: Context<SetConfig>, params: SetConfigParams) -> Result<()> {
        SetConfig::apply(&mut ctx, &params)
    }

    /// --------------------------- For Test ---------------------------
    pub fn revert_call(mut ctx: Context<RevertCall>) -> Result<()> {
        RevertCall::apply(&mut ctx)
    }
}

#[derive(Accounts)]
pub struct GetVersion {}
