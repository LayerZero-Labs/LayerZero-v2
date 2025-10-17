/// DVN Assign Job Module
///
/// This module defines parameters for assigning verification jobs to DVNs.
/// It extends the fee calculation parameters to include job assignment functionality
/// for cross-chain message verification.
module uln_common::dvn_assign_job;

use uln_common::dvn_get_fee::GetFeeParam;

// === Structs ===

/// Parameters for DVN job assignment requests.
///
/// It wraps the GetFeeParam to reuse the same parameter structure for both quoting and sending operations,
/// ensuring consistency and type safety between the quote and send flows.
public struct AssignJobParam has copy, drop, store {
    base: GetFeeParam,
}

// === Creation ===

/// Creates a new AssignJobParam from existing fee parameters.
public fun create_param(base: GetFeeParam): AssignJobParam {
    AssignJobParam { base }
}

// === Getters ===

/// Returns a reference to the base fee calculation parameters.
public fun base(self: &AssignJobParam): &GetFeeParam {
    &self.base
}
