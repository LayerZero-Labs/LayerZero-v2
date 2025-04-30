use crate::*;

#[event]
pub struct OAppRegisteredEvent {
    pub oapp: Pubkey,
    pub delegate: Pubkey,
}

#[event]
pub struct PacketSentEvent {
    pub encoded_packet: Vec<u8>,
    pub options: Vec<u8>,
    pub send_library: Pubkey,
}

#[event]
pub struct PacketVerifiedEvent {
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub receiver: Pubkey,
    pub nonce: u64,
    pub payload_hash: [u8; 32],
}

#[event]
pub struct PacketDeliveredEvent {
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub receiver: Pubkey,
    pub nonce: u64,
}

#[event]
pub struct InboundNonceSkippedEvent {
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub receiver: Pubkey,
    pub nonce: u64,
}

#[event]
pub struct PacketNilifiedEvent {
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub receiver: Pubkey,
    pub nonce: u64,
    pub payload_hash: [u8; 32],
}

#[event]
pub struct PacketBurntEvent {
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub receiver: Pubkey,
    pub nonce: u64,
    pub payload_hash: [u8; 32],
}

#[event]
pub struct ComposeSentEvent {
    pub from: Pubkey,
    pub to: Pubkey,
    pub guid: [u8; 32],
    pub index: u16,
    pub message: Vec<u8>,
}

#[event]
pub struct ComposeDeliveredEvent {
    pub from: Pubkey,
    pub to: Pubkey,
    pub guid: [u8; 32],
    pub index: u16,
}

#[event]
pub struct LzReceiveAlertEvent {
    pub receiver: Pubkey,
    pub executor: Pubkey,
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub nonce: u64,
    pub guid: [u8; 32],
    pub compute_units: u64,
    pub value: u64,
    pub message: Vec<u8>,
    pub extra_data: Vec<u8>,
    pub reason: Vec<u8>,
}

#[event]
pub struct LzComposeAlertEvent {
    pub executor: Pubkey,
    pub from: Pubkey,
    pub to: Pubkey,
    pub guid: [u8; 32],
    pub index: u16,
    pub compute_units: u64,
    pub value: u64,
    pub message: Vec<u8>,
    pub extra_data: Vec<u8>,
    pub reason: Vec<u8>,
}

#[event]
pub struct LibraryRegisteredEvent {
    pub new_lib: Pubkey, // The PDA of the message lib program
    pub new_lib_program: Pubkey,
}

#[event]
pub struct DefaultSendLibrarySetEvent {
    pub eid: u32,
    pub new_lib: Pubkey,
}

#[event]
pub struct DefaultReceiveLibrarySetEvent {
    pub eid: u32,
    pub new_lib: Pubkey,
}

#[event]
pub struct DefaultReceiveLibraryTimeoutSetEvent {
    pub eid: u32,
    pub timeout: Option<ReceiveLibraryTimeout>,
}

#[event]
pub struct SendLibrarySetEvent {
    pub sender: Pubkey,
    pub eid: u32,
    pub new_lib: Pubkey,
}

#[event]
pub struct ReceiveLibrarySetEvent {
    pub receiver: Pubkey,
    pub eid: u32,
    pub new_lib: Pubkey,
}

#[event]
pub struct ReceiveLibraryTimeoutSetEvent {
    pub receiver: Pubkey,
    pub eid: u32,
    pub timeout: Option<ReceiveLibraryTimeout>,
}

#[event]
pub struct RentWithdrawnEvent {
    pub receiver: Pubkey,
    pub amount: u64,
}

#[event]
pub struct AdminTransferredEvent {
    pub new_admin: Pubkey,
}

#[event]
pub struct DelegateSetEvent {
    pub new_delegate: Pubkey,
}

#[event]
pub struct LzTokenSetEvent {
    pub token: Option<Pubkey>,
}
