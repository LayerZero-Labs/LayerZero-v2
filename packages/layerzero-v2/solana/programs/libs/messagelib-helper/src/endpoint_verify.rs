use crate::*;
use anchor_lang::prelude::*;
use endpoint::{cpi::accounts::Verify, instructions::VerifyParams, ConstructCPIContext};
use packet_v1_codec;

pub fn verify(
    endpoint_program: Pubkey,
    receive_library: Pubkey,
    packet_header: &[u8],
    payload_hash: [u8; 32],
    seeds: &[&[u8]],
    accounts: &[AccountInfo],
) -> Result<()> {
    if receive_library != accounts[1].key() {
        return Err(ErrorCode::ConstraintAddress.into());
    }
    let verify_params = VerifyParams {
        src_eid: packet_v1_codec::src_eid(packet_header),
        sender: packet_v1_codec::sender(packet_header),
        receiver: Pubkey::new_from_array(packet_v1_codec::receiver(packet_header)),
        nonce: packet_v1_codec::nonce(packet_header),
        payload_hash,
    };

    let cpi_ctx = Verify::construct_context(endpoint_program, accounts)?;
    endpoint::cpi::verify(cpi_ctx.with_signer(&[seeds]), verify_params)
}
