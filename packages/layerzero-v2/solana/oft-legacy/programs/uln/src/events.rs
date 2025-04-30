use crate::*;
use messagelib_helper::packet_v1_codec::PACKET_HEADER_SIZE;

#[event]
pub struct FeesPaidEvent {
    pub executor: WorkerFee,
    pub dvns: Vec<WorkerFee>,
    pub treasury: Option<TreasuryFee>,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct WorkerFee {
    pub worker: Pubkey,
    pub fee: u64,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct TreasuryFee {
    pub treasury: Pubkey,
    pub fee: u64,
    pub pay_in_lz_token: bool,
}

#[event]
pub struct RentWithdrawnEvent {
    pub receiver: Pubkey,
    pub amount: u64,
}

#[event]
pub struct PayloadVerifiedEvent {
    pub dvn: Pubkey,
    pub header: [u8; PACKET_HEADER_SIZE],
    pub confirmations: u64,
    pub proof_hash: [u8; 32],
}

#[event]
pub struct AdminTransferredEvent {
    pub new_admin: Pubkey,
}

#[event]
pub struct DefaultConfigSetEvent {
    pub eid: u32,
    pub send_uln_config: Option<UlnConfig>,
    pub receive_uln_config: Option<UlnConfig>,
    pub executor_config: Option<ExecutorConfig>,
}

#[event]
pub struct ConfigSetEvent {
    pub oapp: Pubkey,
    pub eid: u32,
    pub config: Config,
}

#[event]
pub struct TreasurySetEvent {
    pub treasury: Option<Treasury>,
}
