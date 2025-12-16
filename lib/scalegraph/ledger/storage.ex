defmodule Scalegraph.Ledger.Storage do
  @moduledoc """
  Pure ledger database storage.
  
  This module manages only the core ledger tables:
  - Accounts
  - Transactions
  
  No business semantics - just double-entry bookkeeping.
  """

  require Logger

  @accounts_table :scalegraph_ledger_accounts
  @transactions_table :scalegraph_ledger_transactions

  def accounts_table, do: @accounts_table
  def transactions_table, do: @transactions_table

  @doc """
  Initialize the ledger database schema and tables.
  """
  def init do
    storage_type = storage_type()
    current_node = node()

    # Create schema on disk if using disc_copies
    schema_result = if storage_type == :disc_copies do
      case :mnesia.create_schema([current_node]) do
        :ok ->
          Logger.info("Created Mnesia schema for ledger database on node #{inspect(current_node)}")
          :ok

        {:error, {_, {:already_exists, _}}} ->
          Logger.info("Mnesia schema already exists for ledger database")
          ensure_node_in_schema(current_node)
          :ok

        {:error, reason} ->
          Logger.error("Failed to create ledger schema: #{inspect(reason)}")
          {:error, {:schema_creation_failed, reason}}
      end
    else
      :ok
    end

    # Return early if schema creation failed
    case schema_result do
      {:error, _} = error -> error
      :ok ->
        # Start Mnesia if not already started
        mnesia_result = case :mnesia.start() do
          :ok -> :ok
          {:error, reason} ->
            Logger.error("Failed to start Mnesia: #{inspect(reason)}")
            {:error, {:mnesia_start_failed, reason}}
          {:already_started, _} -> :ok
        end

        # Return early if Mnesia start failed
        case mnesia_result do
          {:error, _} = error -> error
          :ok ->
            # Create ledger tables
            create_accounts_table()
            create_transactions_table()

            # Wait for tables to be ready
            case :mnesia.wait_for_tables([@accounts_table, @transactions_table], 30_000) do
              :ok ->
                storage_desc =
                  if storage_type == :disc_copies,
                    do: "persistent (disc_copies)",
                    else: "in-memory (ram_copies)"

                Logger.info("Ledger database tables ready (#{storage_desc})")
                :ok

              {:timeout, tables} ->
                Logger.error("Timeout waiting for ledger tables: #{inspect(tables)}")
                {:error, {:table_timeout, tables}}

              {:error, reason} ->
                Logger.error("Error waiting for ledger tables: #{inspect(reason)}")
                {:error, {:table_wait_failed, reason}}
            end
        end
    end
  end

  defp storage_type do
    Application.get_env(:scalegraph, :ledger_storage, :disc_copies)
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

  defp ensure_node_in_schema(current_node) do
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

  defp fix_table_storage(table, desired_storage) do
    current_node = node()

    try do
      case :mnesia.table_info(table, :type) do
        :undefined ->
          Logger.warning("Table #{table} does not exist when trying to fix storage")
          :ok

        _ ->
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
                    Logger.warning("Table #{table} exists but cannot be modified - may need manual cleanup")
                    :ok
                  {:aborted, reason} ->
                    Logger.warning("Could not update #{table} storage: #{inspect(reason)}")
                    Logger.info("Table #{table} exists - continuing with existing configuration")
                    :ok
                end
              end

            _ ->
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
  Clear all ledger data (useful for testing).
  """
  def clear_all do
    :mnesia.clear_table(@accounts_table)
    :mnesia.clear_table(@transactions_table)
    :ok
  end
end

