/// Set Worker PTB (Programmable Transaction Block) Parameter Module
///
/// This module provides a parameter structure and utility functions for worker configuration
/// in the LayerZero message library system. It encapsulates the necessary PTB move calls
/// for setting up workers, including fee calculation and job assignment operations.
///
/// Workers in the LayerZero protocol are entities (like DVNs or Executors) that perform
/// specific tasks in the message verification and execution process.
module msglib_ptb_builder_call_types::set_worker_ptb;

use ptb_move_call::move_call::MoveCall;

// === Structs ===

/// Parameter structure for setting worker configurations via PTB
public struct SetWorkerPtbParam has copy, drop, store {
    // Move calls for getting fee information from the worker
    get_fee_ptb: vector<MoveCall>,
    // Move calls for assigning jobs to the worker
    assign_job_ptb: vector<MoveCall>,
}

// === Creation ===

/// Creates a new SetWorkerPtbParam instance
public fun create_param(get_fee_ptb: vector<MoveCall>, assign_job_ptb: vector<MoveCall>): SetWorkerPtbParam {
    SetWorkerPtbParam { get_fee_ptb, assign_job_ptb }
}

// === Unpacking ===

/// Unpacks a SetWorkerPtbParam instance into its constituent parts
public fun unpack(self: SetWorkerPtbParam): (vector<MoveCall>, vector<MoveCall>) {
    let SetWorkerPtbParam { get_fee_ptb, assign_job_ptb } = self;
    (get_fee_ptb, assign_job_ptb)
}

// === Getters ===

/// Gets a reference to the fee calculation PTB move calls
public fun get_fee_ptb(self: &SetWorkerPtbParam): &vector<MoveCall> {
    &self.get_fee_ptb
}

/// Gets a reference to the job assignment PTB move calls
public fun assign_job_ptb(self: &SetWorkerPtbParam): &vector<MoveCall> {
    &self.assign_job_ptb
}
