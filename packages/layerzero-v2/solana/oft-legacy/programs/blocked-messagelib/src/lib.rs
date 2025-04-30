use anchor_lang::prelude::*;
use messagelib_helper::messagelib_interface::Version;
use solana_helper::program_id_from_env;

declare_id!(Pubkey::new_from_array(program_id_from_env!(
    "BLOCKED_MESSAGELIB_ID",
    "2XrYqmhBMPJgDsb4SVbjV1PnJBprurd5bzRCkHwiFCJB"
)));

#[program]
pub mod blocked_messagelib {
    use super::*;

    pub fn version(_ctx: Context<GetVersion>) -> Result<Version> {
        Ok(Version { major: u64::MAX, minor: u8::MAX, endpoint_version: 2 })
    }
}

#[derive(Accounts)]
pub struct GetVersion {}
