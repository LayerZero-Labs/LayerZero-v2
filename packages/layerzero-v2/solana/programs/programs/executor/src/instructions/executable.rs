use crate::*;
use oapp::endpoint::{
    state::{Nonce, PayloadHash, EMPTY_PAYLOAD_HASH, NIL_PAYLOAD_HASH},
    ID as ENDPOINT_ID, NONCE_SEED, PAYLOAD_HASH_SEED,
};

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub enum ExecutionState {
    NotExecutable, // executor: waits for PayloadVerified event and starts polling for executable
    VerifiedButNotExecutable, // executor: starts active polling for executable
    Executable,
    Executed,
}

#[derive(Accounts)]
#[instruction(params: ExecutableParams)]
pub struct Executable<'info> {
    #[account(
        seeds = [
            NONCE_SEED,
            params.receiver.as_ref(),
            &params.src_eid.to_be_bytes(),
            &params.sender[..]
        ],
        bump = nonce.bump,
        seeds::program = ENDPOINT_ID
    )]
    pub nonce: Account<'info, Nonce>,
    #[account(
        seeds = [
            PAYLOAD_HASH_SEED,
            params.receiver.as_ref(),
            &params.src_eid.to_be_bytes(),
            &params.sender[..],
            &params.nonce.to_be_bytes()
        ],
        bump,
        seeds::program = ENDPOINT_ID
    )]
    pub payload_hash: AccountInfo<'info>, // deserialize only it exists
}

impl Executable<'_> {
    pub fn apply(ctx: &Context<Executable>, params: &ExecutableParams) -> Result<ExecutionState> {
        let payload_hash = inbound_payload_hash(&ctx.accounts.payload_hash)?;

        if params.nonce <= ctx.accounts.nonce.inbound_nonce {
            // executed if payload hash is empty and nonce is less than or equals to inboundNonce
            if payload_hash == EMPTY_PAYLOAD_HASH {
                return Ok(ExecutionState::Executed);
            }

            // executable if nonce has not been executed and has not been nilified and nonce is less than or equal to inboundNonce
            if payload_hash != NIL_PAYLOAD_HASH {
                return Ok(ExecutionState::Executable);
            }
        }

        // only start active executable polling if payload hash is not empty nor nil
        if payload_hash != EMPTY_PAYLOAD_HASH && payload_hash != NIL_PAYLOAD_HASH {
            return Ok(ExecutionState::VerifiedButNotExecutable);
        }

        // return NotExecutable as a catch-all
        Ok(ExecutionState::NotExecutable)
    }
}

fn inbound_payload_hash(payload_hash_acc: &AccountInfo) -> Result<[u8; 32]> {
    if payload_hash_acc.owner.key() == ENDPOINT_ID {
        let mut data: &[u8] = &payload_hash_acc.try_borrow_data()?;
        return Ok(PayloadHash::try_deserialize(&mut data)?.hash);
    } else {
        Ok(EMPTY_PAYLOAD_HASH)
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct ExecutableParams {
    pub receiver: Pubkey,
    pub src_eid: u32,
    pub sender: [u8; 32],
    pub nonce: u64,
}
