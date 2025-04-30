use crate::*;
use std::cmp::Ordering;

#[account]
#[derive(InitSpace)]
pub struct UlnSettings {
    // immutable
    pub eid: u32,
    pub endpoint: Pubkey, // the PDA signer of the endpoint program
    pub endpoint_program: Pubkey,
    pub bump: u8,
    // mutable
    pub admin: Pubkey,
    pub treasury: Option<Treasury>,
}

#[derive(InitSpace, Clone, AnchorSerialize, AnchorDeserialize)]
pub struct Treasury {
    pub admin: Option<Pubkey>,
    pub native_receiver: Pubkey,
    pub native_fee_bps: u64,
    pub lz_token: Option<LzTokenTreasury>,
}

#[derive(InitSpace, Clone, AnchorSerialize, AnchorDeserialize)]
pub struct LzTokenTreasury {
    pub receiver: Pubkey,
    pub fee: u64, // amount passed in is always 10^decimals
}

#[derive(Clone, InitSpace, AnchorSerialize, AnchorDeserialize, Default)]
pub struct ExecutorConfig {
    pub max_message_size: u32,
    pub executor: Pubkey, // PDA of executor program (fees paid to this account)
}

impl ExecutorConfig {
    pub fn set_default_config(&mut self, config: &ExecutorConfig) -> Result<()> {
        require!(config.executor != Pubkey::default(), UlnError::InvalidExecutor);
        require!(config.max_message_size > 0, UlnError::ZeroMessageSize);
        self.set_config(config)
    }

    pub fn set_config(&mut self, config: &ExecutorConfig) -> Result<()> {
        self.max_message_size = config.max_message_size;
        self.executor = config.executor;
        Ok(())
    }

    pub fn get_config(
        default_config: &ExecutorConfig,
        custom_config: &ExecutorConfig,
    ) -> ExecutorConfig {
        let mut rtn_config = ExecutorConfig::default();

        rtn_config.max_message_size = if custom_config.max_message_size == 0 {
            default_config.max_message_size
        } else {
            custom_config.max_message_size
        };

        rtn_config.executor = if custom_config.executor == Pubkey::default() {
            default_config.executor
        } else {
            custom_config.executor
        };

        rtn_config
    }
}

#[account]
#[derive(InitSpace, Default)]
pub struct SendConfig {
    pub bump: u8,
    pub uln: UlnConfig,
    pub executor: ExecutorConfig,
}

#[account]
#[derive(InitSpace, Default)]
pub struct ReceiveConfig {
    pub bump: u8,
    pub uln: UlnConfig,
}

// the max data size that can be sent through a CPI is 1280 bytes
// the total size of (optional) dvn list is not more than 20
pub const DVN_MAX_LEN: u8 = 16;

#[derive(Clone, InitSpace, AnchorSerialize, AnchorDeserialize, Default)]
pub struct UlnConfig {
    pub confirmations: u64,
    pub required_dvn_count: u8,
    pub optional_dvn_count: u8,
    pub optional_dvn_threshold: u8,
    #[max_len(DVN_MAX_LEN)]
    pub required_dvns: Vec<Pubkey>, // PDA of DVN program (fees paid to these accounts)
    #[max_len(DVN_MAX_LEN)]
    pub optional_dvns: Vec<Pubkey>, // PDA of DVN program (fees paid to these accounts)
}

impl UlnConfig {
    pub const MAX_COUNT: u8 = DVN_MAX_LEN;
    pub const NIL_DVN_COUNT: u8 = u8::MAX;
    pub const NIL_CONFIRMATIONS: u64 = u64::MAX;
    pub const DEFAULT: u8 = 0;

    pub fn set_config(&mut self, config: &UlnConfig) -> Result<()> {
        // required dvns
        // if dvnCount == NONE, dvns list must be empty
        // if dvnCount == DEFAULT, dvn list must be empty
        // otherwise, dvnList.length == dvnCount and assert the list is valid
        if config.required_dvn_count == Self::NIL_DVN_COUNT
            || config.required_dvn_count == Self::DEFAULT
        {
            require!(config.required_dvns.len() == 0, UlnError::InvalidRequiredDVNCount);
        } else {
            require!(
                config.required_dvns.len() == config.required_dvn_count as usize
                    && config.required_dvn_count <= Self::MAX_COUNT,
                UlnError::InvalidRequiredDVNCount
            );
            Self::assert_no_duplicates(&config.required_dvns)?;
        }

        // optional dvns
        // if optionalDVNCount == NONE, optionalDVNs list must be empty and threshold must be 0
        // if optionalDVNCount == DEFAULT, optionalDVNs list must be empty and threshold must be 0
        // otherwise, optionalDVNs.length == optionalDVNCount, threshold > 0 && threshold <=
        // optionalDVNCount and assert the list is valid

        // example use case: an oapp uses the DEFAULT 'required' but
        //     a) use a custom 1/1 dvn (practically a required dvn), or
        //     b) use a custom 2/3 dvn
        if config.optional_dvn_count == Self::NIL_DVN_COUNT
            || config.optional_dvn_count == Self::DEFAULT
        {
            require!(config.optional_dvns.len() == 0, UlnError::InvalidOptionalDVNCount);
            require!(config.optional_dvn_threshold == 0, UlnError::InvalidOptionalDVNThreshold);
        } else {
            require!(
                config.optional_dvns.len() == config.optional_dvn_count as usize
                    && config.optional_dvn_count <= Self::MAX_COUNT,
                UlnError::InvalidOptionalDVNCount
            );
            require!(
                config.optional_dvn_threshold > 0
                    && config.optional_dvn_threshold <= config.optional_dvn_count,
                UlnError::InvalidOptionalDVNThreshold
            );
            Self::assert_no_duplicates(&config.optional_dvns)?;
        }

        // don't assert valid count here, as it needs to be validated along side default config
        self.confirmations = config.confirmations;
        self.required_dvn_count = config.required_dvn_count;
        self.optional_dvn_count = config.optional_dvn_count;
        self.optional_dvn_threshold = config.optional_dvn_threshold;
        self.required_dvns = config.required_dvns.clone();
        self.optional_dvns = config.optional_dvns.clone();

        Ok(())
    }

    /// 1) its values are all LITERAL (e.g. 0 is 0). whereas in the oapp ULN config, 0 (default
    ///    value) points to the default ULN config this design enables the oapp to point to DEFAULT
    ///    config without explicitly setting the config
    /// 2) its configuration is more restrictive than the oapp ULN config that a) it must not use
    ///    NIL value, where NIL is used only by oapps to indicate the LITERAL 0 b) it must have at
    ///    least one DVN
    pub fn set_default_config(&mut self, config: &UlnConfig) -> Result<()> {
        // 2.a must not use NIL
        require!(
            config.required_dvn_count != Self::NIL_DVN_COUNT,
            UlnError::InvalidRequiredDVNCount
        );
        require!(
            config.optional_dvn_count != Self::NIL_DVN_COUNT,
            UlnError::InvalidOptionalDVNCount
        );
        require!(config.confirmations != Self::NIL_CONFIRMATIONS, UlnError::InvalidConfirmations);

        // 2.b must have at least one dvn
        Self::assert_at_least_one_dvn(config)?;

        self.set_config(config)?;

        Ok(())
    }

    fn assert_no_duplicates(dvns: &Vec<Pubkey>) -> Result<()> {
        let mut last_dvn = &Pubkey::default();
        for dvn in dvns {
            require!(dvn.cmp(&last_dvn) == Ordering::Greater, UlnError::Unsorted);
            last_dvn = dvn;
        }
        Ok(())
    }

    fn assert_at_least_one_dvn(config: &UlnConfig) -> Result<()> {
        require!(
            config.required_dvn_count > 0 || config.optional_dvn_threshold > 0,
            UlnError::AtLeastOneDVN
        );
        Ok(())
    }

    pub fn get_config(default_config: &UlnConfig, custom_config: &UlnConfig) -> Result<UlnConfig> {
        let mut rtn_config = UlnConfig::default();

        if custom_config.confirmations == Self::DEFAULT as u64 {
            rtn_config.confirmations = default_config.confirmations;
        } else if custom_config.confirmations != Self::NIL_CONFIRMATIONS {
            rtn_config.confirmations = custom_config.confirmations;
        } // else do nothing, rtnConfig.confirmation is 0

        if custom_config.required_dvn_count == Self::DEFAULT {
            if default_config.required_dvn_count > 0 {
                rtn_config.required_dvns = default_config.required_dvns.clone();
                rtn_config.required_dvn_count = default_config.required_dvn_count;
            }
        } else {
            if custom_config.required_dvn_count != Self::NIL_DVN_COUNT {
                rtn_config.required_dvns = custom_config.required_dvns.clone();
                rtn_config.required_dvn_count = custom_config.required_dvn_count;
            }
        }

        if custom_config.optional_dvn_count == Self::DEFAULT {
            if default_config.optional_dvn_count > 0 {
                rtn_config.optional_dvns = default_config.optional_dvns.clone();
                rtn_config.optional_dvn_count = default_config.optional_dvn_count;
                rtn_config.optional_dvn_threshold = default_config.optional_dvn_threshold;
            }
        } else {
            if custom_config.optional_dvn_count != Self::NIL_DVN_COUNT {
                rtn_config.optional_dvns = custom_config.optional_dvns.clone();
                rtn_config.optional_dvn_count = custom_config.optional_dvn_count;
                rtn_config.optional_dvn_threshold = custom_config.optional_dvn_threshold;
            }
        }

        // the final value must have at least one dvn
        // it is possible that some default config result into 0 dvns
        Self::assert_at_least_one_dvn(&rtn_config)?;

        Ok(rtn_config)
    }
}

utils::generate_account_size_test!(UlnSettings, uln_settings_test);
utils::generate_account_size_test!(SendConfig, send_config_test);
utils::generate_account_size_test!(ReceiveConfig, receive_config_test);
