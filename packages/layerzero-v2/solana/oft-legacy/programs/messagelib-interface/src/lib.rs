use anchor_lang::prelude::*;

declare_id!("J8tfaWEsewRGacgvAeQsXLTRTuUQz5FGyUuqDW2TpiTJ");

#[program]
pub mod messagelib_interface {
    use super::*;

    pub fn send(_ctx: Context<Interface>, _params: SendParams) -> Result<(MessagingFee, Vec<u8>)> {
        Ok((MessagingFee::default(), Vec::new()))
    }

    pub fn send_with_lz_token(
        _ctx: Context<Interface>,
        _params: SendWithLzTokenParams,
    ) -> Result<(MessagingFee, Vec<u8>)> {
        Ok((MessagingFee::default(), Vec::new()))
    }

    pub fn quote(_ctx: Context<Interface>, _params: QuoteParams) -> Result<MessagingFee> {
        Ok(MessagingFee::default())
    }

    pub fn init_config(_ctx: Context<Interface>, _params: InitConfigParams) -> Result<()> {
        Ok(())
    }

    pub fn set_config(_ctx: Context<Interface>, _params: SetConfigParams) -> Result<()> {
        Ok(())
    }
}

#[derive(Accounts)]
pub struct Interface<'info> {
    pub endpoint: Signer<'info>,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SendParams {
    pub packet: Packet,
    pub options: Vec<u8>,
    pub native_fee: u64,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SendWithLzTokenParams {
    pub packet: Packet,
    pub options: Vec<u8>,
    pub native_fee: u64,
    pub lz_token_fee: u64,
    pub lz_token_mint: Pubkey,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct QuoteParams {
    pub packet: Packet,
    pub options: Vec<u8>,
    pub pay_in_lz_token: bool,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct Packet {
    pub nonce: u64,
    pub src_eid: u32,
    pub sender: Pubkey,
    pub dst_eid: u32,
    pub receiver: [u8; 32],
    pub guid: [u8; 32],
    pub message: Vec<u8>,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize, Default)]
pub struct MessagingFee {
    pub native_fee: u64,
    pub lz_token_fee: u64,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize, Default)]
pub struct MessagingReceipt {
    pub guid: [u8; 32],
    pub nonce: u64,
    pub fee: MessagingFee,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitConfigParams {
    pub oapp: Pubkey,
    pub eid: u32,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetConfigParams {
    pub oapp: Pubkey,
    pub eid: u32,
    pub config_type: u32,
    pub config: Vec<u8>,
}

#[derive(InitSpace, Clone, AnchorSerialize, AnchorDeserialize, PartialEq)]
pub enum MessageLibType {
    Send,
    Receive,
    SendAndReceive,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct Version {
    pub major: u64,
    pub minor: u8,
    pub endpoint_version: u8,
}
