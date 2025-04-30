#[cfg(test)]
mod test_dvn_config {
    use anchor_lang::prelude::Pubkey;
    use anchor_lang::solana_program::keccak;
    use dvn::state::{DvnConfig, Multisig};
    use secp256k1::rand::rngs::OsRng;
    use secp256k1::{All, Message, Secp256k1, SecretKey};
    use worker_interface::worker_utils;

    struct TestFixture {
        dvn_config: DvnConfig,
        secp: Secp256k1<All>,
        secrets: Vec<SecretKey>,
    }
    impl TestFixture {
        fn new() -> Self {
            let secp = Secp256k1::new();

            let quorum = 2;
            let mut signers = vec![];
            let mut secrets = vec![];
            for _ in 0..quorum {
                let (secret_key, public_key) = secp.generate_keypair(&mut OsRng);
                secrets.push(secret_key);

                let public_key_uncompressed = public_key.serialize_uncompressed();
                let mut pubkey = [0u8; 64];
                pubkey.copy_from_slice(&public_key_uncompressed[1..65]); // prefix 0x04 used to indicate uncompressed public key
                signers.push(pubkey);
            }

            TestFixture {
                dvn_config: DvnConfig {
                    vid: 0,
                    bump: 0,
                    acl: worker_utils::Acl { allow_list: vec![], deny_list: vec![] },
                    default_multiplier_bps: 0,
                    price_feed: Pubkey::new_unique(),
                    paused: false,
                    admins: vec![],
                    msglibs: vec![],
                    dst_configs: vec![],
                    multisig: Multisig { quorum: 2, signers },
                },
                secrets,
                secp,
            }
        }

        fn sign(&self, digest: &[u8; 32], secret_key: &SecretKey) -> [u8; 65] {
            let message = Message::from_digest(*digest);

            // Sign the message with a recoverable signature
            let recoverable_sig = self.secp.sign_ecdsa_recoverable(&message, &secret_key);

            // Extract the recovery ID
            let (recovery_id, serialized_sig) = recoverable_sig.serialize_compact();

            let mut sig: [u8; 65] = [0; 65];
            sig[..64].copy_from_slice(&serialized_sig);
            sig[64] = recovery_id.to_i32() as u8;
            return sig;
        }
    }

    #[test]
    fn verify_signatures_fails_with_signer_not_in_committee() {
        let fixture = TestFixture::new();

        let (new_secret_key, _) = fixture.secp.generate_keypair(&mut OsRng);

        let digest = &keccak::hash("Hello World!".as_bytes()).to_bytes();

        let sig_1 = fixture.sign(&digest, &fixture.secrets[0]);
        let sig_2 = fixture.sign(&digest, &new_secret_key);

        let signatures = vec![sig_1, sig_2];

        let result = fixture.dvn_config.multisig.verify_signatures(&signatures, digest);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("SignerNotInCommittee"));
    }

    #[test]
    fn verify_signatures_fails_with_signatures_len_lt_quorum() {
        let fixture = TestFixture::new();

        let digest = &keccak::hash("Hello World!".as_bytes()).to_bytes();

        let sig_1 = fixture.sign(&digest, &fixture.secrets[0]);
        let signatures = vec![sig_1];

        // pass no sigs
        let result = fixture.dvn_config.multisig.verify_signatures(&signatures, digest);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("InvalidSignatureLen"));
    }

    #[test]
    fn verify_signatures_fails_with_duplicated_signatures() {
        let fixture = TestFixture::new();

        let digest = &keccak::hash("Hello World!".as_bytes()).to_bytes();

        let sig_1 = fixture.sign(&digest, &fixture.secrets[0]);
        let sig_dup = fixture.sign(&digest, &fixture.secrets[0]);
        let signatures = vec![sig_1, sig_dup];

        let result = fixture.dvn_config.multisig.verify_signatures(&signatures, digest);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("DuplicateSignature"));
    }

    #[test]
    fn verify_signatures() {
        let fixture = TestFixture::new();

        let digest = &keccak::hash("Hello World!".as_bytes()).to_bytes();

        let sig_1 = fixture.sign(&digest, &fixture.secrets[0]);
        let sig_2 = fixture.sign(&digest, &fixture.secrets[1]);
        let signatures = vec![sig_1, sig_2];

        assert!(fixture.dvn_config.multisig.verify_signatures(&signatures, digest).is_ok());
    }
}
