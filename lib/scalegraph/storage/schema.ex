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
  @invoices_table :scalegraph_invoices
  @loans_table :scalegraph_loans

  def participants_table, do: @participants_table
  def accounts_table, do: @accounts_table
  def transactions_table, do: @transactions_table
  def invoices_table, do: @invoices_table
  def loans_table, do: @loans_table

  @doc """
  Valid participant roles in the ecosystem.
  """
  def participant_roles do
    [
      # e.g., ASSA ABLOY
      :access_provider,
      # e.g., SEB
      :banking_partner,
      # e.g., Studio Solveig, Hair and Beard
      :ecosystem_partner,
      # e.g., Schampo etc, Clipper Oy, Essity
      :supplier,
      # e.g., Hairgrowers United (pay-per-use)
      :equipment_provider,
      # e.g., Beauty Hosting
      :ecosystem_orchestrator
    ]
  end

  @doc """
  Initialize Mnesia schema and tables.
  Call this during application startup.
  """
  def init do
    storage_type = storage_type()
    current_node = node()

    # Create schema on disk if using disc_copies
    if storage_type == :disc_copies do
      case :mnesia.create_schema([current_node]) do
        :ok ->
          Logger.info("Created Mnesia schema on disk for node #{inspect(current_node)}")

        {:error, {_, {:already_exists, _}}} ->
          Logger.info("Mnesia schema already exists on disk")
          # Ensure current node is in the schema
          ensure_node_in_schema(current_node)

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
    create_invoices_table()
    create_loans_table()

    # Wait for tables to be ready
    :mnesia.wait_for_tables([
      @participants_table,
      @accounts_table,
      @transactions_table,
      @invoices_table,
      @loans_table
    ], 30_000)

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
        attributes: [:id, :name, :role, :created_at, :metadata, :services, :about, :contact],
        type: :set
      ] ++ [{storage, [node()]}]

    case :mnesia.create_table(@participants_table, table_opts) do
      {:atomic, :ok} ->
        Logger.info("Created #{@participants_table} table")

      {:aborted, {:already_exists, @participants_table}} ->
        Logger.info("#{@participants_table} table already exists")
        # Table exists, but may have wrong node configuration - try to change it
        fix_table_storage(@participants_table, storage)

      {:aborted, {:bad_type, table, _storage_type, node}} ->
        Logger.warning(
          "Table #{table} exists with different storage type on node #{inspect(node)}. Attempting to fix..."
        )
        fix_table_storage(@participants_table, storage)

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
        fix_table_storage(@accounts_table, storage)

      {:aborted, {:bad_type, table, _storage_type, node}} ->
        Logger.warning(
          "Table #{table} exists with different storage type on node #{inspect(node)}. Attempting to fix..."
        )
        fix_table_storage(@accounts_table, storage)

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
        fix_table_storage(@transactions_table, storage)

      {:aborted, {:bad_type, table, _storage_type, node}} ->
        Logger.warning(
          "Table #{table} exists with different storage type on node #{inspect(node)}. Attempting to fix..."
        )
        fix_table_storage(@transactions_table, storage)

      {:aborted, reason} ->
        Logger.error("Failed to create #{@transactions_table}: #{inspect(reason)}")
    end
  end

  defp create_invoices_table do
    storage = storage_type()

    table_opts =
      [
        attributes: [
          :id,
          :supplier_id,
          :buyer_id,
          :amount,
          :due_date,
          :status,
          :ledger_transaction_id,
          :reference,
          :created_at,
          :paid_at,
          :metadata
        ],
        type: :set,
        index: [:supplier_id, :buyer_id, :status]
      ] ++ [{storage, [node()]}]

    case :mnesia.create_table(@invoices_table, table_opts) do
      {:atomic, :ok} ->
        Logger.info("Created #{@invoices_table} table")

      {:aborted, {:already_exists, @invoices_table}} ->
        Logger.info("#{@invoices_table} table already exists")
        fix_table_storage(@invoices_table, storage)

      {:aborted, {:bad_type, table, _storage_type, node}} ->
        Logger.warning(
          "Table #{table} exists with different storage type on node #{inspect(node)}. Attempting to fix..."
        )
        fix_table_storage(@invoices_table, storage)

      {:aborted, reason} ->
        Logger.error("Failed to create #{@invoices_table}: #{inspect(reason)}")
    end
  end

  defp create_loans_table do
    storage = storage_type()

    table_opts =
      [
        attributes: [
          :id,
          :lender_id,
          :borrower_id,
          :principal_amount,
          :interest_rate,
          :repayment_schedule,
          :status,
          :disbursement_transaction_id,
          :repayment_transaction_ids,
          :created_at,
          :metadata
        ],
        type: :set,
        index: [:lender_id, :borrower_id, :status]
      ] ++ [{storage, [node()]}]

    case :mnesia.create_table(@loans_table, table_opts) do
      {:atomic, :ok} ->
        Logger.info("Created #{@loans_table} table")

      {:aborted, {:already_exists, @loans_table}} ->
        Logger.info("#{@loans_table} table already exists")
        fix_table_storage(@loans_table, storage)

      {:aborted, {:bad_type, table, _storage_type, node}} ->
        Logger.warning(
          "Table #{table} exists with different storage type on node #{inspect(node)}. Attempting to fix..."
        )
        fix_table_storage(@loans_table, storage)

      {:aborted, reason} ->
        Logger.error("Failed to create #{@loans_table}: #{inspect(reason)}")
    end
  end

  # Ensure current node is in the Mnesia schema
  defp ensure_node_in_schema(current_node) do
    # Check if schema table exists and has current node
    case :mnesia.table_info(:schema, :disc_copies) do
      nodes when is_list(nodes) ->
        if current_node in nodes do
          Logger.info("Current node #{inspect(current_node)} is already in schema")
          :ok
        else
          Logger.info("Adding current node #{inspect(current_node)} to schema...")
          case :mnesia.change_table_copy_type(:schema, current_node, :disc_copies) do
            {:atomic, :ok} ->
              Logger.info("Successfully added node to schema")
              :ok
            {:aborted, reason} ->
              Logger.warning("Could not add node to schema: #{inspect(reason)}")
              :ok
          end
        end
      _ ->
        :ok
    end
  end

  # Fix table storage type if it exists with wrong node configuration
  defp fix_table_storage(table, desired_storage) do
    current_node = node()
    
    # Try to check and fix storage, but handle errors gracefully
    try do
      # First check if table actually exists
      case :mnesia.table_info(table, :type) do
        :undefined ->
          # Table doesn't exist, this shouldn't happen but log it
          Logger.warning("Table #{table} does not exist when trying to fix storage")
          :ok
        
        _ ->
          # Table exists, try to check and fix storage
          case :mnesia.table_info(table, desired_storage) do
            nodes when is_list(nodes) ->
              if current_node in nodes do
                Logger.info("Table #{table} already has correct storage configuration")
                :ok
              else
                Logger.info("Adding current node to #{table} storage configuration...")
                case :mnesia.change_table_copy_type(table, current_node, desired_storage) do
                  {:atomic, :ok} ->
                    Logger.info("Successfully updated #{table} storage configuration")
                    :ok
                  {:aborted, {:no_exists, ^table, _}} ->
                    # Table doesn't exist in the way we expected
                    Logger.warning("Table #{table} exists but cannot be modified - may need manual cleanup")
                    :ok
                  {:aborted, reason} ->
                    Logger.warning("Could not update #{table} storage: #{inspect(reason)}")
                    Logger.info("Table #{table} exists - continuing with existing configuration")
                    :ok  # Continue anyway, table exists
                end
              end
            
            _ ->
              # Table might not be accessible, but that's okay if it exists
              Logger.info("Table #{table} exists but storage info unavailable - continuing")
              :ok
          end
      end
    catch
      :exit, {:aborted, {:no_exists, ^table, _}} ->
        Logger.warning("Table #{table} does not exist in expected format - continuing")
        :ok
      :exit, reason ->
        Logger.warning("Error accessing table #{table}: #{inspect(reason)} - continuing")
        :ok
    end
  end

  @doc """
  Check if the participants table has the correct schema (6 attributes including services).
  Returns :ok if schema is correct, {:error, :schema_mismatch} if not.
  """
  def check_participants_schema do
    case :mnesia.table_info(@participants_table, :attributes) do
      [:id, :name, :role, :created_at, :metadata, :services, :about, :contact] ->
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

    with {:ok, participants} <- read_all_participants(),
         :ok <- delete_old_participants_table(),
         :ok <- create_new_participants_table(),
         :ok <- write_migrated_participants(participants) do
      Logger.info("Successfully migrated #{length(participants)} participants to new schema")

      :ok
    else
      {:error, reason} = error ->
        log_migration_error(reason)
        error
    end
  end

  defp log_migration_error(reason) do
    case reason do
      _ when is_atom(reason) ->
        Logger.error("Migration failed: #{inspect(reason)}")

      _ ->
        Logger.error("Migration failed: #{inspect(reason)}")
    end
  end

  # Private migration helpers

  defp read_all_participants do
    read_result =
      :mnesia.transaction(fn ->
        :mnesia.foldl(
          fn record, acc ->
            normalized = normalize_participant_record(record)
            [normalized | acc]
          end,
          [],
          @participants_table
        )
      end)

    case read_result do
      {:atomic, participants} -> {:ok, participants}
      {:aborted, reason} -> {:error, reason}
    end
  end

  defp normalize_participant_record({_table, id, name, role, created_at, metadata}) do
    # Old format (5 fields) - add empty services, about, contact
    {id, name, role, created_at, metadata, [], "", %{}}
  end

  defp normalize_participant_record({_table, id, name, role, created_at, metadata, services}) do
    # Format (6 fields) - add about, contact
    {id, name, role, created_at, metadata, services || [], "", %{}}
  end

  defp normalize_participant_record({_table, id, name, role, created_at, metadata, services, about, contact}) do
    # New format (8 fields) - ensure contact is a map
    contact_map = cond do
      is_map(contact) -> contact
      is_binary(contact) -> %{}  # Old string format, convert to empty map
      true -> %{}
    end
    {id, name, role, created_at, metadata, services || [], about || "", contact_map}
  end

  defp delete_old_participants_table do
    case :mnesia.delete_table(@participants_table) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:error, reason}
    end
  end

  defp create_new_participants_table do
    storage = storage_type()

    table_opts =
      [
        attributes: [:id, :name, :role, :created_at, :metadata, :services, :about, :contact],
        type: :set
      ] ++ [{storage, [node()]}]

    case :mnesia.create_table(@participants_table, table_opts) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:error, reason}
    end
  end

  defp write_migrated_participants(participants) do
    write_result =
      :mnesia.transaction(fn ->
        Enum.each(participants, fn participant ->
          record = case participant do
            {id, name, role, created_at, metadata, services} ->
              {@participants_table, id, name, role, created_at, metadata, services, "", %{}}
            {id, name, role, created_at, metadata, services, about, contact} ->
              contact_map = cond do
                is_map(contact) -> contact
                is_binary(contact) -> %{}  # Old string format
                true -> %{}
              end
              {@participants_table, id, name, role, created_at, metadata, services, about || "", contact_map}
          end
          :mnesia.write(record)
        end)
      end)

    case write_result do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:error, reason}
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
    :mnesia.clear_table(@invoices_table)
    :mnesia.clear_table(@loans_table)
    :ok
  end
end
