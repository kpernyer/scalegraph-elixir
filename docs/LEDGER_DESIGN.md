# Ledger Design: Separation of Concerns

## Overview

This document describes the design for the separation between **Ledger Layer** (double-entry bookkeeping) and **Business/Contract Layer** (business logic and smart contracts).

## Architecture Principles

### Ledger Layer = Double-Entry Bookkeeping

The ledger is **immutable** and handles only:
- Debit/credit entries that sum to zero
- Account balances
- Transaction audit trail

**The ledger does NOT know about:**
- What a transaction represents (invoice, loan, etc.)
- Business rules or conditions
- Future events or deadlines

### Business/Contract Layer = Business Logic

This layer handles:
- Invoices (with due dates, status, etc.)
- Loans (with interest, repayment schedule, etc.)
- Revenue-share contracts
- Conditional payments
- Subscription contracts
- Smart contracts (future)

**This layer:**
- References ledger transactions
- Stores business metadata separately
- Can query and aggregate data
- Handles state machines and workflows

## Recommendation: Option A (Generic Transfer)

### Why Option A?

1. **Flexibility**: A generic transfer can represent EVERYTHING
   - Simple transfer: `[{A, -100}, {B, +100}]`
   - Invoice: `[{supplier:receivables, +100}, {buyer:payables, -100}]`
   - Loan: `[{lender:operating, -100}, {borrower:operating, +100}, {lender:receivables, +100}, {borrower:payables, -100}]`
   - Multi-party with fees: `[{A, -100}, {B, +80}, {platform:fees, +20}]`

2. **Replayability**: All transactions are self-describing
   - Can reconstruct entire state by replaying transactions
   - No special cases or business logic in the ledger

3. **Consistency**: Follows double-entry bookkeeping principles
   - All entries sum to zero (or allow fees)
   - Easy to validate and verify

4. **Future-proof**: New business constructs require no changes to the ledger
   - Revenue-share? Just new entries
   - Conditional payment? Just new entries
   - Subscription? Just new entries

### What should Transaction.type be?

**Recommendation**: Remove `type` from Transaction, or make it purely informational.

**Alternative 1: Remove type completely**
```protobuf
message Transaction {
  string id = 1;
  repeated TransferEntry entries = 2;  // Everything needed
  int64 timestamp = 3;
  string reference = 4;  // Human-readable, can contain "INVOICE: INV-001"
}
```

**Alternative 2: Keep type as metadata (optional)**
```protobuf
message Transaction {
  string id = 1;
  string type = 2;  // Optional, informational only: "transfer", "invoice", etc.
  repeated TransferEntry entries = 3;
  int64 timestamp = 4;
  string reference = 5;
}
```

**Recommendation**: Alternative 1 - remove `type`. Semantics exist in `reference` and in Business Layer.

## Database Structure

### Ledger Tables (Mnesia)

```
scalegraph_accounts
  - id
  - participant_id
  - account_type
  - balance
  - created_at
  - metadata

scalegraph_transactions
  - id
  - entries  [{account_id, amount}, ...]
  - timestamp
  - reference
```

### Business/Contract Tables (Mnesia, same database)

```
scalegraph_invoices
  - id
  - supplier_id
  - buyer_id
  - amount
  - due_date
  - status  (pending, paid, overdue, cancelled)
  - ledger_transaction_id  # Reference to ledger transaction
  - reference
  - created_at
  - paid_at
  - metadata

scalegraph_loans
  - id
  - lender_id
  - borrower_id
  - principal_amount
  - interest_rate
  - repayment_schedule
  - status  (active, repaid, defaulted)
  - disbursement_transaction_id  # Reference to ledger transaction
  - repayment_transaction_ids    # List of repayment transactions
  - created_at
  - metadata

scalegraph_revenue_share_contracts
  - id
  - parties  [{participant_id, percentage}, ...]
  - revenue_source_id
  - start_date
  - end_date
  - status
  - ledger_transaction_ids  # All revenue distribution transactions
  - metadata

scalegraph_conditional_payments
  - id
  - payer_id
  - payee_id
  - amount
  - conditions  # JSON or structured data
  - status  (pending, conditions_met, executed, cancelled)
  - ledger_transaction_id  # When conditions are met
  - created_at
  - metadata

scalegraph_subscription_contracts
  - id
  - subscriber_id
  - provider_id
  - amount_per_period
  - period  (monthly, yearly, etc.)
  - start_date
  - end_date
  - status  (active, cancelled, expired)
  - ledger_transaction_ids  # All subscription payment transactions
  - next_billing_date
  - metadata
```

## Data Flow Examples

### Example 1: Invoice

**Step 1: Business Layer creates invoice**
```elixir
# Business.Transactions.purchase_invoice/4
# 1. Create ledger transaction
Ledger.transfer([
  {"supplier:receivables", +amount},
  {"buyer:payables", -amount}
], "INVOICE: #{reference}")

# 2. Create invoice contract
Business.Contracts.create_invoice(%{
  supplier_id: supplier_id,
  buyer_id: buyer_id,
  amount: amount,
  due_date: due_date,
  ledger_transaction_id: tx.id,
  reference: reference
})
```

**Step 2: Query invoices**
```elixir
# Get all pending invoices for a buyer
Business.Contracts.list_invoices(buyer_id: buyer_id, status: :pending)

# Get invoice + its ledger transaction
invoice = Business.Contracts.get_invoice(invoice_id)
tx = Ledger.get_transaction(invoice.ledger_transaction_id)
```

### Example 2: Loan

**Step 1: Create loan**
```elixir
# Business.Transactions.create_loan/4
# 1. Create ledger transaction (4 entries)
Ledger.transfer([
  {"lender:operating", -amount},
  {"borrower:operating", +amount},
  {"lender:receivables", +amount},
  {"borrower:payables", -amount}
], "LOAN: #{reference}")

# 2. Create loan contract
Business.Contracts.create_loan(%{
  lender_id: lender_id,
  borrower_id: borrower_id,
  principal_amount: amount,
  interest_rate: 0.05,
  repayment_schedule: %{...},
  disbursement_transaction_id: tx.id,
  reference: reference
})
```

**Step 2: Query loans**
```elixir
# Get all active loans for a lender
loans = Business.Contracts.list_loans(lender_id: lender_id, status: :active)

# For each loan, get ledger transactions
for loan <- loans do
  disbursement = Ledger.get_transaction(loan.disbursement_transaction_id)
  repayments = Enum.map(loan.repayment_transaction_ids, &Ledger.get_transaction/1)
  {loan, disbursement, repayments}
end
```

### Example 3: Revenue-Share Contract

**Step 1: Create contract**
```elixir
# Business.Contracts.create_revenue_share(%{
#   parties: [
#     {"beauty_hosting", 0.60},  # 60%
#     {"salon_glamour", 0.30},   # 30%
#     {"equipment_provider", 0.10} # 10%
#   ],
#   revenue_source_id: "service_xyz",
#   start_date: ~D[2024-01-01],
#   end_date: ~D[2024-12-31]
# })
```

**Step 2: When revenue comes in**
```elixir
# Business.Transactions.distribute_revenue(revenue_share_id, amount)
# 1. Get contract
contract = Business.Contracts.get_revenue_share(revenue_share_id)

# 2. Calculate distribution
entries = Enum.map(contract.parties, fn {participant_id, percentage} ->
  share = round(amount * percentage)
  {"#{participant_id}:operating", share}
end)

# 3. Create ledger transaction
Ledger.transfer(entries, "REVENUE_SHARE: #{contract.id}")

# 4. Update contract with transaction_id
Business.Contracts.add_revenue_transaction(contract.id, tx.id)
```

## Smart Contract Layer (Future)

Smart contracts build on the Business/Contract Layer:

```
┌─────────────────────────────────────┐
│     Smart Contract Layer           │
│  - Conditional logic                │
│  - Automated execution              │
│  - Multi-party agreements           │
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│     Business/Contract Layer         │
│  - Invoice contracts                │
│  - Loan contracts                   │
│  - Revenue-share contracts          │
│  - Conditional payments              │
│  - Subscription contracts           │
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│     Ledger Layer                    │
│  - Accounts                         │
│  - Transactions (generic transfers) │
└─────────────────────────────────────┘
```

Smart contracts can:
- Automatically execute conditional payments when conditions are met
- Automatically invoice subscriptions
- Automatically distribute revenue according to contracts
- Handle complex multi-party agreements

## Implementation Plan

### Phase 1: Refine Ledger
1. ✅ Remove `type` from Transaction (or make it optional/informational)
2. ✅ Ensure all transactions are generic transfers
3. ✅ Validate that entries sum to zero (or allow fees)

### Phase 2: Create Business/Contract Layer
1. Create `Business.Contracts` module
2. Create Mnesia tables for contracts
3. Migrate existing business logic to use contracts
4. Update Business.Transactions to create contracts

### Phase 3: Query and Aggregation
1. Create query functions for contracts
2. Create aggregation functions (e.g., total outstanding loans)
3. Create reporting functions

### Phase 4: Smart Contracts (Future)
1. Design smart contract DSL
2. Implement execution engine
3. Integrate with Business/Contract Layer

## Summary

**Ledger Layer:**
- ✅ Generic transfer with entries that sum to zero
- ✅ No business semantics
- ✅ Immutable audit trail
- ✅ Simple and replayable

**Business/Contract Layer:**
- ✅ Stores business metadata separately
- ✅ References ledger transactions
- ✅ Handles state machines and workflows
- ✅ Can query and aggregate

**Smart Contract Layer (Future):**
- ✅ Builds on Business/Contract Layer
- ✅ Automated execution
- ✅ Conditional logic

This design provides:
- **Separation of concerns**: Ledger is simple, business logic is separate
- **Flexibility**: New business constructs require no changes to the ledger
- **Scalability**: Can build smart contracts on top
- **Replayability**: All transactions are self-describing
