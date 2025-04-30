use crate::*;
use oapp::endpoint::{instructions::RegisterOAppParams, ID as ENDPOINT_ID};

#[account]
#[derive(InitSpace)]
pub struct OftConfig {
    // immutable
    pub ld2sd_rate: u64,
    pub token_mint: Pubkey,
    pub token_program: Pubkey,
    pub endpoint_program: Pubkey,
    pub bump: u8,
    // mutable
    pub admin: Pubkey,
    pub ext: OftConfigExt,
}

#[derive(InitSpace, Clone, AnchorSerialize, AnchorDeserialize, PartialEq, Eq)]
pub enum OftConfigExt {
    Native(Option<Pubkey>), // mint authority
    Adapter(Pubkey),        // token escrow
}

impl OftConfig {
    // todo: optimize
    pub fn init(
        &mut self,
        endpoint_program: Option<Pubkey>,
        admin: Pubkey,
        shared_decimals: u8,
        decimals: u8,
        accounts: &[AccountInfo],
        oapp_signer: Pubkey,
    ) -> Result<()> {
        self.admin = admin;
        self.endpoint_program = if let Some(endpoint_program) = endpoint_program {
            endpoint_program
        } else {
            ENDPOINT_ID
        };

        require!(decimals >= shared_decimals, OftError::InvalidDecimals);
        self.ld2sd_rate = 10u64.pow((decimals - shared_decimals) as u32);

        // register oapp
        oapp::endpoint_cpi::register_oapp(
            self.endpoint_program,
            oapp_signer,
            accounts,
            &[OFT_SEED, &get_oft_config_seed(self).to_bytes(), &[self.bump]],
            RegisterOAppParams { delegate: self.admin },
        )
    }

    pub fn ld2sd(&self, amount_ld: u64) -> u64 {
        amount_ld / self.ld2sd_rate
    }

    pub fn sd2ld(&self, amount_sd: u64) -> u64 {
        amount_sd * self.ld2sd_rate
    }

    pub fn remove_dust(&self, amount_ld: u64) -> u64 {
        amount_ld - amount_ld % self.ld2sd_rate
    }
}

/// LzReceiveTypesAccounts includes accounts that are used in the LzReceiveTypes
/// instruction.
#[account]
#[derive(InitSpace)]
pub struct LzReceiveTypesAccounts {
    pub oft_config: Pubkey,
    pub token_mint: Pubkey,
}
