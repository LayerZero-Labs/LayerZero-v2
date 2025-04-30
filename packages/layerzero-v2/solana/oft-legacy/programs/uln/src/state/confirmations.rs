use crate::*;

#[account]
#[derive(InitSpace)]
pub struct Confirmations {
    pub value: Option<u64>,
    pub bump: u8,
}

utils::generate_account_size_test!(Confirmations, confirmations_test);
