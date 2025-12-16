# Scalegraph Ledger Demo Script

This demo showcases the Scalegraph ledger system's capabilities through Claude Desktop (MCP). It demonstrates multi-party transactions, embedded financing, loan management, and real-time access payments.

## Prerequisites

1. **Start the Elixir gRPC server:**
   ```bash
   mix run --no-halt
   ```

2. **Ensure MCP server is built:**
   ```bash
   cd mcp && cargo build --release
   ```

3. **Configure Claude Desktop** with the MCP server (see `mcp/README.md`)

## Demo Scenario: Beauty Ecosystem

We'll simulate a real-world scenario where:
- **Salon Glamour** needs to pay a $2,000 platform fee to **Beauty Hosting**
- **Salon Glamour** only has $499.77 available
- **SEB Bank** provides embedded financing to cover the gap
- The entire settlement happens atomically in a single transaction

## Demo Script

Copy and paste these prompts into Claude Desktop:

---

### Step 1: Check Initial State

```
Show me all participants in the Scalegraph system and their account balances.
```

---

### Step 2: Create a Purchase Invoice

```
Create a purchase invoice from schampo_etc to salon_glamour for $4,550.00 worth of shampoo products. Use reference "INV-2024-001 ABC Shine 300x".
```

**Expected Result:** 
- `schampo_etc:receivables` increases by $4,550.00
- `salon_glamour:payables` decreases by $4,550.00 (negative = debt)

---

### Step 3: Pay the Invoice

```
Pay the invoice from salon_glamour to schampo_etc for $4,550.00. Use reference "PAY-INV-2024-001".
```

**Expected Result:**
- Money moves: `salon_glamour:operating` → `schampo_etc:operating`
- Receivables/payables cleared

---

### Step 4: Create a Loan

```
Create a loan from SEB (lender_id: "seb") to Salon Glamour (borrower_id: "salon_glamour") for $1,500.23. Use reference "LOAN-2024-001".
```

**Expected Result:**
- `seb:operating` debited by $1,500.23
- `salon_glamour:operating` credited by $1,500.23
- `seb:receivables` credited by $1,500.23 (SEB is owed)
- `salon_glamour:payables` debited by $1,500.23 (Salon owes)

---

### Step 5: Check Loan Status

```
What are the outstanding loans for SEB (lender_id: "seb")?
```

```
What is the total debt for Salon Glamour (borrower_id: "salon_glamour")?
```

**Expected Result:**
- SEB has $1,500.23 outstanding
- Salon Glamour owes $1,500.23

---

### Step 6: Three-Party Atomic Settlement (Embedded Financing)

This is the key demo: **Salon Glamour needs to pay $2,000 to Beauty Hosting but only has $499.77. SEB provides financing atomically.**

```
Execute a three-party atomic transfer:
- SEB (seb:operating) debits $1,500.23
- Salon Glamour (salon_glamour:operating) debits $499.77
- Beauty Hosting (beauty_hosting:fees) credits $2,000.00

Use reference "SETTLEMENT-2024-001 Embedded Financing".
```

**Expected Result:**
- All three parties see a single atomic transaction
- Salon Glamour never needed the full $2,000 upfront
- The fee is paid, salon stays in marketplace
- Debt is cleanly recorded

---

### Step 7: Access Payment (Micro-transaction)

```
Process an access payment: Salon Glamour pays $8.00 to ASSA ABLOY for door access. Use reference "DOOR-MAIN-20241215". Include a $0.50 platform fee to Beauty Hosting.
```

**Expected Result:**
- `salon_glamour:operating` debited $8.00
- `assa_abloy:fees` credited $7.50
- `beauty_hosting:fees` credited $0.50

---

### Step 8: Repay the Loan

```
Repay the loan from Salon Glamour to SEB for $1,500.23. Use reference "REPAY-LOAN-2024-001".
```

**Expected Result:**
- Money moves: `salon_glamour:operating` → `seb:operating`
- `seb:receivables` cleared
- `salon_glamour:payables` cleared

---

### Step 9: View Transaction History

```
Show me the last 20 transactions in the ledger.
```

---

### Step 10: Check Final Balances

```
Show me all account balances for:
- salon_glamour
- seb
- beauty_hosting
- schampo_etc
- assa_abloy
```

---

### Step 11: Create a Smart Contract (Marketplace Membership)

```
Create a marketplace membership contract for beauty_hosting that charges all participants 60 EUR per month. Use a 3-month grace period and 9 monthly payments after that.
```

**Expected Result:**
- Contract created with all participants enrolled
- Contract scheduled to execute monthly
- First payment due after 3 months

---

### Step 12: List Smart Contracts

```
Show me all active smart contracts in the system.
```

**Expected Result:**
- List of all smart contracts with their status
- Contract types and execution schedules

---

### Step 13: Execute Smart Contract Manually

```
Execute the marketplace membership contract manually (if it's due).
```

**Expected Result:**
- Contract executes if conditions are met
- All participants charged monthly fee
- Execution history recorded

---

### Step 14: Create Supplier Registration Contract

```
Create a supplier registration contract for a new supplier called "new_supplier_123".
```

**Expected Result:**
- Supplier registration contract created
- One-time registration fee (50 EUR) charged
- Monthly fee starts when first provider uses service

---

## Key Features Demonstrated

### Layer 1: Pure Core Ledger
1. **Atomic Multi-Party Transfers**: All-or-nothing guarantees
2. **Generic Transfers**: Flexible transaction model
3. **Immutable Audit Trail**: Complete transaction history

### Layer 2: Business Rules
4. **B2B Invoice Flow**: Purchase invoice → payment
5. **Formal Loan Tracking**: Receivables/payables for obligation tracking
6. **Embedded Financing**: Loans provided during settlement
7. **Real-Time Micro-Payments**: Access control payments
8. **Platform Fees**: Multi-party fee distribution

### Layer 3: Smart Contracts
9. **Automated Billing**: Marketplace membership contract
10. **Cron Scheduling**: Periodic contract execution
11. **Supplier Registration**: Automated registration and monthly fees
12. **Execution History**: Complete audit trail of contract executions

## Advanced Demo: Multi-Salon Scenario

For a more complex demo, try:

```
Create a new salon participant called "klipp_trim" with name "Klipp & Trim" as an ecosystem partner. Give them $2,750.00 in their operating account.

Now execute a four-party settlement:
- SEB debits $1,500.23
- Salon Glamour debits $499.77
- Klipp & Trim debits $0.00 (they're not involved but could be)
- Beauty Hosting credits $2,000.00

Use reference "MULTI-PARTY-SETTLEMENT-2024-001".
```

---

## Troubleshooting

If you get errors:
1. Ensure the Elixir server is running: `mix run --no-halt`
2. Check MCP server is built: `cd mcp && cargo build --release`
3. Verify Claude Desktop config includes the MCP server
4. Check account balances before transfers (insufficient funds errors)

---

## What Makes This Demo Interesting

### Three-Layer Architecture
1. **Layer 1 (Ledger)**: Pure double-entry bookkeeping with generic transfers
2. **Layer 2 (Business)**: Explicit financial terminology (loans, invoices) with business semantics
3. **Layer 3 (Smart Contracts)**: Automation and cron-based contract execution

### Real-World Scenarios
4. **Real-World Scenario**: Models actual business needs (salon needs to pay fees)
5. **Embedded Financing**: Shows how loans can be provided during settlement
6. **Automated Billing**: Smart contracts handle recurring payments automatically
7. **Supplier Onboarding**: Automated registration and fee management

### Technical Features
8. **Atomic Guarantees**: Demonstrates all-or-nothing transaction safety
9. **Multi-Party Complexity**: Shows how multiple parties coordinate atomically
10. **Loan Tracking**: Demonstrates formal obligation tracking via receivables/payables
11. **Micro-Payments**: Shows real-time access control payments
12. **Execution History**: Complete audit trail of all contract executions

This demo showcases that Scalegraph isn't just a ledger—it's a complete financial coordination system for multi-party ecosystems with three distinct layers: pure ledger, business rules, and smart contract automation.

