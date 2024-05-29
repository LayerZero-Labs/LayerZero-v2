use crate::*;
use utils::sorted_list_helper;
use worker_interface::worker_utils;
use worker_interface::worker_utils::insert_or_remove_sorted_pubkey_list;

pub const ADMINS_MAX_LEN: usize = 5;
pub const EXECUTOR_MAX_LEN: usize = 8;
pub const MSGLIBS_MAX_LEN: usize = 10;
pub const DST_CONFIG_MAX_LEN: usize = 140;

#[account]
#[derive(InitSpace)]
pub struct ExecutorConfig {
    pub bump: u8,
    // set by owner
    pub owner: Pubkey,
    pub acl: worker_utils::Acl,
    #[max_len(ADMINS_MAX_LEN)]
    pub admins: Vec<Pubkey>,
    #[max_len(EXECUTOR_MAX_LEN)]
    pub executors: Vec<Pubkey>,
    #[max_len(MSGLIBS_MAX_LEN)]
    pub msglibs: Vec<Pubkey>,
    pub paused: bool,
    // set by admin
    pub default_multiplier_bps: u16,
    pub price_feed: Pubkey,
    #[max_len(DST_CONFIG_MAX_LEN)]
    pub dst_configs: Vec<DstConfig>,
}

impl ExecutorConfig {
    pub fn set_admins(&mut self, admins: Vec<Pubkey>) -> Result<()> {
        require!(admins.len() <= ADMINS_MAX_LEN, ExecutorError::TooManyAdmins);
        for admin in &admins {
            require!(!self.executors.contains(admin), ExecutorError::ExecutorIsAdmin);
        }
        self.admins = admins;
        Ok(())
    }

    pub fn set_executors(&mut self, executors: Vec<Pubkey>) -> Result<()> {
        require!(executors.len() <= EXECUTOR_MAX_LEN, ExecutorError::TooManyExecutors);
        for executor in &executors {
            require!(!self.admins.contains(executor), ExecutorError::ExecutorIsAdmin);
        }
        self.executors = executors;
        Ok(())
    }

    pub fn set_msglibs(&mut self, msglibs: Vec<Pubkey>) -> Result<()> {
        for lib in &msglibs {
            insert_or_remove_sorted_pubkey_list(&mut self.msglibs, MSGLIBS_MAX_LEN, lib)?;
        }
        Ok(())
    }

    pub fn set_dst_configs(&mut self, dst_configs: Vec<DstConfig>) -> Result<()> {
        for config in &dst_configs {
            sorted_list_helper::insert_or_update_sorted_list_by_eid(
                &mut self.dst_configs,
                config.clone(),
                DST_CONFIG_MAX_LEN,
            )?;
        }
        Ok(())
    }
}

#[derive(InitSpace, Clone, AnchorSerialize, AnchorDeserialize)]
pub struct DstConfig {
    pub eid: u32,
    pub lz_receive_base_gas: u32,
    pub lz_compose_base_gas: u32,
    pub multiplier_bps: Option<u16>,
    pub floor_margin_usd: Option<u128>,
    pub native_drop_cap: u128,
}

impl sorted_list_helper::EID for DstConfig {
    fn eid(&self) -> u32 {
        self.eid
    }
}
utils::generate_account_size_test!(ExecutorConfig, executor_config_test);
