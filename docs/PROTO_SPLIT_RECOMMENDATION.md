# Proto File Split Recommendation

## Recommendation: **YES, Split the Proto Files**

Splitting into three proto files aligns with your three-layer architecture and provides clear separation of concerns.

## Proposed Structure

```
proto/
├── common.proto          # Shared messages (Participant, Account, etc.)
├── ledger.proto          # Layer 1: Core ledger (accounts & transactions)
├── business-rules.proto  # Layer 2: Business rules (invoices, loans, etc.)
└── smart-contracts.proto # Layer 3: Smart contracts & automation
```

## Benefits of Splitting

### 1. **Clear Separation of Concerns**
- Each file represents one architectural layer
- Easier to understand what belongs where
- Clear boundaries between layers

### 2. **Independent Evolution**
- Each layer can evolve independently
- Version services separately if needed
- Easier to maintain and extend

### 3. **Better Documentation**
- Each file is focused and self-contained
- Easier to explain to new developers
- Clear API boundaries

### 4. **Microservices Ready**
- Each service can be split into separate services later
- Clear service boundaries already defined
- Easier to scale independently

### 5. **Reduced Cognitive Load**
- Smaller, focused files are easier to understand
- Developers only need to look at relevant files
- Less scrolling through large files

## Proposed File Contents

### `common.proto` - Shared Messages

**Purpose**: Messages used by multiple layers

**Contains**:
- `Participant` message and related enums (`ParticipantRole`, `Contact`)
- `Account` message and `AccountType` enum
- `Transaction` and `TransferEntry` (referenced by business layer)
- Common request/response patterns
- `ErrorResponse`

**Rationale**: 
- Participant and Account are foundational concepts used everywhere
- Transaction is referenced by business layer to link contracts to ledger entries
- Prevents duplication across files

### `ledger.proto` - Core Ledger Layer

**Purpose**: Pure double-entry bookkeeping

**Contains**:
- `LedgerService` service definition
- Account operations: `CreateAccount`, `GetAccount`, `GetBalance`
- Transaction operations: `Credit`, `Debit`, `Transfer`, `ListTransactions`
- Request/response messages for ledger operations only

**Rationale**:
- Focused on core accounting operations
- No business semantics
- Pure generic transfers

### `business-rules.proto` - Business Rules Layer

**Purpose**: Business contracts and rules

**Contains**:
- `BusinessService` service definition
- Invoice operations: `PurchaseInvoice`, `PayInvoice`, `GetInvoice`, `ListInvoices`
- Loan operations: `CreateLoan`, `RepayLoan`, `GetLoan`, `ListLoans`
- Access payment operations: `AccessPayment`
- Contract query operations
- Request/response messages for business operations
- Contract-specific messages (e.g., `Invoice`, `Loan`, `RevenueShareContract`)

**Rationale**:
- All business semantics live here
- Contracts reference ledger transactions (via transaction_id)
- Can query and aggregate business data

### `smart-contracts.proto` - Smart Contracts Layer

**Purpose**: Automation and conditional execution

**Contains**:
- `SmartContractService` service definition
- Contract creation: `CreateContract`, `UpdateContract`, `DeleteContract`
- Contract execution: `ExecuteContract`, `TriggerContract`
- Contract query: `GetContract`, `ListContracts`, `GetContractState`
- Contract-specific messages (e.g., `Contract`, `ContractCondition`, `ContractAction`)
- Automation messages (e.g., `ScheduleExecution`, `ConditionalPayment`)

**Rationale**:
- Future-focused: automation layer
- Executes business rules when conditions are met
- Can schedule recurring operations (subscriptions, revenue-share distributions)

## Import Strategy

### Option A: Import Common (Recommended)

```protobuf
// ledger.proto
syntax = "proto3";
package scalegraph.ledger;

import "common.proto";

service LedgerService {
  rpc CreateAccount(CreateAccountRequest) returns (scalegraph.common.Account);
  // ...
}
```

**Pros**:
- Clear dependency: ledger depends on common
- Business depends on common + ledger
- Smart contracts depend on all three

**Cons**:
- Need to manage import paths
- Build scripts need to handle imports

### Option B: Separate Packages

```protobuf
// common.proto
package scalegraph.common;

// ledger.proto
package scalegraph.ledger;
import "common.proto";

// business-rules.proto
package scalegraph.business;
import "common.proto";
import "ledger.proto";
```

**Pros**:
- Clear package boundaries
- Type-safe references

**Cons**:
- More complex import management
- Need to update all references

## Implementation Plan

### Phase 1: Extract Common Messages

1. Create `proto/common.proto` with:
   - `Participant`, `ParticipantRole`, `Contact`
   - `Account`, `AccountType`
   - `Transaction`, `TransferEntry`
   - `ErrorResponse`

2. Update `proto/ledger.proto` to:
   - Import `common.proto`
   - Keep only ledger-specific messages
   - Reference common types

3. Update build scripts to handle imports

### Phase 2: Split Business Rules

1. Create `proto/business-rules.proto` with:
   - Import `common.proto`
   - All business operation messages
   - `BusinessService` definition
   - Contract messages (Invoice, Loan, etc.)

2. Update `proto/ledger.proto` to remove business messages

3. Update Elixir code generation

### Phase 3: Add Smart Contracts (Future)

1. Create `proto/smart-contracts.proto` with:
   - Import `common.proto`, `ledger.proto`, `business-rules.proto`
   - Smart contract messages
   - `SmartContractService` definition

2. Implement smart contract layer

## Build Script Updates

### Rust Build Scripts

Update `cli/build.rs` and `mcp/build.rs`:

```rust
// Include all proto files
tonic_build::configure()
    .build_server(true)
    .compile(
        &[
            "../proto/common.proto",
            "../proto/ledger.proto",
            "../proto/business-rules.proto",
            "../proto/smart-contracts.proto", // Future
        ],
        &["../proto"],
    )?;
```

### Elixir Code Generation

Update proto generation command:

```bash
protoc --elixir_out=./lib/scalegraph/proto \
  --proto_path=./proto \
  proto/common.proto \
  proto/ledger.proto \
  proto/business-rules.proto \
  proto/smart-contracts.proto
```

## Service Registration

No changes needed to service registration - each service is still registered independently:

```elixir
defmodule Scalegraph.Endpoint do
  use GRPC.Endpoint
  
  run(Scalegraph.Ledger.Server)
  run(Scalegraph.Participant.Server)
  run(Scalegraph.Business.Server)
  # Future: run(Scalegraph.SmartContract.Server)
end
```

## Alternative: Keep Single File (Not Recommended)

If you choose to keep a single file, consider at least organizing with clear sections:

```protobuf
// ============================================================================
// COMMON MESSAGES
// ============================================================================

// ============================================================================
// LEDGER LAYER
// ============================================================================

// ============================================================================
// BUSINESS RULES LAYER
// ============================================================================

// ============================================================================
// SMART CONTRACTS LAYER
// ============================================================================
```

**Why not recommended**:
- File will grow very large (already 300+ lines)
- Harder to navigate
- Less clear boundaries
- Harder to version independently

## Recommendation Summary

**✅ Split into three files:**
1. `common.proto` - Shared foundational messages
2. `ledger.proto` - Core ledger operations
3. `business-rules.proto` - Business contracts and rules
4. `smart-contracts.proto` - Future automation layer

**Benefits:**
- Clear architectural boundaries
- Easier to maintain and extend
- Better separation of concerns
- Ready for microservices split

**Trade-offs:**
- Slightly more complex build setup (need to handle imports)
- Need to manage multiple files
- Initial refactoring effort

**Verdict**: The benefits far outweigh the costs, especially as the system grows.

