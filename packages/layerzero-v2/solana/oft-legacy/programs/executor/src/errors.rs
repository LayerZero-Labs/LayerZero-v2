use anchor_lang::prelude::error_code;

#[error_code]
pub enum ExecutorError {
    InvalidSize,
    Paused,
    UnsupportedOptionType,
    ZeroLzComposeGasProvided,
    ZeroLzReceiveGasProvided,
    NativeAmountExceedsCap,
    NotAdmin,
    NotExecutor,
    MsgLibNotAllowed,
    TooManyAdmins,
    TooManyExecutors,
    TooManyOptionTypes,
    InvalidNativeDropRequestsLength,
    InvalidNativeDropReceiver,
    InsufficientBalance,
    EidNotSupported,
    ExecutorIsAdmin,
    InvalidOwner,
}
