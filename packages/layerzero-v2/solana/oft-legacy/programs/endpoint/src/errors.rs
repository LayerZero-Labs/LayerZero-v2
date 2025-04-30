use anchor_lang::prelude::error_code;

#[error_code]
pub enum LayerZeroError {
    InvalidSendLibrary,
    InvalidReceiveLibrary,
    SameValue,
    AccountNotFound,
    OnlySendLib,
    OnlyReceiveLib,
    InvalidExpiry,
    OnlyNonDefaultLib,
    InvalidAmount,
    InvalidNonce,
    Unauthorized,
    PayloadHashNotFound,
    ComposeNotFound,
    InvalidPayloadHash,
    LzTokenUnavailable,
    ReadOnlyAccount,
    InvalidMessageLib,
    WritableAccountNotAllowed,
}
