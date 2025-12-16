defmodule Scalegraph.Business.CreateParticipantRequest.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Business.CreateParticipantRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :id, 1, type: :string
  field :name, 2, type: :string
  field :role, 3, type: Scalegraph.Common.ParticipantRole, enum: true

  field :metadata, 4,
    repeated: true,
    type: Scalegraph.Business.CreateParticipantRequest.MetadataEntry,
    map: true

  field :about, 5, type: :string
  field :contact, 6, type: Scalegraph.Common.Contact
end

defmodule Scalegraph.Business.GetParticipantRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :participant_id, 1, type: :string, json_name: "participantId"
end

defmodule Scalegraph.Business.ListParticipantsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :role, 1, type: Scalegraph.Common.ParticipantRole, enum: true
end

defmodule Scalegraph.Business.ListParticipantsResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :participants, 1, repeated: true, type: Scalegraph.Common.Participant
end

defmodule Scalegraph.Business.CreateParticipantAccountRequest.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Business.CreateParticipantAccountRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :participant_id, 1, type: :string, json_name: "participantId"

  field :account_type, 2,
    type: Scalegraph.Common.AccountType,
    json_name: "accountType",
    enum: true

  field :initial_balance, 3, type: :int64, json_name: "initialBalance"

  field :metadata, 4,
    repeated: true,
    type: Scalegraph.Business.CreateParticipantAccountRequest.MetadataEntry,
    map: true
end

defmodule Scalegraph.Business.GetParticipantAccountsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :participant_id, 1, type: :string, json_name: "participantId"
end

defmodule Scalegraph.Business.GetParticipantAccountsResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :accounts, 1, repeated: true, type: Scalegraph.Common.Account
end

defmodule Scalegraph.Business.AddServiceRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :participant_id, 1, type: :string, json_name: "participantId"
  field :service_id, 2, type: :string, json_name: "serviceId"
end

defmodule Scalegraph.Business.RemoveServiceRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :participant_id, 1, type: :string, json_name: "participantId"
  field :service_id, 2, type: :string, json_name: "serviceId"
end

defmodule Scalegraph.Business.ListServicesRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :participant_id, 1, type: :string, json_name: "participantId"
end

defmodule Scalegraph.Business.ListServicesResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :services, 1, repeated: true, type: :string
end

defmodule Scalegraph.Business.BusinessTransactionResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :transaction_id, 1, type: :string, json_name: "transactionId"
  field :reference, 2, type: :string
  field :amount, 3, type: :int64
  field :platform_fee, 4, type: :int64, json_name: "platformFee"
  field :status, 5, type: :string
  field :message, 6, type: :string
end

defmodule Scalegraph.Business.PurchaseInvoiceRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :supplier_id, 1, type: :string, json_name: "supplierId"
  field :buyer_id, 2, type: :string, json_name: "buyerId"
  field :amount, 3, type: :int64
  field :reference, 4, type: :string
end

defmodule Scalegraph.Business.PayInvoiceRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :supplier_id, 1, type: :string, json_name: "supplierId"
  field :buyer_id, 2, type: :string, json_name: "buyerId"
  field :amount, 3, type: :int64
  field :reference, 4, type: :string
end

defmodule Scalegraph.Business.GetInvoiceRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :invoice_id, 1, type: :string, json_name: "invoiceId"
end

defmodule Scalegraph.Business.Invoice.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Business.Invoice do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :id, 1, type: :string
  field :supplier_id, 2, type: :string, json_name: "supplierId"
  field :buyer_id, 3, type: :string, json_name: "buyerId"
  field :amount, 4, type: :int64
  field :issue_date, 5, type: :int64, json_name: "issueDate"
  field :due_date, 6, type: :int64, json_name: "dueDate"
  field :status, 7, type: :string
  field :ledger_transaction_id, 8, type: :string, json_name: "ledgerTransactionId"
  field :reference, 9, type: :string
  field :created_at, 10, type: :int64, json_name: "createdAt"
  field :paid_at, 11, type: :int64, json_name: "paidAt"
  field :metadata, 12, repeated: true, type: Scalegraph.Business.Invoice.MetadataEntry, map: true
end

defmodule Scalegraph.Business.ListInvoicesRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :supplier_id, 1, type: :string, json_name: "supplierId"
  field :buyer_id, 2, type: :string, json_name: "buyerId"
  field :status, 3, type: :string
  field :limit, 4, type: :int32
end

defmodule Scalegraph.Business.ListInvoicesResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :invoices, 1, repeated: true, type: Scalegraph.Business.Invoice
end

defmodule Scalegraph.Business.CreateLoanRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :lender_id, 1, type: :string, json_name: "lenderId"
  field :borrower_id, 2, type: :string, json_name: "borrowerId"
  field :principal_cents, 3, type: :int64, json_name: "principalCents"
  field :annual_interest_rate, 4, type: :double, json_name: "annualInterestRate"
  field :term_months, 5, type: :int32, json_name: "termMonths"
  field :reference, 6, type: :string
end

defmodule Scalegraph.Business.RepayLoanRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :lender_id, 1, type: :string, json_name: "lenderId"
  field :borrower_id, 2, type: :string, json_name: "borrowerId"
  field :amount, 3, type: :int64
  field :reference, 4, type: :string
end

defmodule Scalegraph.Business.GetLoanRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :loan_id, 1, type: :string, json_name: "loanId"
end

defmodule Scalegraph.Business.LoanRepaymentSchedule do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :due_date, 1, type: :int64, json_name: "dueDate"
  field :amount_cents, 2, type: :int64, json_name: "amountCents"
  field :paid, 3, type: :bool
  field :payment_transaction_id, 4, type: :string, json_name: "paymentTransactionId"
end

defmodule Scalegraph.Business.Loan.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Business.Loan do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :id, 1, type: :string
  field :lender_id, 2, type: :string, json_name: "lenderId"
  field :borrower_id, 3, type: :string, json_name: "borrowerId"
  field :principal_cents, 4, type: :int64, json_name: "principalCents"
  field :annual_interest_rate, 5, type: :double, json_name: "annualInterestRate"
  field :term_months, 6, type: :int32, json_name: "termMonths"
  field :monthly_payment_cents, 7, type: :int64, json_name: "monthlyPaymentCents"
  field :first_payment_due, 8, type: :int64, json_name: "firstPaymentDue"

  field :repayment_schedule, 9,
    repeated: true,
    type: Scalegraph.Business.LoanRepaymentSchedule,
    json_name: "repaymentSchedule"

  field :status, 10, type: :string
  field :disbursement_transaction_id, 11, type: :string, json_name: "disbursementTransactionId"

  field :repayment_transaction_ids, 12,
    repeated: true,
    type: :string,
    json_name: "repaymentTransactionIds"

  field :reference, 13, type: :string
  field :created_at, 14, type: :int64, json_name: "createdAt"
  field :auto_execute, 15, type: :bool, json_name: "autoExecute"
  field :metadata, 16, repeated: true, type: Scalegraph.Business.Loan.MetadataEntry, map: true
end

defmodule Scalegraph.Business.ListLoansRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :lender_id, 1, type: :string, json_name: "lenderId"
  field :borrower_id, 2, type: :string, json_name: "borrowerId"
  field :status, 3, type: :string
  field :limit, 4, type: :int32
end

defmodule Scalegraph.Business.ListLoansResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :loans, 1, repeated: true, type: Scalegraph.Business.Loan
end

defmodule Scalegraph.Business.GetOutstandingLoansRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :lender_id, 1, type: :string, json_name: "lenderId"
end

defmodule Scalegraph.Business.GetOutstandingLoansResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :lender_id, 1, type: :string, json_name: "lenderId"
  field :total_outstanding, 2, type: :int64, json_name: "totalOutstanding"
end

defmodule Scalegraph.Business.GetTotalDebtRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :borrower_id, 1, type: :string, json_name: "borrowerId"
end

defmodule Scalegraph.Business.GetTotalDebtResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :borrower_id, 1, type: :string, json_name: "borrowerId"
  field :total_debt, 2, type: :int64, json_name: "totalDebt"
end

defmodule Scalegraph.Business.AccessPaymentRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :payer_id, 1, type: :string, json_name: "payerId"
  field :access_provider_id, 2, type: :string, json_name: "accessProviderId"
  field :amount, 3, type: :int64
  field :reference, 4, type: :string
  field :platform_id, 5, type: :string, json_name: "platformId"
  field :platform_fee, 6, type: :int64, json_name: "platformFee"
end

defmodule Scalegraph.Business.ParticipantService.Service do
  @moduledoc false

  use GRPC.Service,
    name: "scalegraph.business.ParticipantService",
    protoc_gen_elixir_version: "0.15.0"

  rpc :CreateParticipant,
      Scalegraph.Business.CreateParticipantRequest,
      Scalegraph.Common.Participant

  rpc :GetParticipant, Scalegraph.Business.GetParticipantRequest, Scalegraph.Common.Participant

  rpc :ListParticipants,
      Scalegraph.Business.ListParticipantsRequest,
      Scalegraph.Business.ListParticipantsResponse

  rpc :CreateParticipantAccount,
      Scalegraph.Business.CreateParticipantAccountRequest,
      Scalegraph.Common.Account

  rpc :GetParticipantAccounts,
      Scalegraph.Business.GetParticipantAccountsRequest,
      Scalegraph.Business.GetParticipantAccountsResponse

  rpc :AddService, Scalegraph.Business.AddServiceRequest, Scalegraph.Common.Participant

  rpc :RemoveService, Scalegraph.Business.RemoveServiceRequest, Scalegraph.Common.Participant

  rpc :ListServices,
      Scalegraph.Business.ListServicesRequest,
      Scalegraph.Business.ListServicesResponse
end

defmodule Scalegraph.Business.ParticipantService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Scalegraph.Business.ParticipantService.Service
end

defmodule Scalegraph.Business.BusinessService.Service do
  @moduledoc false

  use GRPC.Service,
    name: "scalegraph.business.BusinessService",
    protoc_gen_elixir_version: "0.15.0"

  rpc :PurchaseInvoice,
      Scalegraph.Business.PurchaseInvoiceRequest,
      Scalegraph.Business.BusinessTransactionResponse

  rpc :PayInvoice,
      Scalegraph.Business.PayInvoiceRequest,
      Scalegraph.Business.BusinessTransactionResponse

  rpc :GetInvoice, Scalegraph.Business.GetInvoiceRequest, Scalegraph.Business.Invoice

  rpc :ListInvoices,
      Scalegraph.Business.ListInvoicesRequest,
      Scalegraph.Business.ListInvoicesResponse

  rpc :CreateLoan,
      Scalegraph.Business.CreateLoanRequest,
      Scalegraph.Business.BusinessTransactionResponse

  rpc :RepayLoan,
      Scalegraph.Business.RepayLoanRequest,
      Scalegraph.Business.BusinessTransactionResponse

  rpc :GetLoan, Scalegraph.Business.GetLoanRequest, Scalegraph.Business.Loan

  rpc :ListLoans, Scalegraph.Business.ListLoansRequest, Scalegraph.Business.ListLoansResponse

  rpc :GetOutstandingLoans,
      Scalegraph.Business.GetOutstandingLoansRequest,
      Scalegraph.Business.GetOutstandingLoansResponse

  rpc :GetTotalDebt,
      Scalegraph.Business.GetTotalDebtRequest,
      Scalegraph.Business.GetTotalDebtResponse

  rpc :AccessPayment,
      Scalegraph.Business.AccessPaymentRequest,
      Scalegraph.Business.BusinessTransactionResponse
end

defmodule Scalegraph.Business.BusinessService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Scalegraph.Business.BusinessService.Service
end
