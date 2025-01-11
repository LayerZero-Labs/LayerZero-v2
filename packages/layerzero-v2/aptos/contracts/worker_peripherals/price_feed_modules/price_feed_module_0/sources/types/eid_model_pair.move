module price_feed_module_0::eid_model_pair {
    use std::vector;

    use endpoint_v2_common::serde::{append_u16, append_u32, extract_u16, extract_u32};

    public inline fun DEFAULT_MODEL_TYPE(): u16 { 0 }

    public inline fun ARBITRUM_MODEL_TYPE(): u16 { 1 }

    public inline fun OPTIMISM_MODEL_TYPE(): u16 { 2 }

    /// A pair containing the destination EID and pricing model type (default, arbitrum, or optimism)
    struct EidModelPair has store, copy, drop {
        dst_eid: u32,
        model_type: u16,
    }

    // Constructor for EidModelPair
    public fun new_eid_model_pair(dst_eid: u32, model_type: u16): EidModelPair {
        EidModelPair {
            dst_eid,
            model_type,
        }
    }

    /// Get the destination EID from the EidModelPair
    public fun get_dst_eid(pair: &EidModelPair): u32 { pair.dst_eid }

    /// Get the model type from the EidModelPair
    public fun get_model_type(pair: &EidModelPair): u16 { pair.model_type }

    /// Check if the model type is valid
    /// @dev The model type must be one of the following: default 0, arbitrum 1, or optimism 2
    public fun is_valid_model_type(model_type: u16): bool {
        model_type == DEFAULT_MODEL_TYPE() ||
            model_type == ARBITRUM_MODEL_TYPE() ||
            model_type == OPTIMISM_MODEL_TYPE()
    }

    /// Serialize EidModelPair to the end of a byte buffer
    public fun append_eid_model_pair(buf: &mut vector<u8>, obj: &EidModelPair) {
        append_u32(buf, obj.dst_eid);
        append_u16(buf, obj.model_type);
    }

    /// Serialize a list of EidModelPair
    /// This is a series of EidModelPairs serialized one after the other
    public fun serialize_eid_model_pair_list(objs: &vector<EidModelPair>): vector<u8> {
        let buf = vector<u8>[];
        for (i in 0..vector::length(objs)) {
            append_eid_model_pair(&mut buf, vector::borrow(objs, i));
        };
        buf
    }

    /// Deserialize EidModelPair from a byte buffer at a given position
    /// The position to be updated to the next position after the deserialized EidModelPair
    public fun extract_eid_model_pair(buf: &vector<u8>, position: &mut u64): EidModelPair {
        let dst_eid = extract_u32(buf, position);
        let model_type = extract_u16(buf, position);
        EidModelPair {
            dst_eid,
            model_type,
        }
    }

    /// Deserialize a list of EidModelPair
    /// This accepts a series of EidModelPairs serialized one after the other
    public fun deserialize_eid_model_pair_list(buf: &vector<u8>): vector<EidModelPair> {
        let result = vector<EidModelPair>[];
        let position = 0;
        while (position < vector::length(buf)) {
            vector::push_back(&mut result, extract_eid_model_pair(buf, &mut position));
        };
        result
    }
}
