pub mod errors;
pub mod events;
pub mod instructions;
pub mod options_codec;
pub mod state;

use anchor_lang::prelude::*;
use errors::*;
use events::*;
use instructions::*;
use messagelib_helper::messagelib_interface::{
    InitConfigParams, MessagingFee, QuoteParams, SendParams, SendWithLzTokenParams,
    SetConfigParams, Version,
};
use options_codec::*;
use solana_helper::program_id_from_env;
use state::*;

declare_id!(Pubkey::new_from_array(program_id_from_env!(
    "ULN_ID",
    "7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH"
)));

pub const PACKET_VERSION: u8 = 1;

pub const ULN_SEED: &[u8] = messagelib_helper::MESSAGE_LIB_SEED;
pub const SEND_CONFIG_SEED: &[u8] = b"SendConfig";
pub const RECEIVE_CONFIG_SEED: &[u8] = b"ReceiveConfig";
pub const CONFIRMATIONS_SEED: &[u8] = b"Confirmations";

pub const BPS_DENOMINATOR: u64 = 10000;

#[program]
pub mod uln {
    use super::*;

    pub fn version(_ctx: Context<GetVersion>) -> Result<Version> {
        Ok(Version { major: 3, minor: 0, endpoint_version: 2 })
    }

    /// --------------------------- ULN Admin Instructions ---------------------------
    pub fn init_uln(mut ctx: Context<InitUln>, params: InitUlnParams) -> Result<()> {
        InitUln::apply(&mut ctx, &params)
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

    pub fn transfer_admin(
        mut ctx: Context<TransferAdmin>,
        params: TransferAdminParams,
    ) -> Result<()> {
        TransferAdmin::apply(&mut ctx, &params)
    }

    pub fn set_treasury(mut ctx: Context<SetTreasury>, params: SetTreasuryParams) -> Result<()> {
        SetTreasury::apply(&mut ctx, &params)
    }

    pub fn withdraw_rent(mut ctx: Context<WithdrawRent>, params: WithdrawRentParams) -> Result<()> {
        WithdrawRent::apply(&mut ctx, &params)
    }

    /// --------------------------- Endpoint Instructions ---------------------------
    pub fn init_config(mut ctx: Context<InitConfig>, params: InitConfigParams) -> Result<()> {
        InitConfig::apply(&mut ctx, &params)
    }

    pub fn set_config(mut ctx: Context<SetConfig>, params: SetConfigParams) -> Result<()> {
        SetConfig::apply(&mut ctx, &params)
    }

    pub fn quote(ctx: Context<Quote>, params: QuoteParams) -> Result<MessagingFee> {
        Quote::apply(&ctx, &params)
    }

    pub fn send<'c: 'info, 'info>(
        mut ctx: Context<'_, '_, 'c, 'info, Send<'info>>,
        params: SendParams,
    ) -> Result<(MessagingFee, Vec<u8>)> {
        Send::apply(&mut ctx, &params)
    }

    pub fn send_with_lz_token<'c: 'info, 'info>(
        mut ctx: Context<'_, '_, 'c, 'info, SendWithLzToken<'info>>,
        params: SendWithLzTokenParams,
    ) -> Result<(MessagingFee, Vec<u8>)> {
        SendWithLzToken::apply(&mut ctx, &params)
    }

    /// --------------------------- DVN Instructions ---------------------------
    pub fn init_verify(mut ctx: Context<InitVerify>, params: InitVerifyParams) -> Result<()> {
        InitVerify::apply(&mut ctx, &params)
    }

    pub fn verify(mut ctx: Context<Verify>, params: VerifyParams) -> Result<()> {
        Verify::apply(&mut ctx, &params)
    }

    pub fn close_verify(_ctx: Context<CloseVerify>, _params: CloseVerifyParams) -> Result<()> {
        CloseVerify::apply()
    }

    pub fn commit_verification(
        mut ctx: Context<CommitVerification>,
        params: CommitVerificationParams,
    ) -> Result<()> {
        CommitVerification::apply(&mut ctx, &params)
    }
}

#[derive(Accounts)]
pub struct GetVersion {}
