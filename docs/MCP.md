# Scalegraph MCP Server

The Scalegraph Model Context Protocol (MCP) server provides a comprehensive interface for LLMs to interact with the Scalegraph ledger system. It exposes all three layers of the architecture: **Ledger**, **Business Rules**, and **Smart Contracts**.

## Overview

The MCP server enables AI assistants (like Claude Desktop) to:
- Query ledger accounts and balances
- Execute financial transactions
- Manage participants and accounts
- Create and manage business contracts (invoices, loans)
- Create and manage smart contracts (subscriptions, conditional payments, revenue sharing)
- Automate financial workflows

## Installation

### Prerequisites

- Rust toolchain (for building the MCP server)
- Scalegraph Elixir server running (default: `http://localhost:50051`)

### Building

```bash
cd mcp
cargo build --release
```

The binary will be at `mcp/target/release/scalegraph-mcp`.

## Configuration

### Environment Variables

- `SCALEGRAPH_GRPC_URL` - gRPC server URL (default: `http://localhost:50051`)
- `SCALEGRAPH_DEBUG` - Enable debug output to stderr (set to any value)

### Claude Desktop Configuration

Add to your Claude Desktop settings (`~/Library/Application Support/Claude/claude_desktop_config.json` on macOS):

```json
{
  "mcpServers": {
    "scalegraph": {
      "command": "/path/to/scalegraph-elexir/mcp/target/release/scalegraph-mcp",
      "env": {
        "SCALEGRAPH_GRPC_URL": "http://localhost:50051"
      }
    }
  }
}
```

Restart Claude Desktop after configuration.

## Available Tools

The MCP server exposes **25 tools** organized into four categories:

### 1. Participant Management (4 tools)

#### `list_participants`
List all participants in the Scalegraph ecosystem.

**Returns:** Participant IDs, names, and roles (Access Provider, Banking Partner, Ecosystem Partner, Supplier, Equipment Provider)

**Example:**
```json
{
  "participants": [
    {
      "id": "salon_glamour",
      "name": "Salon Glamour",
      "role": "Ecosystem Partner"
    }
  ]
}
```

#### `create_participant`
Create a new participant in the ecosystem.

**Parameters:**
- `id` (string, required) - Unique participant ID
- `name` (string, required) - Display name
- `role` (string, required) - One of: `access_provider`, `banking_partner`, `ecosystem_partner`, `supplier`, `equipment_provider`

#### `create_participant_account`
Create a ledger account for a participant.

**Parameters:**
- `participant_id` (string, required) - Participant ID
- `account_type` (string, required) - One of: `operating`, `receivables`, `payables`, `escrow`, `fees`, `usage`
- `initial_balance_cents` (integer, optional) - Initial balance in cents (default: 0)

**Account Types:**
- `operating` - Main cash account for daily operations
- `receivables` - Money owed to the participant (A/R)
- `payables` - Money the participant owes (A/P)
- `escrow` - Held funds (security deposits)
- `fees` - Accumulated fees to collect
- `usage` - Usage-based revenue

#### `get_participant_accounts`
Get all ledger accounts for a participant.

**Parameters:**
- `participant_id` (string, required)

**Returns:** List of accounts with IDs, types, and balances

---

### 2. Ledger Operations (3 tools)

#### `get_account_balance`
Get the current balance of a specific account.

**Parameters:**
- `account_id` (string, required) - Format: `participant_id:account_type`

**Returns:** Account ID, balance (formatted and in cents)

#### `transfer`
Execute an atomic multi-party transfer. All entries must sum to zero.

**Parameters:**
- `entries` (array, required) - Array of transfer entries
  - Each entry: `account_id` (string), `amount_cents` (integer)
  - Positive amounts = credit, negative = debit
- `reference` (string, required) - Transaction reference/description

**Example:**
```json
{
  "entries": [
    {"account_id": "buyer:operating", "amount_cents": -10000},
    {"account_id": "seller:operating", "amount_cents": 10000}
  ],
  "reference": "Payment for services"
}
```

#### `list_transactions`
List recent transactions from the ledger.

**Parameters:**
- `limit` (integer, optional) - Max transactions (default: 50)
- `account_id` (string, optional) - Filter by account

**Returns:** Transaction history with IDs, types, references, timestamps, and entries

---

### 3. Business Transactions (6 tools)

#### `purchase_invoice`
Create a B2B purchase invoice. Records debt: increases supplier's receivables and buyer's payables.

**Parameters:**
- `supplier_id` (string, required)
- `buyer_id` (string, required)
- `amount_cents` (integer, required)
- `reference` (string, required)

**Creates 2 ledger entries atomically:**
- Supplier's receivables: +amount
- Buyer's payables: -amount

#### `pay_invoice`
Pay/settle a B2B invoice. Transfers money and clears receivables/payables.

**Parameters:**
- `supplier_id` (string, required)
- `buyer_id` (string, required)
- `amount_cents` (integer, required)
- `reference` (string, required)

**Creates 4 ledger entries atomically:**
- Buyer's operating: -amount
- Supplier's operating: +amount
- Buyer's payables: +amount (clears debt)
- Supplier's receivables: -amount (clears receivable)

#### `access_payment`
Process real-time micro-payment for access control (e.g., door unlock).

**Parameters:**
- `payer_id` (string, required)
- `access_provider_id` (string, required)
- `amount_cents` (integer, required)
- `reference` (string, required)
- `platform_id` (string, optional) - Platform to receive fee
- `platform_fee_cents` (integer, optional) - Platform fee in cents

**Creates 2-3 ledger entries:**
- Payer's operating: -amount
- Access provider's operating: +amount (or +amount - fee)
- Platform's fees: +fee (if platform specified)

#### `create_loan`
Create a loan with formal obligation tracking.

**Parameters:**
- `lender_id` (string, required)
- `borrower_id` (string, required)
- `amount_cents` (integer, required)
- `reference` (string, required)

**Creates 4 ledger entries atomically:**
- Lender's operating: -amount
- Borrower's operating: +amount
- Lender's receivables: +amount
- Borrower's payables: -amount

#### `repay_loan`
Repay a loan and clear obligations.

**Parameters:**
- `lender_id` (string, required)
- `borrower_id` (string, required)
- `amount_cents` (integer, required)
- `reference` (string, required)

**Reverses the loan entries atomically.**

#### `get_outstanding_loans`
Get total outstanding loans for a lender.

**Parameters:**
- `lender_id` (string, required)

**Returns:** Total outstanding amount (positive balance in lender's receivables)

#### `get_total_debt`
Get total debt for a borrower.

**Parameters:**
- `borrower_id` (string, required)

**Returns:** Total debt (absolute value of negative balance in borrower's payables)

---

### 4. Smart Contracts (11 tools)

Smart contracts provide automation and conditional execution capabilities.

#### Invoice Contracts

##### `create_invoice_contract`
Create a smart invoice contract with automation (auto-debit on due date, late fees).

**Parameters:**
- `supplier_id` (string, required)
- `buyer_id` (string, required)
- `amount_cents` (integer, required)
- `issue_date` (integer, required) - Unix timestamp in milliseconds
- `due_date` (integer, required) - Unix timestamp in milliseconds
- `payment_terms` (string, optional) - e.g., "Net 30"
- `auto_debit` (boolean, optional) - Enable automatic debit on due date
- `late_fee_cents` (integer, optional) - Late fee if not paid by due date
- `reference` (string, required)

**Features:**
- Automatic debit on due date (if enabled)
- Late fee calculation
- Status tracking (pending, paid, overdue, cancelled)

##### `get_invoice_contract`
Get details of an invoice contract by ID.

**Parameters:**
- `contract_id` (string, required)

#### Subscription Contracts

##### `create_subscription_contract`
Create a subscription contract with recurring billing (e.g., monthly SaaS fee).

**Parameters:**
- `provider_id` (string, required) - Service provider
- `subscriber_id` (string, required) - Subscriber
- `monthly_fee_cents` (integer, required)
- `billing_date` (string, required) - Pattern: "every 1st", "every 15th"
- `auto_debit` (boolean, optional) - Enable automatic monthly debit
- `cancellation_notice_days` (integer, optional) - Days notice required
- `start_date` (integer, required) - Unix timestamp in milliseconds
- `end_date` (integer, optional) - Unix timestamp in milliseconds

**Features:**
- Recurring monthly billing
- Automatic debit on billing date
- Cancellation notice period
- Next billing date tracking

##### `get_subscription_contract`
Get details of a subscription contract by ID.

**Parameters:**
- `contract_id` (string, required)

#### Conditional Payment Contracts

##### `create_conditional_payment`
Create a conditional payment contract that executes when conditions are met.

**Parameters:**
- `payer_id` (string, required)
- `receiver_id` (string, required)
- `amount_cents` (integer, required)
- `condition_type` (string, required) - e.g., "if_service_completed"
- `trigger` (string, required) - Condition expression, e.g., "status = 'completed'"

**Use Cases:**
- Escrow payments
- Milestone-based payments
- Service completion payments

**Features:**
- Payment held until conditions met
- Manual or automatic execution
- Status tracking (pending, conditions_met, executed, cancelled)

##### `get_conditional_payment`
Get details of a conditional payment contract by ID.

**Parameters:**
- `contract_id` (string, required)

#### Revenue Share Contracts

##### `create_revenue_share_contract`
Create a revenue share contract that automatically splits revenue among multiple parties.

**Parameters:**
- `transaction_type` (string, required) - e.g., "service_sale"
- `parties` (array, required) - Array of parties with shares
  - Each party: `participant_id` (string), `share` (number, 0.0-1.0)
- `auto_split` (boolean, optional) - Enable automatic revenue splitting

**Example:**
```json
{
  "transaction_type": "service_sale",
  "parties": [
    {"participant_id": "salon_glamour", "share": 0.70},
    {"participant_id": "hairgrowers_united", "share": 0.20},
    {"participant_id": "beauty_hosting", "share": 0.10}
  ],
  "auto_split": true
}
```

**Features:**
- Automatic revenue distribution
- Multiple party support
- Percentage-based shares
- Transaction history tracking

##### `get_revenue_share_contract`
Get details of a revenue share contract by ID.

**Parameters:**
- `contract_id` (string, required)

#### Generic Contract Operations

##### `list_contracts`
List all contracts with optional filters.

**Parameters:**
- `contract_type` (string, optional) - Filter: `loan`, `invoice`, `subscription`, `conditional_payment`, `revenue_share`
- `status` (string, optional) - Filter: `active`, `completed`, `cancelled`, etc.
- `participant_id` (string, optional) - Filter by participant (any role)
- `limit` (integer, optional) - Max results (default: 100)

**Returns:** List of contracts with type and basic details

##### `execute_contract`
Manually execute a contract (e.g., trigger conditional payment, process subscription billing).

**Parameters:**
- `contract_id` (string, required)
- `contract_type` (string, required) - One of: `loan`, `invoice`, `subscription`, `conditional_payment`, `revenue_share`

**Returns:** Execution result with transaction IDs created

##### `update_contract_status`
Update the status of a contract (pause, cancel, complete).

**Parameters:**
- `contract_id` (string, required)
- `contract_type` (string, required) - One of: `loan`, `invoice`, `subscription`, `conditional_payment`, `revenue_share`
- `status` (string, required) - One of: `active`, `paused`, `completed`, `cancelled`

---

## Architecture Layers

The MCP server exposes three distinct layers:

### Layer 1: Ledger (Core)
- Generic account management
- Atomic multi-party transfers
- Balance queries
- Transaction history

**Tools:** `get_account_balance`, `transfer`, `list_transactions`

### Layer 2: Business Rules
- High-level financial constructs
- Invoices (purchase, payment)
- Loans (create, repay)
- Access payments
- Debt tracking

**Tools:** `purchase_invoice`, `pay_invoice`, `create_loan`, `repay_loan`, `access_payment`, `get_outstanding_loans`, `get_total_debt`

### Layer 3: Smart Contracts
- Automation and conditional execution
- Invoice contracts (with auto-debit, late fees)
- Subscription contracts (recurring billing)
- Conditional payments (escrow, milestones)
- Revenue share contracts (automatic distribution)

**Tools:** All `*_contract` tools

---

## Example Workflows

### Workflow 1: Create and Pay Invoice

```json
// 1. Create invoice
{
  "tool": "purchase_invoice",
  "arguments": {
    "supplier_id": "schampo_etc",
    "buyer_id": "salon_glamour",
    "amount_cents": 455000,
    "reference": "INV-2024-001 ABC Shine 300x"
  }
}

// 2. Later, pay the invoice
{
  "tool": "pay_invoice",
  "arguments": {
    "supplier_id": "schampo_etc",
    "buyer_id": "salon_glamour",
    "amount_cents": 455000,
    "reference": "PAY-INV-2024-001"
  }
}
```

### Workflow 2: Create Subscription with Auto-Billing

```json
{
  "tool": "create_subscription_contract",
  "arguments": {
    "provider_id": "beauty_hosting",
    "subscriber_id": "salon_glamour",
    "monthly_fee_cents": 200000,
    "billing_date": "every 1st",
    "auto_debit": true,
    "cancellation_notice_days": 30,
    "start_date": 1704067200000
  }
}
```

### Workflow 3: Revenue Share Setup

```json
{
  "tool": "create_revenue_share_contract",
  "arguments": {
    "transaction_type": "service_sale",
    "parties": [
      {"participant_id": "salon_glamour", "share": 0.70},
      {"participant_id": "hairgrowers_united", "share": 0.20},
      {"participant_id": "beauty_hosting", "share": 0.10}
    ],
    "auto_split": true
  }
}
```

### Workflow 4: Conditional Payment (Escrow)

```json
{
  "tool": "create_conditional_payment",
  "arguments": {
    "payer_id": "customer",
    "receiver_id": "salon_glamour",
    "amount_cents": 50000,
    "condition_type": "if_service_completed",
    "trigger": "status = 'completed'"
  }
}

// Later, when condition is met:
{
  "tool": "execute_contract",
  "arguments": {
    "contract_id": "...",
    "contract_type": "conditional_payment"
  }
}
```

---

## Error Handling

The MCP server returns JSON-RPC errors for:
- Invalid parameters
- Missing required fields
- gRPC connection failures
- Business logic errors (e.g., insufficient funds)

Errors follow the JSON-RPC 2.0 specification:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32602,
    "message": "Invalid params: missing required field 'participant_id'"
  }
}
```

---

## Development

### Testing Locally

1. Start the Elixir server:
   ```bash
   mix run --no-halt
   ```

2. Run the MCP server:
   ```bash
   SCALEGRAPH_DEBUG=1 ./target/release/scalegraph-mcp
   ```

3. Test with JSON-RPC requests via stdin:
   ```json
   {"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}
   ```

### Debugging

Set `SCALEGRAPH_DEBUG=1` to see:
- Connection status
- gRPC URL
- Request/response details (to stderr)

---

## Limitations

- The Smart Contracts layer requires the Elixir server to implement `SmartContractService`
- Contract execution automation requires a scheduler/cron service
- Conditional payment triggers require external event system integration

---

## Future Enhancements

- Contract execution scheduler
- Event-driven contract triggers
- Contract templates
- Bulk operations
- Contract analytics and reporting

---

## See Also

- [Architecture Documentation](../ARCHITECTURE.md)
- [Proto Split Documentation](PROTO_SPLIT_RECOMMENDATION.md)
- [CLI User Guide](CLI-USER-GUIDE.md)

