use crate::*;
use cpi_helper::CpiContext;
use solana_program::clock::Slot;

/// MESSAGING STEP 2
/// requires init_verify()
#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: VerifyParams)]
pub struct Verify<'info> {
    /// The PDA of the receive library.
    #[account(
        constraint = is_valid_receive_library(
            receive_library.key(),
            &receive_library_config,
            &default_receive_library_config,
            Clock::get()?.slot
        ) @LayerZeroError::InvalidReceiveLibrary
    )]
    pub receive_library: Signer<'info>,
    #[account(
        seeds = [RECEIVE_LIBRARY_CONFIG_SEED, &params.receiver.to_bytes(), &params.src_eid.to_be_bytes()],
        bump = receive_library_config.bump
    )]
    pub receive_library_config: Account<'info, ReceiveLibraryConfig>,
    #[account(
        seeds = [RECEIVE_LIBRARY_CONFIG_SEED, &params.src_eid.to_be_bytes()],
        bump = default_receive_library_config.bump
    )]
    pub default_receive_library_config: Account<'info, ReceiveLibraryConfig>,
    #[account(
        mut,
        seeds = [
            NONCE_SEED,
            &params.receiver.to_bytes(),
            &params.src_eid.to_be_bytes(),
            &params.sender[..]
        ],
        bump = nonce.bump
    )]
    pub nonce: Account<'info, Nonce>,
    #[account(
        mut,
        seeds = [
            PENDING_NONCE_SEED,
            &params.receiver.to_bytes(),
            &params.src_eid.to_be_bytes(),
            &params.sender[..]
        ],
        bump = pending_inbound_nonce.bump
    )]
    pub pending_inbound_nonce: Account<'info, PendingInboundNonce>,
    #[account(
        mut,
        seeds = [
            PAYLOAD_HASH_SEED,
            &params.receiver.to_bytes(),
            &params.src_eid.to_be_bytes(),
            &params.sender[..],
            &params.nonce.to_be_bytes()
        ],
        bump = payload_hash.bump,
        constraint = params.payload_hash != EMPTY_PAYLOAD_HASH @LayerZeroError::InvalidPayloadHash
    )]
    pub payload_hash: Account<'info, PayloadHash>,
}

impl Verify<'_> {
    pub fn apply(ctx: &mut Context<Verify>, params: &VerifyParams) -> Result<()> {
        // don't need initializable() as the Nonce account was initiated by the delegate
        // don't need verifiable() as the init_verify() already checks the nonce requirement

        if params.nonce > ctx.accounts.nonce.inbound_nonce {
            ctx.accounts
                .pending_inbound_nonce
                .insert_pending_inbound_nonce(params.nonce, &mut ctx.accounts.nonce)?;
        }

        ctx.accounts.payload_hash.hash = params.payload_hash;

        emit_cpi!(PacketVerifiedEvent {
            src_eid: params.src_eid,
            sender: params.sender,
            receiver: params.receiver,
            nonce: params.nonce,
            payload_hash: params.payload_hash,
        });

        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct VerifyParams {
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub receiver: Pubkey,
    pub nonce: u64,
    pub payload_hash: [u8; 32],
}

pub fn is_valid_receive_library(
    actual_receiver_library: Pubkey,
    receiver_library_config: &ReceiveLibraryConfig,
    default_receiver_library_config: &ReceiveLibraryConfig,
    slot: Slot,
) -> bool {
    let (expected_receiver_library, is_default) =
        if receiver_library_config.message_lib == DEFAULT_MESSAGE_LIB {
            (default_receiver_library_config.message_lib, true)
        } else {
            (receiver_library_config.message_lib, false)
        };

    // early return true if the actual_receiver_library is the currently configured one
    if actual_receiver_library == expected_receiver_library {
        return true;
    }

    // check the timeout condition otherwise
    // if the Oapp is using default_receiver_library_config, use the default timeout config
    // otherwise, use the timeout configured by the Oapp
    let timeout = if is_default {
        &default_receiver_library_config.timeout
    } else {
        &receiver_library_config.timeout
    };

    // requires the actual_receiver_library to be the same as the one in grace period and the grace period has not expired
    if let Some(timeout) = timeout {
        if timeout.message_lib == actual_receiver_library && timeout.expiry > slot {
            return true;
        }
    }

    // returns false by default
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_valid_receive_library_with_slot() {
        let msg_lib_v1 = Pubkey::new_unique();
        let msg_lib_v2 = Pubkey::new_unique();
        let mut receiver_library_config =
            ReceiveLibraryConfig { message_lib: msg_lib_v2, timeout: None, bump: 0 };
        let mut default_receiver_library_config =
            ReceiveLibraryConfig { message_lib: DEFAULT_MESSAGE_LIB, timeout: None, bump: 0 };

        // Test case 1: oapp has a custom config, without timeout
        // true, actual_receiver_library is the same as expected_receiver_library
        let actual_receiver_library = msg_lib_v2;
        let result = is_valid_receive_library(
            actual_receiver_library,
            &receiver_library_config,
            &default_receiver_library_config,
            0,
        );
        assert_eq!(result, true);

        // false, if the actual_receiver_library is not the same as expected_receiver_library
        let actual_receiver_library = msg_lib_v1;
        let result = is_valid_receive_library(
            actual_receiver_library,
            &receiver_library_config,
            &default_receiver_library_config,
            0,
        );
        assert_eq!(result, false);

        // Test case 2: oapp has a custom config, with timeout
        // true, actual_receiver_library is different from expected_receiver_library but within the grace period
        let actual_receiver_library = msg_lib_v1;
        receiver_library_config.timeout =
            Some(ReceiveLibraryTimeout { message_lib: msg_lib_v1, expiry: 100 });
        let result = is_valid_receive_library(
            actual_receiver_library,
            &receiver_library_config,
            &default_receiver_library_config,
            99, // lest than the expiry
        );
        assert_eq!(result, true);

        // false, if the grace period has expired
        let result = is_valid_receive_library(
            actual_receiver_library,
            &receiver_library_config,
            &default_receiver_library_config,
            100, // equal to the expiry
        );
        assert_eq!(result, false);

        let result = is_valid_receive_library(
            actual_receiver_library,
            &receiver_library_config,
            &default_receiver_library_config,
            1001, // greater than the expiry
        );
        assert_eq!(result, false);

        // Test case 3: oapp config is default, default config doesn't have timeout
        // true, actual_receiver_library is the same as default expected_receiver_library
        let actual_receiver_library = msg_lib_v2;
        receiver_library_config.message_lib = DEFAULT_MESSAGE_LIB;
        default_receiver_library_config.message_lib = msg_lib_v2;
        let result = is_valid_receive_library(
            actual_receiver_library,
            &receiver_library_config,
            &default_receiver_library_config,
            0,
        );
        assert_eq!(result, true);

        // false, if the actual_receiver_library is different with default expected_receiver_library
        let actual_receiver_library = msg_lib_v1;
        let result = is_valid_receive_library(
            actual_receiver_library,
            &receiver_library_config,
            &default_receiver_library_config,
            0,
        );
        assert_eq!(result, false);

        // Test case 4: oapp config is default, default config has timeout
        // true, actual_receiver_library is different from expected_receiver_library but within the grace period
        let actual_receiver_library = msg_lib_v1;
        default_receiver_library_config.timeout =
            Some(ReceiveLibraryTimeout { message_lib: msg_lib_v1, expiry: 100 });
        let result = is_valid_receive_library(
            actual_receiver_library,
            &receiver_library_config,
            &default_receiver_library_config,
            99,
        );
        assert_eq!(result, true);

        // false, if the grace period has expired
        let result = is_valid_receive_library(
            actual_receiver_library,
            &receiver_library_config,
            &default_receiver_library_config,
            100, // equal to the expiry
        );
        assert_eq!(result, false);

        let result = is_valid_receive_library(
            actual_receiver_library,
            &receiver_library_config,
            &default_receiver_library_config,
            101, // greater than the expiry
        );
        assert_eq!(result, false);
    }
}
