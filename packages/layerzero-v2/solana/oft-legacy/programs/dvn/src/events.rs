use crate::*;

#[event]
pub struct AdminConfigSetEvent {
    pub config: AdminConfig,
}

#[event]
pub struct MultisigConfigSetEvent {
    pub config: MultisigConfig,
}

#[event]
pub struct FeeWithdrawnEvent {
    pub receiver: Pubkey,
    pub amount: u64,
}
