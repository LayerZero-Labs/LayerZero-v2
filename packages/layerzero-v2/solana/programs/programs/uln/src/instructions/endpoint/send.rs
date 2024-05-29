use crate::*;
use anchor_lang::solana_program::{program, system_instruction};
use messagelib_helper::{
    endpoint::instructions::hash_payload,
    messagelib_interface::Packet,
    packet_v1_codec::{encode, encode_packet_header},
};

#[event_cpi]
#[derive(Accounts)]
#[instruction(params: SendParams)]
pub struct Send<'info> {
    pub endpoint: Signer<'info>,
    #[account(has_one = endpoint, seeds = [ULN_SEED], bump = uln.bump)]
    pub uln: Account<'info, UlnSettings>,
    /// The custom send config account may be uninitialized, so deserialize it only if it's initialized
    #[account(
        seeds = [SEND_CONFIG_SEED, &params.packet.dst_eid.to_be_bytes(), &params.packet.sender.to_bytes()],
        bump
    )]
    pub send_config: AccountInfo<'info>,
    #[account(
        seeds = [SEND_CONFIG_SEED, &params.packet.dst_eid.to_be_bytes()],
        bump = default_send_config.bump,
    )]
    pub default_send_config: Account<'info, SendConfig>,
    /// pay for the native fee
    #[account(
        mut,
        constraint = payer.key() != endpoint.key() @UlnError::InvalidPayer,
    )]
    pub payer: Signer<'info>,
    /// The treasury account to receive the native fee
    #[account(mut)]
    pub treasury: Option<AccountInfo<'info>>,
    /// for native fee transfer
    pub system_program: Program<'info, System>,
}

impl Send<'_> {
    pub fn apply<'c: 'info, 'info>(
        ctx: &mut Context<'_, '_, 'c, 'info, Send<'info>>,
        params: &SendParams,
    ) -> Result<(MessagingFee, Vec<u8>)> {
        let (executor_fee, dvn_fees) = assign_job_to_workers(
            &ctx.accounts.uln.key(),
            &ctx.accounts.payer,
            &params.packet,
            &params.options,
            &ctx.accounts.send_config,
            &ctx.accounts.default_send_config,
            ctx.remaining_accounts,
        )?;
        let worker_fee = executor_fee.fee + dvn_fees.iter().map(|f| f.fee).sum::<u64>();

        // treasury fee
        let treasury_fee = if let Some(treasury) = &ctx.accounts.uln.treasury {
            let fee = quote_treasury(treasury, worker_fee, false)?;

            // assert the treasury receiver is the same as the treasury account
            let treasury_acc = ctx.accounts.treasury.as_ref().ok_or(UlnError::InvalidTreasury)?;
            require!(treasury_acc.key() == treasury.native_receiver, UlnError::InvalidTreasury);

            if fee > 0 {
                program::invoke(
                    &system_instruction::transfer(ctx.accounts.payer.key, treasury_acc.key, fee),
                    &[ctx.accounts.payer.to_account_info(), treasury_acc.to_account_info()],
                )?;
                Some(TreasuryFee {
                    treasury: treasury.native_receiver,
                    fee,
                    pay_in_lz_token: false,
                })
            } else {
                None
            }
        } else {
            None
        };

        let total_fee = worker_fee + treasury_fee.as_ref().map(|f| f.fee).unwrap_or(0);
        require!(params.native_fee >= total_fee, UlnError::InsufficientFee);

        emit_cpi!(FeesPaidEvent { executor: executor_fee, dvns: dvn_fees, treasury: treasury_fee });

        Ok((MessagingFee { native_fee: total_fee, lz_token_fee: 0 }, encode(&params.packet)))
    }
}

pub(crate) fn assign_job_to_workers<'c: 'info, 'info>(
    uln: &Pubkey,
    payer: &AccountInfo<'info>,
    packet: &Packet,
    options: &[u8],
    send_config: &AccountInfo,
    default_send_config: &SendConfig,
    worker_accounts: &[AccountInfo<'info>],
) -> Result<(WorkerFee, Vec<WorkerFee>)> {
    let (uln_config, executor_config) = get_send_config(send_config, default_send_config)?;
    let (executor_options, dvn_options) = decode_options(options)?;

    // pay executor fee
    let executor_accounts = &worker_accounts[0..4]; // each worker can have 4 accounts
    let executor_fee = quote_executor(
        uln,
        &executor_config,
        packet.dst_eid,
        &packet.sender,
        packet.message.len() as u64,
        executor_options,
        executor_accounts,
    )?;
    if executor_fee.fee > 0 {
        // the account at index 1 is the executor config account, which is the account that needs to be paid
        program::invoke(
            &system_instruction::transfer(payer.key, executor_accounts[1].key, executor_fee.fee),
            &[payer.to_account_info(), executor_accounts[1].to_account_info()],
        )?;
    }

    // pay dvn fees
    let dvn_accounts = &worker_accounts[4..];
    let dvn_fees = quote_dvns(
        uln,
        &uln_config,
        packet.dst_eid,
        &packet.sender,
        encode_packet_header(&packet),
        hash_payload(&packet.guid, &packet.message),
        dvn_options,
        dvn_accounts,
    )?;
    for (i, chunk) in dvn_accounts.chunks(4).enumerate() {
        let fee = dvn_fees[i].fee;
        if fee > 0 {
            // the account at index 1 is the dvn config account,
            // which is the account that needs to be paid
            let dvn_acc = &chunk[1];
            program::invoke(
                &system_instruction::transfer(payer.key, dvn_acc.key, fee),
                &[payer.to_account_info(), chunk[1].to_account_info()],
            )?;
        }
    }

    Ok((executor_fee, dvn_fees))
}

pub(crate) fn get_send_config(
    custom_config_acc: &AccountInfo,
    default_config: &SendConfig,
) -> Result<(UlnConfig, ExecutorConfig)> {
    let custom_config = local_custom_config::<SendConfig>(custom_config_acc)?;
    let uln_config = UlnConfig::get_config(&default_config.uln, &custom_config.uln)?;
    let executor_config =
        ExecutorConfig::get_config(&default_config.executor, &custom_config.executor);
    Ok((uln_config, executor_config))
}

pub(crate) fn local_custom_config<T: Default + AccountDeserialize>(
    custom_config_acc: &AccountInfo,
) -> Result<T> {
    // if the custom config account is not initialized, return the default config
    let custom_config = if custom_config_acc.owner.key() == ID {
        let mut config_data: &[u8] = &custom_config_acc.try_borrow_data()?;
        T::try_deserialize(&mut config_data)?
    } else {
        T::default()
    };
    Ok(custom_config)
}
