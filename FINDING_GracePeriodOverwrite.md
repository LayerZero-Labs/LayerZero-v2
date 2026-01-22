# FINDING: Grace-Period Cross-Library Payload Hash Overwrite

**Severity**: MEDIUM
**Type**: State Manipulation / DoS
**Status**: Confirmed with PoC
**Test**: `Exploit_GracePeriodOverwrite.t.sol::test_FINDING_GracePeriodPayloadOverwrite()`

---

## Executive Summary

During receive library upgrades with grace periods, the old library can **reverify** the same nonce with a **different payload hash**, overwriting the new library's verification. This causes:

1. **Deterministic DoS**: Honest executors delivering the originally-verified payload will fail
2. **Message substitution**: Different payload can execute under the same nonce
3. **Invariant violation**: Breaks "once verified, immutable" property

**This is NOT "malicious admin compromised"** - it occurs in a **legitimate upgrade scenario** where both libraries are intentionally valid.

---

## Vulnerability Details

### Root Cause

**File**: `packages/layerzero-v2/evm/protocol/contracts/MessagingChannel.sol`
**Line**: 44

```solidity
function _inbound(
    address _receiver,
    uint32 _srcEid,
    bytes32 _sender,
    uint64 _nonce,
    bytes32 _payloadHash
) internal {
    if (_payloadHash == EMPTY_PAYLOAD_HASH) revert Errors.LZ_InvalidPayloadHash();
    inboundPayloadHash[_receiver][_srcEid][_sender][_nonce] = _payloadHash;  // ← UNCONDITIONAL OVERWRITE
}
```

**Problem**: No check prevents overwriting an existing hash. The only validation is that the NEW hash cannot be EMPTY.

### Enabling Condition

**File**: `packages/layerzero-v2/evm/protocol/contracts/EndpointV2.sol`
**Lines**: 348-352

```solidity
function _verifiable(
    Origin calldata _origin,
    address _receiver,
    uint64 _lazyInboundNonce
) internal view returns (bool) {
    return
        _origin.nonce > _lazyInboundNonce || // either initializing an empty slot or reverifying
        inboundPayloadHash[_receiver][_origin.srcEid][_origin.sender][_origin.nonce] != EMPTY_PAYLOAD_HASH; // ← ALLOWS REVERIFY
}
```

**Reverify is allowed when**:
- `nonce > lazyInboundNonce` (new slot OR verified but not executed), OR
- `hash != EMPTY` (already verified but not executed)

This means **any valid library can reverify any unexecuted message**.

---

## Attack Scenario

### Setup (Legitimate Upgrade)

1. **OApp currently uses LibOld**
2. **OApp upgrades to LibNew with 1000-block grace period**
   ```solidity
   setReceiveLibrary(oapp, REMOTE_EID, LibNew, gracePeriod=1000)
   ```
3. **Both libraries are now valid** (this is BY DESIGN for safe transitions)

### Attack Sequence

**Time: T+0 (within grace period)**

**Step 1**: LibNew verifies message with legitimate payload
```
LibNew calls: verify(origin nonce=1, payloadHash_A)
→ _verifiable() returns TRUE (nonce > lazyInboundNonce)
→ _inbound() sets: hash[1] = payloadHash_A
→ Event: PacketVerified(srcEid, sender, receiver, nonce=1, payloadHash_A)
```

**Step 2**: Honest executor observes verification
```
Executor sees: PacketVerified with payloadHash_A
Executor prepares: payload_A for delivery
```

**Step 3**: LibOld reverifies with different payload
```
LibOld calls: verify(origin nonce=1, payloadHash_B)  // Different hash!
→ _verifiable() returns TRUE (hash[1] != EMPTY)
→ _inbound() OVERWRITES: hash[1] = payloadHash_B  // ← VULNERABILITY
→ No event required (silent overwrite)
```

**Step 4**: Executor delivery FAILS
```
Executor calls: lzReceive(origin, payload_A)
→ _clearPayload() computes: actualHash = keccak256(payload_A) = payloadHash_A
→ _clearPayload() reads: expectedHash = hash[1] = payloadHash_B
→ actualHash != expectedHash
→ REVERT with LZ_PayloadHashNotFound(payloadHash_B, payloadHash_A)
```

**Result**:
- Message is stuck/DoS'd
- Executor must somehow discover and deliver payload_B (which they didn't see verified)
- OR wait for manual intervention (nilify/burn)

---

## Impact Analysis

### 1. Deterministic DoS

**Affected**: Honest executors following PacketVerified events

**Flow**:
```
LibNew emits: PacketVerified(hash_A)
     ↓
Executor prepares: payload_A
     ↓
LibOld overwrites: hash[1] = hash_B
     ↓
Executor delivery: FAILS (hash mismatch)
     ↓
Message stuck until manual recovery
```

**Severity**: MEDIUM
- Breaks normal execution flow
- Requires manual intervention (nilify or executor discovery of payload_B)
- No automatic recovery mechanism

### 2. Message Substitution

**Scenario**: Attacker controls LibOld or can call verify through it

**Flow**:
```
LibNew verifies: "Transfer 100 USDC to Alice" (hash_A)
     ↓
LibOld verifies: "Transfer 100 USDC to Attacker" (hash_B)
     ↓
Attacker delivers: payload_B
     ↓
OApp executes: "Transfer 100 USDC to Attacker"
```

**Severity**: HIGH (conditional)
- Requires attacker to control LibOld's verification logic
- OR exploit LibOld's verification rules
- Impact depends on OApp's message handling

### 3. Invariant Violation

**Expected Property** (implied by design):
> "Once a payloadHash for a given nonce is verified, it remains stable unless explicitly nilified/burned by the OApp owner"

**Actual Behavior**:
> "Any valid receive library can overwrite the payloadHash for unexecuted nonces"

This breaks:
- Offchain executor expectations
- Event-based monitoring systems
- Message delivery guarantees

---

## Why This is NOT "Malicious Admin"

**Common Misinterpretation**:
> "If the receive library is malicious, it can verify arbitrary payloads anyway - game over."

**Why This is Different**:

1. **Both libraries are intentionally trusted**
   - OApp owner chose BOTH LibOld and LibNew
   - Both are registered by endpoint owner
   - Grace period is INTENTIONAL for safe upgrades

2. **Overwrite creates NEW attack surface**
   - Without overwrite: each library verifies independently, no conflict
   - With overwrite: old library can **sabotage** new library's verification
   - This is incremental harm beyond "lib can verify new messages"

3. **Real-world scenario**:
   - LibOld has a **bug** or **weaker security rules** (not malicious)
   - OApp upgrades to LibNew (stricter verification)
   - LibOld (still valid during grace) can **undo** LibNew's verification
   - This is **not expected behavior** during an upgrade

4. **No warning/protection**:
   - No event when hash is overwritten
   - No way for OApp to prevent it during grace period
   - Executors have no visibility into overwrite

---

## Proof of Concept

**File**: `packages/layerzero-v2/evm/protocol/test/Exploit_GracePeriodOverwrite.t.sol`

**Run**:
```bash
cd packages/layerzero-v2/evm/protocol
forge test --match-test test_FINDING_GracePeriodPayloadOverwrite -vv
```

**Expected Output** (abbreviated):
```
PHASE 1: OApp Upgrade with Grace Period
✓ Initial library: LibOld
✓ Upgraded to: LibNew (grace period = 1000 blocks)
  LibNew valid: true
  LibOld valid: true  // ← Both valid by design

PHASE 2: LibNew Verifies Message
Message A: Transfer 100 USDC to Alice
Payload Hash A: 0x1234...
✓ LibNew verified message

PHASE 3: LibOld Reverifies with Different Payload
Message B: Transfer 100 USDC to Attacker
Payload Hash B: 0x5678...
✓ LibOld reverify succeeded

Stored hash AFTER LibOld reverify: 0x5678...  // ← OVERWRITTEN!

╔═══════════════════════════════════════╗
║  🚨 VULNERABILITY CONFIRMED 🚨        ║
║  Stored hash was OVERWRITTEN from A to B  ║
╚═══════════════════════════════════════╝

PHASE 4: Impact Demonstration
→ Executor attempting to deliver payload A...
✓ Delivery FAILED: PayloadHashNotFound(expected=0x5678, actual=0x1234)

╔═══════════════════════════════════════╗
║        IMPACT CONFIRMED               ║
║  ✗ Honest executor delivery FAILS     ║
║  ✗ Message is stuck/DoS'd             ║
╚═══════════════════════════════════════╝

PHASE 5: Message Substitution
→ Attacker delivering payload B...
✓ Payload B delivered successfully
OApp received: "Transfer 100 USDC to Attacker"  // ← WRONG MESSAGE!

╔═══════════════════════════════════════╗
║   MESSAGE SUBSTITUTION CONFIRMED      ║
║  Original: Transfer to Alice          ║
║  Executed: Transfer to Attacker       ║
╚═══════════════════════════════════════╝
```

---

## Recommended Fix

### Option 1: Prevent Reverify (Strictest)

```solidity
function _inbound(
    address _receiver,
    uint32 _srcEid,
    bytes32 _sender,
    uint64 _nonce,
    bytes32 _payloadHash
) internal {
    if (_payloadHash == EMPTY_PAYLOAD_HASH) revert Errors.LZ_InvalidPayloadHash();

    bytes32 existing = inboundPayloadHash[_receiver][_srcEid][_sender][_nonce];
    if (existing != EMPTY_PAYLOAD_HASH) revert Errors.LZ_AlreadyVerified();  // ← NEW CHECK

    inboundPayloadHash[_receiver][_srcEid][_sender][_nonce] = _payloadHash;
}
```

**Pros**:
- Completely prevents overwrite
- Enforces "once verified, immutable" invariant
- Clear error when reverify attempted

**Cons**:
- Breaks any intentional reverify use cases (if they exist)
- May affect DVN redundancy patterns

### Option 2: Idempotent Verify (Safer for Grace Periods)

```solidity
function _inbound(
    address _receiver,
    uint32 _srcEid,
    bytes32 _sender,
    uint64 _nonce,
    bytes32 _payloadHash
) internal {
    if (_payloadHash == EMPTY_PAYLOAD_HASH) revert Errors.LZ_InvalidPayloadHash();

    bytes32 existing = inboundPayloadHash[_receiver][_srcEid][_sender][_nonce];
    if (existing != EMPTY_PAYLOAD_HASH && existing != _payloadHash) {  // ← NEW CHECK
        revert Errors.LZ_PayloadHashMismatch(existing, _payloadHash);
    }

    inboundPayloadHash[_receiver][_srcEid][_sender][_nonce] = _payloadHash;
}
```

**Pros**:
- Allows reverify with **same hash** (idempotent, safe)
- Prevents reverify with **different hash** (attack vector)
- Compatible with DVN redundancy (multiple DVNs verifying same message)

**Cons**:
- Slightly more complex logic

### Option 3: Event + Warning (Minimal Change)

```solidity
function _inbound(
    address _receiver,
    uint32 _srcEid,
    bytes32 _sender,
    uint64 _nonce,
    bytes32 _payloadHash
) internal {
    if (_payloadHash == EMPTY_PAYLOAD_HASH) revert Errors.LZ_InvalidPayloadHash();

    bytes32 existing = inboundPayloadHash[_receiver][_srcEid][_sender][_nonce];
    if (existing != EMPTY_PAYLOAD_HASH && existing != _payloadHash) {
        emit PayloadHashOverwritten(_receiver, _srcEid, _sender, _nonce, existing, _payloadHash);  // ← NEW EVENT
    }

    inboundPayloadHash[_receiver][_srcEid][_sender][_nonce] = _payloadHash;
}
```

**Pros**:
- Maintains current behavior (backward compatible)
- Adds visibility for monitoring

**Cons**:
- Doesn't prevent the attack
- Relies on offchain detection

---

## Recommendation

**Implement Option 2 (Idempotent Verify)**:

**Rationale**:
1. Prevents the attack (different hash = revert)
2. Allows legitimate reverify with same hash (DVN redundancy, grace period harmony)
3. Clear error message for debugging
4. Minimal behavior change for honest usage

**Regression Test** (negative control):
```solidity
function test_Fix_ReverifyWithDifferentHashReverts() public {
    // Verify with hash_A
    endpoint.verify(origin, oapp, hash_A);

    // Attempt reverify with hash_B
    vm.expectRevert(Errors.LZ_PayloadHashMismatch.selector);
    endpoint.verify(origin, oapp, hash_B);  // ← Should REVERT after fix
}

function test_Fix_ReverifyWithSameHashSucceeds() public {
    // Verify with hash_A
    endpoint.verify(origin, oapp, hash_A);

    // Reverify with same hash_A
    endpoint.verify(origin, oapp, hash_A);  // ← Should SUCCEED (idempotent)

    // Hash should still be hash_A
    assertEq(endpoint.inboundPayloadHash(...), hash_A);
}
```

---

## Timeline Impact

**Discovery**: 2026-01-22
**PoC Confirmed**: 2026-01-22
**Disclosure**: Immediate (internal audit)

**Exploitability**: MEDIUM
- Requires grace period window
- Requires access to old library's verify function
- But: Grace periods are common during upgrades

**Real-World Risk**:
- HIGH for OApps with frequent library upgrades
- MEDIUM for OApps with time-sensitive messages (OFT, lending, etc.)
- LOW for OApps with manual message execution

---

## References

- **PoC**: `packages/layerzero-v2/evm/protocol/test/Exploit_GracePeriodOverwrite.t.sol`
- **Root Cause**: `MessagingChannel.sol:44` (unconditional overwrite)
- **Enabling Condition**: `EndpointV2.sol:350-351` (_verifiable allows reverify)
- **Related**: Grace period mechanism in `MessageLibManager.sol:108-135`

---

## FAQ

**Q: Is this exploitable by an external attacker?**

A: No. It requires:
- Access to a valid receive library's verify function
- Both libraries to be registered (requires endpoint owner action)
- Grace period to be active (requires OApp owner action)

**Q: Why is this worse than "malicious library can verify anything"?**

A: Because it allows **sabotage during upgrade**:
- OApp intentionally trusts BOTH libraries during grace period
- Old library can **undo** new library's verification
- This breaks the upgrade safety guarantee

**Q: Can this be exploited after grace period expires?**

A: No. After expiry, only the new library is valid. Old library cannot call verify.

**Q: What if LibOld is buggy (not malicious)?**

A: Still exploitable:
- LibOld may have weaker verification rules (e.g., accepts fewer DVN signatures)
- Attacker exploits LibOld's weakness to verify malicious payload
- This overwrites LibNew's strict verification
- Even though OApp intended to upgrade to stronger security

**Q: Does nilify/burn recover from this?**

A: Yes, but requires manual intervention:
- OApp must call `nilify(nonce, hash_B)` to set hash to NIL
- OR call `burn(nonce, hash_B)` if nonce ≤ lazyInboundNonce
- This is a workaround, not a prevention

---

**Document Version**: 2.0
**Last Updated**: 2026-01-22
**Status**: Ready for Review
