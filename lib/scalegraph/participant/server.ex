defmodule Scalegraph.Participant.Server do
  @moduledoc """
  gRPC server implementation for the Participant service.

  Business errors (not_found, already_exists, invalid_argument) are returned
  as gRPC error tuples and logged at info level.

  System errors are raised as exceptions and logged at error level.
  """

  use GRPC.Server, service: Scalegraph.Business.ParticipantService.Service

  require Logger

  alias Scalegraph.Participant.Core
  alias Scalegraph.Common
  alias Scalegraph.Business

  # Role mapping from proto enum to internal atoms
  @role_mapping %{
    :ACCESS_PROVIDER => :access_provider,
    :BANKING_PARTNER => :banking_partner,
    :ECOSYSTEM_PARTNER => :ecosystem_partner,
    :SUPPLIER => :supplier,
    :EQUIPMENT_PROVIDER => :equipment_provider,
    :ECOSYSTEM_ORCHESTRATOR => :ecosystem_orchestrator
  }

  @reverse_role_mapping Map.new(@role_mapping, fn {k, v} -> {v, k} end)

  # Account type mapping
  @account_type_mapping %{
    :STANDALONE => :standalone,
    :OPERATING => :operating,
    :RECEIVABLES => :receivables,
    :PAYABLES => :payables,
    :ESCROW => :escrow,
    :FEES => :fees,
    :USAGE => :usage
  }

  @reverse_account_type_mapping Map.new(@account_type_mapping, fn {k, v} -> {v, k} end)

  @doc """
  Create a new participant.
  """
  def create_participant(request, _stream) do
    role = Map.get(@role_mapping, request.role, :ecosystem_partner)
    metadata = Map.new(request.metadata || [])
    about = request.about || ""
    
    # Convert Contact proto to map
    contact = if request.contact do
      %{
        email: request.contact.email || "",
        phone: request.contact.phone || "",
        website: request.contact.website || "",
        address: request.contact.address || "",
        postal_code: request.contact.postal_code || "",
        city: request.contact.city || "",
        country: request.contact.country || ""
      }
    else
      %{}
    end

    case Core.create_participant(request.id, request.name, role, metadata, about, contact) do
      {:ok, participant} ->
        Logger.info("Participant created: #{participant.id}")
        participant_to_proto(participant)

      {:error, :participant_exists} ->
        business_error(:already_exists, "Participant already exists: #{request.id}")

      {:error, {:invalid_role, role, valid_roles}} ->
        business_error(:invalid_argument, "Invalid role #{role}. Valid: #{inspect(valid_roles)}")

      {:error, {:schema_mismatch, message}} ->
        Logger.error("Schema mismatch error: #{message}")

        business_error(
          :failed_precondition,
          "Database schema mismatch. The participants table may have been created with an older schema. Try recreating the table or clearing the database."
        )

      {:error, reason} ->
        system_error("Failed to create participant", reason)
    end
  end

  @doc """
  Get participant by ID.
  """
  def get_participant(request, _stream) do
    case Core.get_participant(request.participant_id) do
      {:ok, participant} ->
        participant_to_proto(participant)

      {:error, :not_found} ->
        business_error(:not_found, "Participant not found: #{request.participant_id}")

      {:error, reason} ->
        system_error("Failed to get participant", reason)
    end
  end

  @doc """
  List all participants, optionally filtered by role.
  """
  def list_participants(request, _stream) do
    role_filter =
      if request.role == :PARTICIPANT_ROLE_UNSPECIFIED do
        nil
      else
        Map.get(@role_mapping, request.role)
      end

    case Core.list_participants(role_filter) do
      {:ok, participants} ->
        %Business.ListParticipantsResponse{
          participants: Enum.map(participants, &participant_to_proto/1)
        }

      {:error, reason} ->
        system_error("Failed to list participants", reason)
    end
  end

  @doc """
  Create an account for a participant.
  """
  def create_participant_account(request, _stream) do
    account_type = Map.get(@account_type_mapping, request.account_type, :operating)
    metadata = Map.new(request.metadata || [])

    case Core.create_participant_account(
           request.participant_id,
           account_type,
           request.initial_balance,
           metadata
         ) do
      {:ok, account} ->
        Logger.info("Account created: #{account.id}")
        account_to_proto(account)

      {:error, :participant_not_found} ->
        business_error(:not_found, "Participant not found: #{request.participant_id}")

      {:error, :account_exists} ->
        business_error(
          :already_exists,
          "Account already exists for #{request.participant_id}:#{account_type}"
        )

      {:error, reason} ->
        system_error("Failed to create account", reason)
    end
  end

  @doc """
  Get all accounts for a participant.
  """
  def get_participant_accounts(request, _stream) do
    case Core.get_participant_accounts(request.participant_id) do
      {:ok, accounts} ->
        %Business.GetParticipantAccountsResponse{
          accounts: Enum.map(accounts, &account_to_proto/1)
        }

      {:error, reason} ->
        system_error("Failed to get accounts", reason)
    end
  end

  @doc """
  Add a service to a participant.
  """
  def add_service(request, _stream) do
    case Core.add_service(request.participant_id, request.service_id) do
      {:ok, participant} ->
        Logger.info(
          "Service #{request.service_id} added to participant #{request.participant_id}"
        )

        participant_to_proto(participant)

      {:error, :not_found} ->
        business_error(:not_found, "Participant not found: #{request.participant_id}")

      {:error, :service_exists} ->
        business_error(
          :already_exists,
          "Service #{request.service_id} already declared for participant #{request.participant_id}"
        )

      {:error, {:schema_mismatch, message}} ->
        Logger.error("Schema mismatch error: #{message}")

        business_error(
          :failed_precondition,
          "Database schema mismatch. The participants table may have been created with an older schema. Try recreating the table or clearing the database."
        )

      {:error, reason} ->
        system_error("Failed to add service", reason)
    end
  end

  @doc """
  Remove a service from a participant.
  """
  def remove_service(request, _stream) do
    case Core.remove_service(request.participant_id, request.service_id) do
      {:ok, participant} ->
        Logger.info(
          "Service #{request.service_id} removed from participant #{request.participant_id}"
        )

        participant_to_proto(participant)

      {:error, :not_found} ->
        business_error(:not_found, "Participant not found: #{request.participant_id}")

      {:error, :service_not_found} ->
        business_error(
          :not_found,
          "Service #{request.service_id} not found for participant #{request.participant_id}"
        )

      {:error, {:schema_mismatch, message}} ->
        Logger.error("Schema mismatch error: #{message}")

        business_error(
          :failed_precondition,
          "Database schema mismatch. The participants table may have been created with an older schema. Try recreating the table or clearing the database."
        )

      {:error, reason} ->
        system_error("Failed to remove service", reason)
    end
  end

  @doc """
  List all services provided by a participant.
  """
  def list_services(request, _stream) do
    case Core.list_services(request.participant_id) do
      {:ok, services} ->
        %Business.ListServicesResponse{
          services: services
        }

      {:error, :not_found} ->
        business_error(:not_found, "Participant not found: #{request.participant_id}")

      {:error, reason} ->
        system_error("Failed to list services", reason)
    end
  end

  # Business errors - expected conditions, logged at info level
  defp business_error(status, message) do
    Logger.info("Business error [#{status}]: #{message}")
    raise GRPC.RPCError, status: status, message: message
  end

  # System errors - unexpected conditions, raised as exceptions (logged at error level)
  defp system_error(context, reason) do
    raise GRPC.RPCError, status: :internal, message: "#{context}: #{inspect(reason)}"
  end

  # Private helpers

  defp participant_to_proto(participant) do
    # Convert contact map to Contact proto
    contact_map = participant.contact || %{}
    contact_proto = %Common.Contact{
      email: Map.get(contact_map, :email, "") || Map.get(contact_map, "email", ""),
      phone: Map.get(contact_map, :phone, "") || Map.get(contact_map, "phone", ""),
      website: Map.get(contact_map, :website, "") || Map.get(contact_map, "website", ""),
      address: Map.get(contact_map, :address, "") || Map.get(contact_map, "address", ""),
      postal_code: Map.get(contact_map, :postal_code, "") || Map.get(contact_map, "postal_code", ""),
      city: Map.get(contact_map, :city, "") || Map.get(contact_map, "city", ""),
      country: Map.get(contact_map, :country, "") || Map.get(contact_map, "country", "")
    }
    
    %Common.Participant{
      id: participant.id,
      name: participant.name,
      role: Map.get(@reverse_role_mapping, participant.role, :PARTICIPANT_ROLE_UNSPECIFIED),
      created_at: participant.created_at,
      metadata: participant.metadata || %{},
      services: participant.services || [],
      about: participant.about || "",
      contact: contact_proto
    }
  end

  defp account_to_proto(account) do
    %Common.Account{
      id: account.id,
      participant_id: account.participant_id || "",
      account_type:
        Map.get(@reverse_account_type_mapping, account.account_type, :ACCOUNT_TYPE_UNSPECIFIED),
      balance: account.balance,
      created_at: account.created_at,
      metadata: account.metadata || %{}
    }
  end
end
