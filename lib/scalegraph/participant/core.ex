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
  alias Scalegraph.Ledger.Storage, as: LedgerStorage

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
  def create_participant(id, name, role, metadata \\ %{}, about \\ "", contact \\ %{})
      when is_binary(id) and is_binary(name) and is_atom(role) do
    # Validate role first
    if role in Schema.participant_roles() do
      created_at = System.system_time(:millisecond)

      result =
        :mnesia.transaction(fn ->
          create_participant_record(id, name, role, created_at, metadata, about, contact)
        end)

      handle_participant_creation_result(result)
    else
      {:error, {:invalid_role, role, Schema.participant_roles()}}
    end
  end

  # Private participant creation helpers

  defp create_participant_record(id, name, role, created_at, metadata, about, contact) do
    case :mnesia.read(Schema.participants_table(), id) do
      [] ->
        services = []
        # Ensure contact is a map
        contact_map = if is_map(contact), do: contact, else: %{}
        record = {Schema.participants_table(), id, name, role, created_at, metadata, services, about, contact_map}
        :mnesia.write(record)

        {:ok,
         %{
           id: id,
           name: name,
           role: role,
           created_at: created_at,
           metadata: metadata,
           services: services,
           about: about,
           contact: contact_map
         }}

      [_existing] ->
        :mnesia.abort({:error, :participant_exists})
    end
  end

  defp handle_participant_creation_result({:atomic, {:ok, participant}}) do
    {:ok, participant}
  end

  defp handle_participant_creation_result({:aborted, {:error, reason}}) do
    {:error, reason}
  end

  defp handle_participant_creation_result({:aborted, {:bad_type, record}}) do
    {:error,
     {:schema_mismatch,
      "Table schema mismatch. Record: #{inspect(record)}. Expected 8 attributes: [:id, :name, :role, :created_at, :metadata, :services, :about, :contact]. The table may need to be recreated with the correct schema."}}
  end

  defp handle_participant_creation_result({:aborted, reason}) do
    {:error, reason}
  end

  @doc """
  Get a participant by ID.
  """
  def get_participant(id) when is_binary(id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Schema.participants_table(), id) do
          # Handle old formats for backward compatibility
          [{_table, id, name, role, created_at, metadata}] ->
            {:ok,
             %{
               id: id,
               name: name,
               role: role,
               created_at: created_at,
               metadata: metadata,
               services: [],
               about: "",
               contact: %{}
             }}

          [{_table, id, name, role, created_at, metadata, services}] ->
            {:ok,
             %{
               id: id,
               name: name,
               role: role,
               created_at: created_at,
               metadata: metadata,
               services: services || [],
               about: "",
               contact: %{}
             }}

          [{_table, id, name, role, created_at, metadata, services, about, contact}] ->
            # Handle both old string format and new map format for backward compatibility
            contact_map = cond do
              is_map(contact) -> contact
              is_binary(contact) -> %{}  # Old string format, convert to empty map
              true -> %{}
            end
            
            {:ok,
             %{
               id: id,
               name: name,
               role: role,
               created_at: created_at,
               metadata: metadata,
               services: services || [],
               about: about || "",
               contact: contact_map
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
        collect_participants(role)
      end)

    case result do
      {:atomic, participants} -> {:ok, Enum.reverse(participants)}
      {:aborted, reason} -> {:error, reason}
    end
  end

  defp collect_participants(role) do
    :mnesia.foldl(
      fn record, acc ->
        participant = normalize_participant_record_for_listing(record)

        if should_include_participant?(participant, role) do
          [participant | acc]
        else
          acc
        end
      end,
      [],
      Schema.participants_table()
    )
  end

  # Private participant listing helpers

  defp normalize_participant_record_for_listing({_table, id, name, role, created_at, metadata}) do
    # Old format (5 fields) - add services, about, contact
    %{
      id: id,
      name: name,
      role: role,
      created_at: created_at,
      metadata: metadata,
      services: [],
      about: "",
      contact: %{}
    }
  end

  defp normalize_participant_record_for_listing(
         {_table, id, name, role, created_at, metadata, services}
       ) do
    # Format (6 fields) - add about, contact
    %{
      id: id,
      name: name,
      role: role,
      created_at: created_at,
      metadata: metadata,
      services: services || [],
      about: "",
      contact: %{}
    }
  end

  defp normalize_participant_record_for_listing(
         {_table, id, name, role, created_at, metadata, services, about, contact}
       ) do
    # New format (8 fields) - ensure contact is a map
    contact_map = cond do
      is_map(contact) -> contact
      is_binary(contact) -> %{}  # Old string format
      true -> %{}
    end
    
    %{
      id: id,
      name: name,
      role: role,
      created_at: created_at,
      metadata: metadata,
      services: services || [],
      about: about || "",
      contact: contact_map
    }
  end

  defp should_include_participant?(_participant, nil), do: true

  defp should_include_participant?(participant, role) do
    participant.role == role
  end

  @doc """
  Get all accounts belonging to a participant.
  """
  def get_participant_accounts(participant_id) when is_binary(participant_id) do
    result =
      :mnesia.transaction(fn ->
        # Use the secondary index on participant_id
        :mnesia.index_read(LedgerStorage.accounts_table(), participant_id, :participant_id)
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
        verify_participant_exists(participant_id)

        create_account_record(
          account_id,
          participant_id,
          account_type,
          initial_balance,
          created_at,
          metadata
        )
      end)

    case result do
      {:atomic, {:ok, account}} -> {:ok, account}
      {:aborted, {:error, reason}} -> {:error, reason}
      {:aborted, reason} -> {:error, reason}
    end
  end

  # Private account creation helpers

  defp verify_participant_exists(participant_id) do
    case :mnesia.read(Schema.participants_table(), participant_id) do
      [] -> :mnesia.abort({:error, :participant_not_found})
      [_participant] -> :ok
    end
  end

  defp create_account_record(
         account_id,
         participant_id,
         account_type,
         initial_balance,
         created_at,
         metadata
       ) do
    case :mnesia.read(LedgerStorage.accounts_table(), account_id) do
      [] ->
        record =
          {LedgerStorage.accounts_table(), account_id, participant_id, account_type, initial_balance,
           created_at, metadata}

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

  @doc """
  Add a service to a participant's service list.

  Services are identifiers for capabilities the participant provides
  (e.g., "access_control", "payment_processing", "equipment_rental").
  """
  def add_service(participant_id, service_id)
      when is_binary(participant_id) and is_binary(service_id) do
    result =
      :mnesia.transaction(fn ->
        add_service_to_participant(participant_id, service_id)
      end)

    handle_service_operation_result(result)
  end

  # Private service operation helpers

  defp add_service_to_participant(participant_id, service_id) do
    case :mnesia.read(Schema.participants_table(), participant_id) do
      [] ->
        :mnesia.abort({:error, :not_found})

      # Handle old format (5 fields)
      [{_table, id, name, role, created_at, metadata}] ->
        services = [service_id]
        record = {Schema.participants_table(), id, name, role, created_at, metadata, services, "", %{}}
        :mnesia.write(record)

        {:ok,
         %{
           id: id,
           name: name,
           role: role,
           created_at: created_at,
           metadata: metadata,
           services: services,
           about: "",
           contact: %{}
         }}

      # Handle format (6 fields - services added)
      [{_table, id, name, role, created_at, metadata, existing_services}] ->
        add_service_to_existing_list(
          id,
          name,
          role,
          created_at,
          metadata,
          existing_services,
          service_id,
          "",
          %{}
        )

      # Handle current format (8 fields - with about and contact)
      [{_table, id, name, role, created_at, metadata, existing_services, about, contact}] ->
        contact_map = cond do
          is_map(contact) -> contact
          is_binary(contact) -> %{}  # Old string format
          true -> %{}
        end
        add_service_to_existing_list(
          id,
          name,
          role,
          created_at,
          metadata,
          existing_services,
          service_id,
          about || "",
          contact_map
        )
    end
  end

  defp add_service_to_existing_list(
         id,
         name,
         role,
         created_at,
         metadata,
         existing_services,
         service_id,
         about \\ "",
         contact \\ %{}
       ) do
    services = existing_services || []

    if service_id in services do
      :mnesia.abort({:error, :service_exists})
    else
      updated_services = [service_id | services]

      record =
        {Schema.participants_table(), id, name, role, created_at, metadata, updated_services, about, contact}

      :mnesia.write(record)

      {:ok,
       %{
         id: id,
         name: name,
         role: role,
         created_at: created_at,
         metadata: metadata,
         services: updated_services,
         about: about,
         contact: contact
       }}
    end
  end

  @doc """
  Remove a service from a participant's service list.
  """
  def remove_service(participant_id, service_id)
      when is_binary(participant_id) and is_binary(service_id) do
    result =
      :mnesia.transaction(fn ->
        remove_service_from_participant(participant_id, service_id)
      end)

    handle_service_operation_result(result)
  end

  defp remove_service_from_participant(participant_id, service_id) do
    case :mnesia.read(Schema.participants_table(), participant_id) do
      [] ->
        :mnesia.abort({:error, :not_found})

      # Handle old format (5 fields)
      [{_table, _id, _name, _role, _created_at, _metadata}] ->
        :mnesia.abort({:error, :service_not_found})

      # Handle format (6 fields - services added)
      [{_table, id, name, role, created_at, metadata, services}] ->
        remove_service_from_existing_list(
          id,
          name,
          role,
          created_at,
          metadata,
          services,
          service_id,
          "",
          %{}
        )

      # Handle current format (8 fields - with about and contact)
      [{_table, id, name, role, created_at, metadata, services, about, contact}] ->
        contact_map = cond do
          is_map(contact) -> contact
          is_binary(contact) -> %{}  # Old string format
          true -> %{}
        end
        remove_service_from_existing_list(
          id,
          name,
          role,
          created_at,
          metadata,
          services,
          service_id,
          about || "",
          contact_map
        )
    end
  end

  defp remove_service_from_existing_list(
         id,
         name,
         role,
         created_at,
         metadata,
         services,
         service_id,
         about \\ "",
         contact \\ %{}
       ) do
    services = services || []

    if service_id in services do
      updated_services = List.delete(services, service_id)

      record =
        {Schema.participants_table(), id, name, role, created_at, metadata, updated_services, about, contact}

      :mnesia.write(record)

      {:ok,
       %{
         id: id,
         name: name,
         role: role,
         created_at: created_at,
         metadata: metadata,
         services: updated_services,
         about: about,
         contact: contact
       }}
    else
      :mnesia.abort({:error, :service_not_found})
    end
  end

  defp handle_service_operation_result({:atomic, {:ok, participant}}) do
    {:ok, participant}
  end

  defp handle_service_operation_result({:aborted, {:error, reason}}) do
    {:error, reason}
  end

  defp handle_service_operation_result({:aborted, {:bad_type, record}}) do
    {:error,
     {:schema_mismatch,
      "Table schema mismatch. Record: #{inspect(record)}. Expected 8 attributes: [:id, :name, :role, :created_at, :metadata, :services, :about, :contact]. The table may need to be recreated with the correct schema."}}
  end

  defp handle_service_operation_result({:aborted, reason}) do
    {:error, reason}
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
