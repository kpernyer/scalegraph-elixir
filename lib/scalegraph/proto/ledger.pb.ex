# Generated protobuf modules for Scalegraph Ledger
# NOTE: Nested modules (MetadataEntry) must be defined BEFORE parent modules

# ============================================================================
# Enums
# ============================================================================

defmodule Scalegraph.Proto.ParticipantRole do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :PARTICIPANT_ROLE_UNSPECIFIED, 0
  field :ACCESS_PROVIDER, 1
  field :BANKING_PARTNER, 2
  field :ECOSYSTEM_PARTNER, 3
  field :SUPPLIER, 4
  field :EQUIPMENT_PROVIDER, 5
end

defmodule Scalegraph.Proto.AccountType do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :ACCOUNT_TYPE_UNSPECIFIED, 0
  field :STANDALONE, 1
  field :OPERATING, 2
  field :RECEIVABLES, 3
  field :PAYABLES, 4
  field :ESCROW, 5
  field :FEES, 6
  field :USAGE, 7
end

# ============================================================================
# Map Entry Types (must be defined before parent messages)
# ============================================================================

defmodule Scalegraph.Proto.Participant.MetadataEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Proto.Account.MetadataEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Proto.CreateParticipantRequest.MetadataEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Proto.CreateParticipantAccountRequest.MetadataEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Proto.CreateAccountRequest.MetadataEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :key, 1, type: :string
  field :value, 2, type: :string
end

# ============================================================================
# Core Messages
# ============================================================================

defmodule Scalegraph.Proto.Participant do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :id, 1, type: :string
  field :name, 2, type: :string
  field :role, 3, type: Scalegraph.Proto.ParticipantRole, enum: true
  field :created_at, 4, type: :int64
  field :metadata, 5, repeated: true, type: Scalegraph.Proto.Participant.MetadataEntry, map: true
end

defmodule Scalegraph.Proto.Account do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :id, 1, type: :string
  field :participant_id, 2, type: :string
  field :account_type, 3, type: Scalegraph.Proto.AccountType, enum: true
  field :balance, 4, type: :int64
  field :created_at, 5, type: :int64
  field :metadata, 6, repeated: true, type: Scalegraph.Proto.Account.MetadataEntry, map: true
end

defmodule Scalegraph.Proto.TransferEntry do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :account_id, 1, type: :string
  field :amount, 2, type: :int64
end

defmodule Scalegraph.Proto.Transaction do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :id, 1, type: :string
  field :type, 2, type: :string
  field :entries, 3, repeated: true, type: Scalegraph.Proto.TransferEntry
  field :timestamp, 4, type: :int64
  field :reference, 5, type: :string
end

# ============================================================================
# Participant Service Request/Response Messages
# ============================================================================

defmodule Scalegraph.Proto.CreateParticipantRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :id, 1, type: :string
  field :name, 2, type: :string
  field :role, 3, type: Scalegraph.Proto.ParticipantRole, enum: true
  field :metadata, 4, repeated: true, type: Scalegraph.Proto.CreateParticipantRequest.MetadataEntry, map: true
end

defmodule Scalegraph.Proto.GetParticipantRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :participant_id, 1, type: :string
end

defmodule Scalegraph.Proto.ListParticipantsRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :role, 1, type: Scalegraph.Proto.ParticipantRole, enum: true
end

defmodule Scalegraph.Proto.ListParticipantsResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :participants, 1, repeated: true, type: Scalegraph.Proto.Participant
end

defmodule Scalegraph.Proto.CreateParticipantAccountRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :participant_id, 1, type: :string
  field :account_type, 2, type: Scalegraph.Proto.AccountType, enum: true
  field :initial_balance, 3, type: :int64
  field :metadata, 4, repeated: true, type: Scalegraph.Proto.CreateParticipantAccountRequest.MetadataEntry, map: true
end

defmodule Scalegraph.Proto.GetParticipantAccountsRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :participant_id, 1, type: :string
end

defmodule Scalegraph.Proto.GetParticipantAccountsResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :accounts, 1, repeated: true, type: Scalegraph.Proto.Account
end

# ============================================================================
# Ledger Service Request/Response Messages
# ============================================================================

defmodule Scalegraph.Proto.CreateAccountRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :account_id, 1, type: :string
  field :initial_balance, 2, type: :int64
  field :metadata, 3, repeated: true, type: Scalegraph.Proto.CreateAccountRequest.MetadataEntry, map: true
end

defmodule Scalegraph.Proto.GetAccountRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :account_id, 1, type: :string
end

defmodule Scalegraph.Proto.GetBalanceRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :account_id, 1, type: :string
end

defmodule Scalegraph.Proto.GetBalanceResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :account_id, 1, type: :string
  field :balance, 2, type: :int64
end

defmodule Scalegraph.Proto.CreditRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :account_id, 1, type: :string
  field :amount, 2, type: :int64
  field :reference, 3, type: :string
end

defmodule Scalegraph.Proto.DebitRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :account_id, 1, type: :string
  field :amount, 2, type: :int64
  field :reference, 3, type: :string
end

defmodule Scalegraph.Proto.TransferRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :entries, 1, repeated: true, type: Scalegraph.Proto.TransferEntry
  field :reference, 2, type: :string
end

defmodule Scalegraph.Proto.ListTransactionsRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :limit, 1, type: :int32
  field :account_id, 2, type: :string
end

defmodule Scalegraph.Proto.ListTransactionsResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :transactions, 1, repeated: true, type: Scalegraph.Proto.Transaction
end

defmodule Scalegraph.Proto.ErrorResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :code, 1, type: :string
  field :message, 2, type: :string
end

# ============================================================================
# gRPC Service Definitions
# ============================================================================

defmodule Scalegraph.Proto.ParticipantService.Service do
  @moduledoc false
  use GRPC.Service, name: "scalegraph.ledger.ParticipantService", protoc_gen_elixir_version: "0.12.0"

  rpc :CreateParticipant, Scalegraph.Proto.CreateParticipantRequest, Scalegraph.Proto.Participant
  rpc :GetParticipant, Scalegraph.Proto.GetParticipantRequest, Scalegraph.Proto.Participant
  rpc :ListParticipants, Scalegraph.Proto.ListParticipantsRequest, Scalegraph.Proto.ListParticipantsResponse
  rpc :CreateParticipantAccount, Scalegraph.Proto.CreateParticipantAccountRequest, Scalegraph.Proto.Account
  rpc :GetParticipantAccounts, Scalegraph.Proto.GetParticipantAccountsRequest, Scalegraph.Proto.GetParticipantAccountsResponse
end

defmodule Scalegraph.Proto.ParticipantService.Stub do
  @moduledoc false
  use GRPC.Stub, service: Scalegraph.Proto.ParticipantService.Service
end

defmodule Scalegraph.Proto.LedgerService.Service do
  @moduledoc false
  use GRPC.Service, name: "scalegraph.ledger.LedgerService", protoc_gen_elixir_version: "0.12.0"

  rpc :CreateAccount, Scalegraph.Proto.CreateAccountRequest, Scalegraph.Proto.Account
  rpc :GetAccount, Scalegraph.Proto.GetAccountRequest, Scalegraph.Proto.Account
  rpc :GetBalance, Scalegraph.Proto.GetBalanceRequest, Scalegraph.Proto.GetBalanceResponse
  rpc :Credit, Scalegraph.Proto.CreditRequest, Scalegraph.Proto.Transaction
  rpc :Debit, Scalegraph.Proto.DebitRequest, Scalegraph.Proto.Transaction
  rpc :Transfer, Scalegraph.Proto.TransferRequest, Scalegraph.Proto.Transaction
  rpc :ListTransactions, Scalegraph.Proto.ListTransactionsRequest, Scalegraph.Proto.ListTransactionsResponse
end

defmodule Scalegraph.Proto.LedgerService.Stub do
  @moduledoc false
  use GRPC.Stub, service: Scalegraph.Proto.LedgerService.Service
end

# ============================================================================
# Business Service Request/Response Messages
# ============================================================================

defmodule Scalegraph.Proto.PurchaseInvoiceRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :supplier_id, 1, type: :string
  field :buyer_id, 2, type: :string
  field :amount, 3, type: :int64
  field :reference, 4, type: :string
end

defmodule Scalegraph.Proto.PayInvoiceRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :supplier_id, 1, type: :string
  field :buyer_id, 2, type: :string
  field :amount, 3, type: :int64
  field :reference, 4, type: :string
end

defmodule Scalegraph.Proto.AccessPaymentRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :payer_id, 1, type: :string
  field :access_provider_id, 2, type: :string
  field :amount, 3, type: :int64
  field :reference, 4, type: :string
  field :platform_id, 5, type: :string
  field :platform_fee, 6, type: :int64
end

defmodule Scalegraph.Proto.BusinessTransactionResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :transaction_id, 1, type: :string
  field :reference, 2, type: :string
  field :amount, 3, type: :int64
  field :platform_fee, 4, type: :int64
  field :status, 5, type: :string
  field :message, 6, type: :string
end

defmodule Scalegraph.Proto.BusinessService.Service do
  @moduledoc false
  use GRPC.Service, name: "scalegraph.ledger.BusinessService", protoc_gen_elixir_version: "0.12.0"

  rpc :PurchaseInvoice, Scalegraph.Proto.PurchaseInvoiceRequest, Scalegraph.Proto.BusinessTransactionResponse
  rpc :PayInvoice, Scalegraph.Proto.PayInvoiceRequest, Scalegraph.Proto.BusinessTransactionResponse
  rpc :AccessPayment, Scalegraph.Proto.AccessPaymentRequest, Scalegraph.Proto.BusinessTransactionResponse
end

defmodule Scalegraph.Proto.BusinessService.Stub do
  @moduledoc false
  use GRPC.Stub, service: Scalegraph.Proto.BusinessService.Service
end
