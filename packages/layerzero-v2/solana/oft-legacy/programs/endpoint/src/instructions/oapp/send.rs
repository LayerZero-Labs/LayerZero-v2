use crate::*;
use anchor_lang::solana_program::keccak::hash;
use cpi_helper::CpiContext;

/// MESSAGING STEP 1

#[event_cpi]
#[derive(CpiContext, Accounts)]
#[instruction(params: SendParams)]
pub struct Send<'info> {
    pub sender: Signer<'info>,
    /// CHECK: assert this program in assert_send_library()
    pub send_library_program: UncheckedAccount<'info>,
    #[account(
        seeds = [SEND_LIBRARY_CONFIG_SEED, sender.key.as_ref(), &params.dst_eid.to_be_bytes()],
        bump = send_library_config.bump
    )]
    pub send_library_config: Account<'info, SendLibraryConfig>,
    #[account(
        seeds = [SEND_LIBRARY_CONFIG_SEED, &params.dst_eid.to_be_bytes()],
        bump = default_send_library_config.bump
    )]
    pub default_send_library_config: Account<'info, SendLibraryConfig>,
    /// The PDA signer to the send library when the endpoint calls the send library.
    #[account(
        seeds = [
            MESSAGE_LIB_SEED,
            &get_send_library(
                &send_library_config,
                &default_send_library_config
            ).key().to_bytes()
        ],
        bump = send_library_info.bump,
        constraint = !send_library_info.to_account_info().is_writable @LayerZeroError::ReadOnlyAccount
    )]
    pub send_library_info: Account<'info, MessageLibInfo>,
    #[account(seeds = [ENDPOINT_SEED], bump = endpoint.bump)]
    pub endpoint: Account<'info, EndpointSettings>,
    #[account(
        mut,
        seeds = [
            NONCE_SEED,
            &sender.key().to_bytes(),
            &params.dst_eid.to_be_bytes(),
            &params.receiver[..]
        ],
        bump = nonce.bump
    )]
    pub nonce: Account<'info, Nonce>,
}

impl Send<'_> {
    pub fn apply<'c: 'info, 'info>(
        ctx: &mut Context<'_, '_, 'c, 'info, Send<'info>>,
        params: &SendParams,
    ) -> Result<MessagingReceipt> {
        // increment nonce
        ctx.accounts.nonce.outbound_nonce += 1;

        // build and encode the packet
        let sender = ctx.accounts.sender.key();
        let guid = get_guid(
            ctx.accounts.nonce.outbound_nonce,
            ctx.accounts.endpoint.eid,
            sender,
            params.dst_eid,
            params.receiver,
        );
        let packet = Packet {
            nonce: ctx.accounts.nonce.outbound_nonce,
            src_eid: ctx.accounts.endpoint.eid,
            sender,
            dst_eid: params.dst_eid,
            receiver: params.receiver,
            guid,
            message: params.message.clone(),
        };

        let send_library = assert_send_library(
            &ctx.accounts.send_library_info,
            &ctx.accounts.send_library_program.key,
            &ctx.accounts.send_library_config,
            &ctx.accounts.default_send_library_config,
        )?;

        // call the send library
        let seeds: &[&[&[u8]]] =
            &[&[MESSAGE_LIB_SEED, send_library.as_ref(), &[ctx.accounts.send_library_info.bump]]];
        let cpi_ctx = CpiContext::new_with_signer(
            ctx.accounts.send_library_program.to_account_info(),
            messagelib_interface::cpi::accounts::Interface {
                endpoint: ctx.accounts.send_library_info.to_account_info(),
            },
            seeds,
        )
        .with_remaining_accounts(ctx.remaining_accounts.to_vec());

        // separate send and send_with_lz_token interface to be implemented by message library, for the benefits of:
        // 1. as different accounts are required, they can be validated through anchor constraints rather than manually handling remaining accounts
        // 2. idl can be generated and used by sdk to assembled the required accounts
        // subsequently, due to this design, fee payment is handled in the message library for simplicity
        let (fee, encoded_packet) = if params.lz_token_fee == 0 {
            let send_params = messagelib_interface::SendParams {
                packet,
                options: params.options.clone(),
                native_fee: params.native_fee,
            };
            messagelib_interface::cpi::send(cpi_ctx, send_params)?.get()
        } else {
            let lz_token_mint =
                ctx.accounts.endpoint.lz_token_mint.ok_or(LayerZeroError::LzTokenUnavailable)?;
            let send_params = messagelib_interface::SendWithLzTokenParams {
                packet,
                options: params.options.clone(),
                native_fee: params.native_fee,
                lz_token_fee: params.lz_token_fee,
                lz_token_mint,
            };
            messagelib_interface::cpi::send_with_lz_token(cpi_ctx, send_params)?.get()
        };

        emit_cpi!(PacketSentEvent {
            encoded_packet,
            options: params.options.clone(),
            send_library,
        });

        Ok(MessagingReceipt { guid, nonce: ctx.accounts.nonce.outbound_nonce, fee })
    }
}

pub(crate) fn assert_send_library(
    send_library_info: &MessageLibInfo,
    send_library_program: &Pubkey,
    send_library_config: &SendLibraryConfig,
    default_send_library_config: &SendLibraryConfig,
) -> Result<Pubkey> {
    let send_library = get_send_library(send_library_config, default_send_library_config);
    require!(
        send_library
            == Pubkey::create_program_address(
                &[MESSAGE_LIB_SEED, &[send_library_info.message_lib_bump]],
                send_library_program
            )
            .map_err(|_| LayerZeroError::InvalidSendLibrary)?,
        LayerZeroError::InvalidSendLibrary
    );
    Ok(send_library)
}

pub(crate) fn get_send_library(
    config: &SendLibraryConfig,
    default_config: &SendLibraryConfig,
) -> Pubkey {
    if config.message_lib == DEFAULT_MESSAGE_LIB {
        default_config.message_lib
    } else {
        config.message_lib
    }
}

pub fn get_guid(
    nonce: u64,
    src_eid: u32,
    sender: Pubkey,
    dst_eid: u32,
    receiver: [u8; 32],
) -> [u8; 32] {
    hash(
        &[
            &nonce.to_be_bytes()[..],
            &src_eid.to_be_bytes()[..],
            &sender.to_bytes()[..],
            &dst_eid.to_be_bytes()[..],
            &receiver[..],
        ]
        .concat(),
    )
    .to_bytes()
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SendParams {
    pub dst_eid: u32,
    pub receiver: [u8; 32],
    pub message: Vec<u8>,
    pub options: Vec<u8>,
    pub native_fee: u64,
    pub lz_token_fee: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_assert_send_library() {
        let send_library_program1 = &Pubkey::new_unique();
        let send_library_program2 = &Pubkey::new_unique();
        let (send_library1, send_library_bump1) =
            Pubkey::find_program_address(&[MESSAGE_LIB_SEED], send_library_program1);
        let (send_library2, send_library_bump2) =
            Pubkey::find_program_address(&[MESSAGE_LIB_SEED], send_library_program2);

        // set library config
        let mut send_library_config = SendLibraryConfig { message_lib: send_library1, bump: 0 };
        let message_lib_info = MessageLibInfo {
            message_lib_bump: send_library_bump1,
            message_lib_type: MessageLibType::Send,
            bump: 0,
        };
        // default send library config
        let default_send_library_config = SendLibraryConfig { message_lib: send_library2, bump: 0 };
        let message_lib_info_default = MessageLibInfo {
            message_lib_bump: send_library_bump2,
            message_lib_type: MessageLibType::Send,
            bump: 0,
        };

        // test assert_send_library with oapp setting, which is send_library1
        assert_eq!(
            assert_send_library(
                &message_lib_info,
                send_library_program1,
                &send_library_config,
                &default_send_library_config
            )
            .unwrap(),
            send_library1
        );

        // test assert_send_library with default setting
        send_library_config.message_lib = DEFAULT_MESSAGE_LIB.clone(); // oapp set send library to default
        assert_eq!(
            assert_send_library(
                &message_lib_info_default,
                send_library_program2,
                &send_library_config,
                &default_send_library_config
            )
            .unwrap(),
            send_library2
        );

        // expect err if wrong library
        assert_eq!(
            assert_send_library(
                &message_lib_info_default, // send-lib bump 2
                send_library_program1,     // wrong program
                &send_library_config,
                &default_send_library_config
            )
            .unwrap_err(),
            LayerZeroError::InvalidSendLibrary.into()
        );
    }
}
