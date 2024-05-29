use crate::*;
use messagelib_interface::MessageLibType;

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

utils::generate_account_size_test!(MessageLibInfo, message_lib_info_test);
utils::generate_account_size_test!(SendLibraryConfig, send_library_config_test);
utils::generate_account_size_test!(ReceiveLibraryConfig, receive_library_config_test);
