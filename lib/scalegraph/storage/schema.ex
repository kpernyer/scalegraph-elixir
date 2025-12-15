defmodule Scalegraph.Storage.Schema do
  @moduledoc """
  Mnesia schema setup for the ledger.

  Tables:
  - :participants - stores participant/organization records
  - :accounts - stores account records (linked to participants)
  - :transactions - stores transaction audit log
  """

  require Logger

  @participants_table :scalegraph_participants
  @accounts_table :scalegraph_accounts
  @transactions_table :scalegraph_transactions

  def participants_table, do: @participants_table
  def accounts_table, do: @accounts_table
  def transactions_table, do: @transactions_table

  @doc """
  Valid participant roles in the ecosystem.
  """
  def participant_roles do
    [
      # e.g., ASSA ABLOY
      :access_provider,
      # e.g., SEB
      :banking_partner,
      # e.g., Beauty Hosting
      :ecosystem_partner,
      # e.g., Schampo etc, Clipper Oy
      :supplier,
      # e.g., Hairgrowers United (pay-per-use)
      :equipment_provider
    ]
  end

  @doc """
  Initialize Mnesia schema and tables.
  Call this during application startup.
  """
  def init do
    storage_type = storage_type()

    # Create schema on disk if using disc_copies
    if storage_type == :disc_copies do
      case :mnesia.create_schema([node()]) do
        :ok ->
          Logger.info("Created Mnesia schema on disk")

        {:error, {_, {:already_exists, _}}} ->
          Logger.info("Mnesia schema already exists on disk")

        {:error, reason} ->
          Logger.error("Failed to create Mnesia schema: #{inspect(reason)}")
      end
    end

    # Start Mnesia
    :mnesia.start()

    # Create tables with configured storage type
    create_participants_table()
    create_accounts_table()
    create_transactions_table()

    # Wait for tables to be ready
    :mnesia.wait_for_tables([@participants_table, @accounts_table, @transactions_table], 30_000)

    storage_desc =
      if storage_type == :disc_copies,
        do: "persistent (disc_copies)",
        else: "in-memory (ram_copies)"

    Logger.info("Mnesia tables ready (#{storage_desc})")
    :ok
  end

  # Get storage type from config, default to disc_copies
  defp storage_type do
    Application.get_env(:scalegraph, :mnesia_storage, :disc_copies)
  end

  defp create_participants_table do
    storage = storage_type()

    table_opts =
      [
        attributes: [:id, :name, :role, :created_at, :metadata, :services],
        type: :set
      ] ++ [{storage, [node()]}]

    case :mnesia.create_table(@participants_table, table_opts) do
      {:atomic, :ok} ->
        Logger.info("Created #{@participants_table} table")

      {:aborted, {:already_exists, @participants_table}} ->
        Logger.info("#{@participants_table} table already exists")

      {:aborted, reason} ->
        Logger.error("Failed to create #{@participants_table}: #{inspect(reason)}")
    end
  end

  defp create_accounts_table do
    storage = storage_type()

    table_opts =
      [
        attributes: [:id, :participant_id, :account_type, :balance, :created_at, :metadata],
        type: :set,
        index: [:participant_id]
      ] ++ [{storage, [node()]}]

    case :mnesia.create_table(@accounts_table, table_opts) do
      {:atomic, :ok} ->
        Logger.info("Created #{@accounts_table} table")

      {:aborted, {:already_exists, @accounts_table}} ->
        Logger.info("#{@accounts_table} table already exists")

      {:aborted, reason} ->
        Logger.error("Failed to create #{@accounts_table}: #{inspect(reason)}")
    end
  end

  defp create_transactions_table do
    storage = storage_type()

    table_opts =
      [
        attributes: [:id, :type, :entries, :timestamp, :reference],
        type: :set
      ] ++ [{storage, [node()]}]

    case :mnesia.create_table(@transactions_table, table_opts) do
      {:atomic, :ok} ->
        Logger.info("Created #{@transactions_table} table")

      {:aborted, {:already_exists, @transactions_table}} ->
        Logger.info("#{@transactions_table} table already exists")

      {:aborted, reason} ->
        Logger.error("Failed to create #{@transactions_table}: #{inspect(reason)}")
    end
  end

  @doc """
  Clear all data (useful for testing).
  """
  def clear_all do
    :mnesia.clear_table(@participants_table)
    :mnesia.clear_table(@accounts_table)
    :mnesia.clear_table(@transactions_table)
    :ok
  end
end
