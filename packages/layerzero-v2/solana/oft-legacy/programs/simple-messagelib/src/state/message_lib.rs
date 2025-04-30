use crate::*;

#[account]
#[derive(InitSpace)]
pub struct MessageLib {
    // immutable
    pub eid: u32,
    pub endpoint: Pubkey, // the PDA signer of the endpoint program
    pub endpoint_program: Pubkey,
    pub bump: u8,
    // mutable
    pub admin: Pubkey,
    pub fee: u64,
    pub lz_token_fee: u64,
    pub wl_caller: Pubkey,
}

#[account]
#[derive(InitSpace, Default)]
pub struct SendConfigStore {
    pub bump: u8,
    #[max_len(10)]
    pub data: Vec<u8>,
}

#[account]
#[derive(InitSpace, Default)]
pub struct ReceiveConfigStore {
    pub bump: u8,
    #[max_len(10)]
    pub data: Vec<u8>,
}

utils::generate_account_size_test!(MessageLib, message_lib_test);
utils::generate_account_size_test!(SendConfigStore, send_config_store_test);
utils::generate_account_size_test!(ReceiveConfigStore, receive_config_store_test);
