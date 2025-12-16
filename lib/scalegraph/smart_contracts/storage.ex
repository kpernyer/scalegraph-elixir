defmodule Scalegraph.SmartContracts.Storage do
  @moduledoc """
  Smart contracts database storage.
  
  This module manages smart contract execution state, schedules, and automation rules.
  Separate database context for insulation from business and ledger layers.
  """

  require Logger

  @contracts_table :scalegraph_smart_contracts
  @executions_table :scalegraph_smart_contract_executions
  @schedules_table :scalegraph_smart_contract_schedules

  def contracts_table, do: @contracts_table
  def executions_table, do: @executions_table
  def schedules_table, do: @schedules_table

  @doc """
  Initialize the smart contracts database schema and tables.
  """
  def init do
    storage_type = storage_type()
    current_node = node()

    # Create schema on disk if using disc_copies
    if storage_type == :disc_copies do
      case :mnesia.create_schema([current_node]) do
        :ok ->
          Logger.info("Created Mnesia schema for smart contracts database on node #{inspect(current_node)}")

        {:error, {_, {:already_exists, _}}} ->
          Logger.info("Mnesia schema already exists for smart contracts database")
          ensure_node_in_schema(current_node)

        {:error, reason} ->
          Logger.error("Failed to create smart contracts schema: #{inspect(reason)}")
      end
    end

    # Start Mnesia if not already started
    :mnesia.start()

    # Create smart contracts tables
    create_contracts_table()
    create_executions_table()
    create_schedules_table()

    # Wait for tables to be ready
    :mnesia.wait_for_tables([@contracts_table, @executions_table, @schedules_table], 30_000)

    storage_desc =
      if storage_type == :disc_copies,
        do: "persistent (disc_copies)",
        else: "in-memory (ram_copies)"

    Logger.info("Smart contracts database tables ready (#{storage_desc})")
    :ok
  end

  defp storage_type do
    Application.get_env(:scalegraph, :smart_contracts_storage, :disc_copies)
  end

  defp create_contracts_table do
    storage = storage_type()

    table_opts =
      [
        attributes: [
          :id,
          :name,
          :description,
          :contract_type,
          :business_contract_id,
          :conditions,
          :actions,
          :status,
          :created_at,
          :last_executed_at,
          :metadata
        ],
        type: :set,
        index: [:contract_type, :status, :business_contract_id]
      ] ++ [{storage, [node()]}]

    case :mnesia.create_table(@contracts_table, table_opts) do
      {:atomic, :ok} ->
        Logger.info("Created #{@contracts_table} table")

      {:aborted, {:already_exists, @contracts_table}} ->
        Logger.info("#{@contracts_table} table already exists")
        fix_table_storage(@contracts_table, storage)

      {:aborted, {:bad_type, table, _storage_type, node}} ->
        Logger.warning(
          "Table #{table} exists with different storage type on node #{inspect(node)}. Attempting to fix..."
        )
        fix_table_storage(@contracts_table, storage)

      {:aborted, reason} ->
        Logger.error("Failed to create #{@contracts_table}: #{inspect(reason)}")
    end
  end

  defp create_executions_table do
    storage = storage_type()

    table_opts =
      [
        attributes: [
          :id,
          :contract_id,
          :executed_at,
          :status,
          :result,
          :transaction_ids,
          :error_message,
          :metadata
        ],
        type: :set,
        index: [:contract_id, :executed_at, :status]
      ] ++ [{storage, [node()]}]

    case :mnesia.create_table(@executions_table, table_opts) do
      {:atomic, :ok} ->
        Logger.info("Created #{@executions_table} table")

      {:aborted, {:already_exists, @executions_table}} ->
        Logger.info("#{@executions_table} table already exists")
        fix_table_storage(@executions_table, storage)

      {:aborted, {:bad_type, table, _storage_type, node}} ->
        Logger.warning(
          "Table #{table} exists with different storage type on node #{inspect(node)}. Attempting to fix..."
        )
        fix_table_storage(@executions_table, storage)

      {:aborted, reason} ->
        Logger.error("Failed to create #{@executions_table}: #{inspect(reason)}")
    end
  end

  defp create_schedules_table do
    storage = storage_type()

    table_opts =
      [
        attributes: [
          :id,
          :contract_id,
          :schedule_type,
          :cron_expression,
          :next_execution_at,
          :enabled,
          :metadata
        ],
        type: :set,
        index: [:contract_id, :next_execution_at, :enabled]
      ] ++ [{storage, [node()]}]

    case :mnesia.create_table(@schedules_table, table_opts) do
      {:atomic, :ok} ->
        Logger.info("Created #{@schedules_table} table")

      {:aborted, {:already_exists, @schedules_table}} ->
        Logger.info("#{@schedules_table} table already exists")
        fix_table_storage(@schedules_table, storage)

      {:aborted, {:bad_type, table, _storage_type, node}} ->
        Logger.warning(
          "Table #{table} exists with different storage type on node #{inspect(node)}. Attempting to fix..."
        )
        fix_table_storage(@schedules_table, storage)

      {:aborted, reason} ->
        Logger.error("Failed to create #{@schedules_table}: #{inspect(reason)}")
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
  Clear all smart contracts data (useful for testing).
  """
  def clear_all do
    :mnesia.clear_table(@contracts_table)
    :mnesia.clear_table(@executions_table)
    :mnesia.clear_table(@schedules_table)
    :ok
  end
end

