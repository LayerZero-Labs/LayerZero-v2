use crate::*;

pub const EMPTY_PAYLOAD_HASH: [u8; 32] = [0u8; 32];
pub const NIL_PAYLOAD_HASH: [u8; 32] = [0xffu8; 32];

pub const PENDING_INBOUND_NONCE_MAX_LEN: u64 = 256;

#[account]
#[derive(InitSpace)]
pub struct Nonce {
    pub bump: u8,
    pub outbound_nonce: u64,
    pub inbound_nonce: u64,
}

impl Nonce {
    /// update the inbound_nonce to the max nonce, to which the pending_inbound_nonces are continuous
    /// from the current inbound_nonce
    pub fn update_inbound_nonce(&mut self, pending_inbound_nonce: &mut PendingInboundNonce) {
        let mut new_inbound_nonce = self.inbound_nonce;
        for nonce in pending_inbound_nonce.nonces.iter() {
            if *nonce == new_inbound_nonce + 1 {
                new_inbound_nonce = *nonce;
            } else {
                break;
            }
        }

        if new_inbound_nonce > self.inbound_nonce {
            let diff = new_inbound_nonce - self.inbound_nonce;
            self.inbound_nonce = new_inbound_nonce;
            pending_inbound_nonce.nonces.drain(0..diff as usize);
        }
    }
}

#[account]
#[derive(InitSpace)]
pub struct PendingInboundNonce {
    #[max_len(PENDING_INBOUND_NONCE_MAX_LEN)]
    pub nonces: Vec<u64>,
    pub bump: u8,
}

impl PendingInboundNonce {
    /// Insert a new nonce into the pending inbound nonce list if it doesn't already exist.
    pub fn insert_pending_inbound_nonce(
        &mut self,
        new_inbound_nonce: u64,
        nonce: &mut Nonce,
    ) -> Result<()> {
        require!(
            nonce.inbound_nonce < new_inbound_nonce
                && nonce.inbound_nonce + PENDING_INBOUND_NONCE_MAX_LEN >= new_inbound_nonce,
            LayerZeroError::InvalidNonce
        );

        // allow to re-verify at the same nonce and insert the new nonce if it doesn't already exist
        if let Err(index) = self.nonces.binary_search(&new_inbound_nonce) {
            self.nonces.insert(index, new_inbound_nonce);

            // update the inbound nonce on insert
            nonce.update_inbound_nonce(self);
        }
        Ok(())
    }
}

#[account]
#[derive(InitSpace)]
pub struct PayloadHash {
    pub hash: [u8; 32],
    pub bump: u8,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_insert_pending_inbound_nonce() {
        let mut pending_inbound_nonce =
            PendingInboundNonce { nonces: vec![1, 3, 5, 7, 9], bump: 0 };
        let mut nonce = Nonce { bump: 0, outbound_nonce: 0, inbound_nonce: 0 };

        // Insert a new nonce that doesn't already exist
        let new_inbound_nonce = 6;
        let result =
            pending_inbound_nonce.insert_pending_inbound_nonce(new_inbound_nonce, &mut nonce);
        assert!(result.is_ok());
        assert_eq!(pending_inbound_nonce.nonces, vec![3, 5, 6, 7, 9]);
        assert_eq!(nonce.inbound_nonce, 1);

        // Insert a new nonce that already exists
        let new_inbound_nonce = 7;
        let result =
            pending_inbound_nonce.insert_pending_inbound_nonce(new_inbound_nonce, &mut nonce);
        assert!(result.is_ok());
        assert_eq!(pending_inbound_nonce.nonces, vec![3, 5, 6, 7, 9]);
        assert_eq!(nonce.inbound_nonce, 1);

        // Insert a new nonce that is bigger than the current nonce
        let new_inbound_nonce = 200;
        let result =
            pending_inbound_nonce.insert_pending_inbound_nonce(new_inbound_nonce, &mut nonce);
        assert!(result.is_ok());
        assert_eq!(pending_inbound_nonce.nonces, vec![3, 5, 6, 7, 9, 200]);
        assert_eq!(nonce.inbound_nonce, 1);

        let new_inbound_nonce = 100;
        let result =
            pending_inbound_nonce.insert_pending_inbound_nonce(new_inbound_nonce, &mut nonce);
        assert!(result.is_ok());
        assert_eq!(pending_inbound_nonce.nonces, vec![3, 5, 6, 7, 9, 100, 200]);
        assert_eq!(nonce.inbound_nonce, 1);

        // Insert sequential nonce to update the inbound nonce
        let new_inbound_nonce = 2;
        let result =
            pending_inbound_nonce.insert_pending_inbound_nonce(new_inbound_nonce, &mut nonce);
        assert!(result.is_ok());
        assert_eq!(pending_inbound_nonce.nonces, vec![5, 6, 7, 9, 100, 200]);
        assert_eq!(nonce.inbound_nonce, 3);

        let new_inbound_nonce = 4;
        let result =
            pending_inbound_nonce.insert_pending_inbound_nonce(new_inbound_nonce, &mut nonce);
        assert!(result.is_ok());
        assert_eq!(pending_inbound_nonce.nonces, vec![9, 100, 200]);
        assert_eq!(nonce.inbound_nonce, 7);

        // Can't insert nonce lest than or equal the current inbound nonce
        for i in 1..=nonce.inbound_nonce {
            let result = pending_inbound_nonce.insert_pending_inbound_nonce(i, &mut nonce);
            assert_eq!(result.unwrap_err(), LayerZeroError::InvalidNonce.into());
        }

        // Can't insert nonce bigger than the current inbound nonce + PENDING_INBOUND_NONCE_MAX_LEN
        let new_inbound_nonce = PENDING_INBOUND_NONCE_MAX_LEN + nonce.inbound_nonce + 1;
        let result =
            pending_inbound_nonce.insert_pending_inbound_nonce(new_inbound_nonce, &mut nonce);
        assert_eq!(result.unwrap_err(), LayerZeroError::InvalidNonce.into());
    }
}

utils::generate_account_size_test!(Nonce, nonce_test);
utils::generate_account_size_test!(PendingInboundNonce, pending_inbound_nonce_test);
utils::generate_account_size_test!(PayloadHash, payload_hash_test);
