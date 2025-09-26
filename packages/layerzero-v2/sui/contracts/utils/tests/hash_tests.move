#[test_only]
module utils::hash_tests;

use utils::hash;

#[test]
fun test_blake2b256_empty_input() {
    let empty_input = vector::empty<u8>();
    let result = hash::blake2b256!(&empty_input);
    assert!(result.to_bytes() == x"0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8", 0);

    let input = b"hello world";
    let result = hash::blake2b256!(&input);
    assert!(result.to_bytes() == x"256c83b297114d201b30179f3f0ef0cace9783622da5974326b436178aeef610", 0);
}

#[test]
fun test_keccak256_empty_input() {
    let empty_input = vector::empty<u8>();
    let result = hash::keccak256!(&empty_input);
    assert!(result.to_bytes() == x"c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470", 0);

    let input = b"hello world";
    let result = hash::keccak256!(&input);
    assert!(result.to_bytes() == x"47173285a8d7341e5e972fc677286384f802f8ef42a5ec5f03bbfa254cb01fad", 0);
}
