use crate::*;
use anchor_lang::solana_program::{
    instruction::Instruction, keccak, program::invoke_signed,
    secp256k1_recover::SECP256K1_PUBLIC_KEY_LENGTH,
};

#[event_cpi]
#[derive(Accounts)]
#[instruction(params: InvokeParams)]
pub struct Invoke<'info> {
    #[account(mut)]
    pub signer: Signer<'info>,
    #[account(mut, seeds = [DVN_CONFIG_SEED], bump = config.bump)]
    pub config: Account<'info, DvnConfig>,
    #[account(
        init,
        payer = signer,
        space = 8 + ExecuteHash::INIT_SPACE,
        seeds = [EXECUTE_HASH_SEED, &keccak::hash(&params.digest.data()?).to_bytes()],
        bump
    )]
    pub execute_hash: Account<'info, ExecuteHash>,
    pub system_program: Program<'info, System>,
}

impl Invoke<'_> {
    pub fn apply(ctx: &mut Context<Invoke>, params: &InvokeParams) -> Result<()> {
        require!(ctx.accounts.config.vid == params.digest.vid, DvnError::InvalidVid);
        require!(params.digest.expiration > Clock::get()?.unix_timestamp, DvnError::Expired);

        // verify signatures
        let hash = keccak::hash(&params.digest.data()?).to_bytes();
        ctx.accounts.config.multisig.verify_signatures(&params.signatures, &hash)?;

        // mark the execute hash as executed
        ctx.accounts.execute_hash.expiration = params.digest.expiration;
        ctx.accounts.execute_hash.bump = ctx.bumps.execute_hash;

        if params.digest.program_id == ID {
            // deserialize the config
            let mut data = params.digest.data.as_slice();
            let config = MultisigConfig::deserialize(&mut data)?;

            // when not set new admins, the signer must be an admin
            let is_set_admin = matches!(config, MultisigConfig::Admins(_));
            if !is_set_admin {
                require!(
                    ctx.accounts.config.admins.contains(ctx.accounts.signer.key),
                    DvnError::NotAdmin
                );
            }

            // apply the config
            config.apply(&mut ctx.accounts.config)?;
            emit_cpi!(MultisigConfigSetEvent { config });
        } else {
            // the signer must be an admin
            require!(
                ctx.accounts.config.admins.contains(ctx.accounts.signer.key),
                DvnError::NotAdmin
            );

            // invoke the transaction
            let mut accounts = Vec::with_capacity(params.digest.accounts.len());
            let config_acc = ctx.accounts.config.key();
            for acc in params.digest.accounts.iter() {
                let mut meta = AccountMeta::from(acc);
                // config account should not be writable to the target program when it is a signer
                if meta.pubkey == config_acc && acc.is_signer {
                    meta.is_writable = false;
                }
                accounts.push(meta);
            }
            let ix = Instruction {
                program_id: params.digest.program_id,
                accounts,
                data: params.digest.data.clone(),
            };
            invoke_signed(
                &ix,
                ctx.remaining_accounts,
                &[&[DVN_CONFIG_SEED, &[ctx.accounts.config.bump]]],
            )?;
        }
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InvokeParams {
    pub digest: ExecuteTransactionDigest,
    pub signatures: Vec<[u8; SIGNATURE_RAW_BYTES]>,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct ExecuteTransactionDigest {
    pub vid: u32,
    // target program to execute against
    pub program_id: Pubkey,
    // accounts required for the transaction
    pub accounts: Vec<TransactionAccount>,
    pub data: Vec<u8>,
    pub expiration: i64,
}
impl ExecuteTransactionDigest {
    fn data(&self) -> Result<Vec<u8>> {
        let mut data = Vec::with_capacity(52 + self.accounts.len() * 34 + self.data.len()); // 4 + 32 + 8 + 4 + 4
        self.serialize(&mut data)?;
        Ok(data)
    }
}

#[test]
fn execute_transaction_digest_data() {
    let digest = ExecuteTransactionDigest {
        vid: 0,
        program_id: Pubkey::new_unique(),
        accounts: vec![
            TransactionAccount { pubkey: Pubkey::new_unique(), is_signer: true, is_writable: true },
            TransactionAccount {
                pubkey: Pubkey::new_unique(),
                is_signer: false,
                is_writable: true,
            },
        ],
        data: vec![1, 2, 3, 4],
        expiration: 0,
    };
    let data = digest.data().unwrap();

    assert_eq!(data.len(), 52 + digest.accounts.len() * 34 + digest.data.len());
    assert_eq!(data.len(), digest.try_to_vec().unwrap().len());
    assert_eq!(data, digest.try_to_vec().unwrap());
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct TransactionAccount {
    pub pubkey: Pubkey,
    pub is_signer: bool,
    pub is_writable: bool,
}

impl From<&TransactionAccount> for AccountMeta {
    fn from(account: &TransactionAccount) -> AccountMeta {
        match account.is_writable {
            false => AccountMeta::new_readonly(account.pubkey, account.is_signer),
            true => AccountMeta::new(account.pubkey, account.is_signer),
        }
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub enum MultisigConfig {
    Admins(Vec<Pubkey>),
    Allowlist(Vec<Pubkey>),
    Denylist(Vec<Pubkey>),
    Msglibs(Vec<Pubkey>),
    Paused(bool),
    Quorum(u8),
    Signers(Vec<[u8; SECP256K1_PUBLIC_KEY_LENGTH]>),
}

impl MultisigConfig {
    pub fn apply(&self, config: &mut DvnConfig) -> Result<()> {
        match self {
            MultisigConfig::Admins(admins) => {
                config.set_admins(admins.clone())?;
            },
            MultisigConfig::Allowlist(allowlist) => {
                for addr in allowlist {
                    config.acl.set_allowlist(addr)?;
                }
            },
            MultisigConfig::Denylist(denylist) => {
                for addr in denylist {
                    config.acl.set_denylist(addr)?;
                }
            },
            MultisigConfig::Msglibs(msglibs) => {
                config.set_msglibs(msglibs.clone())?;
            },
            MultisigConfig::Paused(paused) => {
                config.paused = *paused;
            },
            MultisigConfig::Quorum(quorum) => {
                let signers = config.multisig.signers.clone();
                config.set_multisig(Multisig { quorum: *quorum, signers })?;
            },
            MultisigConfig::Signers(signers) => {
                let quorum = config.multisig.quorum;
                config.set_multisig(Multisig { quorum, signers: signers.clone() })?;
            },
        }
        Ok(())
    }
}
