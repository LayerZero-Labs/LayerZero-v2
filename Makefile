all:
forge test --match-path exploit-tests/solidity

crit:
forge test --match-path exploit-tests/solidity --match "@bounty_estimate $1"

clean:
forge clean
cargo clean || true
rm -rf exploit-tests/**/build
