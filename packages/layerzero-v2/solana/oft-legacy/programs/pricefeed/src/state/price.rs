use crate::*;
use utils::sorted_list_helper;

pub const UPDATERS_MAX_LEN: usize = 8;
pub const PRICES_DEFAULT_LEN: usize = 140;
pub const PRICES_MAX_LEN: usize = 340;
pub const EID_MODULUS: u32 = 30000;

#[account]
#[derive(InitSpace)]
pub struct PriceFeed {
    pub admin: Pubkey,
    #[max_len(UPDATERS_MAX_LEN)]
    pub updaters: Vec<Pubkey>,
    pub price_ratio_denominator: u128,
    pub arbitrum_compression_percent: u128,
    pub native_token_price_usd: Option<u128>,
    #[max_len(PRICES_DEFAULT_LEN)]
    pub prices: Vec<Price>,
    pub bump: u8,
}

#[derive(InitSpace, Clone, AnchorSerialize, AnchorDeserialize)]
pub struct Price {
    pub eid: u32,
    pub price_ratio: u128,
    pub gas_price_in_unit: u64,
    pub gas_per_byte: u32,
    pub model_type: Option<ModelType>,
}

impl sorted_list_helper::EID for Price {
    fn eid(&self) -> u32 {
        self.eid
    }
}

#[derive(Clone, InitSpace, AnchorSerialize, AnchorDeserialize)]
pub enum ModelType {
    Arbitrum { gas_per_l2_tx: u64, gas_per_l1_calldata_byte: u32 },
    Optimism { l1_eid: u32 },
}

utils::generate_account_size_test!(PriceFeed, price_feed_test);

utils::generate_account_size_test!(Price, price_test);
