use crate::*;
use anchor_lang::solana_program::keccak::hash as keccak256;
use messagelib_helper::{
    endpoint_verify,
    packet_v1_codec::{self, PACKET_HEADER_SIZE},
};

#[derive(Accounts)]
#[instruction(params: CommitVerificationParams)]
pub struct CommitVerification<'info> {
    /// The custom receive config account may be uninitialized, so deserialize it only if it's initialized
    #[account(
        seeds = [
            RECEIVE_CONFIG_SEED,
            &packet_v1_codec::src_eid(&params.packet_header).to_be_bytes(),
            &packet_v1_codec::receiver_pubkey(&params.packet_header).to_bytes()
        ],
        bump
    )]
    pub receive_config: AccountInfo<'info>,
    #[account(
        seeds = [RECEIVE_CONFIG_SEED, &packet_v1_codec::src_eid(&params.packet_header).to_be_bytes()],
        bump = default_receive_config.bump,
    )]
    pub default_receive_config: Account<'info, ReceiveConfig>,
    #[account(seeds = [ULN_SEED], bump = uln.bump)]
    pub uln: Account<'info, UlnSettings>,
}

impl CommitVerification<'_> {
    pub fn apply(
        ctx: &mut Context<CommitVerification>,
        params: &CommitVerificationParams,
    ) -> Result<()> {
        let config =
            get_receive_config(&ctx.accounts.receive_config, &ctx.accounts.default_receive_config)?;

        // assert packet header
        require!(
            packet_v1_codec::version(&params.packet_header) == PACKET_VERSION,
            UlnError::InvalidPacketVersion
        );
        require!(
            packet_v1_codec::dst_eid(&params.packet_header) == ctx.accounts.uln.eid,
            UlnError::InvalidEid
        );

        let dvns_size = config.required_dvns.len() + config.optional_dvns.len();

        let confirmation_accounts = &ctx.remaining_accounts[0..dvns_size];
        require!(
            check_verifiable(
                &config,
                confirmation_accounts,
                &keccak256(&params.packet_header).to_bytes(),
                &params.payload_hash
            )?,
            UlnError::Verifying
        );

        endpoint_verify::verify(
            ctx.accounts.uln.endpoint_program,
            ctx.accounts.uln.key(),
            &params.packet_header,
            params.payload_hash,
            &[ULN_SEED, &[ctx.accounts.uln.bump]],
            &ctx.remaining_accounts[dvns_size..],
        )
    }
}

fn get_receive_config(
    custom_config_acc: &AccountInfo,
    default_config: &ReceiveConfig,
) -> Result<UlnConfig> {
    let custom_config = local_custom_config::<ReceiveConfig>(custom_config_acc)?;
    UlnConfig::get_config(&default_config.uln, &custom_config.uln)
}

pub fn check_verifiable(
    config: &UlnConfig,
    accounts: &[AccountInfo],
    header_hash: &[u8; 32],
    payload_hash: &[u8; 32],
) -> Result<bool> {
    // iterate the required DVNs
    if config.required_dvn_count > 0 {
        for (i, dvn) in config.required_dvns.iter().enumerate() {
            if !verified(dvn, &accounts[i], header_hash, payload_hash, config.confirmations)? {
                return Ok(false);
            }
        }

        // returns early if all required DVNs have signed and there are no optional DVNs
        if config.optional_dvn_threshold == 0 {
            return Ok(true);
        }
    }

    // then it must require optional validations
    let mut threshold = config.optional_dvn_threshold as usize;
    let optional_acc_offset = config.required_dvns.len();
    for (i, dvn) in config.optional_dvns.iter().enumerate() {
        if verified(
            dvn,
            &accounts[optional_acc_offset + i],
            header_hash,
            payload_hash,
            config.confirmations,
        )? {
            // increment the optional count if the optional DVN has signed
            threshold -= 1;
            if threshold == 0 {
                // early return if the optional threshold has hit
                return Ok(true);
            }
        }
    }

    // return false as a catch-all
    Ok(false)
}

fn verified(
    dvn: &Pubkey,
    confirmations_account: &AccountInfo,
    header_hash: &[u8; 32],
    payload_hash: &[u8; 32],
    required_conf: u64,
) -> Result<bool> {
    // confirmation exists
    if confirmations_account.owner.key() == ID {
        let mut data: &[u8] = &confirmations_account.try_borrow_data()?;
        let dvn_confirmations: Confirmations = Confirmations::try_deserialize(&mut data)?;

        let expected_address = Pubkey::create_program_address(
            &[
                CONFIRMATIONS_SEED,
                &header_hash[..],
                &payload_hash[..],
                &dvn.to_bytes(),
                &[dvn_confirmations.bump],
            ],
            &ID,
        )
        .map_err(|_| UlnError::InvalidConfirmation)?;
        require!(confirmations_account.key() == expected_address, UlnError::InvalidConfirmation);

        if let Some(conf) = dvn_confirmations.value {
            return Ok(conf >= required_conf);
        }
    }
    Ok(false)
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct CommitVerificationParams {
    pub packet_header: [u8; PACKET_HEADER_SIZE],
    pub payload_hash: [u8; 32],
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_verified() {
        let header_hash = [1u8; 32];
        let payload_hash = [2u8; 32];
        // Create test data
        let dvn = Pubkey::new_unique();
        let cmf_owner = ID;
        let lamports: &mut u64 = &mut 0;

        let (confirmations_key, bump_seed) = Pubkey::find_program_address(
            &[CONFIRMATIONS_SEED, &header_hash[..], &payload_hash[..], &dvn.to_bytes()],
            &ID,
        );

        let dvn_confirmations = Confirmations { value: Some(3), bump: bump_seed };
        // new Confirmations
        let mut data = vec![];
        Confirmations::try_serialize(&dvn_confirmations, &mut data).unwrap();

        let confirmations_account = AccountInfo::new(
            &confirmations_key,
            false,
            false,
            lamports,
            &mut data[..],
            &cmf_owner,
            false,
            0,
        );

        // Verified, required_conf equal to committed conforamtions
        let required_conf = 3;
        let result =
            verified(&dvn, &confirmations_account, &header_hash, &payload_hash, required_conf);
        assert_eq!(result, Ok(true));

        // Verified, required_conf less than committed conforamtions
        let required_conf = 2;
        let result =
            verified(&dvn, &confirmations_account, &header_hash, &payload_hash, required_conf);
        assert_eq!(result, Ok(true));

        // Not verified, required_conf greater than committed conforamtions
        let required_conf = 4;
        let result =
            verified(&dvn, &confirmations_account, &header_hash, &payload_hash, required_conf);
        assert_eq!(result, Ok(false));

        // Failure, invalid confirmation account
        let invalid_key = Pubkey::new_unique();
        let invalid_confirmations_account = AccountInfo::new(
            &invalid_key,
            false,
            false,
            lamports,
            &mut data[..],
            &cmf_owner,
            false,
            0,
        );
        let result = verified(
            &dvn,
            &invalid_confirmations_account,
            &header_hash,
            &payload_hash,
            required_conf,
        );
        assert_eq!(result.unwrap_err(), UlnError::InvalidConfirmation.into());
    }

    #[test]
    fn test_check_verifiable() {
        let header_hash = [1u8; 32];
        let payload_hash = [2u8; 32];

        // Case 1, no required DVN, no optional DVN
        // False, no required DVN, no optional DVN
        let config = UlnConfig {
            required_dvn_count: 0,
            required_dvns: vec![],
            optional_dvn_threshold: 0,
            optional_dvns: vec![],
            optional_dvn_count: 0,
            confirmations: 3,
        };
        let accounts = vec![];
        let result = check_verifiable(&config, &accounts, &header_hash, &payload_hash);
        assert_eq!(result, Ok(false));

        let dvn1 = Pubkey::new_unique();
        let (acc_key1, bump_seed1) = Pubkey::find_program_address(
            &[CONFIRMATIONS_SEED, &header_hash[..], &payload_hash[..], &dvn1.to_bytes()],
            &ID,
        );

        let dvn2 = Pubkey::new_unique();
        let (acc_key2, bump_seed2) = Pubkey::find_program_address(
            &[CONFIRMATIONS_SEED, &header_hash[..], &payload_hash[..], &dvn2.to_bytes()],
            &ID,
        );

        let dvn3 = Pubkey::new_unique();
        let (acc_key3, bump_seed3) = Pubkey::find_program_address(
            &[CONFIRMATIONS_SEED, &header_hash[..], &payload_hash[..], &dvn3.to_bytes()],
            &ID,
        );

        // Case 2, only one required DVN, no optional DVN
        let config = UlnConfig {
            required_dvn_count: 1,
            required_dvns: vec![dvn1],
            optional_dvn_threshold: 0,
            optional_dvns: vec![],
            optional_dvn_count: 0,
            confirmations: 3,
        };
        // True, the only one required DVN signed
        let dvn_confirmations = Confirmations { value: Some(3), bump: bump_seed1 }; // sign
        let lamports: &mut u64 = &mut 0;
        let mut data = vec![];
        Confirmations::try_serialize(&dvn_confirmations, &mut data).unwrap();
        let conf_acc =
            AccountInfo::new(&acc_key1, false, false, lamports, &mut data[..], &ID, false, 0);
        let accounts = vec![conf_acc];
        let result = check_verifiable(&config, &accounts, &header_hash, &payload_hash);
        assert_eq!(result, Ok(true));

        // False, the only one required DVN not signed
        let dvn_confirmations = Confirmations { value: Some(0), bump: bump_seed1 }; // not sign
        let lamports: &mut u64 = &mut 0;
        let mut data = vec![];
        Confirmations::try_serialize(&dvn_confirmations, &mut data).unwrap();
        let conf_acc =
            AccountInfo::new(&acc_key1, false, false, lamports, &mut data[..], &ID, false, 0);
        let accounts = vec![conf_acc];
        let result = check_verifiable(&config, &accounts, &header_hash, &payload_hash);
        assert_eq!(result, Ok(false));

        // Case 3, more than one required DVNs, no optional DVN
        let config = UlnConfig {
            required_dvn_count: 2,
            required_dvns: vec![dvn1, dvn2],
            optional_dvn_threshold: 0,
            optional_dvns: vec![],
            optional_dvn_count: 0,
            confirmations: 3,
        };
        // True, all required DVN signed
        let dvn_confirmations = Confirmations { value: Some(3), bump: bump_seed1 }; // sign
        let lamports: &mut u64 = &mut 0;
        let mut data = vec![];
        Confirmations::try_serialize(&dvn_confirmations, &mut data).unwrap();
        let conf_acc1 =
            AccountInfo::new(&acc_key1, false, false, lamports, &mut data[..], &ID, false, 0);

        let dvn_confirmations = Confirmations { value: Some(3), bump: bump_seed2 }; // sign
        let mut data = vec![];
        Confirmations::try_serialize(&dvn_confirmations, &mut data).unwrap();
        let lamports: &mut u64 = &mut 0;
        let conf_acc2 =
            AccountInfo::new(&acc_key2, false, false, lamports, &mut data[..], &ID, false, 0);

        let accounts = vec![conf_acc1, conf_acc2];
        let result = check_verifiable(&config, &accounts, &header_hash, &payload_hash);
        assert_eq!(result, Ok(true));

        // False, one of required DVN not signed
        let dvn_confirmations = Confirmations { value: Some(3), bump: bump_seed1 }; // sign
        let mut data = vec![];
        Confirmations::try_serialize(&dvn_confirmations, &mut data).unwrap();
        let lamports: &mut u64 = &mut 0;
        let conf_acc1 =
            AccountInfo::new(&acc_key1, false, false, lamports, &mut data[..], &ID, false, 0);

        let dvn_confirmations = Confirmations { value: Some(0), bump: bump_seed2 }; // not sign
        let mut data = vec![];
        Confirmations::try_serialize(&dvn_confirmations, &mut data).unwrap();
        let lamports: &mut u64 = &mut 0;
        let conf_acc2 =
            AccountInfo::new(&acc_key2, false, false, lamports, &mut data[..], &ID, false, 0);

        let accounts = vec![conf_acc1, conf_acc2];
        let result = check_verifiable(&config, &accounts, &header_hash, &payload_hash);
        assert_eq!(result, Ok(false));

        // Case 4, one required DVN, two optional DVNs, optional threshold 1
        let config = UlnConfig {
            required_dvn_count: 1,
            required_dvns: vec![dvn1],
            optional_dvn_threshold: 1,
            optional_dvns: vec![dvn2, dvn3],
            optional_dvn_count: 2,
            confirmations: 3,
        };
        // False, the only one required DVN not signed
        let dvn_confirmations = Confirmations { value: Some(0), bump: bump_seed1 }; // not sign
        let mut data = vec![];
        Confirmations::try_serialize(&dvn_confirmations, &mut data).unwrap();
        let lamports: &mut u64 = &mut 0;
        let conf_acc1 =
            AccountInfo::new(&acc_key1, false, false, lamports, &mut data[..], &ID, false, 0);

        let dvn_confirmations = Confirmations { value: Some(3), bump: bump_seed2 }; // sign
        let mut data = vec![];
        Confirmations::try_serialize(&dvn_confirmations, &mut data).unwrap();
        let lamports: &mut u64 = &mut 0;
        let conf_acc2 =
            AccountInfo::new(&acc_key2, false, false, lamports, &mut data[..], &ID, false, 0);

        let dvn_confirmations = Confirmations { value: Some(3), bump: bump_seed3 }; // sign
        let mut data = vec![];
        Confirmations::try_serialize(&dvn_confirmations, &mut data).unwrap();
        let lamports: &mut u64 = &mut 0;
        let conf_acc3 =
            AccountInfo::new(&acc_key3, false, false, lamports, &mut data[..], &ID, false, 0);

        let accounts = vec![conf_acc1, conf_acc2, conf_acc3];
        let result = check_verifiable(&config, &accounts, &header_hash, &payload_hash);
        assert_eq!(result, Ok(false));

        // False, the only one required DVN signed, none of optional DVN signed
        let dvn_confirmations = Confirmations { value: Some(3), bump: bump_seed1 }; // sign
        let mut data = vec![];
        Confirmations::try_serialize(&dvn_confirmations, &mut data).unwrap();
        let lamports: &mut u64 = &mut 0;
        let conf_acc1 =
            AccountInfo::new(&acc_key1, false, false, lamports, &mut data[..], &ID, false, 0);

        let dvn_confirmations = Confirmations { value: Some(0), bump: bump_seed2 }; // not sign
        let mut data = vec![];
        Confirmations::try_serialize(&dvn_confirmations, &mut data).unwrap();
        let lamports: &mut u64 = &mut 0;
        let conf_acc2 =
            AccountInfo::new(&acc_key2, false, false, lamports, &mut data[..], &ID, false, 0);

        let dvn_confirmations = Confirmations { value: Some(0), bump: bump_seed3 }; // not sign
        let mut data = vec![];
        Confirmations::try_serialize(&dvn_confirmations, &mut data).unwrap();
        let lamports: &mut u64 = &mut 0;
        let conf_acc3 =
            AccountInfo::new(&acc_key3, false, false, lamports, &mut data[..], &ID, false, 0);

        let accounts = vec![conf_acc1, conf_acc2, conf_acc3];
        let result = check_verifiable(&config, &accounts, &header_hash, &payload_hash);
        assert_eq!(result, Ok(false));

        // True, the only one required DVN signed, one of optional DVN signed
        let dvn_confirmations = Confirmations { value: Some(3), bump: bump_seed1 }; // sign
        let mut data = vec![];
        Confirmations::try_serialize(&dvn_confirmations, &mut data).unwrap();
        let lamports: &mut u64 = &mut 0;
        let conf_acc1 =
            AccountInfo::new(&acc_key1, false, false, lamports, &mut data[..], &ID, false, 0);
        let dvn_confirmations = Confirmations { value: Some(3), bump: bump_seed2 }; // sign
        let mut data = vec![];
        Confirmations::try_serialize(&dvn_confirmations, &mut data).unwrap();
        let lamports: &mut u64 = &mut 0;
        let conf_acc2 =
            AccountInfo::new(&acc_key2, false, false, lamports, &mut data[..], &ID, false, 0);

        let dvn_confirmations = Confirmations { value: Some(0), bump: bump_seed3 }; // not sign
        let mut data = vec![];
        Confirmations::try_serialize(&dvn_confirmations, &mut data).unwrap();
        let lamports: &mut u64 = &mut 0;
        let conf_acc3 =
            AccountInfo::new(&acc_key3, false, false, lamports, &mut data[..], &ID, false, 0);

        let accounts = vec![conf_acc1, conf_acc2, conf_acc3];
        let result = check_verifiable(&config, &accounts, &header_hash, &payload_hash);
        assert_eq!(result, Ok(true));
    }
}
