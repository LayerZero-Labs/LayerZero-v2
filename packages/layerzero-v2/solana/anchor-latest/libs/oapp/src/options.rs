use anchor_lang::prelude::*;

pub fn combine_options(mut enforced_options: Vec<u8>, extra_options: &Vec<u8>) -> Result<Vec<u8>> {
    // No enforced options, pass whatever the caller supplied, even if it's empty or legacy type
    // 1/2 options.
    if enforced_options.len() == 0 {
        return Ok(extra_options.to_vec());
    }

    // No caller options, return enforced
    if extra_options.len() == 0 {
        return Ok(enforced_options);
    }

    // If caller provided extra_options, must be type 3 as it's the ONLY type that can be
    // combined.
    if extra_options.len() >= 2 {
        assert_type_3(extra_options)?;
        // Remove the first 2 bytes containing the type from the extra_options and combine with
        // enforced.
        enforced_options.extend_from_slice(&extra_options[2..]);
        return Ok(enforced_options);
    }

    // No valid set of options was found.
    Err(ErrorCode::InvalidOptions.into())
}

pub fn assert_type_3(options: &Vec<u8>) -> anchor_lang::Result<()> {
    let mut option_type_bytes = [0; 2];
    option_type_bytes.copy_from_slice(&options[0..2]);
    require!(u16::from_be_bytes(option_type_bytes) == 3, ErrorCode::InvalidOptions);
    Ok(())
}

#[error_code]
enum ErrorCode {
    InvalidOptions,
}
