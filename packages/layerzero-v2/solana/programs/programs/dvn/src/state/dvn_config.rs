use crate::*;
use anchor_lang::solana_program::secp256k1_recover::{
    secp256k1_recover, SECP256K1_PUBLIC_KEY_LENGTH,
};
use std::collections::HashSet;
use utils::sorted_list_helper;
use worker_interface::worker_utils::{self, insert_or_remove_sorted_pubkey_list};

/// encoded: funcSigHash + params -> 4  + (32 * 2)
pub const EXECUTE_FIXED_BYTES: u64 = 68;

/// not encoded
/// The raw bytes of the signature are 65 bytes long, the first 64 bytes are the signature, and the last byte is the recovery ID.
pub const SIGNATURE_RAW_BYTES: usize = 65;

// callData(verify) = 228 (4 + 64 + 81 + 15 + 32 + 32), padded to 32 = 256 + 64 = 320
pub const VERIFY_BYTES: u64 = 320;

pub const ADMINS_MAX_LEN: usize = 5;
pub const SIGNERS_MAX_LEN: usize = 7;
pub const MSGLIBS_MAX_LEN: usize = 10;
pub const DST_CONFIG_MAX_LEN: usize = 140;

#[account]
#[derive(InitSpace)]
pub struct DvnConfig {
    // immutable
    // to uniquely identify this DVN instance
    // set to endpoint v1 eid if available OR endpoint v2 eid % 30_000
    pub vid: u32,
    pub bump: u8,
    // set by quorum
    pub multisig: Multisig,
    pub acl: worker_utils::Acl,
    pub paused: bool,
    #[max_len(MSGLIBS_MAX_LEN)]
    pub msglibs: Vec<Pubkey>,
    #[max_len(ADMINS_MAX_LEN)]
    pub admins: Vec<Pubkey>,
    // set by admins
    pub price_feed: Pubkey,
    #[max_len(DST_CONFIG_MAX_LEN)]
    pub dst_configs: Vec<DstConfig>,
    pub default_multiplier_bps: u16,
}

impl DvnConfig {
    pub fn set_multisig(&mut self, multisig: Multisig) -> Result<()> {
        multisig.sanity_check()?;
        self.multisig = multisig;
        Ok(())
    }

    pub fn set_admins(&mut self, admins: Vec<Pubkey>) -> Result<()> {
        require!(admins.len() <= ADMINS_MAX_LEN, DvnError::TooManyAdmins);
        self.admins = admins;
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

    pub fn remove_dst_configs(&mut self, dst_eids: Vec<u32>) -> Result<()> {
        for eid in dst_eids {
            sorted_list_helper::remove_from_sorted_list_by_eid(&mut self.dst_configs, eid)?;
        }
        Ok(())
    }
}

impl sorted_list_helper::EID for DstConfig {
    fn eid(&self) -> u32 {
        self.eid
    }
}

#[derive(InitSpace, Clone, AnchorSerialize, AnchorDeserialize)]
pub struct DstConfig {
    pub eid: u32,
    pub dst_gas: u32,
    pub multiplier_bps: Option<u16>,
    pub floor_margin_usd: Option<u128>,
}

#[derive(InitSpace, Clone, AnchorSerialize, AnchorDeserialize)]
pub struct Multisig {
    #[max_len(SIGNERS_MAX_LEN)]
    pub signers: Vec<[u8; SECP256K1_PUBLIC_KEY_LENGTH]>,
    pub quorum: u8,
}

impl Multisig {
    pub fn verify_signatures(
        &self,
        sigs: &Vec<[u8; SIGNATURE_RAW_BYTES]>,
        hash: &[u8; 32],
    ) -> Result<()> {
        require!(sigs.len() >= self.quorum as usize, DvnError::InvalidSignatureLen);

        let mut signed: HashSet<[u8; 64]> = HashSet::new();
        for i in 0..self.quorum as usize {
            let sig = &sigs[i][..(SIGNATURE_RAW_BYTES - 1)];
            let recovery_id = sigs[i][SIGNATURE_RAW_BYTES - 1];
            let pubkey = secp256k1_recover(&hash[..], recovery_id, sig)
                .map_err(|_| DvnError::SignatureError)?
                .to_bytes();
            require!(self.signers.contains(&pubkey), DvnError::SignerNotInCommittee);
            require!(signed.insert(pubkey), DvnError::DuplicateSignature);
        }

        Ok(())
    }

    pub fn sanity_check(&self) -> Result<()> {
        require!(
            self.signers.len() > 0 && self.signers.len() <= SIGNERS_MAX_LEN,
            DvnError::InvalidSignersLen
        );
        require!(
            self.quorum > 0 && self.quorum as usize <= self.signers.len(),
            DvnError::InvalidQuorum
        );
        let mut unique = HashSet::new();
        for signer in &self.signers {
            require!(unique.insert(signer), DvnError::UniqueOwners);
        }
        Ok(())
    }
}

utils::generate_account_size_test!(DvnConfig, dvn_config_test);
