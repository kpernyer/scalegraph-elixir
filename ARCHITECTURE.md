# Architecture

## Three-Layer Architecture

Scalegraph follows a clean three-layer architecture with strict separation of concerns:

```
┌─────────────────────────────────────────────────────────┐
│              Layer 3: Smart Contracts                   │
│  - Automation & Cron Scheduling                         │
│  - Agent-driven Management                               │
│  - Conditional Execution                                 │
│  - Time-based triggers                                  │
│  Database: scalegraph_smart_contracts_*                 │
└─────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│              Layer 2: Business Rules                     │
│  - Loans (explicit financial terminology)               │
│  - Invoices (explicit financial terminology)           │
│  - Revenue Share (explicit financial terminology)       │
│  - Subscriptions (explicit financial terminology)       │
│  Database: scalegraph_business_*                         │
└─────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│              Layer 1: Pure Core Ledger                  │
│  - Accounts                                              │
│  - Transactions (generic transfers only)                 │
│  - No business semantics                                 │
│  - Immutable audit trail                                 │
│  Database: scalegraph_ledger_*                          │
└─────────────────────────────────────────────────────────┘
```

## Layer 1: Pure Core Ledger

**Location**: `lib/scalegraph/ledger/`

**Purpose**: Pure double-entry bookkeeping with no business semantics.

### Modules
- `Ledger.Core` - Core ledger operations (create_account, transfer, etc.)
- `Ledger.Server` - gRPC server for ledger operations
- `Ledger.Storage` - Database schema for ledger tables

### Database Tables
- `scalegraph_ledger_accounts` - Account records
- `scalegraph_ledger_transactions` - Transaction audit log

### Key Principles
- **Generic Transfers**: All transactions are generic transfers - the ledger doesn't know if it's a payment, invoice, or loan
- **No Business Terminology**: No "invoice", "loan", etc. in the ledger layer
- **Immutable Audit Trail**: All transactions are recorded and cannot be modified
- **Atomic Multi-Party Transfers**: Supports arbitrary numbers of parties in a single atomic transaction
- **Balance Validation**: Each account is checked for sufficient funds before any updates

### Example: Generic Transfer

```elixir
alias Scalegraph.Ledger.Core, as: Ledger

# Simple two-party transfer
Ledger.transfer([
  {"sender:operating", -1000},
  {"receiver:operating", 1000}
], "payment")

# Multi-party transfer with fees (entries can be unbalanced)
Ledger.transfer([
  {"payer:operating", -1000},
  {"payee:operating", 950},
  {"platform:fees", 50}
], "payment_with_fee")

# Three-party embedded financing
Ledger.transfer([
  {"seb:operating", -150023},           # SEB provides financing
  {"salon_glamour:operating", -49977},  # Salon contributes
  {"beauty_hosting:fees", 200000}       # Beauty Hosting receives
], "embedded_financing_settlement")
```

### Insulation
The ledger layer has **no knowledge** of:
- Business rules or contracts
- Smart contracts
- What transactions represent (invoice, loan, etc.)

## Layer 2: Business Rules Layer

**Location**: `lib/scalegraph/business/`

**Purpose**: Business rules with explicit financial terminology.

### Modules
- `Business.Loans` - Loan management with explicit terminology
- `Business.Invoices` - Invoice management with explicit terminology
- `Business.RevenueShare` - Revenue share contracts
- `Business.Subscriptions` - Subscription contracts
- `Business.Contracts` - Contract management (shared functionality)
- `Business.Transactions` - High-level business transactions
- `Business.Server` - gRPC server for business operations
- `Business.Storage` - Database schema for business tables

### Database Tables
- `scalegraph_business_invoices` - Invoice contracts
- `scalegraph_business_loans` - Loan contracts
- `scalegraph_business_revenue_share` - Revenue share contracts
- `scalegraph_business_subscriptions` - Subscription contracts

### Key Principles
- **Explicit Financial Terminology**: Uses terms like "loan", "invoice", "revenue share"
- **References Ledger**: Business contracts reference ledger transactions but don't modify ledger directly
- **Business Semantics**: Stores business metadata separately from ledger
- **Separate Database Context**: Operates in its own database context for insulation

### Example: Creating a Loan

```elixir
alias Scalegraph.Business.Loans

# Create a loan - automatically creates ledger transaction
{:ok, loan} = Loans.create_loan(
  "seb",              # lender_id
  "salon_glamour",    # borrower_id
  150023,             # principal_amount (cents)
  "LOAN-2024-001",    # reference
  []                  # options
)

# The loan contract:
# - Records business semantics (lender, borrower, amount)
# - Creates ledger transaction via Ledger.Core.transfer
# - Tracks loan status separately from ledger
```

### Example: Creating an Invoice

```elixir
alias Scalegraph.Business.Invoices

# Create an invoice - automatically creates ledger transaction
{:ok, invoice} = Invoices.create_invoice(
  "schampo_etc",      # supplier_id
  "salon_glamour",    # buyer_id
  455000,             # amount (cents)
  "INV-2024-001",     # reference
  []                  # options
)

# The invoice contract:
# - Records business semantics (supplier, buyer, amount)
# - Creates ledger transaction via Ledger.Core.transfer
# - Tracks invoice status separately from ledger
```

### Insulation
The business layer:
- **Can**: Create business contracts and call ledger operations
- **Cannot**: Know about smart contracts
- **Cannot**: Directly modify ledger tables

## Layer 3: Smart Contracts Layer

**Location**: `lib/scalegraph/smart_contracts/`

**Purpose**: Automation, cron scheduling, and agent-driven contract management.

### Modules
- `SmartContracts.Core` - Contract creation, execution, and management
- `SmartContracts.Scheduler` - Cron-based automation (GenServer)
- `SmartContracts.Storage` - Database schema for smart contracts
- `SmartContracts.Examples` - Reusable contract examples

### Database Tables
- `scalegraph_smart_contracts` - Smart contract definitions
- `scalegraph_smart_contract_executions` - Execution history
- `scalegraph_smart_contract_schedules` - Cron schedules

### Features
- **Automation**: Conditional execution based on triggers (time, balance, events)
- **Cron Scheduling**: Periodic contract execution (e.g., daily subscription billing)
- **Agent-driven Management**: Active monitoring and execution of contracts
- **Execution History**: Complete audit trail of all contract executions

### Key Principles
- **Can Execute Business Operations**: Can call business layer operations (loans, invoices, etc.)
- **Can Execute Ledger Operations**: Can call ledger operations (transfers)
- **Separate Database Context**: Operates in its own database context for insulation
- **Runs as GenServer**: Continuous automation via scheduler

### Example: Marketplace Membership Contract

A smart contract that automatically charges all ecosystem participants a monthly membership fee:

```elixir
alias Scalegraph.SmartContracts.Examples

# Create marketplace membership contract
{:ok, contract} = Examples.create_marketplace_membership("beauty_hosting",
  monthly_fee_cents: 6000,        # 60 EUR per month
  grace_period_months: 3,         # 3 months grace period
  payment_months: 9,               # 9 monthly payments
  renewal_notice_days: 30         # 30 days notice for renewal
)

# Contract automatically:
# - Charges all participants monthly (after grace period)
# - Executes via scheduler (checks daily for due payments)
# - Records execution history
# - Handles renewal deadlines
```

### Example: Supplier Registration Contract

A smart contract that handles registration fees and monthly subscription fees:

```elixir
alias Scalegraph.SmartContracts.Core

# Create supplier registration contract
{:ok, contract} = Core.create_supplier_registration_contract("supplier_123")

# When first ecosystem provider uses the service
{:ok, :started} = Core.trigger_supplier_monthly_fee("supplier_123", "ecosystem_provider_456")

# Contract automatically:
# - Charges one-time registration fee (50 EUR)
# - Starts monthly fees when first provider uses service
# - Splits monthly fee (90% to orchestrator, 10% to first provider)
```

### Example: Ecosystem Partner Membership Contract

A smart contract that automatically manages payments between the ecosystem orchestrator and ecosystem partners:

```elixir
alias Scalegraph.SmartContracts.Examples

# Partner accepts rules and is added to the contract
{:ok, contract} = Examples.accept_ecosystem_rules("new_salon", "beauty_hosting")

# Contract automatically:
# - Charges all partners monthly (50 EUR/month)
# - Executes on the 1st of each month
# - Adds new partners when they accept rules
```

### Insulation
The smart contracts layer:
- **Can**: Create and execute smart contracts
- **Can**: Call business layer operations
- **Can**: Call ledger operations
- **Can**: Schedule cron jobs
- **Cannot**: Directly modify business or ledger tables

## Data Flow Example: Subscription Billing

Here's how the three layers work together:

```
1. Smart Contract (cron scheduled) triggers at billing date
   └─> SmartContracts.Scheduler checks for due contracts
   
2. Smart Contract executes
   └─> SmartContracts.Core.execute_contract/1
   
3. Smart Contract calls Business Layer
   └─> Business.Subscriptions.get_subscription/1
   └─> Business.Transactions.access_payment/4
   
4. Business Layer calls Ledger Layer
   └─> Ledger.Core.transfer/2
   
5. Ledger Layer executes atomic transfer
   └─> Updates account balances
   └─> Records transaction
   
6. Business Layer updates subscription contract
   └─> Updates business metadata
   
7. Smart Contract records execution history
   └─> Records in scalegraph_smart_contract_executions
```

Each layer maintains its own database context while working together.

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

## OTP Application Structure

```
Scalegraph.Application
└── Supervisor (one_for_one)
    ├── SmartContracts.Scheduler (GenServer)
    └── GRPC.Server.Supervisor
        └── gRPC Server (port 50051)
```

The application:
1. Initializes Mnesia schema before supervision tree starts
2. Initializes all three database layers (ledger, business, smart contracts)
3. Starts Smart Contracts Scheduler for automation
4. Starts gRPC server under supervision

## Database Schema

### Ledger Tables

| Table | Key | Indices | Storage |
|-------|-----|---------|---------|
| `scalegraph_ledger_accounts` | id | participant_id | disc_copies |
| `scalegraph_ledger_transactions` | id | - | disc_copies |

### Business Tables

| Table | Key | Indices | Storage |
|-------|-----|---------|---------|
| `scalegraph_business_invoices` | id | - | disc_copies |
| `scalegraph_business_loans` | id | - | disc_copies |
| `scalegraph_business_revenue_share` | id | - | disc_copies |
| `scalegraph_business_subscriptions` | id | - | disc_copies |

### Smart Contracts Tables

| Table | Key | Indices | Storage |
|-------|-----|---------|---------|
| `scalegraph_smart_contracts` | id | - | disc_copies |
| `scalegraph_smart_contract_executions` | id | contract_id | disc_copies |
| `scalegraph_smart_contract_schedules` | contract_id | - | disc_copies |

### Participant Tables (Legacy)

| Table | Key | Indices | Storage |
|-------|-----|---------|---------|
| `scalegraph_participants` | id | - | disc_copies |
| `scalegraph_accounts` | id | participant_id | disc_copies |
| `scalegraph_transactions` | id | - | disc_copies |

## Error Handling

### Core Layer

Returns tagged tuples:
- `{:ok, result}` on success
- `{:error, reason}` on failure

Common error reasons:
- `:not_found` - Resource doesn't exist
- `:account_exists` - Account already exists
- `{:insufficient_funds, account_id, balance, required}` - Balance too low
- `{:invalid_role, role, valid_roles}` - Invalid participant role

### Service Layer

Maps errors to gRPC status codes:

| Error | gRPC Status |
|-------|-------------|
| `:not_found` | `NOT_FOUND` |
| `:account_exists` | `ALREADY_EXISTS` |
| `{:insufficient_funds, _, _, _}` | `FAILED_PRECONDITION` |
| Other | `INTERNAL` |

## Concurrency Model

### Mnesia Transactions

Mnesia uses pessimistic locking:
- Read locks for reads
- Write locks for writes
- Automatic deadlock detection and resolution

### gRPC Server

The gRPC server handles requests concurrently. Each request runs in its own process, with Mnesia managing isolation.

### Smart Contracts Scheduler

The scheduler runs as a GenServer that:
- Checks for due contracts every minute
- Executes contracts in separate tasks (non-blocking)
- Records execution history

## Benefits of Three-Layer Architecture

1. **Clean Separation**: Each layer has a single responsibility
2. **Insulation**: Changes in one layer don't affect others
3. **Testability**: Each layer can be tested independently
4. **Scalability**: Layers can be scaled independently
5. **Maintainability**: Clear boundaries make code easier to understand
6. **Extensibility**: New business rules or smart contract types can be added without affecting other layers
7. **Replayability**: All transactions are self-describing and can reconstruct entire state

## Future Enhancements

- **Separate Execution Container**: Smart contracts could run in a separate Elixir node/container for even better isolation
- **Event Sourcing**: Smart contracts could subscribe to ledger events for reactive execution
- **Advanced Cron**: Full cron expression parsing (currently simplified)
- **Condition Evaluation**: More sophisticated condition evaluation engine
- **Multi-node Mnesia cluster**: Replicate data across nodes
- **Read replicas**: Add ram_copies nodes for read scaling

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
5. Rate limiting for smart contract execution

## Monitoring Points

Key metrics to track:
- Transaction throughput (ledger layer)
- Transaction latency (ledger layer)
- Business contract creation rate (business layer)
- Smart contract execution rate (smart contracts layer)
- Mnesia table sizes (all layers)
- gRPC error rates by status code
- Smart contract execution failures

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
