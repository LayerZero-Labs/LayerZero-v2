use crate::*;

#[event]
pub struct NativeDropAppliedEvent {
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub nonce: u64,
    pub dst_eid: u32,
    pub oapp: Pubkey,
    pub native_drop_requests: Vec<NativeDropRequest>,
    pub successes: Vec<bool>,
}
