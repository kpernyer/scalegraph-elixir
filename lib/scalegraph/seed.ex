defmodule Scalegraph.Seed do
  @moduledoc """
  Seed data loader for the Scalegraph ledger.

  Reads participant and account data from `priv/seed_data.yaml` and
  populates the database on startup.
  """

  require Logger

  alias Scalegraph.Participant.Core, as: Participant
  alias Scalegraph.Storage.Schema

  @seed_file "priv/seed_data.yaml"

  @doc """
  Load and seed all participants and accounts from the YAML file.
  """
  def run do
    case load_seed_file() do
      {:ok, data} ->
        seed_participants(data["participants"] || [])

      {:error, reason} ->
        Logger.error("Failed to load seed file: #{inspect(reason)}")
        %{created: 0, failed: 0, details: [{:error, "Failed to load seed file", reason}]}
    end
  end

  @doc """
  Reset database and re-seed from file.
  """
  def reset do
    Schema.clear_all()
    run()
  end

  @doc """
  Load and validate the seed file without applying changes.
  Returns {:ok, data} or {:error, reason}.
  """
  def validate do
    case load_seed_file() do
      {:ok, data} ->
        participants = data["participants"] || []
        Logger.info("Seed file valid: #{length(participants)} participants defined")
        {:ok, %{participants: length(participants)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the path to the seed file.
  """
  def seed_file_path do
    Path.join(:code.priv_dir(:scalegraph), "seed_data.yaml")
  end

  @doc """
  Enrich existing participants in the database with services from seed data.

  This function:
  - Loads the seed file
  - Gets all existing participants from the database
  - Matches them by ID with seed data and adds missing services
  - For participants not in seed data, adds default services based on their role

  Returns a summary of the enrichment operation.
  """
  def enrich_existing_participants do
    case load_seed_file() do
      {:ok, data} ->
        seed_participants = data["participants"] || []
        enrich_participants_with_services(seed_participants)

      {:error, reason} ->
        Logger.error("Failed to load seed file for enrichment: #{inspect(reason)}")
        %{enriched: 0, skipped: 0, failed: 0, details: []}
    end
  end

  defp enrich_participants_with_services(seed_participants) do
    # Create a map of participant_id -> services from seed data
    seed_services_map =
      Enum.reduce(seed_participants, %{}, fn p, acc ->
        id = p["id"]
        services = p["services"] || []
        Map.put(acc, id, services)
      end)

    # Get all existing participants from database
    case Participant.list_participants() do
      {:ok, existing_participants} ->
        results =
          Enum.map(existing_participants, fn participant ->
            enrich_single_participant(participant, seed_services_map)
          end)

        {enriched, skipped, failed} =
          Enum.reduce(results, {0, 0, 0}, fn result, {e, s, f} ->
            case result do
              {:enriched, _, _} -> {e + 1, s, f}
              {:skipped, _, _} -> {e, s + 1, f}
              {:failed, _, _} -> {e, s, f + 1}
            end
          end)

        Logger.info(
          "Enrichment complete: #{enriched} enriched, #{skipped} skipped, #{failed} failed"
        )

        %{
          enriched: enriched,
          skipped: skipped,
          failed: failed,
          details: results
        }

      {:error, reason} ->
        Logger.error("Failed to list participants: #{inspect(reason)}")
        %{enriched: 0, skipped: 0, failed: 0, details: [{:error, reason}]}
    end
  end

  defp enrich_single_participant(participant, seed_services_map) do
    participant_id = participant.id
    existing_services = participant.services || []

    case Map.get(seed_services_map, participant_id) do
      nil ->
        # Participant not in seed data, add default services based on role
        default_services = default_services_for_role(participant.role)

        if Enum.empty?(default_services) do
          {:skipped, participant_id, "not in seed data and no default services for role"}
        else
          # Filter out services that already exist
          missing_services =
            Enum.filter(default_services, fn service_id ->
              service_id not in existing_services
            end)

          if Enum.empty?(missing_services) do
            {:skipped, participant_id, "already has all default services for role"}
          else
            # Add missing default services
            results =
              Enum.map(missing_services, fn service_id ->
                Participant.add_service(participant_id, service_id)
              end)

            errors =
              Enum.filter(results, fn
                {:error, _} -> true
                _ -> false
              end)

            if Enum.empty?(errors) do
              {:enriched, participant_id, missing_services}
            else
              Logger.warning(
                "Failed to add some default services to #{participant_id}: #{inspect(errors)}"
              )

              {:failed, participant_id, errors}
            end
          end
        end

      seed_services when is_list(seed_services) ->
        # Find services that need to be added from seed data
        missing_services =
          Enum.filter(seed_services, fn service_id ->
            service_id not in existing_services
          end)

        if Enum.empty?(missing_services) do
          {:skipped, participant_id, "already has all services from seed data"}
        else
          # Add missing services
          results =
            Enum.map(missing_services, fn service_id ->
              Participant.add_service(participant_id, service_id)
            end)

          errors =
            Enum.filter(results, fn
              {:error, _} -> true
              _ -> false
            end)

          if Enum.empty?(errors) do
            {:enriched, participant_id, missing_services}
          else
            Logger.warning("Failed to add some services to #{participant_id}: #{inspect(errors)}")

            {:failed, participant_id, errors}
          end
        end

      _ ->
        {:skipped, participant_id, "invalid services format in seed data"}
    end
  end

  # Default services based on participant role
  defp default_services_for_role(:access_provider), do: ["access_control"]
  defp default_services_for_role(:banking_partner), do: ["payment_processing", "banking"]
  defp default_services_for_role(:ecosystem_partner), do: ["platform"]
  defp default_services_for_role(:supplier), do: ["product_delivery", "supply"]
  defp default_services_for_role(:equipment_provider), do: ["equipment_rental", "pay_per_use"]
  defp default_services_for_role(_), do: []

  # Private functions

  defp load_seed_file do
    path = seed_file_path()

    if File.exists?(path) do
      YamlElixir.read_from_file(path)
    else
      # Try relative path for development
      if File.exists?(@seed_file) do
        YamlElixir.read_from_file(@seed_file)
      else
        {:error, :seed_file_not_found}
      end
    end
  end

  defp seed_participants(participants) do
    results =
      Enum.map(participants, fn p ->
        case create_participant_with_accounts(p) do
          {:ok, participant, accounts} ->
            {:ok, participant.name, length(accounts)}

          {:error, reason} ->
            {:error, p["name"] || p["id"], reason}
        end
      end)

    {successes, failures} =
      Enum.split_with(results, fn
        {:ok, _, _} -> true
        _ -> false
      end)

    Logger.info("Seeding complete: #{length(successes)} created, #{length(failures)} failed")

    %{
      created: length(successes),
      failed: length(failures),
      details: results
    }
  end

  defp create_participant_with_accounts(params) do
    id = params["id"]
    name = params["name"]
    role = parse_role(params["role"])
    metadata = params["metadata"] || %{}
    accounts = params["accounts"] || []
    services = params["services"] || []
    about = params["about"] || ""
    
    # Parse contact - can be a map (structured) or string (legacy format)
    contact = case params["contact"] do
      contact_map when is_map(contact_map) ->
        # Structured contact map
        %{
          email: Map.get(contact_map, "email", "") || Map.get(contact_map, :email, ""),
          phone: Map.get(contact_map, "phone", "") || Map.get(contact_map, :phone, ""),
          website: Map.get(contact_map, "website", "") || Map.get(contact_map, :website, ""),
          address: Map.get(contact_map, "address", "") || Map.get(contact_map, :address, ""),
          postal_code: Map.get(contact_map, "postal_code", "") || Map.get(contact_map, :postal_code, ""),
          city: Map.get(contact_map, "city", "") || Map.get(contact_map, :city, ""),
          country: Map.get(contact_map, "country", "") || Map.get(contact_map, :country, "")
        }
      contact_str when is_binary(contact_str) ->
        # Legacy string format - try to parse "email | phone" format
        parse_contact_string(contact_str)
      _ ->
        %{}
    end

    # Try to create participant, but continue if it already exists
    participant_result = Participant.create_participant(id, name, role, metadata, about, contact)
    
    case participant_result do
      {:ok, participant} ->
        # New participant created, proceed with services and accounts
        with :ok <- add_services_to_participant(id, services),
             {:ok, created_accounts} <- create_accounts(id, accounts) do
          {:ok, participant, created_accounts}
        end
      
      {:error, :participant_exists} ->
        # Participant already exists, but we should still add services and accounts
        Logger.info("Participant #{id} already exists, adding services and accounts...")
        with :ok <- add_services_to_participant(id, services),
             {:ok, created_accounts} <- create_accounts(id, accounts) do
          # Get the existing participant to return
          case Participant.get_participant(id) do
            {:ok, participant} ->
              {:ok, participant, created_accounts}
            {:error, reason} ->
              {:error, "Failed to retrieve existing participant: #{inspect(reason)}"}
          end
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Parse legacy contact string format "email | phone" into structured map
  defp parse_contact_string(contact_str) when is_binary(contact_str) do
    parts = String.split(contact_str, "|")
    |> Enum.map(&String.trim/1)
    
    email = parts
    |> Enum.find(fn part -> String.contains?(part, "@") end)
    |> Kernel.||("")
    
    phone = parts
    |> Enum.find(fn part -> Regex.match?(~r/^\+?\d/, part) end)
    |> Kernel.||("")
    
    %{
      email: email,
      phone: phone,
      website: "",
      address: "",
      postal_code: "",
      city: "",
      country: ""
    }
  end

  defp parse_contact_string(_), do: %{}

  defp add_services_to_participant(_participant_id, []), do: :ok

  defp add_services_to_participant(participant_id, services) when is_list(services) do
    results =
      Enum.map(services, fn service_id ->
        case Participant.add_service(participant_id, service_id) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            # Log error but don't fail - service might already exist or participant might not exist
            Logger.warning("Could not add service #{service_id} to participant #{participant_id}: #{inspect(reason)}")
            :skipped
        end
      end)

    errors =
      Enum.filter(results, fn
        {:error, _} -> true
        _ -> false
      end)

    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end

  defp add_services_to_participant(_participant_id, _), do: :ok

  defp create_accounts(participant_id, accounts) do
    results =
      Enum.map(accounts, fn acc ->
        account_type = parse_account_type(acc["type"])
        initial_balance = acc["initial_balance"] || 0
        metadata = acc["metadata"] || %{}

        case Participant.create_participant_account(
               participant_id,
               account_type,
               initial_balance,
               metadata
             ) do
          {:ok, account} ->
            {:ok, account}

          {:error, :account_exists} ->
            # Account already exists, skip it (idempotent seeding)
            Logger.debug("Account #{participant_id}:#{account_type} already exists, skipping")
            {:skipped, account_type}

          {:error, reason} ->
            {:error, reason}
        end
      end)

    errors =
      Enum.filter(results, fn
        {:error, _} -> true
        _ -> false
      end)

    if Enum.empty?(errors) do
      # Return only successfully created accounts (skip already-existing ones)
      created_accounts =
        results
        |> Enum.filter(fn
          {:ok, _acc} -> true
          _ -> false
        end)
        |> Enum.map(fn {:ok, acc} -> acc end)

      {:ok, created_accounts}
    else
      {:error, errors}
    end
  end

  defp parse_role(role) when is_binary(role) do
    String.to_existing_atom(role)
  rescue
    ArgumentError -> :ecosystem_partner
  end

  defp parse_role(_), do: :ecosystem_partner

  defp parse_account_type(type) when is_binary(type) do
    String.to_existing_atom(type)
  rescue
    ArgumentError -> :operating
  end

  defp parse_account_type(_), do: :operating
end
