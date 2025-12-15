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
      :access_provider,      # e.g., ASSA ABLOY
      :banking_partner,      # e.g., SEB
      :ecosystem_partner,    # e.g., Beauty Hosting
      :supplier,             # e.g., Schampo etc, Clipper Oy
      :equipment_provider    # e.g., Hairgrowers United (pay-per-use)
    ]
  end

  @doc """
  Initialize Mnesia schema and tables.
  Call this during application startup.
  """
  def init do
    # Start Mnesia (in-memory mode for simplicity)
    :mnesia.start()

    # Create tables (ram_copies = in-memory, no persistence issues)
    create_participants_table()
    create_accounts_table()
    create_transactions_table()

    # Wait for tables to be ready
    :mnesia.wait_for_tables([@participants_table, @accounts_table, @transactions_table], 30_000)

    Logger.info("Mnesia tables ready (in-memory mode)")
    :ok
  end

  defp create_participants_table do
    case :mnesia.create_table(@participants_table, [
      attributes: [:id, :name, :role, :created_at, :metadata],
      ram_copies: [node()],
      type: :set
    ]) do
      {:atomic, :ok} ->
        Logger.info("Created #{@participants_table} table")

      {:aborted, {:already_exists, @participants_table}} ->
        Logger.info("#{@participants_table} table already exists")

      {:aborted, reason} ->
        Logger.error("Failed to create #{@participants_table}: #{inspect(reason)}")
    end
  end

  defp create_accounts_table do
    case :mnesia.create_table(@accounts_table, [
      attributes: [:id, :participant_id, :account_type, :balance, :created_at, :metadata],
      ram_copies: [node()],
      type: :set,
      index: [:participant_id]
    ]) do
      {:atomic, :ok} ->
        Logger.info("Created #{@accounts_table} table")

      {:aborted, {:already_exists, @accounts_table}} ->
        Logger.info("#{@accounts_table} table already exists")

      {:aborted, reason} ->
        Logger.error("Failed to create #{@accounts_table}: #{inspect(reason)}")
    end
  end

  defp create_transactions_table do
    case :mnesia.create_table(@transactions_table, [
      attributes: [:id, :type, :entries, :timestamp, :reference],
      ram_copies: [node()],
      type: :set
    ]) do
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
