use crate::*;

#[account]
#[derive(InitSpace)]
pub struct ExecuteHash {
    pub expiration: i64,
    pub bump: u8,
}

utils::generate_account_size_test!(ExecuteHash, execute_hash_test);
