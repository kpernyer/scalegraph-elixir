defmodule Scalegraph.Smartcontracts.ContractType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :CONTRACT_TYPE_UNSPECIFIED, 0
  field :LOAN, 1
  field :INVOICE, 2
  field :SUBSCRIPTION, 3
  field :CONDITIONAL_PAYMENT, 4
  field :REVENUE_SHARE, 5
end

defmodule Scalegraph.Smartcontracts.ContractStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :CONTRACT_STATUS_UNSPECIFIED, 0
  field :ACTIVE, 1
  field :PAUSED, 2
  field :COMPLETED, 3
  field :CANCELLED, 4
end

defmodule Scalegraph.Smartcontracts.InvoiceContract.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Smartcontracts.InvoiceContract do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :id, 1, type: :string
  field :supplier_id, 2, type: :string, json_name: "supplierId"
  field :buyer_id, 3, type: :string, json_name: "buyerId"
  field :amount_cents, 4, type: :int64, json_name: "amountCents"
  field :issue_date, 5, type: :int64, json_name: "issueDate"
  field :due_date, 6, type: :int64, json_name: "dueDate"
  field :payment_terms, 7, type: :string, json_name: "paymentTerms"
  field :auto_debit, 8, type: :bool, json_name: "autoDebit"
  field :late_fee_cents, 9, type: :int64, json_name: "lateFeeCents"
  field :status, 10, type: :string
  field :ledger_transaction_id, 11, type: :string, json_name: "ledgerTransactionId"
  field :reference, 12, type: :string
  field :created_at, 13, type: :int64, json_name: "createdAt"
  field :paid_at, 14, type: :int64, json_name: "paidAt"

  field :metadata, 15,
    repeated: true,
    type: Scalegraph.Smartcontracts.InvoiceContract.MetadataEntry,
    map: true
end

defmodule Scalegraph.Smartcontracts.SubscriptionContract.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Smartcontracts.SubscriptionContract do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :id, 1, type: :string
  field :provider_id, 2, type: :string, json_name: "providerId"
  field :subscriber_id, 3, type: :string, json_name: "subscriberId"
  field :monthly_fee_cents, 4, type: :int64, json_name: "monthlyFeeCents"
  field :billing_date, 5, type: :string, json_name: "billingDate"
  field :auto_debit, 6, type: :bool, json_name: "autoDebit"
  field :cancellation_notice_days, 7, type: :int32, json_name: "cancellationNoticeDays"
  field :start_date, 8, type: :int64, json_name: "startDate"
  field :end_date, 9, type: :int64, json_name: "endDate"
  field :status, 10, type: :string

  field :payment_transaction_ids, 11,
    repeated: true,
    type: :string,
    json_name: "paymentTransactionIds"

  field :next_billing_date, 12, type: :int64, json_name: "nextBillingDate"
  field :created_at, 13, type: :int64, json_name: "createdAt"

  field :metadata, 14,
    repeated: true,
    type: Scalegraph.Smartcontracts.SubscriptionContract.MetadataEntry,
    map: true
end

defmodule Scalegraph.Smartcontracts.ConditionalPaymentContract.ConditionParametersEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Smartcontracts.ConditionalPaymentContract.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Smartcontracts.ConditionalPaymentContract do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :id, 1, type: :string
  field :payer_id, 2, type: :string, json_name: "payerId"
  field :receiver_id, 3, type: :string, json_name: "receiverId"
  field :amount_cents, 4, type: :int64, json_name: "amountCents"
  field :condition_type, 5, type: :string, json_name: "conditionType"
  field :trigger, 6, type: :string

  field :condition_parameters, 7,
    repeated: true,
    type: Scalegraph.Smartcontracts.ConditionalPaymentContract.ConditionParametersEntry,
    json_name: "conditionParameters",
    map: true

  field :status, 8, type: :string
  field :ledger_transaction_id, 9, type: :string, json_name: "ledgerTransactionId"
  field :created_at, 10, type: :int64, json_name: "createdAt"
  field :executed_at, 11, type: :int64, json_name: "executedAt"

  field :metadata, 12,
    repeated: true,
    type: Scalegraph.Smartcontracts.ConditionalPaymentContract.MetadataEntry,
    map: true
end

defmodule Scalegraph.Smartcontracts.RevenueShareParty do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :participant_id, 1, type: :string, json_name: "participantId"
  field :share, 2, type: :double
end

defmodule Scalegraph.Smartcontracts.RevenueShareContract.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Smartcontracts.RevenueShareContract do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :id, 1, type: :string
  field :transaction_type, 2, type: :string, json_name: "transactionType"
  field :parties, 3, repeated: true, type: Scalegraph.Smartcontracts.RevenueShareParty
  field :auto_split, 4, type: :bool, json_name: "autoSplit"
  field :status, 5, type: :string

  field :distribution_transaction_ids, 6,
    repeated: true,
    type: :string,
    json_name: "distributionTransactionIds"

  field :created_at, 7, type: :int64, json_name: "createdAt"
  field :last_distributed_at, 8, type: :int64, json_name: "lastDistributedAt"

  field :metadata, 9,
    repeated: true,
    type: Scalegraph.Smartcontracts.RevenueShareContract.MetadataEntry,
    map: true
end

defmodule Scalegraph.Smartcontracts.CreateInvoiceContractRequest.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Smartcontracts.CreateInvoiceContractRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :supplier_id, 1, type: :string, json_name: "supplierId"
  field :buyer_id, 2, type: :string, json_name: "buyerId"
  field :amount_cents, 3, type: :int64, json_name: "amountCents"
  field :issue_date, 4, type: :int64, json_name: "issueDate"
  field :due_date, 5, type: :int64, json_name: "dueDate"
  field :payment_terms, 6, type: :string, json_name: "paymentTerms"
  field :auto_debit, 7, type: :bool, json_name: "autoDebit"
  field :late_fee_cents, 8, type: :int64, json_name: "lateFeeCents"
  field :reference, 9, type: :string

  field :metadata, 10,
    repeated: true,
    type: Scalegraph.Smartcontracts.CreateInvoiceContractRequest.MetadataEntry,
    map: true
end

defmodule Scalegraph.Smartcontracts.CreateSubscriptionContractRequest.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Smartcontracts.CreateSubscriptionContractRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :provider_id, 1, type: :string, json_name: "providerId"
  field :subscriber_id, 2, type: :string, json_name: "subscriberId"
  field :monthly_fee_cents, 3, type: :int64, json_name: "monthlyFeeCents"
  field :billing_date, 4, type: :string, json_name: "billingDate"
  field :auto_debit, 5, type: :bool, json_name: "autoDebit"
  field :cancellation_notice_days, 6, type: :int32, json_name: "cancellationNoticeDays"
  field :start_date, 7, type: :int64, json_name: "startDate"
  field :end_date, 8, type: :int64, json_name: "endDate"

  field :metadata, 9,
    repeated: true,
    type: Scalegraph.Smartcontracts.CreateSubscriptionContractRequest.MetadataEntry,
    map: true
end

defmodule Scalegraph.Smartcontracts.CreateConditionalPaymentRequest.ConditionParametersEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Smartcontracts.CreateConditionalPaymentRequest.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Smartcontracts.CreateConditionalPaymentRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :payer_id, 1, type: :string, json_name: "payerId"
  field :receiver_id, 2, type: :string, json_name: "receiverId"
  field :amount_cents, 3, type: :int64, json_name: "amountCents"
  field :condition_type, 4, type: :string, json_name: "conditionType"
  field :trigger, 5, type: :string

  field :condition_parameters, 6,
    repeated: true,
    type: Scalegraph.Smartcontracts.CreateConditionalPaymentRequest.ConditionParametersEntry,
    json_name: "conditionParameters",
    map: true

  field :metadata, 7,
    repeated: true,
    type: Scalegraph.Smartcontracts.CreateConditionalPaymentRequest.MetadataEntry,
    map: true
end

defmodule Scalegraph.Smartcontracts.CreateRevenueShareContractRequest.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Smartcontracts.CreateRevenueShareContractRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :transaction_type, 1, type: :string, json_name: "transactionType"
  field :parties, 2, repeated: true, type: Scalegraph.Smartcontracts.RevenueShareParty
  field :auto_split, 3, type: :bool, json_name: "autoSplit"

  field :metadata, 4,
    repeated: true,
    type: Scalegraph.Smartcontracts.CreateRevenueShareContractRequest.MetadataEntry,
    map: true
end

defmodule Scalegraph.Smartcontracts.GetContractRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :contract_id, 1, type: :string, json_name: "contractId"

  field :contract_type, 2,
    type: Scalegraph.Smartcontracts.ContractType,
    json_name: "contractType",
    enum: true
end

defmodule Scalegraph.Smartcontracts.ListContractsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :contract_type, 1,
    type: Scalegraph.Smartcontracts.ContractType,
    json_name: "contractType",
    enum: true

  field :status, 2, type: :string
  field :participant_id, 3, type: :string, json_name: "participantId"
  field :limit, 4, type: :int32
end

defmodule Scalegraph.Smartcontracts.ContractResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof :contract, 0

  field :invoice, 1, type: Scalegraph.Smartcontracts.InvoiceContract, oneof: 0
  field :subscription, 2, type: Scalegraph.Smartcontracts.SubscriptionContract, oneof: 0

  field :conditional_payment, 3,
    type: Scalegraph.Smartcontracts.ConditionalPaymentContract,
    json_name: "conditionalPayment",
    oneof: 0

  field :revenue_share, 4,
    type: Scalegraph.Smartcontracts.RevenueShareContract,
    json_name: "revenueShare",
    oneof: 0
end

defmodule Scalegraph.Smartcontracts.ListContractsResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :contracts, 1, repeated: true, type: Scalegraph.Smartcontracts.ContractResponse
end

defmodule Scalegraph.Smartcontracts.ExecuteContractRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :contract_id, 1, type: :string, json_name: "contractId"

  field :contract_type, 2,
    type: Scalegraph.Smartcontracts.ContractType,
    json_name: "contractType",
    enum: true
end

defmodule Scalegraph.Smartcontracts.ExecuteContractResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :contract_id, 1, type: :string, json_name: "contractId"
  field :executed, 2, type: :bool
  field :message, 3, type: :string
  field :transaction_ids, 4, repeated: true, type: :string, json_name: "transactionIds"
end

defmodule Scalegraph.Smartcontracts.UpdateContractStatusRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :contract_id, 1, type: :string, json_name: "contractId"

  field :contract_type, 2,
    type: Scalegraph.Smartcontracts.ContractType,
    json_name: "contractType",
    enum: true

  field :status, 3, type: Scalegraph.Smartcontracts.ContractStatus, enum: true
end

defmodule Scalegraph.Smartcontracts.SmartContractService.Service do
  @moduledoc false

  use GRPC.Service,
    name: "scalegraph.smartcontracts.SmartContractService",
    protoc_gen_elixir_version: "0.15.0"

  rpc :CreateInvoiceContract,
      Scalegraph.Smartcontracts.CreateInvoiceContractRequest,
      Scalegraph.Smartcontracts.InvoiceContract

  rpc :GetInvoiceContract,
      Scalegraph.Smartcontracts.GetContractRequest,
      Scalegraph.Smartcontracts.InvoiceContract

  rpc :CreateSubscriptionContract,
      Scalegraph.Smartcontracts.CreateSubscriptionContractRequest,
      Scalegraph.Smartcontracts.SubscriptionContract

  rpc :GetSubscriptionContract,
      Scalegraph.Smartcontracts.GetContractRequest,
      Scalegraph.Smartcontracts.SubscriptionContract

  rpc :CreateConditionalPayment,
      Scalegraph.Smartcontracts.CreateConditionalPaymentRequest,
      Scalegraph.Smartcontracts.ConditionalPaymentContract

  rpc :GetConditionalPayment,
      Scalegraph.Smartcontracts.GetContractRequest,
      Scalegraph.Smartcontracts.ConditionalPaymentContract

  rpc :CreateRevenueShareContract,
      Scalegraph.Smartcontracts.CreateRevenueShareContractRequest,
      Scalegraph.Smartcontracts.RevenueShareContract

  rpc :GetRevenueShareContract,
      Scalegraph.Smartcontracts.GetContractRequest,
      Scalegraph.Smartcontracts.RevenueShareContract

  rpc :GetContract,
      Scalegraph.Smartcontracts.GetContractRequest,
      Scalegraph.Smartcontracts.ContractResponse

  rpc :ListContracts,
      Scalegraph.Smartcontracts.ListContractsRequest,
      Scalegraph.Smartcontracts.ListContractsResponse

  rpc :ExecuteContract,
      Scalegraph.Smartcontracts.ExecuteContractRequest,
      Scalegraph.Smartcontracts.ExecuteContractResponse

  rpc :UpdateContractStatus,
      Scalegraph.Smartcontracts.UpdateContractStatusRequest,
      Scalegraph.Smartcontracts.ContractResponse
end

defmodule Scalegraph.Smartcontracts.SmartContractService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Scalegraph.Smartcontracts.SmartContractService.Service
end
