# Proto Split - Example Structure

This document shows how the current `ledger.proto` would be split into three files.

## File 1: `common.proto`

```protobuf
syntax = "proto3";

package scalegraph.common;

// Elixir-specific option (ignored by Rust/tonic)
option elixir_module_prefix = "Scalegraph.Proto";

// ============================================================================
// Participant Types
// ============================================================================

enum ParticipantRole {
  PARTICIPANT_ROLE_UNSPECIFIED = 0;
  ACCESS_PROVIDER = 1;            // i.e., ASSA ABLOY 
  BANKING_PARTNER = 2;            // i.e., SEB
  ECOSYSTEM_PARTNER = 3;          // e.g., Studio Solveig, Hair and Beard
  SUPPLIER = 4;                   // e.g., Schampo etc, Clipper Oy, Essity
  EQUIPMENT_PROVIDER = 5;         // e.g., Hairgrowers United (pay-per-use)
  ECOSYSTEM_ORCHESTRATOR = 6;     // e.g., Beauty Hosting
}

message Contact {
  string email = 1;
  string phone = 2;
  string website = 3;
  string address = 4;
  string postal_code = 5;
  string city = 6;
  string country = 7;
}

message Participant {
  string id = 1;
  string name = 2;
  ParticipantRole role = 3;
  int64 created_at = 4;
  map<string, string> metadata = 5;
  repeated string services = 6;
  string about = 7;
  Contact contact = 8;
}

// ============================================================================
// Account Types
// ============================================================================

enum AccountType {
  ACCOUNT_TYPE_UNSPECIFIED = 0;
  STANDALONE = 1;
  OPERATING = 2;
  RECEIVABLES = 3;
  PAYABLES = 4;
  ESCROW = 5;
  FEES = 6;
  USAGE = 7;
}

message Account {
  string id = 1;
  string participant_id = 2;
  AccountType account_type = 3;
  int64 balance = 4;
  int64 created_at = 5;
  map<string, string> metadata = 6;
}

// ============================================================================
// Transaction Types
// ============================================================================

message TransferEntry {
  string account_id = 1;
  int64 amount = 2;  // positive = credit, negative = debit
}

message Transaction {
  string id = 1;
  string type = 2;  // Optional, informational only: "transfer" (default)
  repeated TransferEntry entries = 3;
  int64 timestamp = 4;
  string reference = 5;  // Human-readable reference
}

// ============================================================================
// Common Responses
// ============================================================================

message ErrorResponse {
  string code = 1;
  string message = 2;
}
```

## File 2: `ledger.proto`

```protobuf
syntax = "proto3";

package scalegraph.ledger;

import "common.proto";

// Elixir-specific option (ignored by Rust/tonic)
option elixir_module_prefix = "Scalegraph.Proto";

// ============================================================================
// Ledger Service - Core Double-Entry Bookkeeping
// ============================================================================

// Account operations
message CreateAccountRequest {
  string account_id = 1;
  int64 initial_balance = 2;
  map<string, string> metadata = 3;
}

message GetAccountRequest {
  string account_id = 1;
}

message GetBalanceRequest {
  string account_id = 1;
}

message GetBalanceResponse {
  string account_id = 1;
  int64 balance = 2;
}

// Transaction operations
message CreditRequest {
  string account_id = 1;
  int64 amount = 2;
  string reference = 3;
}

message DebitRequest {
  string account_id = 1;
  int64 amount = 2;
  string reference = 3;
}

message TransferRequest {
  repeated scalegraph.common.TransferEntry entries = 1;
  string reference = 2;
}

message ListTransactionsRequest {
  int32 limit = 1;           // Max transactions to return (default: 50)
  string account_id = 2;     // Optional: filter by account
}

message ListTransactionsResponse {
  repeated scalegraph.common.Transaction transactions = 1;
}

// Ledger service definition
service LedgerService {
  // Account operations
  rpc CreateAccount(CreateAccountRequest) returns (scalegraph.common.Account);
  rpc GetAccount(GetAccountRequest) returns (scalegraph.common.Account);
  rpc GetBalance(GetBalanceRequest) returns (GetBalanceResponse);

  // Transaction operations
  rpc Credit(CreditRequest) returns (scalegraph.common.Transaction);
  rpc Debit(DebitRequest) returns (scalegraph.common.Transaction);
  rpc Transfer(TransferRequest) returns (scalegraph.common.Transaction);
  rpc ListTransactions(ListTransactionsRequest) returns (ListTransactionsResponse);
}
```

## File 3: `business-rules.proto`

```protobuf
syntax = "proto3";

package scalegraph.business;

import "common.proto";
import "ledger.proto";

// Elixir-specific option (ignored by Rust/tonic)
option elixir_module_prefix = "Scalegraph.Proto";

// ============================================================================
// Participant Service - Participant Management
// ============================================================================

message CreateParticipantRequest {
  string id = 1;
  string name = 2;
  scalegraph.common.ParticipantRole role = 3;
  map<string, string> metadata = 4;
  string about = 5;
  scalegraph.common.Contact contact = 6;
}

message GetParticipantRequest {
  string participant_id = 1;
}

message ListParticipantsRequest {
  scalegraph.common.ParticipantRole role = 1;  // optional filter
}

message ListParticipantsResponse {
  repeated scalegraph.common.Participant participants = 1;
}

message CreateParticipantAccountRequest {
  string participant_id = 1;
  scalegraph.common.AccountType account_type = 2;
  int64 initial_balance = 3;
  map<string, string> metadata = 4;
}

message GetParticipantAccountsRequest {
  string participant_id = 1;
}

message GetParticipantAccountsResponse {
  repeated scalegraph.common.Account accounts = 1;
}

message AddServiceRequest {
  string participant_id = 1;
  string service_id = 2;
}

message RemoveServiceRequest {
  string participant_id = 1;
  string service_id = 2;
}

message ListServicesRequest {
  string participant_id = 1;
}

message ListServicesResponse {
  repeated string services = 1;
}

service ParticipantService {
  rpc CreateParticipant(CreateParticipantRequest) returns (scalegraph.common.Participant);
  rpc GetParticipant(GetParticipantRequest) returns (scalegraph.common.Participant);
  rpc ListParticipants(ListParticipantsRequest) returns (ListParticipantsResponse);
  rpc CreateParticipantAccount(CreateParticipantAccountRequest) returns (scalegraph.common.Account);
  rpc GetParticipantAccounts(GetParticipantAccountsRequest) returns (GetParticipantAccountsResponse);
  rpc AddService(AddServiceRequest) returns (scalegraph.common.Participant);
  rpc RemoveService(RemoveServiceRequest) returns (scalegraph.common.Participant);
  rpc ListServices(ListServicesRequest) returns (ListServicesResponse);
}

// ============================================================================
// Business Rules Service - Business Contracts and Rules
// ============================================================================

// Invoice operations
message PurchaseInvoiceRequest {
  string supplier_id = 1;
  string buyer_id = 2;
  int64 amount = 3;
  string reference = 4;
}

message PayInvoiceRequest {
  string supplier_id = 1;
  string buyer_id = 2;
  int64 amount = 3;
  string reference = 4;
}

message GetInvoiceRequest {
  string invoice_id = 1;
}

message Invoice {
  string id = 1;
  string supplier_id = 2;
  string buyer_id = 3;
  int64 amount = 4;
  int64 due_date = 5;
  string status = 6;  // "pending", "paid", "overdue", "cancelled"
  string ledger_transaction_id = 7;  // Reference to ledger transaction
  string reference = 8;
  int64 created_at = 9;
  int64 paid_at = 10;
  map<string, string> metadata = 11;
}

message ListInvoicesRequest {
  string supplier_id = 1;  // Optional filter
  string buyer_id = 2;     // Optional filter
  string status = 3;      // Optional filter
  int32 limit = 4;        // Max results (default: 100)
}

message ListInvoicesResponse {
  repeated Invoice invoices = 1;
}

// Loan operations
message CreateLoanRequest {
  string lender_id = 1;
  string borrower_id = 2;
  int64 amount = 3;
  string reference = 4;
  double interest_rate = 5;  // Optional, default: 0.0
}

message RepayLoanRequest {
  string lender_id = 1;
  string borrower_id = 2;
  int64 amount = 3;
  string reference = 4;
}

message GetLoanRequest {
  string loan_id = 1;
}

message Loan {
  string id = 1;
  string lender_id = 2;
  string borrower_id = 3;
  int64 principal_amount = 4;
  double interest_rate = 5;
  string status = 6;  // "active", "repaid", "defaulted"
  string disbursement_transaction_id = 7;  // Reference to ledger transaction
  repeated string repayment_transaction_ids = 8;
  string reference = 9;
  int64 created_at = 10;
  map<string, string> metadata = 11;
}

message ListLoansRequest {
  string lender_id = 1;   // Optional filter
  string borrower_id = 2;  // Optional filter
  string status = 3;      // Optional filter
  int32 limit = 4;        // Max results (default: 100)
}

message ListLoansResponse {
  repeated Loan loans = 1;
}

message GetOutstandingLoansRequest {
  string lender_id = 1;
}

message GetOutstandingLoansResponse {
  string lender_id = 1;
  int64 total_outstanding = 2;
}

message GetTotalDebtRequest {
  string borrower_id = 1;
}

message GetTotalDebtResponse {
  string borrower_id = 1;
  int64 total_debt = 2;
}

// Access payment
message AccessPaymentRequest {
  string payer_id = 1;
  string access_provider_id = 2;
  int64 amount = 3;
  string reference = 4;
  string platform_id = 5;      // Optional platform for fees
  int64 platform_fee = 6;      // Optional platform fee in cents
}

// Business transaction response
message BusinessTransactionResponse {
  string transaction_id = 1;
  string reference = 2;
  int64 amount = 3;
  int64 platform_fee = 4;  // Only for access payments with fees
  string status = 5;       // "completed", "failed"
  string message = 6;      // Human-readable result
}

service BusinessService {
  // Invoice operations
  rpc PurchaseInvoice(PurchaseInvoiceRequest) returns (BusinessTransactionResponse);
  rpc PayInvoice(PayInvoiceRequest) returns (BusinessTransactionResponse);
  rpc GetInvoice(GetInvoiceRequest) returns (Invoice);
  rpc ListInvoices(ListInvoicesRequest) returns (ListInvoicesResponse);

  // Loan operations
  rpc CreateLoan(CreateLoanRequest) returns (BusinessTransactionResponse);
  rpc RepayLoan(RepayLoanRequest) returns (BusinessTransactionResponse);
  rpc GetLoan(GetLoanRequest) returns (Loan);
  rpc ListLoans(ListLoansRequest) returns (ListLoansResponse);
  rpc GetOutstandingLoans(GetOutstandingLoansRequest) returns (GetOutstandingLoansResponse);
  rpc GetTotalDebt(GetTotalDebtRequest) returns (GetTotalDebtResponse);

  // Access payment
  rpc AccessPayment(AccessPaymentRequest) returns (BusinessTransactionResponse);
}
```

## File 4: `smart-contracts.proto` (Future)

```protobuf
syntax = "proto3";

package scalegraph.smartcontracts;

import "common.proto";
import "ledger.proto";
import "business-rules.proto";

// Elixir-specific option (ignored by Rust/tonic)
option elixir_module_prefix = "Scalegraph.Proto";

// ============================================================================
// Smart Contracts Service - Automation and Conditional Execution
// ============================================================================

message ContractCondition {
  string type = 1;  // "time", "balance", "event", "custom"
  map<string, string> parameters = 2;
}

message ContractAction {
  string type = 1;  // "transfer", "invoice", "loan", "custom"
  map<string, string> parameters = 2;
}

message Contract {
  string id = 1;
  string name = 2;
  string description = 3;
  repeated ContractCondition conditions = 4;
  repeated ContractAction actions = 5;
  string status = 6;  // "active", "paused", "completed", "cancelled"
  int64 created_at = 7;
  int64 last_executed_at = 8;
  map<string, string> metadata = 9;
}

message CreateContractRequest {
  string name = 1;
  string description = 2;
  repeated ContractCondition conditions = 3;
  repeated ContractAction actions = 4;
  map<string, string> metadata = 5;
}

message GetContractRequest {
  string contract_id = 1;
}

message ListContractsRequest {
  string status = 1;  // Optional filter
  int32 limit = 2;    // Max results (default: 100)
}

message ListContractsResponse {
  repeated Contract contracts = 1;
}

message ExecuteContractRequest {
  string contract_id = 1;
}

message ExecuteContractResponse {
  string contract_id = 1;
  bool executed = 2;
  string message = 3;
  repeated string transaction_ids = 4;  // Ledger transactions created
}

service SmartContractService {
  rpc CreateContract(CreateContractRequest) returns (Contract);
  rpc GetContract(GetContractRequest) returns (Contract);
  rpc ListContracts(ListContractsRequest) returns (ListContractsResponse);
  rpc ExecuteContract(ExecuteContractRequest) returns (ExecuteContractResponse);
  rpc UpdateContract(Contract) returns (Contract);
  rpc DeleteContract(GetContractRequest) returns (scalegraph.common.ErrorResponse);
}
```

## Key Differences from Current Structure

1. **Common messages extracted**: Participant, Account, Transaction moved to `common.proto`
2. **Ledger is minimal**: Only core accounting operations
3. **Business rules expanded**: Added contract query operations (GetInvoice, ListInvoices, etc.)
4. **Smart contracts added**: Future automation layer with clear structure

## Build Script Changes

### Rust (`cli/build.rs` and `mcp/build.rs`)

```rust
tonic_build::configure()
    .build_server(true)
    .compile(
        &[
            "../proto/common.proto",
            "../proto/ledger.proto",
            "../proto/business-rules.proto",
            "../proto/smart-contracts.proto",
        ],
        &["../proto"],
    )?;
```

### Elixir

```bash
protoc --elixir_out=./lib/scalegraph/proto \
  --proto_path=./proto \
  proto/common.proto \
  proto/ledger.proto \
  proto/business-rules.proto \
  proto/smart-contracts.proto
```

