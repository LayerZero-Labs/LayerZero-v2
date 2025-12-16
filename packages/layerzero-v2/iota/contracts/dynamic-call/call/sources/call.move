/// Cross-contract communication module using hot-potato pattern for LayerZero V2
///
/// This module provides a simple, secure framework for coordinating LayerZero V2 workflows
/// across multiple contracts using capability-based authorization.
module call::call;

use call::call_cap::CallCap;

// === Errors ===

const ECallNotActive: u64 = 1;
const ECallNotCompleted: u64 = 2;
const ECallNotCreating: u64 = 3;
const ECallNotRoot: u64 = 4;
const ECallNotWaiting: u64 = 5;
const EInvalidChild: u64 = 6;
const EInvalidNonce: u64 = 7;
const EInvalidParent: u64 = 8;
const EParameterNotMutable: u64 = 9;
const EUnauthorized: u64 = 10;

// === Constants ===

const ROOT_CALL_PARENT_ID: address = @0x0;

// === Structs ===

/// Generic call hot-potato for cross-contract communication
///
/// Represents a request-response workflow that flows through multiple contracts.
/// The call carries input parameters from caller to callee, and returns results
/// from callee to recipient. Supports hierarchical workflows through batched
/// child calls.
public struct Call<Param, Result> {
    // Unique identifier for this call
    id: address,
    // Identifier of the caller that created this call
    caller: address,
    // Identifier of the callee that processes this call and sets the result
    callee: address,
    // Whether this call is one-way. If true, the callee can destroy the call
    // after processing. Otherwise, only the caller can destroy the call.
    one_way: bool,
    // Input parameters for the callee to process
    param: Param,
    // Whether the callee can modify the parameters
    mutable_param: bool,
    // Result set by the callee (None until status becomes Completed)
    result: Option<Result>,
    // ID of parent call (ROOT_CALL_PARENT_ID for root calls)
    parent_id: address,
    // Sequential counter tracking child batch creation cycles, incremented each time
    // a new batch of child calls is created to prevent replay attacks
    batch_nonce: u64,
    // IDs of child calls in the current batch that haven't been destroyed yet
    // Stored in order and destroyed in FIFO order.
    child_batch: vector<address>,
    // Current status of the call, transitions automatically based on operations
    status: CallStatus,
}

/// Call lifecycle status with automatic transitions
///
/// Status transitions occur automatically based on call operations:
/// - [Start] → Active: when the call is created
/// - Active → Creating: when new_child_batch() is called
/// - Creating → Waiting: when create_child() is called with is_last=true
/// - Waiting → Active: when the last child call is destroyed
/// - Active → Completed: when complete() is called with result
/// - Completed → [End]: when destroy() is called
public enum CallStatus has copy, drop, store {
    // Call is active and can create new child batches or be completed
    Active,
    // Call is in the process of creating child calls in the current batch
    Creating,
    // Call is waiting for all child calls in the current batch to be destroyed
    Waiting,
    // Call is completed with a result, ready for destruction
    Completed,
}

/// Empty result type for calls that don't return meaningful data
public struct Void has copy, drop, store {}

/// Create a void result for calls with no meaningful return value
public fun void(): Void { Void {} }

// === Caller Functions ===

/// Create a new root call
///
/// Initiates a new workflow by creating a call object with input parameters.
/// The callee will process these parameters and complete the call with a result.
///
/// The call starts in Active status, allowing the callee to create child
/// batches or complete it.
///
/// Status transition: [Start] → Active
public fun create<Param, Result>(
    caller: &CallCap,
    callee: address,
    one_way: bool,
    param: Param,
    ctx: &mut TxContext,
): Call<Param, Result> {
    Call {
        id: ctx.fresh_object_address(),
        caller: caller.id(),
        callee,
        one_way,
        param,
        mutable_param: false,
        result: option::none(),
        parent_id: ROOT_CALL_PARENT_ID,
        batch_nonce: 0,
        child_batch: vector::empty(),
        status: CallStatus::Active,
    }
}

/// Create a child call for sub-workflows
///
/// Allows the callee of a parent call to create child calls for delegating
/// work to other contracts. The parent call cannot be completed until all
/// child calls in the current batch are destroyed.
///
/// Only the callee of the parent call can create child calls.
/// Parent must be in Creating status.
///
/// If `is_last` is true, this child is the last child in the current batch.
/// The parent transitions to Waiting status after creating this child.
/// This prevents creating more children in the current batch and waits for
/// all children to be destroyed.
///
/// Parent status transition: Creating → Waiting (if `is_last` is true)
/// Child status transition: [Start] → Active
public fun create_child<ParentParam, ParentResult, ChildParam, ChildResult>(
    parent_call: &mut Call<ParentParam, ParentResult>,
    parent_callee: &CallCap,
    child_callee: address,
    param: ChildParam,
    is_last: bool,
    ctx: &mut TxContext,
): Call<ChildParam, ChildResult> {
    let parent_callee_address = parent_callee.id();
    assert!(parent_callee_address == parent_call.callee, EUnauthorized);
    assert!(parent_call.status.is_creating(), ECallNotCreating);

    // Update parent call state
    let child_call_id = ctx.fresh_object_address();
    parent_call.child_batch.push_back(child_call_id);
    if (is_last) {
        // Reverse the child batch to destroy in FIFO order
        parent_call.child_batch.reverse();
        parent_call.status = CallStatus::Waiting;
    };

    Call {
        id: child_call_id,
        caller: parent_callee_address,
        callee: child_callee,
        one_way: false,
        param,
        mutable_param: false,
        result: option::none(),
        parent_id: parent_call.id,
        batch_nonce: 0,
        child_batch: vector::empty(),
        status: CallStatus::Active,
    }
}

/// Enable the mutable_param flag
///
/// It should be enabled only if the callee is trusted to modify the parameters.
/// Only the caller can enable the mutable_param flag after the call is created.
public fun enable_mutable_param<Param, Result>(call: &mut Call<Param, Result>, caller: &CallCap) {
    assert!(caller.id() == call.caller, EUnauthorized);
    assert!(call.status.is_active(), ECallNotActive);
    call.mutable_param = true;
}

// === Callee Functions ===

/// Start a new child batch - begin creating child calls
///
/// Changes an active call to creating status for building a new batch
/// of child calls.
///
/// Only the callee can start a new batch. Call must be in Active status.
/// This means all existing child calls from previous batches must have
/// been destroyed. The expected_nonce must be exactly batch_nonce + 1 to
/// prevent replay attacks.
///
/// Status transition: Active → Creating
public fun new_child_batch<Param, Result>(call: &mut Call<Param, Result>, callee: &CallCap, expected_nonce: u64) {
    assert!(callee.id() == call.callee, EUnauthorized);
    assert!(call.status.is_active(), ECallNotActive);
    assert!(call.batch_nonce + 1 == expected_nonce, EInvalidNonce);
    call.batch_nonce = expected_nonce;
    call.status = CallStatus::Creating;
}

/// Complete the call with a result
///
/// Completes the call by setting its result. Only active calls can be
/// completed. The call must not have any active children (child_batch
/// must be empty).
///
/// Only the callee can complete the call.
///
/// Status transition: Active → Completed
public fun complete<Param, Result>(call: &mut Call<Param, Result>, callee: &CallCap, result: Result) {
    assert!(callee.id() == call.callee, EUnauthorized);
    assert!(call.status.is_active(), ECallNotActive);
    call.result.fill(result);
    call.status = CallStatus::Completed;
}

// === Recipient Functions ===

/// Destroy a completed root call and extract the result
///
/// Consumes a completed call object and returns its components.
/// This is the final step in the call lifecycle.
///
/// Only the designated recipient can destroy the call.
/// Call must be Completed and a root call (no parent).
///
/// Status transition: Completed → [End]
public fun destroy<Param, Result>(call: Call<Param, Result>, recipient: &CallCap): (address, Param, Result) {
    assert!(recipient.id() == call.recipient(), EUnauthorized);
    assert!(call.is_root(), ECallNotRoot);
    assert!(call.status.is_completed(), ECallNotCompleted);

    let Call { callee, param, result, .. } = call;
    (callee, param, result.destroy_some())
}

/// Destroy a completed child call and extract the result
///
/// Consumes a child call and removes it from the parent's child batch.
/// The child call must be completed before it can be destroyed and the
/// parent call must be waiting. The parent call returns to active status
/// after all children in the batch are destroyed. Children must be
/// destroyed in FIFO order (first created, first destroyed).
///
/// Parent status transition: Waiting → Active (if all children are destroyed)
/// Child status transition: Completed → [End]
public fun destroy_child<ParentParam, ParentResult, ChildParam, ChildResult>(
    parent_call: &mut Call<ParentParam, ParentResult>,
    parent_callee: &CallCap,
    child_call: Call<ChildParam, ChildResult>,
): (address, ChildParam, ChildResult) {
    // Check that the parent call is valid
    let parent_callee_address = parent_callee.id();
    assert!(parent_callee_address == parent_call.callee, EUnauthorized);
    assert!(parent_call.status.is_waiting(), ECallNotWaiting);

    // Check that the child call is authorized to be destroyed
    // The parent callee must be the recipient of the child call
    assert!(child_call.recipient() == parent_callee_address, EUnauthorized);
    assert!(child_call.parent_id == parent_call.id, EInvalidParent);
    assert!(child_call.status.is_completed(), ECallNotCompleted);

    // Update parent call state
    let expected_child_id = parent_call.child_batch.pop_back();
    assert!(expected_child_id == child_call.id, EInvalidChild);
    if (parent_call.child_batch.is_empty()) parent_call.status = CallStatus::Active;

    let Call { callee, param, result, .. } = child_call;
    (callee, param, result.destroy_some())
}

// === View Functions ===

/// Get the unique identifier of the call
public fun id<Param, Result>(call: &Call<Param, Result>): address { call.id }

/// Get the address of the caller (who created the call)
public fun caller<Param, Result>(call: &Call<Param, Result>): address { call.caller }

/// Validates that the provided caller address matches the call's caller.
public fun assert_caller<Param, Result>(call: &Call<Param, Result>, caller: address) {
    assert!(caller == call.caller, EUnauthorized);
}

/// Get the address of the callee (who processes the call)
public fun callee<Param, Result>(call: &Call<Param, Result>): address { call.callee }

/// Get whether this call is one-way
public fun one_way<Param, Result>(call: &Call<Param, Result>): bool { call.one_way }

/// Get the address of the recipient (who can destroy the call)
/// For one-way calls, the callee can destroy the call
/// Otherwise, the caller can destroy the call
public fun recipient<Param, Result>(call: &Call<Param, Result>): address {
    if (call.one_way) call.callee else call.caller
}

/// Get a reference to the input parameters
public fun param<Param, Result>(call: &Call<Param, Result>): &Param { &call.param }

/// Get a mutable reference to the input parameters
public fun param_mut<Param, Result>(call: &mut Call<Param, Result>, callee: &CallCap): &mut Param {
    assert!(callee.id() == call.callee, EUnauthorized);
    assert!(call.mutable_param, EParameterNotMutable);
    &mut call.param
}

/// Whether the callee can modify the parameters
public fun mutable_param<Param, Result>(call: &Call<Param, Result>): bool { call.mutable_param }

/// Get a reference to the result (None until status is Completed)
public fun result<Param, Result>(call: &Call<Param, Result>): &Option<Result> { &call.result }

/// Get the parent call ID (ROOT_CALL_PARENT_ID for root calls)
public fun parent_id<Param, Result>(call: &Call<Param, Result>): address { call.parent_id }

/// Check if this is a root call (has no parent)
public fun is_root<Param, Result>(call: &Call<Param, Result>): bool { call.parent_id == ROOT_CALL_PARENT_ID }

/// Get the current batch nonce (increments with each new batch)
public fun batch_nonce<Param, Result>(call: &Call<Param, Result>): u64 { call.batch_nonce }

/// Get a reference to the current child batch IDs (stored in reverse order, destroyed FIFO)
public fun child_batch<Param, Result>(call: &Call<Param, Result>): &vector<address> { &call.child_batch }

/// Get the current status of the call
public fun status<Param, Result>(call: &Call<Param, Result>): &CallStatus { &call.status }

// === Status Functions ===

/// Check if the call is in Active status
/// Active calls can create new child batches or be completed
public fun is_active(status: &CallStatus): bool { status == CallStatus::Active }

/// Check if the call is in Creating status
/// Creating calls can add more children to the current batch
public fun is_creating(status: &CallStatus): bool { status == CallStatus::Creating }

/// Check if the call is in Waiting status
/// Waiting calls cannot create more children and are waiting for all children to be destroyed
public fun is_waiting(status: &CallStatus): bool { status == CallStatus::Waiting }

/// Check if the call is in Completed status
/// Completed calls can be destroyed to extract the result
public fun is_completed(status: &CallStatus): bool { status == CallStatus::Completed }

// === Helper Functions ===

/// Create a single child call in one operation
///
/// This is a convenience function that combines new_child_batch() and create_child()
/// for the common case where you want to create exactly one child call.
///
/// Parent status transition: Active → Creating → Waiting
/// Child status transition: [Start] → Active
public fun create_single_child<ParentParam, ParentResult, ChildParam, ChildResult>(
    parent_call: &mut Call<ParentParam, ParentResult>,
    parent_callee: &CallCap,
    child_callee: address,
    param: ChildParam,
    ctx: &mut TxContext,
): Call<ChildParam, ChildResult> {
    // Only one batch is allowed for this parent call
    new_child_batch(parent_call, parent_callee, 1);
    // Create the single child call
    create_child(parent_call, parent_callee, child_callee, param, true, ctx)
}

/// Complete a one-way call and destroy it in a single operation
///
/// This is a convenience function that combines complete() and destroy()
/// for one-way calls that use Void as the result type. Since one-way calls
/// allow the callee to destroy the call, this function streamlines the
/// common pattern of completing with a void result and immediately destroying.
///
/// The call must be a one-way call (callee is the recipient) and in Active status.
/// Only the callee can perform this operation.
///
/// Status transition: Active → Completed → [End]
public fun complete_and_destroy<Param>(mut call: Call<Param, Void>, callee: &CallCap): Param {
    call.complete(callee, void());
    let (_, param, _) = call.destroy(callee);
    param
}
