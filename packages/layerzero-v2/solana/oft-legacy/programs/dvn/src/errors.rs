use anchor_lang::prelude::error_code;

#[error_code]
pub enum DvnError {
    InvalidSignatureLen,
    NotAdmin,
    MsgLibNotAllowed,
    InvalidQuorum,
    InvalidSignersLen,
    UniqueOwners,
    SignatureError,
    SignerNotInCommittee,
    TooManyAdmins,
    TooManyOptionTypes,
    DuplicateSignature,
    Expired,
    InvalidVid,
    Paused,
    UnexpiredExecuteHash,
    InvalidAmount,
    EidNotSupported,
}
