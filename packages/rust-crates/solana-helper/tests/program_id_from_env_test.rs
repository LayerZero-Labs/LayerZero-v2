use anchor_lang::solana_program::pubkey::Pubkey;
use solana_helper::program_id_from_env;

const TEST_PROGRAM: Pubkey = Pubkey::new_from_array(program_id_from_env!(
    "TEST_ID",
    "6GsmxMTHAAiFKfemuM4zBjumTjNSX5CAiw4xSSXM2Toy"
));

#[test]
fn test_program_id_from_env() {
    let actual = bs58::encode(TEST_PROGRAM.to_bytes()).into_string();
    let expected = "6GsmxMTHAAiFKfemuM4zBjumTjNSX5CAiw4xSSXM2Toy";
    assert_eq!(expected, actual.as_str());
}
