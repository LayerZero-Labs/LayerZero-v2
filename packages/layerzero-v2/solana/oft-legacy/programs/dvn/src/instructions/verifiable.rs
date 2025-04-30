use crate::*;
use anchor_lang::solana_program::keccak;
use messagelib_helper::{
    endpoint::{
        state::{Nonce, PayloadHash, PENDING_INBOUND_NONCE_MAX_LEN},
        ID as ENDPOINT_ID, NONCE_SEED, PAYLOAD_HASH_SEED,
    },
    packet_v1_codec::{self, PACKET_HEADER_SIZE},
};
use uln::{
    instructions::check_verifiable,
    state::{ReceiveConfig, UlnConfig},
    ID as ULN_ID, RECEIVE_CONFIG_SEED,
};

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub enum VerificationState {
    Verifying,
    Verifiable,
    Verified,
    NotInitializable,
    VerifiableButCapExceeded, // verifiable but not enough pending nonce space
}

#[derive(Accounts)]
#[instruction(params: VerifiableParams)]
pub struct Verifiable<'info> {
    #[account(
        seeds = [
            NONCE_SEED,
            packet_v1_codec::receiver(&params.packet_header).as_ref(),
            &packet_v1_codec::src_eid(&params.packet_header).to_be_bytes(),
            &packet_v1_codec::sender(&params.packet_header)[..]
        ],
        bump,
        seeds::program = ENDPOINT_ID
    )]
    pub nonce: AccountInfo<'info>, // deserialize only if exists (possibly not initializable)
    #[account(
        seeds = [
            PAYLOAD_HASH_SEED,
            packet_v1_codec::receiver(&params.packet_header).as_ref(),
            &packet_v1_codec::src_eid(&params.packet_header).to_be_bytes(),
            &packet_v1_codec::sender(&params.packet_header)[..],
            &packet_v1_codec::nonce(&params.packet_header).to_be_bytes()
        ],
        bump,
        seeds::program = ENDPOINT_ID
    )]
    pub payload_hash: AccountInfo<'info>, // deserialize only if exists
    #[account(
        seeds = [
            RECEIVE_CONFIG_SEED,
            &packet_v1_codec::src_eid(&params.packet_header).to_be_bytes(),
            packet_v1_codec::receiver(&params.packet_header).as_ref()
        ],
        bump,
        seeds::program = ULN_ID
    )]
    pub receive_config: AccountInfo<'info>, // deserialize only if configured
    #[account(
        seeds = [RECEIVE_CONFIG_SEED, &packet_v1_codec::src_eid(&params.packet_header).to_be_bytes()],
        bump = default_receive_config.bump,
        seeds::program = ULN_ID
    )]
    pub default_receive_config: Account<'info, ReceiveConfig>,
}

impl Verifiable<'_> {
    pub fn apply(
        ctx: &Context<Verifiable>,
        params: &VerifiableParams,
    ) -> Result<VerificationState> {
        // skip assert packet header, assume always correct
        let new_inbound_nonce = packet_v1_codec::nonce(&params.packet_header);

        // check endpoint initializable
        let nonce = initializable(&ctx.accounts.nonce)?;
        if nonce.is_none() {
            return Ok(VerificationState::NotInitializable);
        }

        let nonce = nonce.unwrap();
        // check endpoint verifiable
        // 1. return verified if same payload hash
        // 2. return verified if payload hash is closed and nonce <= inbound_nonce
        // 3. return verifiable but cap exceeded if not enough pending nonce space
        if !endpoint_verifiable(new_inbound_nonce, nonce.inbound_nonce, ctx, &params.payload_hash)?
        {
            return Ok(VerificationState::Verified);
        }
        // 3. check enough pending nonce
        if nonce.inbound_nonce < new_inbound_nonce
            && nonce.inbound_nonce + PENDING_INBOUND_NONCE_MAX_LEN < new_inbound_nonce
        {
            return Ok(VerificationState::VerifiableButCapExceeded);
        }

        // check uln verifiable
        if check_verifiable(
            &get_receive_config(
                &ctx.accounts.receive_config,
                &ctx.accounts.default_receive_config,
            )?,
            ctx.remaining_accounts, // confirmation accounts
            &keccak::hash(&params.packet_header).to_bytes(),
            &params.payload_hash,
        )? {
            return Ok(VerificationState::Verifiable);
        }

        Ok(VerificationState::Verifying)
    }
}

fn get_receive_config(
    receive_config_acc: &AccountInfo,
    default_receive_config: &Account<ReceiveConfig>,
) -> Result<UlnConfig> {
    let custom_cfg = if receive_config_acc.owner.key() == ULN_ID {
        let mut data: &[u8] = &receive_config_acc.try_borrow_data()?;
        ReceiveConfig::try_deserialize(&mut data)?
    } else {
        // using default
        ReceiveConfig::default()
    };

    UlnConfig::get_config(&default_receive_config.uln, &custom_cfg.uln)
}

// returns None if not initializable
fn initializable(nonce_acc: &AccountInfo) -> Result<Option<Nonce>> {
    if nonce_acc.owner.key() == ENDPOINT_ID {
        let mut data: &[u8] = &nonce_acc.try_borrow_data()?;
        Ok(Some(Nonce::try_deserialize(&mut data)?))
    } else {
        Ok(None)
    }
}

fn endpoint_verifiable(
    new_inbound_nonce: u64,
    inbound_nonce: u64,
    ctx: &Context<Verifiable>,
    hash: &[u8; 32],
) -> Result<bool> {
    // skip check for valid receive library, assume always correct
    // skip empty payload hash, assume always correct
    if ctx.accounts.payload_hash.owner.key() == ENDPOINT_ID {
        // 1. verified if same payload hash
        let mut data: &[u8] = &ctx.accounts.payload_hash.try_borrow_data()?;
        if *hash == PayloadHash::try_deserialize(&mut data)?.hash {
            return Ok(false);
        }
    } else {
        // 2. verified if cannot init_verify
        if new_inbound_nonce <= inbound_nonce {
            return Ok(false);
        }
    }

    Ok(true)
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct VerifiableParams {
    pub packet_header: [u8; PACKET_HEADER_SIZE],
    pub payload_hash: [u8; 32],
}
