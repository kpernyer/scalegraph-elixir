# Architecture Separation

This document describes the clean separation of concerns in the Scalegraph Elixir server, with three distinct layers:

1. **Pure Core Ledger** - Double-entry bookkeeping only
2. **Business Rules Layer** - Explicit financial terminology (loans, invoices, revenue share, subscriptions)
3. **Smart Contracts Layer** - Automation, cron scheduling, and agent-driven management

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│              Smart Contracts Layer                       │
│  - Automation & Cron Scheduling                         │
│  - Agent-driven Management                               │
│  - Conditional Execution                                 │
│  Database: scalegraph_smart_contracts_*                 │
└─────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│              Business Rules Layer                       │
│  - Loans (explicit financial terminology)               │
│  - Invoices (explicit financial terminology)           │
│  - Revenue Share (explicit financial terminology)       │
│  - Subscriptions (explicit financial terminology)       │
│  Database: scalegraph_business_*                         │
└─────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│              Pure Core Ledger                           │
│  - Accounts                                              │
│  - Transactions (generic transfers only)                 │
│  - No business semantics                                 │
│  Database: scalegraph_ledger_*                          │
└─────────────────────────────────────────────────────────┘
```

## Layer 1: Pure Core Ledger

**Location**: `lib/scalegraph/ledger/`

**Purpose**: Pure double-entry bookkeeping with no business semantics.

**Modules**:
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

**Insulation**: The ledger layer has no knowledge of business rules or smart contracts.

## Layer 2: Business Rules Layer

**Location**: `lib/scalegraph/business/`

**Purpose**: Business rules with explicit financial terminology.

**Modules**:
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

**Insulation**: The business layer references ledger transactions but operates in its own database context. It has no knowledge of smart contracts.

## Layer 3: Smart Contracts Layer

**Location**: `lib/scalegraph/smart_contracts/`

**Purpose**: Automation, cron scheduling, and agent-driven contract management.

**Modules**:
- `SmartContracts.Core` - Contract creation, execution, and management
- `SmartContracts.Scheduler` - Cron-based automation (GenServer)
- `SmartContracts.Storage` - Database schema for smart contracts

**Database Tables**:
- `scalegraph_smart_contracts` - Smart contract definitions
- `scalegraph_smart_contract_executions` - Execution history
- `scalegraph_smart_contract_schedules` - Cron schedules

**Features**:
- **Automation**: Conditional execution based on triggers (time, balance, events)
- **Cron Scheduling**: Periodic contract execution (e.g., daily subscription billing)
- **Agent-driven Management**: Active monitoring and execution of contracts
- **Execution History**: Complete audit trail of all contract executions

**Key Principles**:
- Can execute business layer operations (loans, invoices, etc.)
- Can execute ledger operations (transfers)
- Separate database context for insulation
- Runs as a GenServer for continuous automation

**Insulation**: The smart contracts layer can call business and ledger layers, but operates in its own database context. It provides automation on top of the business layer.

## Database Separation

All three layers use separate table namespaces:

- **Ledger**: `scalegraph_ledger_*`
- **Business**: `scalegraph_business_*`
- **Smart Contracts**: `scalegraph_smart_contracts_*`

While Mnesia uses a single schema, the table namespaces provide logical separation and insulation between layers.

## Initialization Order

The application initializes databases in this order:

1. **Ledger Database** - Pure ledger tables
2. **Business Database** - Business contract tables
3. **Smart Contracts Database** - Smart contract tables
4. **Participants** - Legacy participant tables (for backward compatibility)

Then starts:
- **Smart Contracts Scheduler** - GenServer for automation
- **gRPC Server** - API endpoints

## Module Boundaries

### Ledger Layer
- **Can**: Create accounts, execute transfers, query transactions
- **Cannot**: Know about business semantics (loans, invoices, etc.)
- **Cannot**: Know about smart contracts

### Business Layer
- **Can**: Create business contracts (loans, invoices, etc.)
- **Can**: Call ledger operations (via `Ledger.Core`)
- **Cannot**: Know about smart contracts
- **Cannot**: Directly modify ledger tables

### Smart Contracts Layer
- **Can**: Create and execute smart contracts
- **Can**: Call business layer operations
- **Can**: Call ledger operations
- **Can**: Schedule cron jobs
- **Cannot**: Directly modify business or ledger tables

## Example Flow

### Subscription Billing (Smart Contract)

1. **Smart Contract** (cron scheduled) triggers at billing date
2. **Smart Contract** calls `Business.Subscriptions.get_subscription/1`
3. **Smart Contract** calls `Business.Transactions.access_payment/4` (or similar)
4. **Business.Transactions** calls `Ledger.Core.transfer/2`
5. **Ledger.Core** executes atomic transfer
6. **Business.Transactions** updates subscription contract
7. **Smart Contract** records execution history

Each layer maintains its own database context while working together.

## Benefits of This Architecture

1. **Clean Separation**: Each layer has a single responsibility
2. **Insulation**: Changes in one layer don't affect others
3. **Testability**: Each layer can be tested independently
4. **Scalability**: Layers can be scaled independently
5. **Maintainability**: Clear boundaries make code easier to understand
6. **Extensibility**: New business rules or smart contract types can be added without affecting other layers

## Future Enhancements

- **Separate Execution Container**: Smart contracts could run in a separate Elixir node/container for even better isolation
- **Event Sourcing**: Smart contracts could subscribe to ledger events for reactive execution
- **Advanced Cron**: Full cron expression parsing (currently simplified)
- **Condition Evaluation**: More sophisticated condition evaluation engine

