#[macro_export]
macro_rules! generate_account_size_test {
    ($name:ident, $test_case:ident) => {
        #[cfg(test)]
        mod $test_case {
            use super::*;
            #[test]
            fn $test_case() {
                const MAX_INNER_INSTRUCTION_REALLOCATION_SIZE: usize = 1024 * 10; // 10 KB
                assert!(
                    8 + super::$name::INIT_SPACE <= MAX_INNER_INSTRUCTION_REALLOCATION_SIZE,
                    "Size too large: {}",
                    8 + super::$name::INIT_SPACE
                );
            }
        }
    };
}
