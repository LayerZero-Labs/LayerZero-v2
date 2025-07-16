pub mod instructions;

use anchor_lang::prelude::*;
use instructions::*;
pub use messagelib_interface::{InitConfigParams, MessagingFee, MessagingReceipt, SetConfigParams};

declare_id!("FGNZea2SzeNM8pdugux1qnrMwRzdNb4McX25FtKWe72y");

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

    pub fn verify(mut ctx: Context<Verify>, params: VerifyParams) -> Result<()> {
        Verify::apply(&mut ctx, &params)
    }

    pub fn lz_compose_alert(mut ctx: Context<LzComposeAlert>, params: LzComposeAlertParams) -> Result<()> {
        LzComposeAlert::apply(&mut ctx, &params)
    }

    pub fn lz_receive_alert(mut ctx: Context<LzReceiveAlert>, params: LzReceiveAlertParams) -> Result<()> {
        LzReceiveAlert::apply(&mut ctx, &params)
    }

    /// --------------------------- OApp Instructions ---------------------------
    pub fn burn(mut ctx: Context<Burn>, params: BurnParams) -> Result<()> {
        Burn::apply(&mut ctx, &params)
    }

    pub fn clear_compose(mut ctx: Context<ClearCompose>, params: ClearComposeParams) -> Result<()> {
        ClearCompose::apply(&mut ctx, &params)
    }

    pub fn clear(mut ctx: Context<Clear>, params: ClearParams) -> Result<[u8; 32]> {
        Clear::apply(&mut ctx, &params)
    }

    pub fn init_config(mut ctx: Context<InitConfig>, params: InitConfigParams) -> Result<()> {
        InitConfig::apply(&mut ctx, &params)
    }

    pub fn init_nonce(mut ctx: Context<InitNonce>, params: InitNonceParams) -> Result<()> {
        InitNonce::apply(&mut ctx, &params)
    }

    pub fn init_receive_library(
        mut ctx: Context<InitReceiveLibrary>,
        params: InitReceiveLibraryParams,
    ) -> Result<()> {
        InitReceiveLibrary::apply(&mut ctx, &params)
    }

    pub fn init_send_library(
        mut ctx: Context<InitSendLibrary>,
        params: InitSendLibraryParams,
    ) -> Result<()> {
        InitSendLibrary::apply(&mut ctx, &params)
    }

    pub fn nilify(mut ctx: Context<Nilify>, params: NilifyParams) -> Result<()> {
        Nilify::apply(&mut ctx, &params)
    }

    pub fn quote(mut ctx: Context<Quote>, params: QuoteParams) -> Result<MessagingFee> {
        Quote::apply(&mut ctx, &params)
    }

    pub fn register_oapp(mut ctx: Context<RegisterOApp>, params: RegisterOAppParams) -> Result<()> {
        RegisterOApp::apply(&mut ctx, &params)
    }

    pub fn send_compose(mut ctx: Context<SendCompose>, params: SendComposeParams) -> Result<()> {
        SendCompose::apply(&mut ctx, &params)
    }

    pub fn send(mut ctx: Context<Send>, params: SendParams) -> Result<MessagingReceipt> {
        Send::apply(&mut ctx, &params)
    }

    pub fn set_config(mut ctx: Context<SetConfig>, params: SetConfigParams) -> Result<()> {
        SetConfig::apply(&mut ctx, &params)
    }

    pub fn set_delegate(mut ctx: Context<SetDelegate>, params: SetDelegateParams) -> Result<()> {
        SetDelegate::apply(&mut ctx, &params)
    }

    pub fn set_receive_library_timeout(
        mut ctx: Context<SetReceiveLibraryTimeout>,
        params: SetReceiveLibraryTimeoutParams,
    ) -> Result<()> {
        SetReceiveLibraryTimeout::apply(&mut ctx, &params)
    }

    pub fn set_receive_library(
        mut ctx: Context<SetReceiveLibrary>,
        params: SetReceiveLibraryParams,
    ) -> Result<()> {
        SetReceiveLibrary::apply(&mut ctx, &params)
    }

    pub fn set_send_library(
        mut ctx: Context<SetSendLibrary>,
        params: SetSendLibraryParams,
    ) -> Result<()> {
        SetSendLibrary::apply(&mut ctx, &params)
    }

    pub fn skip(mut ctx: Context<Skip>, params: SkipParams) -> Result<()> {
        Skip::apply(&mut ctx, &params)
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
