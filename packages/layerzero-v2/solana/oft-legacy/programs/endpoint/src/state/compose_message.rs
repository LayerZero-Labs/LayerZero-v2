use crate::*;

#[account]
#[derive(InitSpace)]
pub struct ComposeMessageState {
    pub received: bool,
    pub bump: u8,
}

utils::generate_account_size_test!(ComposeMessageState, compose_message_state_test);
