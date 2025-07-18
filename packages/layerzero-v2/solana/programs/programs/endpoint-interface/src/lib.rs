pub mod errors;
pub mod instructions;
pub mod state;

use anchor_lang::prelude::*;
use anchor_lang::solana_program;
use errors::*;
use instructions::*;
pub use messagelib_interface::{
    InitConfigParams, MessageLibType, MessagingFee, MessagingReceipt, SetConfigParams,
};
use state::*;

declare_id!("76y77prsiCMvXMjuoZ5VRrhG5qYBrUMYTE5WgHqgjEn6");

pub const ENDPOINT_SEED: &[u8] = b"Endpoint";
pub const MESSAGE_LIB_SEED: &[u8] = b"MessageLib";
pub const SEND_LIBRARY_CONFIG_SEED: &[u8] = b"SendLibraryConfig";
pub const RECEIVE_LIBRARY_CONFIG_SEED: &[u8] = b"ReceiveLibraryConfig";
pub const NONCE_SEED: &[u8] = b"Nonce";
pub const PENDING_NONCE_SEED: &[u8] = b"PendingNonce";
pub const PAYLOAD_HASH_SEED: &[u8] = b"PayloadHash";
pub const COMPOSED_MESSAGE_HASH_SEED: &[u8] = b"ComposedMessageHash";
pub const OAPP_SEED: &[u8] = b"OApp";

pub const DEFAULT_MESSAGE_LIB: Pubkey = Pubkey::new_from_array([0u8; 32]);

#[program]
pub mod endpoint_interface {
    use super::*;

    pub fn verify(_ctx: Context<Verify>, _params: VerifyParams) -> Result<()> {
        Ok(())
    }

    pub fn lz_compose_alert(
        _ctx: Context<LzComposeAlert>,
        _params: LzComposeAlertParams,
    ) -> Result<()> {
        Ok(())
    }

    pub fn lz_receive_alert(
        _ctx: Context<LzReceiveAlert>,
        _params: LzReceiveAlertParams,
    ) -> Result<()> {
        Ok(())
    }

    /// --------------------------- OApp Instructions ---------------------------
    pub fn burn(_ctx: Context<Burn>, _params: BurnParams) -> Result<()> {
        Ok(())
    }

    pub fn clear_compose(_ctx: Context<ClearCompose>, _params: ClearComposeParams) -> Result<()> {
        Ok(())
    }

    pub fn clear(_ctx: Context<Clear>, _params: ClearParams) -> Result<[u8; 32]> {
        Ok([0u8; 32])
    }

    pub fn init_config(_ctx: Context<InitConfig>, _params: InitConfigParams) -> Result<()> {
        Ok(())
    }

    pub fn init_nonce(_ctx: Context<InitNonce>, _params: InitNonceParams) -> Result<()> {
        Ok(())
    }

    pub fn init_receive_library(
        _ctx: Context<InitReceiveLibrary>,
        _params: InitReceiveLibraryParams,
    ) -> Result<()> {
        Ok(())
    }

    pub fn init_send_library(
        _ctx: Context<InitSendLibrary>,
        _params: InitSendLibraryParams,
    ) -> Result<()> {
        Ok(())
    }

    pub fn nilify(_ctx: Context<Nilify>, _params: NilifyParams) -> Result<()> {
        Ok(())
    }

    pub fn quote(_ctx: Context<Quote>, _params: QuoteParams) -> Result<MessagingFee> {
        Ok(MessagingFee { native_fee: 0, lz_token_fee: 0 })
    }

    pub fn register_oapp(_ctx: Context<RegisterOApp>, _params: RegisterOAppParams) -> Result<()> {
        Ok(())
    }

    pub fn send_compose(_ctx: Context<SendCompose>, _params: SendComposeParams) -> Result<()> {
        Ok(())
    }

    pub fn send(_ctx: Context<Send>, _params: SendParams) -> Result<MessagingReceipt> {
        Ok(MessagingReceipt::default())
    }

    pub fn set_config(_ctx: Context<SetConfig>, _params: SetConfigParams) -> Result<()> {
        Ok(())
    }

    pub fn set_delegate(_ctx: Context<SetDelegate>, _params: SetDelegateParams) -> Result<()> {
        Ok(())
    }

    pub fn set_receive_library_timeout(
        _ctx: Context<SetReceiveLibraryTimeout>,
        _params: SetReceiveLibraryTimeoutParams,
    ) -> Result<()> {
        Ok(())
    }

    pub fn set_receive_library(
        _ctx: Context<SetReceiveLibrary>,
        _params: SetReceiveLibraryParams,
    ) -> Result<()> {
        Ok(())
    }

    pub fn set_send_library(
        _ctx: Context<SetSendLibrary>,
        _params: SetSendLibraryParams,
    ) -> Result<()> {
        Ok(())
    }

    pub fn skip(_ctx: Context<Skip>, _params: SkipParams) -> Result<()> {
        Ok(())
    }
}

pub trait ConstructCPIContext<'a, 'b, 'c, 'info, T>
where
    T: ToAccountMetas + ToAccountInfos<'info>,
{
    const MIN_ACCOUNTS_LEN: usize;

    fn construct_context(
        program_id: Pubkey,
        accounts: &[AccountInfo<'info>],
    ) -> Result<CpiContext<'a, 'b, 'c, 'info, T>>;
}
