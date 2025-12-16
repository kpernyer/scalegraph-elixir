defmodule Scalegraph.Ledger.CreateAccountRequest.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Ledger.CreateAccountRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :account_id, 1, type: :string, json_name: "accountId"
  field :initial_balance, 2, type: :int64, json_name: "initialBalance"

  field :metadata, 3,
    repeated: true,
    type: Scalegraph.Ledger.CreateAccountRequest.MetadataEntry,
    map: true
end

defmodule Scalegraph.Ledger.GetAccountRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :account_id, 1, type: :string, json_name: "accountId"
end

defmodule Scalegraph.Ledger.GetBalanceRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :account_id, 1, type: :string, json_name: "accountId"
end

defmodule Scalegraph.Ledger.GetBalanceResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :account_id, 1, type: :string, json_name: "accountId"
  field :balance, 2, type: :int64
end

defmodule Scalegraph.Ledger.CreditRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :account_id, 1, type: :string, json_name: "accountId"
  field :amount, 2, type: :int64
  field :reference, 3, type: :string
end

defmodule Scalegraph.Ledger.DebitRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :account_id, 1, type: :string, json_name: "accountId"
  field :amount, 2, type: :int64
  field :reference, 3, type: :string
end

defmodule Scalegraph.Ledger.TransferRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :entries, 1, repeated: true, type: Scalegraph.Common.TransferEntry
  field :reference, 2, type: :string
end

defmodule Scalegraph.Ledger.ListTransactionsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :limit, 1, type: :int32
  field :account_id, 2, type: :string, json_name: "accountId"
end

defmodule Scalegraph.Ledger.ListTransactionsResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :transactions, 1, repeated: true, type: Scalegraph.Common.Transaction
end

defmodule Scalegraph.Ledger.LedgerService.Service do
  @moduledoc false

  use GRPC.Service, name: "scalegraph.ledger.LedgerService", protoc_gen_elixir_version: "0.15.0"

  rpc :CreateAccount, Scalegraph.Ledger.CreateAccountRequest, Scalegraph.Common.Account

  rpc :GetAccount, Scalegraph.Ledger.GetAccountRequest, Scalegraph.Common.Account

  rpc :GetBalance, Scalegraph.Ledger.GetBalanceRequest, Scalegraph.Ledger.GetBalanceResponse

  rpc :Credit, Scalegraph.Ledger.CreditRequest, Scalegraph.Common.Transaction

  rpc :Debit, Scalegraph.Ledger.DebitRequest, Scalegraph.Common.Transaction

  rpc :Transfer, Scalegraph.Ledger.TransferRequest, Scalegraph.Common.Transaction

  rpc :ListTransactions,
      Scalegraph.Ledger.ListTransactionsRequest,
      Scalegraph.Ledger.ListTransactionsResponse
end

defmodule Scalegraph.Ledger.LedgerService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Scalegraph.Ledger.LedgerService.Service
end
