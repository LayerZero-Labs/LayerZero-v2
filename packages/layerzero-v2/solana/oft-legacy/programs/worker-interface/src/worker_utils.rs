use crate::*;

pub const SOL_DECIMALS_RATE: u128 = u128::pow(10, 9);
pub const ACL_MAX_LEN: usize = 8;

#[derive(InitSpace, Clone, AnchorSerialize, AnchorDeserialize)]
pub struct Acl {
    #[max_len(ACL_MAX_LEN)]
    pub allow_list: Vec<Pubkey>,
    #[max_len(ACL_MAX_LEN)]
    pub deny_list: Vec<Pubkey>,
}

impl Acl {
    pub fn set_allowlist(&mut self, oapp: &Pubkey) -> Result<()> {
        insert_or_remove_sorted_pubkey_list(&mut self.allow_list, ACL_MAX_LEN, oapp)
    }

    pub fn set_denylist(&mut self, oapp: &Pubkey) -> Result<()> {
        insert_or_remove_sorted_pubkey_list(&mut self.deny_list, ACL_MAX_LEN, oapp)
    }

    pub fn has_permission(&self, oapp: &Pubkey) -> bool {
        if self.deny_list.binary_search(oapp).is_ok() {
            false
        } else if self.allow_list.is_empty() || self.allow_list.binary_search(oapp).is_ok() {
            return true;
        } else {
            false
        }
    }

    pub fn assert_permission(&self, oapp: &Pubkey) -> Result<()> {
        require!(self.has_permission(oapp), WorkerError::PermissionDenied);
        Ok(())
    }
}

pub fn safe_convert_u128_to_u64(value: u128) -> Result<u64> {
    require!(value <= u64::MAX as u128, WorkerError::InvalidSize);
    Ok(value as u64)
}

pub fn insert_or_remove_sorted_pubkey_list(
    list: &mut Vec<Pubkey>,
    list_max_length: usize,
    key: &Pubkey,
) -> Result<()> {
    let result = list.binary_search(key);
    match result {
        Ok(index) => {
            list.remove(index);
        },
        Err(index) => {
            require!(list.len() < list_max_length, WorkerError::InvalidSize);
            list.insert(index, *key);
        },
    }
    Ok(())
}

pub fn increase_fee_with_multiplier_or_floor_margin(
    fee: u128,
    multiplier_bps: u128,
    floor_margin_usd: Option<u128>,
    native_token_price_usd: Option<u128>,
) -> u128 {
    let fee_with_multiplier = fee * multiplier_bps / 10000;

    if floor_margin_usd.is_none() || native_token_price_usd.is_none() {
        return fee_with_multiplier;
    }

    let margin = floor_margin_usd.unwrap() * SOL_DECIMALS_RATE / native_token_price_usd.unwrap();
    let fee_with_margin = fee + margin;

    let fee =
        if fee_with_margin > fee_with_multiplier { fee_with_margin } else { fee_with_multiplier };

    fee
}
