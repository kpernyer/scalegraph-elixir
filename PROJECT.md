# Project Architecture

## System Overview

Scalegraph is a distributed ledger designed for multi-party ecosystems. It enables atomic financial transactions between participants in a business network with a clean three-layer architecture.

```
┌─────────────────────────────────────────────────────────────┐
│                      Rust TUI CLI                           │
│                    (cli/src/main.rs)                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ gRPC (port 50051)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    gRPC Endpoint                            │
│               (Scalegraph.Endpoint)                         │
├─────────────────────────────────────────────────────────────┤
│   Ledger.Server    │  Business.Server  │  SmartContracts   │
│   - CreateAccount  │  - PurchaseInvoice │  - CreateContract │
│   - GetAccount     │  - PayInvoice      │  - ExecuteContract│
│   - GetBalance     │  - CreateLoan      │  - ListContracts  │
│   - Credit         │  - RepayLoan       │  - GetContract    │
│   - Debit          │  - AccessPayment  │                   │
│   - Transfer       │  - RevenueShare    │                   │
│   - ListTransactions│                   │                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Layer 3: Smart Contracts                       │
├─────────────────────────────────────────────────────────────┤
│    SmartContracts.Core                                      │
│    - Contract creation and execution                        │
│    - Condition evaluation                                   │
│    - Action execution                                       │
│    SmartContracts.Scheduler (GenServer)                     │
│    - Cron-based automation                                  │
│    - Periodic contract execution                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Layer 2: Business Rules                        │
├─────────────────────────────────────────────────────────────┤
│    Business.Loans              │  Business.Invoices         │
│    Business.RevenueShare       │  Business.Subscriptions    │
│    Business.Contracts          │  Business.Transactions     │
│    - Business contract CRUD    │  - High-level transactions  │
│    - Financial terminology     │  - Calls ledger layer       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Layer 1: Pure Core Ledger                      │
├─────────────────────────────────────────────────────────────┤
│    Ledger.Core                                               │
│    - Account operations                                      │
│    - Transaction execution                                   │
│    - Balance management                                      │
│    - Generic transfers only                                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Storage Layer (Mnesia)                    │
├─────────────────────────────────────────────────────────────┤
│  Layer 3: Smart Contracts                                   │
│  scalegraph_smart_contracts                                 │
│  scalegraph_smart_contract_executions                       │
│  scalegraph_smart_contract_schedules                        │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: Business Rules                                    │
│  scalegraph_business_invoices                               │
│  scalegraph_business_loans                                  │
│  scalegraph_business_revenue_share                          │
│  scalegraph_business_subscriptions                          │
├─────────────────────────────────────────────────────────────┤
│  Layer 1: Pure Core Ledger                                  │
│  scalegraph_ledger_accounts                                  │
│  scalegraph_ledger_transactions                             │
├─────────────────────────────────────────────────────────────┤
│  Participants (Legacy)                                      │
│  scalegraph_participants                                    │
│  scalegraph_accounts                                        │
│  scalegraph_transactions                                    │
└─────────────────────────────────────────────────────────────┘
```

## Three-Layer Architecture

### Layer 1: Pure Core Ledger

**Location**: `lib/scalegraph/ledger/`

**Purpose**: Pure double-entry bookkeeping with no business semantics.

**Components**:
- `Ledger.Core` - Core ledger operations (create_account, transfer, etc.)
- `Ledger.Server` - gRPC server for ledger operations
- `Ledger.Storage` - Database schema for ledger tables

**Database Tables**:
- `scalegraph_ledger_accounts` - Account records
- `scalegraph_ledger_transactions` - Transaction audit log

**Key Principles**:
- All transactions are generic transfers
- No business terminology (no "invoice", "loan", etc.)
- Immutable audit trail
- Atomic multi-party transfers

### Layer 2: Business Rules Layer

**Location**: `lib/scalegraph/business/`

**Purpose**: Business rules with explicit financial terminology.

**Components**:
- `Business.Loans` - Loan management with explicit terminology
- `Business.Invoices` - Invoice management with explicit terminology
- `Business.RevenueShare` - Revenue share contracts
- `Business.Subscriptions` - Subscription contracts
- `Business.Contracts` - Contract management (shared functionality)
- `Business.Transactions` - High-level business transactions
- `Business.Server` - gRPC server for business operations
- `Business.Storage` - Database schema for business tables

**Database Tables**:
- `scalegraph_business_invoices` - Invoice contracts
- `scalegraph_business_loans` - Loan contracts
- `scalegraph_business_revenue_share` - Revenue share contracts
- `scalegraph_business_subscriptions` - Subscription contracts

**Key Principles**:
- Explicit financial terminology (loans, invoices, revenue share, subscriptions)
- References ledger transactions but doesn't modify ledger directly
- Business semantics stored separately from ledger
- Separate database context for insulation

### Layer 3: Smart Contracts Layer

**Location**: `lib/scalegraph/smart_contracts/`

**Purpose**: Automation, cron scheduling, and agent-driven contract management.

**Components**:
- `SmartContracts.Core` - Contract creation, execution, and management
- `SmartContracts.Scheduler` - Cron-based automation (GenServer)
- `SmartContracts.Storage` - Database schema for smart contracts
- `SmartContracts.Examples` - Reusable contract examples

**Database Tables**:
- `scalegraph_smart_contracts` - Smart contract definitions
- `scalegraph_smart_contract_executions` - Execution history
- `scalegraph_smart_contract_schedules` - Cron schedules

**Key Principles**:
- Can execute business layer operations (loans, invoices, etc.)
- Can execute ledger operations (transfers)
- Separate database context for insulation
- Runs as a GenServer for continuous automation

## Components

### Application Entry Point

**`Scalegraph.Application`** (`lib/scalegraph/application.ex`)
- OTP Application behaviour
- Initializes Mnesia schema on startup
- Initializes all three database layers (ledger, business, smart contracts)
- Starts Smart Contracts Scheduler (GenServer)
- Starts gRPC server supervisor

### gRPC Layer

**`Scalegraph.Endpoint`** (`lib/scalegraph/application.ex`)
- Configures gRPC services and interceptors
- Routes to Ledger, Business, and Smart Contracts servers

**`Scalegraph.Ledger.Server`** (`lib/scalegraph/ledger/server.ex`)
- Implements LedgerService gRPC endpoints
- Translates between protobuf and internal formats
- Handles gRPC error mapping

**`Scalegraph.Business.Server`** (`lib/scalegraph/business/server.ex`)
- Implements BusinessService gRPC endpoints
- Handles business transactions (invoices, loans, etc.)
- Calls ledger layer for actual transfers

**`Scalegraph.SmartContracts.Server`** (`lib/scalegraph/smart_contracts/server.ex`)
- Implements SmartContractService gRPC endpoints
- Manages smart contract lifecycle
- Executes contracts based on conditions

### Core Layers

**Layer 1: `Scalegraph.Ledger.Core`** (`lib/scalegraph/ledger/core.ex`)
- Account CRUD operations
- Single-entry transactions (credit/debit)
- Multi-party atomic transfers
- Balance management with overdraft protection

**Layer 2: `Scalegraph.Business.*`** (`lib/scalegraph/business/`)
- Business contract CRUD operations
- High-level business transactions
- Calls ledger layer for actual transfers
- Manages business semantics separately

**Layer 3: `Scalegraph.SmartContracts.Core`** (`lib/scalegraph/smart_contracts/core.ex`)
- Contract creation and management
- Condition evaluation
- Action execution
- Execution history tracking

### Storage Layer

**`Scalegraph.Storage.Schema`** (`lib/scalegraph/storage/schema.ex`)
- Mnesia schema initialization
- Table definitions with disc persistence
- Secondary indices
- Utility functions for testing

**`Scalegraph.Ledger.Storage`** (`lib/scalegraph/ledger/storage.ex`)
- Ledger table definitions
- Account and transaction storage

**`Scalegraph.Business.Storage`** (`lib/scalegraph/business/storage.ex`)
- Business table definitions
- Invoice, loan, revenue share, subscription storage

**`Scalegraph.SmartContracts.Storage`** (`lib/scalegraph/smart_contracts/storage.ex`)
- Smart contract table definitions
- Contract, execution, and schedule storage

### Protobuf

**Proto Files** (`proto/`)
- `common.proto` - Shared foundational messages
- `ledger.proto` - Layer 1: Core ledger operations
- `business-rules.proto` - Layer 2: Business contracts and rules
- `smart-contracts.proto` - Layer 3: Smart contracts and automation

**Generated Modules** (`lib/scalegraph/proto/`)
- `Common.*` - Common message types
- `Ledger.*` - Ledger service types
- `Business.*` - Business service types
- `SmartContracts.*` - Smart contract service types

### Utilities

**`Scalegraph.Seed`** (`lib/scalegraph/seed.ex`)
- Demo data seeding
- Creates example ecosystem participants
- Initializes accounts and balances

## Domain Model

### Participants

Participants represent organizations in the ecosystem. Each has a role:

| Role | Description | Example |
|------|-------------|---------|
| `access_provider` | Physical access control | ASSA ABLOY |
| `banking_partner` | Financial services | SEB |
| `ecosystem_partner` | Platform operators | Beauty Hosting |
| `supplier` | Product suppliers | Schampo etc |
| `equipment_provider` | Pay-per-use equipment | Hairgrowers United |

### Accounts

Accounts hold balances and are linked to participants:

| Type | Purpose |
|------|---------|
| `standalone` | Independent account |
| `operating` | Main business account |
| `receivables` | Incoming payments |
| `payables` | Outgoing payments |
| `escrow` | Held funds |
| `fees` | Fee collection |
| `usage` | Pay-per-use tracking |

### Business Contracts

Business contracts track business semantics separately from ledger:

| Type | Purpose |
|------|---------|
| `invoice` | Purchase invoices with due dates |
| `loan` | Loans with repayment schedules |
| `revenue_share` | Revenue sharing agreements |
| `subscription` | Subscription contracts |

### Smart Contracts

Smart contracts automate business processes:

| Type | Purpose |
|------|---------|
| `marketplace_membership` | Automatic monthly membership fees |
| `supplier_registration` | Registration and monthly fees |
| `ecosystem_partner_membership` | Partner membership automation |
| `conditional_payment` | Conditional payment execution |

## Data Flow

### Transfer Flow (Layer 1)

```
1. Client sends Transfer request via gRPC
2. Ledger.Server receives request, extracts entries
3. Ledger.Core.transfer/2 starts Mnesia transaction
4. For each entry:
   a. Read account
   b. Validate sufficient balance
   c. Update balance
5. Record transaction entry
6. Commit transaction
7. Return result to client
```

### Business Transaction Flow (Layer 2)

```
1. Client sends business transaction (e.g., CreateInvoice) via gRPC
2. Business.Server receives request
3. Business.Transactions.create_invoice/4:
   a. Creates business contract record
   b. Calls Ledger.Core.transfer/2 for actual transfer
   c. Links business contract to ledger transaction
4. Returns business contract with transaction ID
```

### Smart Contract Execution Flow (Layer 3)

```
1. SmartContracts.Scheduler checks for due contracts (every minute)
2. For each due contract:
   a. Evaluate conditions (time, balance, events)
   b. If conditions met:
      - Execute actions (transfer, business operation, etc.)
      - Record execution history
      - Update contract state
3. Scheduler continues monitoring
```

### Example: Subscription Billing (All Layers)

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

## CLI Architecture

The Rust CLI provides a TUI interface:

```
cli/
├── src/
│   ├── main.rs        # Entry point, Tokio runtime
│   ├── grpc/
│   │   └── mod.rs     # gRPC client, proto types
│   └── ui/
│       ├── mod.rs     # UI module exports
│       ├── app.rs     # Application state
│       └── views.rs   # TUI views/widgets
└── build.rs           # Protobuf compilation
```

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `grpc_port` | 50051 | gRPC server port |
| `mnesia_storage` | `:disc_copies` | Mnesia storage type |

## Dependencies

### Elixir
- `grpc` - gRPC server
- `protobuf` - Protocol buffer support

### Rust CLI
- `tonic` - gRPC client
- `ratatui` - TUI framework
- `tokio` - Async runtime
- `clap` - CLI argument parsing

## Module Boundaries

### Layer 1: Ledger
- **Can**: Create accounts, execute transfers, query transactions
- **Cannot**: Know about business semantics (loans, invoices, etc.)
- **Cannot**: Know about smart contracts

### Layer 2: Business
- **Can**: Create business contracts (loans, invoices, etc.)
- **Can**: Call ledger operations (via `Ledger.Core`)
- **Cannot**: Know about smart contracts
- **Cannot**: Directly modify ledger tables

### Layer 3: Smart Contracts
- **Can**: Create and execute smart contracts
- **Can**: Call business layer operations
- **Can**: Call ledger operations
- **Can**: Schedule cron jobs
- **Cannot**: Directly modify business or ledger tables

## Benefits of Three-Layer Architecture

1. **Clean Separation**: Each layer has a single responsibility
2. **Insulation**: Changes in one layer don't affect others
3. **Testability**: Each layer can be tested independently
4. **Scalability**: Layers can be scaled independently
5. **Maintainability**: Clear boundaries make code easier to understand
6. **Extensibility**: New business rules or smart contract types can be added without affecting other layers
7. **Replayability**: All transactions are self-describing and can reconstruct entire state
