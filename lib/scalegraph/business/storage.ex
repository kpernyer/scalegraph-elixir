defmodule Scalegraph.Business.Storage do
  @moduledoc """
  Business rules database storage.
  
  This module manages business-specific tables with explicit financial terminology:
  - Loans
  - Invoices
  - Revenue Share contracts
  - Subscription contracts
  
  Separate database context from the pure ledger for insulation.
  """

  require Logger

  @invoices_table :scalegraph_business_invoices
  @loans_table :scalegraph_business_loans
  @revenue_share_table :scalegraph_business_revenue_share
  @subscriptions_table :scalegraph_business_subscriptions

  def invoices_table, do: @invoices_table
  def loans_table, do: @loans_table
  def revenue_share_table, do: @revenue_share_table
  def subscriptions_table, do: @subscriptions_table

  @doc """
  Initialize the business database schema and tables.
  """
  def init do
    storage_type = storage_type()
    current_node = node()

    # Create schema on disk if using disc_copies
    schema_result = if storage_type == :disc_copies do
      case :mnesia.create_schema([current_node]) do
        :ok ->
          Logger.info("Created Mnesia schema for business database on node #{inspect(current_node)}")
          :ok

        {:error, {_, {:already_exists, _}}} ->
          Logger.info("Mnesia schema already exists for business database")
          ensure_node_in_schema(current_node)
          :ok

        {:error, reason} ->
          Logger.error("Failed to create business schema: #{inspect(reason)}")
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
            # Create business tables
            create_invoices_table()
            create_loans_table()
            create_revenue_share_table()
            create_subscriptions_table()

            # Wait for tables to be ready
            tables = [
              @invoices_table,
              @loans_table,
              @revenue_share_table,
              @subscriptions_table
            ]

            case :mnesia.wait_for_tables(tables, 30_000) do
              :ok ->
                storage_desc =
                  if storage_type == :disc_copies,
                    do: "persistent (disc_copies)",
                    else: "in-memory (ram_copies)"

                Logger.info("Business database tables ready (#{storage_desc})")
                :ok

              {:timeout, timeout_tables} ->
                Logger.error("Timeout waiting for business tables: #{inspect(timeout_tables)}")
                {:error, {:table_timeout, timeout_tables}}

              {:error, reason} ->
                Logger.error("Error waiting for business tables: #{inspect(reason)}")
                {:error, {:table_wait_failed, reason}}
            end
        end
    end
  end

  defp storage_type do
    Application.get_env(:scalegraph, :business_storage, :disc_copies)
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

  defp create_revenue_share_table do
    storage = storage_type()

    table_opts =
      [
        attributes: [
          :id,
          :provider_id,
          :recipient_id,
          :share_percentage,
          :status,
          :ledger_transaction_ids,
          :reference,
          :created_at,
          :metadata
        ],
        type: :set,
        index: [:provider_id, :recipient_id, :status]
      ] ++ [{storage, [node()]}]

    case :mnesia.create_table(@revenue_share_table, table_opts) do
      {:atomic, :ok} ->
        Logger.info("Created #{@revenue_share_table} table")

      {:aborted, {:already_exists, @revenue_share_table}} ->
        Logger.info("#{@revenue_share_table} table already exists")
        fix_table_storage(@revenue_share_table, storage)

      {:aborted, {:bad_type, table, _storage_type, node}} ->
        Logger.warning(
          "Table #{table} exists with different storage type on node #{inspect(node)}. Attempting to fix..."
        )
        fix_table_storage(@revenue_share_table, storage)

      {:aborted, reason} ->
        Logger.error("Failed to create #{@revenue_share_table}: #{inspect(reason)}")
    end
  end

  defp create_subscriptions_table do
    storage = storage_type()

    table_opts =
      [
        attributes: [
          :id,
          :provider_id,
          :subscriber_id,
          :amount_cents,
          :billing_cycle,
          :next_billing_date,
          :status,
          :ledger_transaction_ids,
          :reference,
          :created_at,
          :metadata
        ],
        type: :set,
        index: [:provider_id, :subscriber_id, :status]
      ] ++ [{storage, [node()]}]

    case :mnesia.create_table(@subscriptions_table, table_opts) do
      {:atomic, :ok} ->
        Logger.info("Created #{@subscriptions_table} table")

      {:aborted, {:already_exists, @subscriptions_table}} ->
        Logger.info("#{@subscriptions_table} table already exists")
        fix_table_storage(@subscriptions_table, storage)

      {:aborted, {:bad_type, table, _storage_type, node}} ->
        Logger.warning(
          "Table #{table} exists with different storage type on node #{inspect(node)}. Attempting to fix..."
        )
        fix_table_storage(@subscriptions_table, storage)

      {:aborted, reason} ->
        Logger.error("Failed to create #{@subscriptions_table}: #{inspect(reason)}")
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
  Clear all business data (useful for testing).
  """
  def clear_all do
    :mnesia.clear_table(@invoices_table)
    :mnesia.clear_table(@loans_table)
    :mnesia.clear_table(@revenue_share_table)
    :mnesia.clear_table(@subscriptions_table)
    :ok
  end
end

