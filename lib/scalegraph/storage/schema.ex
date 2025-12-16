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
  Check if the participants table has the correct schema (6 attributes including services).
  Returns :ok if schema is correct, {:error, :schema_mismatch} if not.
  """
  def check_participants_schema do
    case :mnesia.table_info(@participants_table, :attributes) do
      [:id, :name, :role, :created_at, :metadata, :services] ->
        :ok

      attributes ->
        {:error, :schema_mismatch, attributes}
    end
  end

  @doc """
  Migrate the participants table from old schema (5 fields) to new schema (6 fields).
  This will preserve all existing data by adding an empty services list to each participant.
  """
  def migrate_participants_table do
    Logger.info("Migrating participants table to new schema...")

    # Step 1: Read all existing participants (in a transaction)
    read_result =
      :mnesia.transaction(fn ->
        :mnesia.foldl(
          fn record, acc ->
            case record do
              {_table, id, name, role, created_at, metadata} ->
                # Old format (5 fields) - add empty services
                [{id, name, role, created_at, metadata, []} | acc]

              {_table, id, name, role, created_at, metadata, services} ->
                # New format (6 fields) - keep as is
                [{id, name, role, created_at, metadata, services || []} | acc]
            end
          end,
          [],
          @participants_table
        )
      end)

    case read_result do
      {:atomic, participants} ->
        # Step 2: Delete the old table (outside transaction)
        case :mnesia.delete_table(@participants_table) do
          {:atomic, :ok} ->
            # Step 3: Create the new table with correct schema
            storage = storage_type()
            table_opts =
              [
                attributes: [:id, :name, :role, :created_at, :metadata, :services],
                type: :set
              ] ++ [{storage, [node()]}]

            case :mnesia.create_table(@participants_table, table_opts) do
              {:atomic, :ok} ->
                # Step 4: Write back all participants with new schema (in a transaction)
                write_result =
                  :mnesia.transaction(fn ->
                    Enum.each(participants, fn {id, name, role, created_at, metadata, services} ->
                      record =
                        {@participants_table, id, name, role, created_at, metadata, services}

                      :mnesia.write(record)
                    end)
                  end)

                case write_result do
                  {:atomic, :ok} ->
                    Logger.info("Successfully migrated #{length(participants)} participants to new schema")
                    :ok

                  {:aborted, reason} ->
                    Logger.error("Failed to write migrated participants: #{inspect(reason)}")
                    {:error, reason}
                end

              {:aborted, reason} ->
                Logger.error("Failed to create new participants table: #{inspect(reason)}")
                {:error, reason}
            end

          {:aborted, reason} ->
            Logger.error("Failed to delete old participants table: #{inspect(reason)}")
            {:error, reason}
        end

      {:aborted, reason} ->
        Logger.error("Failed to read existing participants: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Initialize Mnesia schema and tables, with automatic schema migration if needed.
  """
  def init_with_migration do
    init()

    # Check if participants table needs migration
    case check_participants_schema() do
      :ok ->
        :ok

      {:error, :schema_mismatch, old_attributes} ->
        Logger.warning(
          "Participants table has old schema #{inspect(old_attributes)}. Attempting migration..."
        )

        case migrate_participants_table() do
          :ok ->
            Logger.info("Schema migration completed successfully")
            :ok

          {:error, reason} ->
            Logger.error(
              "Schema migration failed: #{inspect(reason)}. You may need to clear the database manually."
            )

            Logger.error("""
            ════════════════════════════════════════════════════════════════════════
            Schema Migration Required
            ════════════════════════════════════════════════════════════════════════

            The participants table has an old schema and cannot be automatically migrated.

            To fix this, you have two options:

            1. Clear the database (WARNING: This will delete all data):
               - Stop the server
               - Delete the Mnesia data directory: rm -rf priv/mnesia_data
               - Restart the server

            2. Manual migration (if you need to preserve data):
               - Export your data first
               - Clear the database
               - Re-import your data

            ════════════════════════════════════════════════════════════════════════
            """)

            {:error, :schema_migration_failed}
        end
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
