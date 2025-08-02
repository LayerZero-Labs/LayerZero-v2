use crate::*;
use messagelib_interface::MessageLibType;

pub const EMPTY_PAYLOAD_HASH: [u8; 32] = [0u8; 32];
pub const NIL_PAYLOAD_HASH: [u8; 32] = [0xffu8; 32];

pub const PENDING_INBOUND_NONCE_MAX_LEN: u64 = 256;

#[account]
#[derive(InitSpace)]
pub struct EndpointSettings {
    // immutable
    pub eid: u32,
    pub bump: u8,
    // configurable
    pub admin: Pubkey,
    pub lz_token_mint: Option<Pubkey>,
}

#[account]
#[derive(InitSpace)]
pub struct OAppRegistry {
    pub delegate: Pubkey,
    pub bump: u8,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize, InitSpace)]
pub struct SendContext {
    pub dst_eid: u32,
    pub sender: Pubkey,
}

#[account]
#[derive(InitSpace)]
pub struct Nonce {
    pub bump: u8,
    pub outbound_nonce: u64,
    pub inbound_nonce: u64,
}

#[account]
#[derive(InitSpace)]
pub struct PendingInboundNonce {
    #[max_len(PENDING_INBOUND_NONCE_MAX_LEN)]
    pub nonces: Vec<u64>,
    pub bump: u8,
}

#[account]
#[derive(InitSpace)]
pub struct PayloadHash {
    pub hash: [u8; 32],
    pub bump: u8,
}

#[account]
#[derive(InitSpace)]
pub struct ComposeMessageState {
    pub received: bool,
    pub bump: u8,
}

#[account]
#[derive(InitSpace)]
pub struct MessageLibInfo {
    pub message_lib_type: MessageLibType,
    // bump for this pda
    pub bump: u8,
    // bump for the pda of the message lib program with the seeds `[MESSAGE_LIB_SEED]`
    pub message_lib_bump: u8,
}

/// the reason for not using Option::None to indicate default is to respect the spec on evm
#[account]
#[derive(InitSpace)]
pub struct SendLibraryConfig {
    pub message_lib: Pubkey,
    pub bump: u8,
}

#[account]
#[derive(InitSpace)]
pub struct ReceiveLibraryConfig {
    pub message_lib: Pubkey,
    pub timeout: Option<ReceiveLibraryTimeout>,
    pub bump: u8,
}

#[derive(InitSpace, Clone, AnchorSerialize, AnchorDeserialize)]
pub struct ReceiveLibraryTimeout {
    pub message_lib: Pubkey,
    pub expiry: u64, // slot number
}
