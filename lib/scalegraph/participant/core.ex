defmodule Scalegraph.Participant.Core do
  @moduledoc """
  Core participant operations.

  Participants are organizations in the ecosystem with specific roles:
  - :access_provider - provides access control (e.g., ASSA ABLOY)
  - :banking_partner - handles payments/banking (e.g., SEB)
  - :ecosystem_partner - platform operators (e.g., Beauty Hosting)
  - :supplier - product suppliers (e.g., Schampo etc, Clipper Oy)
  - :equipment_provider - equipment with pay-per-use (e.g., Hairgrowers United)
  """

  alias Scalegraph.Storage.Schema

  @doc """
  Create a new participant.

  ## Parameters
  - id: unique identifier
  - name: display name
  - role: one of the valid participant roles
  - metadata: optional map of additional data

  ## Example
      create_participant("assa_abloy", "ASSA ABLOY", :access_provider)
  """
  def create_participant(id, name, role, metadata \\ %{})
      when is_binary(id) and is_binary(name) and is_atom(role) do
    unless role in Schema.participant_roles() do
      {:error, {:invalid_role, role, Schema.participant_roles()}}
    else
      created_at = System.system_time(:millisecond)

      result =
        :mnesia.transaction(fn ->
          case :mnesia.read(Schema.participants_table(), id) do
            [] ->
              services = []

              record =
                {Schema.participants_table(), id, name, role, created_at, metadata, services}

              :mnesia.write(record)

              {:ok,
               %{
                 id: id,
                 name: name,
                 role: role,
                 created_at: created_at,
                 metadata: metadata,
                 services: services
               }}

            [_existing] ->
              :mnesia.abort({:error, :participant_exists})
          end
        end)

      case result do
        {:atomic, {:ok, participant}} ->
          {:ok, participant}

        {:aborted, {:error, reason}} ->
          {:error, reason}

        {:aborted, {:bad_type, record}} ->
          {:error,
           {:schema_mismatch,
            "Table schema mismatch. Record: #{inspect(record)}. Expected 6 attributes: [:id, :name, :role, :created_at, :metadata, :services]. The table may need to be recreated with the correct schema."}}

        {:aborted, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Get a participant by ID.
  """
  def get_participant(id) when is_binary(id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Schema.participants_table(), id) do
          # Handle both old format (5 fields) and new format (6 fields) for backward compatibility
          [{_table, id, name, role, created_at, metadata}] ->
            services = []

            {:ok,
             %{
               id: id,
               name: name,
               role: role,
               created_at: created_at,
               metadata: metadata,
               services: services
             }}

          [{_table, id, name, role, created_at, metadata, services}] ->
            {:ok,
             %{
               id: id,
               name: name,
               role: role,
               created_at: created_at,
               metadata: metadata,
               services: services || []
             }}

          [] ->
            {:error, :not_found}
        end
      end)

    case result do
      {:atomic, result} -> result
      {:aborted, reason} -> {:error, reason}
    end
  end

  @doc """
  List all participants, optionally filtered by role.
  """
  def list_participants(role \\ nil) do
    result =
      :mnesia.transaction(fn ->
        :mnesia.foldl(
          fn record, acc ->
            # Handle both old format (5 fields) and new format (6 fields)
            {id, name, r, created_at, metadata, services} =
              case record do
                {_table, i, n, ro, ca, m} -> {i, n, ro, ca, m, []}
                {_table, i, n, ro, ca, m, s} -> {i, n, ro, ca, m, s || []}
              end

            if role == nil or r == role do
              [
                %{
                  id: id,
                  name: name,
                  role: r,
                  created_at: created_at,
                  metadata: metadata,
                  services: services
                }
                | acc
              ]
            else
              acc
            end
          end,
          [],
          Schema.participants_table()
        )
      end)

    case result do
      {:atomic, participants} -> {:ok, Enum.reverse(participants)}
      {:aborted, reason} -> {:error, reason}
    end
  end

  @doc """
  Get all accounts belonging to a participant.
  """
  def get_participant_accounts(participant_id) when is_binary(participant_id) do
    result =
      :mnesia.transaction(fn ->
        # Use the secondary index on participant_id
        :mnesia.index_read(Schema.accounts_table(), participant_id, :participant_id)
        |> Enum.map(fn {_table, id, ^participant_id, account_type, balance, created_at, metadata} ->
          %{
            id: id,
            participant_id: participant_id,
            account_type: account_type,
            balance: balance,
            created_at: created_at,
            metadata: metadata
          }
        end)
      end)

    case result do
      {:atomic, accounts} -> {:ok, accounts}
      {:aborted, reason} -> {:error, reason}
    end
  end

  @doc """
  Create an account for a participant.

  ## Account types
  - :operating - main operating account
  - :receivables - for incoming payments
  - :payables - for outgoing payments
  - :escrow - held funds
  - :fees - fee collection
  - :usage - for pay-per-use tracking
  """
  def create_participant_account(
        participant_id,
        account_type,
        initial_balance \\ 0,
        metadata \\ %{}
      )
      when is_binary(participant_id) and is_atom(account_type) and is_integer(initial_balance) do
    account_id = "#{participant_id}:#{account_type}"
    created_at = System.system_time(:millisecond)

    result =
      :mnesia.transaction(fn ->
        # Verify participant exists
        case :mnesia.read(Schema.participants_table(), participant_id) do
          [] ->
            :mnesia.abort({:error, :participant_not_found})

          [_participant] ->
            # Check account doesn't exist
            case :mnesia.read(Schema.accounts_table(), account_id) do
              [] ->
                record =
                  {Schema.accounts_table(), account_id, participant_id, account_type,
                   initial_balance, created_at, metadata}

                :mnesia.write(record)

                {:ok,
                 %{
                   id: account_id,
                   participant_id: participant_id,
                   account_type: account_type,
                   balance: initial_balance,
                   created_at: created_at,
                   metadata: metadata
                 }}

              [_existing] ->
                :mnesia.abort({:error, :account_exists})
            end
        end
      end)

    case result do
      {:atomic, {:ok, account}} -> {:ok, account}
      {:aborted, {:error, reason}} -> {:error, reason}
      {:aborted, reason} -> {:error, reason}
    end
  end

  @doc """
  Add a service to a participant's service list.

  Services are identifiers for capabilities the participant provides
  (e.g., "access_control", "payment_processing", "equipment_rental").
  """
  def add_service(participant_id, service_id)
      when is_binary(participant_id) and is_binary(service_id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Schema.participants_table(), participant_id) do
          [] ->
            :mnesia.abort({:error, :not_found})

          # Handle old format (5 fields)
          [{_table, id, name, role, created_at, metadata}] ->
            services = [service_id]
            record = {Schema.participants_table(), id, name, role, created_at, metadata, services}
            :mnesia.write(record)

            {:ok,
             %{
               id: id,
               name: name,
               role: role,
               created_at: created_at,
               metadata: metadata,
               services: services
             }}

          # Handle new format (6 fields)
          [{_table, id, name, role, created_at, metadata, existing_services}] ->
            services = existing_services || []

            if service_id in services do
              :mnesia.abort({:error, :service_exists})
            else
              updated_services = [service_id | services]

              record =
                {Schema.participants_table(), id, name, role, created_at, metadata,
                 updated_services}

              :mnesia.write(record)

              {:ok,
               %{
                 id: id,
                 name: name,
                 role: role,
                 created_at: created_at,
                 metadata: metadata,
                 services: updated_services
               }}
            end
        end
      end)

    case result do
      {:atomic, {:ok, participant}} ->
        {:ok, participant}

      {:aborted, {:error, reason}} ->
        {:error, reason}

      {:aborted, {:bad_type, record}} ->
        {:error,
         {:schema_mismatch,
          "Table schema mismatch. Record: #{inspect(record)}. Expected 6 attributes: [:id, :name, :role, :created_at, :metadata, :services]. The table may need to be recreated with the correct schema."}}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Remove a service from a participant's service list.
  """
  def remove_service(participant_id, service_id)
      when is_binary(participant_id) and is_binary(service_id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Schema.participants_table(), participant_id) do
          [] ->
            :mnesia.abort({:error, :not_found})

          # Handle old format (5 fields)
          [{_table, _id, _name, _role, _created_at, _metadata}] ->
            :mnesia.abort({:error, :service_not_found})

          # Handle new format (6 fields)
          [{_table, id, name, role, created_at, metadata, services}] ->
            services = services || []

            if service_id not in services do
              :mnesia.abort({:error, :service_not_found})
            else
              updated_services = List.delete(services, service_id)

              record =
                {Schema.participants_table(), id, name, role, created_at, metadata,
                 updated_services}

              :mnesia.write(record)

              {:ok,
               %{
                 id: id,
                 name: name,
                 role: role,
                 created_at: created_at,
                 metadata: metadata,
                 services: updated_services
               }}
            end
        end
      end)

    case result do
      {:atomic, {:ok, participant}} ->
        {:ok, participant}

      {:aborted, {:error, reason}} ->
        {:error, reason}

      {:aborted, {:bad_type, record}} ->
        {:error,
         {:schema_mismatch,
          "Table schema mismatch. Record: #{inspect(record)}. Expected 6 attributes: [:id, :name, :role, :created_at, :metadata, :services]. The table may need to be recreated with the correct schema."}}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc """
  List all services provided by a participant.
  """
  def list_services(participant_id) when is_binary(participant_id) do
    case get_participant(participant_id) do
      {:ok, participant} -> {:ok, participant.services || []}
      error -> error
    end
  end
end
