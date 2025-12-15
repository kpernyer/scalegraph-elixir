defmodule Scalegraph.Seed do
  @moduledoc """
  Seed data loader for the Scalegraph ledger.

  Reads participant and account data from `priv/seed_data.yaml` and
  populates the database on startup.
  """

  require Logger

  alias Scalegraph.Participant.Core, as: Participant

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
    Scalegraph.Storage.Schema.clear_all()
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
    results = Enum.map(participants, fn p ->
      case create_participant_with_accounts(p) do
        {:ok, participant, accounts} ->
          {:ok, participant.name, length(accounts)}
        {:error, reason} ->
          {:error, p["name"] || p["id"], reason}
      end
    end)

    {successes, failures} = Enum.split_with(results, fn
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

    with {:ok, participant} <- Participant.create_participant(id, name, role, metadata),
         {:ok, created_accounts} <- create_accounts(id, accounts) do
      {:ok, participant, created_accounts}
    end
  end

  defp create_accounts(participant_id, accounts) do
    results = Enum.map(accounts, fn acc ->
      account_type = parse_account_type(acc["type"])
      initial_balance = acc["initial_balance"] || 0
      metadata = acc["metadata"] || %{}

      Participant.create_participant_account(participant_id, account_type, initial_balance, metadata)
    end)

    errors = Enum.filter(results, fn
      {:error, _} -> true
      _ -> false
    end)

    if Enum.empty?(errors) do
      {:ok, Enum.map(results, fn {:ok, acc} -> acc end)}
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
