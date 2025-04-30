use anchor_lang::prelude::*;

pub mod compose_msg_codec;
mod errors;
mod events;
mod instructions;
pub mod msg_codec;
pub mod state;

use errors::*;
use events::*;
use instructions::*;
use oapp::{
    endpoint::{MessagingFee, MessagingReceipt},
    LzReceiveParams,
};
use solana_helper::program_id_from_env;
use state::*;

declare_id!(Pubkey::new_from_array(program_id_from_env!(
    "OFT_ID",
    "HRPXLCqspQocTjfcX4rvAPaY9q6Gwb1rrD3xXWrfJWdW"
)));

pub const OFT_VERSION: u64 = 1;
pub const OFT_SDK_VERSION: u64 = 1;
pub const OFT_SEED: &[u8] = b"Oft";
pub const PEER_SEED: &[u8] = b"Peer";
pub const ENFORCED_OPTIONS_SEED: &[u8] = b"EnforcedOptions";
pub const LZ_RECEIVE_TYPES_SEED: &[u8] = oapp::LZ_RECEIVE_TYPES_SEED;

#[program]
pub mod oft {
    use super::*;

    pub fn version(_ctx: Context<GetVersion>) -> Result<Version> {
        Ok(Version { sdk_version: OFT_SDK_VERSION, oft_version: OFT_VERSION })
    }

    pub fn init_oft(mut ctx: Context<InitOft>, params: InitOftParams) -> Result<()> {
        InitOft::apply(&mut ctx, &params)
    }

    pub fn init_adapter_oft(
        mut ctx: Context<InitAdapterOft>,
        params: InitAdapterOftParams,
    ) -> Result<()> {
        InitAdapterOft::apply(&mut ctx, &params)
    }

    // ============================== Admin ==============================
    pub fn transfer_admin(
        mut ctx: Context<TransferAdmin>,
        params: TransferAdminParams,
    ) -> Result<()> {
        TransferAdmin::apply(&mut ctx, &params)
    }

    pub fn set_peer(mut ctx: Context<SetPeer>, params: SetPeerParams) -> Result<()> {
        SetPeer::apply(&mut ctx, &params)
    }

    pub fn set_enforced_options(
        mut ctx: Context<SetEnforcedOptions>,
        params: SetEnforcedOptionsParams,
    ) -> Result<()> {
        SetEnforcedOptions::apply(&mut ctx, &params)
    }

    pub fn set_mint_authority(
        mut ctx: Context<SetMintAuthority>,
        params: SetMintAuthorityParams,
    ) -> Result<()> {
        SetMintAuthority::apply(&mut ctx, &params)
    }

    pub fn mint_to(mut ctx: Context<MintTo>, params: MintToParams) -> Result<()> {
        MintTo::apply(&mut ctx, &params)
    }

    // ============================== Public ==============================

    pub fn quote_oft(ctx: Context<QuoteOft>, params: QuoteOftParams) -> Result<QuoteOftResult> {
        QuoteOft::apply(&ctx, &params)
    }

    pub fn quote(ctx: Context<Quote>, params: QuoteParams) -> Result<MessagingFee> {
        Quote::apply(&ctx, &params)
    }

    pub fn send(mut ctx: Context<Send>, params: SendParams) -> Result<MessagingReceipt> {
        Send::apply(&mut ctx, &params)
    }

    pub fn lz_receive(mut ctx: Context<LzReceive>, params: LzReceiveParams) -> Result<()> {
        LzReceive::apply(&mut ctx, &params)
    }

    pub fn lz_receive_types(
        ctx: Context<LzReceiveTypes>,
        params: LzReceiveParams,
    ) -> Result<Vec<oapp::endpoint_cpi::LzAccount>> {
        LzReceiveTypes::apply(&ctx, &params)
    }

    pub fn set_rate_limit(
        mut ctx: Context<SetRateLimit>,
        params: SetRateLimitParams,
    ) -> Result<()> {
        SetRateLimit::apply(&mut ctx, &params)
    }

    // Set the LayerZero endpoint delegate for OApp admin functions
    pub fn set_delegate(mut ctx: Context<SetDelegate>, params: SetDelegateParams) -> Result<()> {
        SetDelegate::apply(&mut ctx, &params)
    }
}

#[derive(Accounts)]
pub struct GetVersion {}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct Version {
    pub sdk_version: u64,
    pub oft_version: u64,
}
