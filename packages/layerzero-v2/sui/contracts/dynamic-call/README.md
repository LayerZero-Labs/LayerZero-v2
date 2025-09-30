# Call Module: Dynamic Cross-Contract Coordination

## Overview

The Call Module is a foundational component of LayerZero V2 that implements a secure hot-potato pattern for dynamic cross-contract coordination in the Sui Move VM. It enables runtime contract selection and invocation without requiring compile-time dependencies, addressing the fundamental limitation of static dispatch in Move.

## Table of Contents

- [Overview](#overview)
- [Problem Statement](#problem-statement)
- [Architecture](#architecture)
- [Core Components](#core-components)
- [Data Structure Specification](#data-structure-specification)
- [Development Guidelines](#development-guidelines)

## Problem Statement

### The Dynamic Dispatch Challenge

The Sui Move VM enforces static resolution of all function calls at compile time, which creates fundamental limitations for modular blockchain architectures:

#### Technical Constraints

- **Static Binding**: All function calls must reference specific modules known at compilation
- **No Runtime Polymorphism**: Cannot select implementation based on runtime conditions
- **Compilation Dependencies**: Caller must import and depend on all possible callees
- **Limited Extensibility**: Adding new components requires upgrading dependent contracts

#### LayerZero Requirements

LayerZero V2's modular architecture demands capabilities that conflict with these constraints:

1. **Runtime Library Selection**: Message libraries must be selected based on runtime configuration
2. **Extensible Architecture**: New libraries must integrate without modifying existing contracts
3. **Cross-Module Communication**: Components must communicate without compile-time knowledge

### Traditional Dynamic Dispatch (Not Feasible in Move)

```pseudocode
// Interface-based polymorphism - unsupported in Move
interface MessageLib {
    function send(packet: Packet) -> Receipt;
    function quote(packet: Packet) -> Fee;
}

// Runtime selection and dynamic dispatch
let lib: MessageLib = resolveLibrary(config);
let receipt = lib.send(packet);  // Dynamic method resolution
```

## Architecture

### Design Objectives

The Call Module addresses three primary architectural requirements:

1. **Dynamic Dispatch Emulation**: Simulate runtime contract selection and method invocation
2. **Hierarchical Coordination**: Enable structured, multi-level workflows across contract boundaries
3. **Type-Safe Generics**: Provide compile-time safety through parameterized types

### Design Principles

#### 1. Minimal Surface Area

- Exposes only essential primitives for cross-contract communication
- Maintains simplicity while preserving full functionality
- Minimizes attack surface and reduces complexity-induced errors

#### 2. Self-Contained Safety

- Enforces all safety guarantees internally without external dependencies
- Provides automatic lifecycle management and state transitions
- Implements built-in protection against reentrancy and improper usage
- Enables safe composition of complex workflows

#### 3. Sui Ecosystem Compliance

- **Type Safety**: Leverages Move's type system through generic parameters `<Param, Result>`
- **Capability-Based Security**: Implements access control via `CallCap` objects
- **Resource Management**: Utilizes hot-potato pattern for mandatory resource handling

### Call Module Solution

The Call Module implements a **structured communication protocol** that achieves equivalent functionality through a type-safe hot-potato pattern:

```move
// Runtime target determination with compile-time safety
let call = call::create<SendParams, Receipt>(
    &caller_cap,
    resolve_library_address(config),  // Runtime resolution
    false,                            // Bidirectional communication
    send_params,
    ctx
);

// Type-safe parameter passing and result collection
// ... call flows to selected library ...
call.complete(&library_cap, receipt);

// Guaranteed result extraction
let (callee_addr, params, receipt) = call.destroy(&caller_cap);
```

## Core Components

### Hot-Potato Pattern Implementation

The `Call<Param, Result>` object implements the hot-potato pattern, ensuring mandatory resource handling through the type system:

#### Lifecycle Guarantees

1. **Creation**: Caller instantiates call with typed parameters
2. **Processing**: Callee receives and processes according to parameter type
3. **Delegation** (Optional): Callee creates child calls for complex workflows
4. **Completion**: Callee provides typed result
5. **Destruction**: Authorized party extracts result and consumes call

#### Resource Safety Properties

- **Non-Droppable**: Calls cannot be ignored or abandoned
- **Linear Typing**: Each call has exactly one owner at any time
- **Completion Enforcement**: All workflows must reach a terminal state
- **Automatic Cleanup**: Resources are guaranteed to be released

### Hierarchical Workflow Architecture

The module supports complex, multi-level coordination through structured parent-child relationships:

#### Batch Organization

```
Root Call (A→B)
├── Batch 1 (nonce=1)
│   ├── Child Call 1 (B→C)    [parallel execution]
│   └── Child Call 2 (B→D)    [parallel execution]
├── Batch 2 (nonce=2)         [sequential after Batch 1]
│   └── Child Call 3 (B→E)
│       ├── Batch 1 (nonce=1) [nested hierarchy]
│       │   ├── Grandchild Call 1 (E→F)
│       │   └── Grandchild Call 2 (E→G)
```

#### Coordination Rules

- **Sequential Batches**: Batch N+1 cannot begin until Batch N completes
- **Parallel Children**: All calls within a batch can execute concurrently
- **FIFO Destruction**: Child calls must be destroyed in creation order
- **Completion Propagation**: Parent cannot complete until all children are destroyed

### Lifecycle Management

#### State Transition Diagram

```
                        [Start]
                           │
                           │ create()
                           ↓
         ┌────────────── Active ─────────────────────────────┐
         │                 │                                 │
         │                 │ new_child_batch()               │ complete()
         │                 ↓                                 ↓
         │              Creating                         Completed
         │                 │                                 │
         │                 │ create_child()                  │ destroy()
         │                 │ (is_last=true)                  ↓
         │                 ↓                               [End]
         │              Waiting
         │                 │
         │                 │ (all children destroyed)
         │                 ↓
         └─────────────────┘
```

#### Official State Transitions (from call.move)

As documented in the source code, status transitions occur automatically based on call operations:

- **[Start] → Active**: when the call is created
- **Active → Creating**: when `new_child_batch()` is called
- **Creating → Waiting**: when `create_child()` is called with `is_last=true`
- **Waiting → Active**: when the last child call is destroyed
- **Active → Completed**: when `complete()` is called with result
- **Completed → [End]**: when `destroy()` is called

#### State Definitions

| State       | Description                                             | Valid Operations                  | Entry Condition                            |
| ----------- | ------------------------------------------------------- | --------------------------------- | ------------------------------------------ |
| `Active`    | Can create new child batches or be completed            | `new_child_batch()`, `complete()` | Call creation or all children destroyed    |
| `Creating`  | In the process of creating child calls in current batch | `create_child()`                  | After `new_child_batch()` called           |
| `Waiting`   | Batch finalized, waiting for children to be destroyed   | `destroy_child()`                 | After `create_child()` with `is_last=true` |
| `Completed` | Has result, ready for destruction                       | `destroy()`                       | After `complete()` called with result      |

#### Implementation Constraints

- **FIFO Child Destruction**: Children must be destroyed in creation order (first created, first destroyed)
- **Batch Completion**: All children in a batch must be destroyed before parent can return to Active
- **Sequential Batches**: New batches can only be created when call is in Active status
- **Authorization**: Each operation requires appropriate `CallCap` authorization

## Data Structure Specification

### `Call<Param, Result>` - Core Struct

The primary hot-potato resource that encapsulates cross-contract communication state:

```move
public struct Call<Param, Result> {
    id: address,                    // Globally unique call identifier
    caller: address,                // Originating contract address
    callee: address,                // Target contract address for processing
    one_way: bool,                  // Destruction authorization mode
    param: Param,                   // Type-safe input parameters
    mutable_param: bool,            // Whether callee can modify parameters (default: false)
    result: Option<Result>,         // Optional result (Some after completion)
    parent_id: address,             // Parent call ID (ROOT_CALL_PARENT_ID for roots)
    batch_nonce: u64,               // Monotonic batch sequence number
    child_batch: vector<address>,   // FIFO-ordered child call identifiers
    status: CallStatus,             // Automatically managed lifecycle state
}
```

#### Field Specifications

| Field           | Type              | Purpose                        | Constraints                                          |
| --------------- | ----------------- | ------------------------------ | ---------------------------------------------------- |
| `id`            | `address`         | Unique call identifier         | Generated from object ID                             |
| `caller`        | `address`         | Creator's contract address     | Immutable after creation                             |
| `callee`        | `address`         | Processing contract address    | Immutable after creation                             |
| `one_way`       | `bool`            | Destruction authorization mode | `true`: callee destroys, `false`: caller destroys    |
| `param`         | `Param`           | Input parameters               | Mutable if `mutable_param` is true                   |
| `mutable_param` | `bool`            | Parameter mutability flag      | Default: false, enabled via `enable_mutable_param()` |
| `result`        | `Option<Result>`  | Output result                  | `None` until `complete()` called                     |
| `parent_id`     | `address`         | Parent call reference          | `ROOT_CALL_PARENT_ID` for root calls                 |
| `batch_nonce`   | `u64`             | Batch sequence counter         | Incremented for each new batch                       |
| `child_batch`   | `vector<address>` | Child call identifiers         | FIFO order enforced                                  |
| `status`        | `CallStatus`      | Lifecycle state                | Automatically managed                                |

### `CallCap` - Authorization Capability

Dual-purpose capability object that provides flexible authorization based on capability type:

```move
public struct CallCap has key, store {
    id: UID,                        // Sui object identifier
    cap_type: CapType,              // Determines identity resolution mechanism
}

public enum CapType has copy, drop, store {
    Individual,                     // Uses UID address as identifier
    Package(address),               // Uses package address as identifier
}
```

#### Capability Type Behaviors

| Field        | Individual Capability          | Package Capability                  |
| ------------ | ------------------------------ | ----------------------------------- |
| `identifier` | `CallCap.id.to_address()`      | `package_address` from CapType      |
| **Purpose**  | Individual-specific operations | Protocol-level operations           |
| **Scope**    | Single capability instance     | All instances from same package     |
| **Creation** | `new_individual_cap()`         | `new_package_cap<T>()` with witness |

#### Security Properties

- **Type-Based Identity**: Identity resolution depends on capability type
- **Package Verification**: Package capabilities require one-time witness proof
- **Flexible Authorization**: Supports both individual and package-level operations
- **Operation Authorization**: Required for all state-modifying call operations

#### Design Benefits

- **Eliminates Mapping Overhead**: Direct address resolution without separate lookups
- **Flexible Identity Models**: Supports both individual and package-based authorization
- **Type Safety**: Compile-time guarantees through witness pattern for package capabilities

### `CallStatus` - Lifecycle State Enumeration

Automatic state tracking for lifecycle management:

```move
enum CallStatus {
    Active,      // Ready for batch creation or completion
    Creating,    // Constructing child call batch
    Waiting,     // Awaiting child call destruction
    Completed    // Result available, ready for destruction
}
```

#### State Semantics

- **Active**: Permits `new_child_batch()` and `complete()` operations
- **Creating**: Permits `create_child()` operations only
- **Waiting**: Permits `destroy_child()` operations only
- **Completed**: Permits `destroy()` operation only

## Development Guidelines

### Type Safety Requirements

#### 1. Parameter Type Specificity

Always define distinct parameter types for different execution intents, even when fields are identical:

```move
// ✅ CORRECT: Intent-specific types prevent misrouting
public struct SendMessageParams has copy, drop, store {
    packet: Packet,
    options: vector<u8>
}

public struct QuoteMessageParams has copy, drop, store {
    packet: Packet,
    options: vector<u8>
}

// ❌ INCORRECT: Generic types enable processing errors
public struct MessageParams has copy, drop, store {
    packet: Packet,
    options: vector<u8>
}
```

**Rationale:** Type-specific parameters provide compile-time guarantees that calls are processed by the correct handler functions, preventing runtime errors and security vulnerabilities.

#### 2. Parameter Mutability and Access Control

The Call module supports optional parameter mutability with explicit opt-in by the caller:

```move
// ✅ CORRECT: Enable parameter mutability when needed
let mut call = call::create<ProcessingParams, Result>(
    &caller_cap,
    callee_address,
    false,
    params,
    ctx
);

// Explicitly enable parameter mutability (only caller can do this)
call.enable_mutable_param(&caller_cap);

// Now callee can modify parameters
public fun process_call(call: &mut Call<ProcessingParams, Result>, cap: &CallCap) {
    let params = call.param_mut(cap); // Requires mutable_param = true
    // ... modify parameters ...
}
```

**Parameter Mutability Rules:**

- **Default Immutable**: Parameters are immutable by default (`mutable_param = false`)
- **Caller Authorization**: Only the caller can enable mutability using `enable_mutable_param()`
- **Callee Access**: Callees can only get mutable access if mutability is enabled
- **Module-Level Access Control**: Function visibility of fields determines what callees can access

### Batch Management Protocol

#### 1. Sequential Batch Creation

```move
// ✅ CORRECT: Sequential nonce usage
call.new_child_batch(&cap, 1);  // First batch
// ... process batch 1 ...
call.new_child_batch(&cap, 2);  // Second batch

// ❌ INCORRECT: Non-sequential nonces
call.new_child_batch(&cap, 1);
call.new_child_batch(&cap, 3);  // Skips nonce 2
```

#### 2. Last Child Marking

```move
// ✅ CORRECT: Mark last child in batch
let child1 = call.create_child(&cap, addr1, params1, false, ctx);
let child2 = call.create_child(&cap, addr2, params2, true, ctx);  // is_last=true

// ❌ INCORRECT: No last child marking
let child1 = call.create_child(&cap, addr1, params1, false, ctx);
let child2 = call.create_child(&cap, addr2, params2, false, ctx);  // Batch never completes
```

#### 3. FIFO Destruction Order

```move
// ✅ CORRECT: Destroy in creation order
let (_, _, result1) = call.destroy_child(&cap, child1);  // First created
let (_, _, result2) = call.destroy_child(&cap, child2);  // Second created

// ❌ INCORRECT: Out-of-order destruction
let (_, _, result2) = call.destroy_child(&cap, child2);  // Will fail
let (_, _, result1) = call.destroy_child(&cap, child1);
```

### Security Considerations

#### 1. Capability Isolation

- Each contract must create and manage its own `CallCap`
- Never share capabilities between contracts
- Store capabilities securely within contract state

#### 2. Caller Validation

```move
// ✅ CORRECT: Validate caller identity before processing
public fun handle_call(call: Call<Params, Result>, cap: &CallCap) {
    // Assert that the call came from the expected caller
    call.assert_caller(@expected_caller_address);

    let result = process_call_logic(call.param());
    call.complete(cap, result);
}

// ❌ INCORRECT: No caller validation - security risk
public fun unsafe_handle_call(call: Call<Params, Result>, cap: &CallCap) {
    // Missing caller validation - any contract can call this if the param is public
    let result = process_call_logic(call.param());
    call.complete(cap, result);
}
```

#### 3. Reentrancy Protection

The Call module provides built-in reentrancy protection through:

- Status-based operation gating
- Nonce-based batch enforcement
- Hot-potato resource management
