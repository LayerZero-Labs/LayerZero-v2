use crate::*;

#[account]
#[derive(InitSpace)]
pub struct Peer {
    pub address: [u8; 32],
    pub rate_limiter: Option<RateLimiter>,
    pub bump: u8,
}

#[derive(Clone, Default, AnchorSerialize, AnchorDeserialize, InitSpace)]
pub struct RateLimiter {
    pub capacity: u64,
    pub tokens: u64,
    pub refill_per_second: u64,
    pub last_refill_time: u64,
}

impl RateLimiter {
    pub fn set_rate(&mut self, refill_per_second: u64) -> Result<()> {
        self.refill(0)?;
        self.refill_per_second = refill_per_second;
        Ok(())
    }

    pub fn set_capacity(&mut self, capacity: u64) -> Result<()> {
        self.capacity = capacity;
        self.tokens = capacity;
        self.last_refill_time = Clock::get()?.unix_timestamp.try_into().unwrap();
        Ok(())
    }

    pub fn refill(&mut self, extra_tokens: u64) -> Result<()> {
        let mut new_tokens = extra_tokens;
        let current_time: u64 = Clock::get()?.unix_timestamp.try_into().unwrap();
        if current_time > self.last_refill_time {
            let time_elapsed_in_seconds = current_time - self.last_refill_time;
            new_tokens += time_elapsed_in_seconds * self.refill_per_second;
        }
        self.tokens = std::cmp::min(self.capacity, self.tokens.saturating_add(new_tokens));

        self.last_refill_time = current_time;
        Ok(())
    }

    pub fn try_consume(&mut self, amount: u64) -> Result<()> {
        self.refill(0)?;
        match self.tokens.checked_sub(amount) {
            Some(new_tokens) => {
                self.tokens = new_tokens;
                Ok(())
            },
            None => Err(error!(OftError::RateLimitExceeded)),
        }
    }
}
