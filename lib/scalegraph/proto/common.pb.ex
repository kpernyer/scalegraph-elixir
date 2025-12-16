defmodule Scalegraph.Common.ParticipantRole do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :PARTICIPANT_ROLE_UNSPECIFIED, 0
  field :ACCESS_PROVIDER, 1
  field :BANKING_PARTNER, 2
  field :ECOSYSTEM_PARTNER, 3
  field :SUPPLIER, 4
  field :EQUIPMENT_PROVIDER, 5
  field :ECOSYSTEM_ORCHESTRATOR, 6
end

defmodule Scalegraph.Common.AccountType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :ACCOUNT_TYPE_UNSPECIFIED, 0
  field :STANDALONE, 1
  field :OPERATING, 2
  field :RECEIVABLES, 3
  field :PAYABLES, 4
  field :ESCROW, 5
  field :FEES, 6
  field :USAGE, 7
end

defmodule Scalegraph.Common.Contact do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :email, 1, type: :string
  field :phone, 2, type: :string
  field :website, 3, type: :string
  field :address, 4, type: :string
  field :postal_code, 5, type: :string, json_name: "postalCode"
  field :city, 6, type: :string
  field :country, 7, type: :string
end

defmodule Scalegraph.Common.Participant.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Common.Participant do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :id, 1, type: :string
  field :name, 2, type: :string
  field :role, 3, type: Scalegraph.Common.ParticipantRole, enum: true
  field :created_at, 4, type: :int64, json_name: "createdAt"
  field :metadata, 5, repeated: true, type: Scalegraph.Common.Participant.MetadataEntry, map: true
  field :services, 6, repeated: true, type: :string
  field :about, 7, type: :string
  field :contact, 8, type: Scalegraph.Common.Contact
end

defmodule Scalegraph.Common.Account.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Scalegraph.Common.Account do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :id, 1, type: :string
  field :participant_id, 2, type: :string, json_name: "participantId"

  field :account_type, 3,
    type: Scalegraph.Common.AccountType,
    json_name: "accountType",
    enum: true

  field :balance, 4, type: :int64
  field :created_at, 5, type: :int64, json_name: "createdAt"
  field :metadata, 6, repeated: true, type: Scalegraph.Common.Account.MetadataEntry, map: true
end

defmodule Scalegraph.Common.TransferEntry do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :account_id, 1, type: :string, json_name: "accountId"
  field :amount, 2, type: :int64
end

defmodule Scalegraph.Common.Transaction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :id, 1, type: :string
  field :type, 2, type: :string
  field :entries, 3, repeated: true, type: Scalegraph.Common.TransferEntry
  field :timestamp, 4, type: :int64
  field :reference, 5, type: :string
end

defmodule Scalegraph.Common.ErrorResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :code, 1, type: :string
  field :message, 2, type: :string
end
