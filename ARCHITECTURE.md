# Architecture

## High-Level Design

Scalegraph follows a layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────────────────┐
│                 Transport Layer                 │
│                   (gRPC)                        │
├─────────────────────────────────────────────────┤
│                 Service Layer                   │
│          (Ledger.Server, Participant.Server)    │
├─────────────────────────────────────────────────┤
│                  Core Layer                     │
│           (Ledger.Core, Participant.Core)       │
├─────────────────────────────────────────────────┤
│                 Storage Layer                   │
│                   (Mnesia)                      │
└─────────────────────────────────────────────────┘
```

## Layer Responsibilities

### Transport Layer

The gRPC endpoint handles:
- Protocol buffer serialization/deserialization
- Request routing to services
- Logging via interceptor

### Service Layer

Server modules handle:
- Request validation
- Error mapping to gRPC status codes
- Proto-to-internal type conversion

### Core Layer

Business logic modules handle:
- Domain operations
- Transaction management
- Invariant enforcement (e.g., no negative balances)

### Storage Layer

Mnesia handles:
- Data persistence to disk
- ACID transactions
- Secondary indexing

## Transaction Model

### Atomicity

All ledger operations use Mnesia transactions:

```elixir
:mnesia.transaction(fn ->
  # 1. Read all involved accounts
  # 2. Validate constraints
  # 3. Update balances
  # 4. Record transaction
end)
```

If any step fails, the entire transaction aborts.

### Multi-Party Transfers

Transfers support arbitrary numbers of parties in a single atomic transaction:

```elixir
Ledger.transfer([
  {"account_a", -100},  # debit
  {"account_b", 80},    # credit
  {"fee_account", 20}   # fee
], "reference")
```

**Key Properties:**
- **Atomic**: All entries succeed or all fail - no partial execution
- **Arbitrary parties**: Supports any number of accounts (2, 3, 10+)
- **Flexible amounts**: Sum doesn't need to be zero (allows fees, taxes, discounts)
- **Balance validation**: Each account is checked for sufficient funds before any updates
- **Audit trail**: Complete transaction record with all entries

**Example: Three-Party Settlement with Embedded Financing**
```elixir
# SEB provides financing, buyer contributes, seller receives full amount
Ledger.transfer([
  {"seb:operating", -150023},           # SEB provides $1,500.23 financing
  {"salon_glamour:operating", -49977},  # Salon contributes $499.77
  {"beauty_hosting:fees", 200000}       # Beauty Hosting receives $2,000.00
], "embedded_financing_settlement")
```

This pattern enables **embedded financing** where:
- The buyer never needs to have the full amount
- The financing provider participates directly in the atomic settlement
- The debt is cleanly recorded in the transaction audit trail
- All parties see the transaction as a single atomic operation

## OTP Application Structure

```
Scalegraph.Application
└── Supervisor (one_for_one)
    └── GRPC.Server.Supervisor
        └── gRPC Server (port 50051)
```

The application:
1. Initializes Mnesia schema before supervision tree starts
2. Starts gRPC server under supervision

## Database Schema

### Tables

| Table | Key | Indices | Storage |
|-------|-----|---------|---------|
| `scalegraph_participants` | id | - | disc_copies |
| `scalegraph_accounts` | id | participant_id | disc_copies |
| `scalegraph_transactions` | id | - | disc_copies |

### Record Formats

**Participants:**
```
{:scalegraph_participants, id, name, role, created_at, metadata, services}
```

Where `services` is a list of service identifiers (e.g., `["financing", "access_control"]`).

**Accounts:**
```
{:scalegraph_accounts, id, participant_id, account_type, balance, created_at, metadata}
```

**Transactions:**
```
{:scalegraph_transactions, id, type, entries, timestamp, reference}
```

## Error Handling

### Core Layer

Returns tagged tuples:
- `{:ok, result}` on success
- `{:error, reason}` on failure

Common error reasons:
- `:not_found` - Resource doesn't exist
- `:account_exists` - Account already exists
- `:participant_exists` - Participant already exists
- `{:insufficient_funds, message}` - Balance too low
- `{:invalid_role, role, valid_roles}` - Invalid participant role

### Service Layer

Maps errors to gRPC status codes:

| Error | gRPC Status |
|-------|-------------|
| `:not_found` | `NOT_FOUND` |
| `:account_exists` | `ALREADY_EXISTS` |
| `{:insufficient_funds, _}` | `FAILED_PRECONDITION` |
| Other | `INTERNAL` |

## Multi-Party Transaction Patterns

### Embedded Financing

A powerful pattern where a financing provider participates directly in a settlement:

**Scenario**: Buyer needs $2,000 but only has $499.77. Bank provides $1,500.23 financing.

```elixir
# All three parties in one atomic transaction
Ledger.transfer([
  {"seb:operating", -150023},           # Bank provides financing
  {"salon_glamour:operating", -49977},  # Buyer contributes available funds
  {"beauty_hosting:fees", 200000}       # Seller receives full amount
], "embedded_financing_settlement")
```

**Benefits:**
- Buyer never needs to "have" the full amount upfront
- Debt is recorded in transaction audit trail
- All parties see single atomic operation
- No separate loan creation step required

### Service-Based Discovery

Participants can declare services (e.g., "financing", "access_control") and be discovered:

```elixir
# Declare financing capability
Participant.add_service("seb", "financing")

# Discover financing providers
{:ok, participants} = Participant.list_participants()
financing_providers = Enum.filter(participants, fn p -> 
  "financing" in (p.services || [])
end)
```

### Loan Management Patterns

While Scalegraph doesn't have explicit "loan" entities, loans can be modeled using:

1. **Embedded Financing** (as above) - Loan provided during settlement
2. **Payables/Receivables** - Track debt via account types:
   - Buyer's `:payables` account (negative balance = debt)
   - Lender's `:receivables` account (positive balance = loaned amount)
3. **Transaction Audit Trail** - All loan transactions recorded in `scalegraph_transactions`

**Example: Loan Creation via Payables**
```elixir
# Create loan: SEB lends $1,500.23 to Salon Glamour
Ledger.transfer([
  {"seb:operating", -150023},              # SEB provides funds
  {"salon_glamour:operating", 150023},     # Salon receives funds
  {"salon_glamour:payables", -150023},     # Record debt (negative = owes)
  {"seb:receivables", 150023}              # Record receivable (positive = owed)
], "loan_creation")
```

**Example: Loan Repayment**
```elixir
# Repay loan: Salon pays back $1,500.23 to SEB
Ledger.transfer([
  {"salon_glamour:operating", -150023},    # Salon pays
  {"seb:operating", 150023},               # SEB receives
  {"salon_glamour:payables", 150023},      # Clear debt
  {"seb:receivables", -150023}             # Clear receivable
], "loan_repayment")
```

**Loan Tracking:**
- Outstanding loans = negative balance in `:payables` accounts
- Loaned amounts = positive balance in `:receivables` accounts
- Full history = query transactions by reference or account

## Transaction Data Flow

### Multi-Party Transfer Flow

```
1. Client sends Transfer request via gRPC with multiple entries
2. Ledger.Server receives request, extracts entries
3. Ledger.Core.transfer/2 starts Mnesia transaction
4. For each entry (all validated before any updates):
   a. Read account (acquires read lock)
   b. Validate account exists
   c. Calculate new_balance = balance + amount
   d. Validate new_balance >= 0 (no overdrafts)
5. If all validations pass:
   a. Update all account balances (acquires write locks)
   b. Record transaction with all entries
   c. Commit transaction (all or nothing)
6. Return result to client
```

**Critical Point**: All accounts are validated **before** any updates occur. If any account lacks funds, the entire transaction aborts with no partial updates.

### Embedded Financing Flow

```
1. Business logic calculates:
   - Total amount needed
   - Buyer's available contribution
   - Financing amount = total - contribution
2. Validate financing provider has "financing" service (optional)
3. Execute three-party atomic transfer:
   - Financing provider debited
   - Buyer debited (their contribution)
   - Seller credited (full amount)
4. Transaction recorded with reference
5. All parties see single atomic operation
```

**Benefits:**
- No separate loan creation step
- Debt recorded in transaction audit trail
- Buyer never needs full amount upfront
- All parties see single atomic operation

### Loan Management Flow

**Loan Creation:**
```
1. Create loan via multi-party transfer:
   - Lender's operating debited (money leaves lender)
   - Borrower's operating credited (money arrives)
   - Borrower's payables debited (records debt: negative = owes)
   - Lender's receivables credited (records loan: positive = owed)
2. All in single atomic transaction
3. Outstanding loan = negative payables balance
```

**Loan Repayment:**
```
1. Repay via multi-party transfer:
   - Borrower's operating debited (money leaves borrower)
   - Lender's operating credited (money arrives)
   - Borrower's payables credited (clears debt: moves toward zero)
   - Lender's receivables debited (clears loan: moves toward zero)
2. All in single atomic transaction
3. Query transactions to see full loan history
```

**Loan Querying:**
- Outstanding loans: Query accounts with negative `:payables` balances
- Loan history: Query transactions filtered by reference (e.g., "loan_creation", "loan_repayment")
- Total loaned: Sum of positive `:receivables` balances

## Concurrency Model

### Mnesia Transactions

Mnesia uses pessimistic locking:
- Read locks for reads
- Write locks for writes
- Automatic deadlock detection and resolution

### gRPC Server

The gRPC server handles requests concurrently. Each request runs in its own process, with Mnesia managing isolation.

## Scalability Considerations

### Current Design

Single-node deployment with:
- Mnesia disc_copies for durability
- All data in memory for fast access

### Future Scaling Options

1. **Multi-node Mnesia cluster**: Replicate data across nodes
2. **Read replicas**: Add ram_copies nodes for read scaling
3. **Sharding**: Partition accounts by participant

## Security Model

### Current State

- No authentication on gRPC
- No TLS configured
- Single-tenant deployment assumed

### Production Recommendations

1. Enable gRPC TLS
2. Add authentication interceptor
3. Implement authorization checks
4. Audit logging for all operations

## Monitoring Points

Key metrics to track:
- Transaction throughput
- Transaction latency
- Mnesia table sizes
- gRPC error rates by status code

## Deployment

### Development

```bash
iex -S mix
```

### Production

```bash
MIX_ENV=prod mix release
_build/prod/rel/scalegraph/bin/scalegraph start
```

Mnesia data stored in `Mnesia.nonode@nohost/` (or node-specific directory).
