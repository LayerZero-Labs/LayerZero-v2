#[test_only]
module package_whitelist_validator::mock_witness;

public struct LayerZeroWitness has drop {}

public fun new(): LayerZeroWitness {
    LayerZeroWitness {}
}
