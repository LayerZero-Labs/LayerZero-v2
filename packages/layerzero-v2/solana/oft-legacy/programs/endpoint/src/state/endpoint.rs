use crate::*;

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

utils::generate_account_size_test!(EndpointSettings, endpoint_settings_test);
utils::generate_account_size_test!(OAppRegistry, oapp_registry_test);
