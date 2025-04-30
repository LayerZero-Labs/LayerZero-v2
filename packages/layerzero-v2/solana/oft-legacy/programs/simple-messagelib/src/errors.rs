use anchor_lang::prelude::error_code;

#[error_code]
pub enum SimpleMessageLibError {
    OnlyWhitelistedCaller,
    InsufficientFee,
    InvalidAmount,
    InvalidConfigType,
    InvalidLzTokenMint,
    LzTokenUnavailable,
    SendReentrancy,
    OnlyRevert,
}
