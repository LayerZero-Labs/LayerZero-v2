/// Provides a generic wrapper struct that can tag an EID value with configuration
module endpoint_v2_common::config_eid_tagged {
    struct EidTagged<Config> has drop, copy, store {
        eid: u32,
        config: Config,
    }

    /// Tag a configuration with an EID
    public fun tag_with_eid<Config>(eid: u32, config: Config): EidTagged<Config> {
        EidTagged { eid, config }
    }

    /// Get the EID from the tagged configuration
    public fun get_eid<Config>(c: &EidTagged<Config>): u32 {
        c.eid
    }

    /// Borrow the configuration from the tagged configuration
    public fun borrow_config<Config>(c: &EidTagged<Config>): &Config {
        &c.config
    }

    /// Get the EID and configuration from the tagged configuration
    public fun get_config<Config>(c: EidTagged<Config>): Config {
        let EidTagged<Config> { eid: _, config } = c;
        config
    }

    public fun get_eid_and_config<Config>(c: EidTagged<Config>): (u32, Config) {
        let EidTagged { eid, config } = c;
        (eid, config)
    }
}
