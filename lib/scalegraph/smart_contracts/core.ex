defmodule Scalegraph.SmartContracts.Core do
  @moduledoc """
  Smart contracts core - automation and agent-driven management.
  
  This module provides:
  - Contract creation and management
  - Conditional execution based on triggers
  - Cron-based scheduling
  - Active agent-driven contract execution
  """

  require Logger

  alias Scalegraph.SmartContracts.Storage

  @doc """
  Create a smart contract.
  
  ## Parameters
  - `name` - Contract name
  - `description` - Contract description
  - `contract_type` - Type of contract (:loan, :invoice, :subscription, :revenue_share, :conditional_payment)
  - `business_contract_id` - ID of the business contract this smart contract manages
  - `conditions` - List of condition maps (e.g., %{type: "time", parameters: %{...}})
  - `actions` - List of action maps (e.g., %{type: "transfer", parameters: %{...}})
  - `opts` - Options:
    - `:metadata` - Additional metadata map
  """
  def create_contract(name, description, contract_type, business_contract_id, conditions, actions,
        opts \\ [])
      when is_binary(name) and is_binary(description) and
             contract_type in [:loan, :invoice, :subscription, :revenue_share, :conditional_payment] and
             is_list(conditions) and is_list(actions) do
    contract_id = generate_id()
    created_at = System.system_time(:millisecond)
    metadata = Keyword.get(opts, :metadata, %{})

    contract = %{
      id: contract_id,
      name: name,
      description: description,
      contract_type: contract_type,
      business_contract_id: business_contract_id,
      conditions: conditions,
      actions: actions,
      status: :active,
      created_at: created_at,
      last_executed_at: nil,
      metadata: metadata
    }

    result =
      :mnesia.transaction(fn ->
        record = {
          Storage.contracts_table(),
          contract_id,
          name,
          description,
          contract_type,
          business_contract_id,
          conditions,
          actions,
          :active,
          created_at,
          nil,
          metadata
        }

        :mnesia.write(record)
        contract
      end)

    case result do
      {:atomic, contract} ->
        Logger.info("Created smart contract: #{name} (#{contract_id})")
        {:ok, contract}

      {:aborted, reason} ->
        Logger.error("Failed to create smart contract: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get a smart contract by ID.
  """
  def get_contract(contract_id) when is_binary(contract_id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Storage.contracts_table(), contract_id) do
          [{_table, id, name, description, contract_type, business_contract_id, conditions,
            actions, status, created_at, last_executed_at, metadata}] ->
            {:ok,
             %{
               id: id,
               name: name,
               description: description,
               contract_type: contract_type,
               business_contract_id: business_contract_id,
               conditions: conditions,
               actions: actions,
               status: status,
               created_at: created_at,
               last_executed_at: last_executed_at,
               metadata: metadata
             }}

          [] ->
            {:error, :not_found}
        end
      end)

    case result do
      {:atomic, result} -> result
      {:aborted, reason} -> {:error, reason}
    end
  end

  @doc """
  List smart contracts with filters.
  """
  def list_contracts(opts \\ []) do
    contract_type_filter = Keyword.get(opts, :contract_type)
    status_filter = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 100)

    result =
      :mnesia.transaction(fn ->
        all_contracts = fetch_all_contracts()
        filtered = apply_filters(all_contracts, contract_type_filter, status_filter)
        sort_and_limit(filtered, limit)
      end)

    case result do
      {:atomic, contracts} -> {:ok, contracts}
      {:aborted, reason} -> {:error, reason}
    end
  end

  @doc """
  Execute a smart contract.
  
  Evaluates conditions and executes actions if conditions are met.
  """
  def execute_contract(contract_id) when is_binary(contract_id) do
    case get_contract(contract_id) do
      {:ok, contract} ->
        if contract.status == :active do
          execute_contract_internal(contract)
        else
          {:error, :contract_not_active}
        end

      error ->
        error
    end
  end

  @doc """
  Create a cron schedule for a contract.
  
  ## Parameters
  - `contract_id` - Smart contract ID
  - `cron_expression` - Cron expression (e.g., "0 0 * * *" for daily at midnight)
  - `opts` - Options:
    - `:metadata` - Additional metadata map
  """
  def create_schedule(contract_id, cron_expression, opts \\ [])
      when is_binary(contract_id) and is_binary(cron_expression) do
    schedule_id = generate_id()
    metadata = Keyword.get(opts, :metadata, %{})

    # Calculate next execution time from cron expression
    next_execution_at = calculate_next_execution(cron_expression)

    schedule = %{
      id: schedule_id,
      contract_id: contract_id,
      schedule_type: :cron,
      cron_expression: cron_expression,
      next_execution_at: next_execution_at,
      enabled: true,
      metadata: metadata
    }

    result =
      :mnesia.transaction(fn ->
        record = {
          Storage.schedules_table(),
          schedule_id,
          contract_id,
          :cron,
          cron_expression,
          next_execution_at,
          true,
          metadata
        }

        :mnesia.write(record)
        schedule
      end)

    case result do
      {:atomic, schedule} ->
        Logger.info("Created schedule for contract: #{contract_id} (#{schedule_id})")
        {:ok, schedule}

      {:aborted, reason} ->
        Logger.error("Failed to create schedule: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get contracts that should be executed now (for cron scheduling).
  """
  def get_due_contracts do
    now = System.system_time(:millisecond)

    result =
      :mnesia.transaction(fn ->
        :mnesia.foldl(
          fn {_table, _id, contract_id, _schedule_type, cron_expression, next_execution_at,
              enabled, _metadata},
             acc ->
            if enabled and next_execution_at <= now do
              [contract_id | acc]
            else
              acc
            end
          end,
          [],
          Storage.schedules_table()
        )
      end)

    case result do
      {:atomic, contract_ids} -> {:ok, contract_ids}
      {:aborted, reason} -> {:error, reason}
    end
  end

  @doc """
  Update contract status.
  """
  def update_status(contract_id, status)
      when is_binary(contract_id) and status in [:active, :paused, :completed, :cancelled] do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Storage.contracts_table(), contract_id) do
          [{_table, id, name, description, contract_type, business_contract_id, conditions,
            actions, _old_status, created_at, last_executed_at, metadata}] ->
            record = {
              Storage.contracts_table(),
              id,
              name,
              description,
              contract_type,
              business_contract_id,
              conditions,
              actions,
              status,
              created_at,
              last_executed_at,
              metadata
            }

            :mnesia.write(record)

            %{
              id: id,
              name: name,
              description: description,
              contract_type: contract_type,
              business_contract_id: business_contract_id,
              conditions: conditions,
              actions: actions,
              status: status,
              created_at: created_at,
              last_executed_at: last_executed_at,
              metadata: metadata
            }

          [] ->
            :mnesia.abort({:error, :not_found})
        end
      end)

    case result do
      {:atomic, contract} ->
        Logger.info("Updated contract status: #{contract_id} -> #{status}")
        {:ok, contract}

      {:aborted, {:error, :not_found}} ->
        {:error, :not_found}

      {:aborted, reason} ->
        Logger.error("Failed to update contract status: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private helpers

  defp execute_contract_internal(contract) do
    # Evaluate conditions
    conditions_met = evaluate_conditions(contract.conditions)

    if conditions_met do
      # Execute actions
      case execute_actions(contract.actions, contract) do
        {:ok, transaction_ids} ->
          # Record execution
          record_execution(contract.id, :success, transaction_ids)

          # Update last_executed_at
          update_last_executed(contract.id)

          Logger.info("Executed smart contract: #{contract.id}")
          {:ok, %{executed: true, transaction_ids: transaction_ids}}

        {:error, reason} ->
          record_execution(contract.id, :error, [], inspect(reason))
          Logger.error("Failed to execute smart contract: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.debug("Contract conditions not met: #{contract.id}")
      {:ok, %{executed: false, reason: "conditions_not_met"}}
    end
  end

  defp evaluate_conditions(conditions) do
    # Simple condition evaluation - in production, this would be more sophisticated
    Enum.all?(conditions, fn condition ->
      case condition["type"] || condition[:type] do
        "time" -> evaluate_time_condition(condition)
        "balance" -> evaluate_balance_condition(condition)
        "event" -> evaluate_event_condition(condition)
        _ -> true
      end
    end)
  end

  defp evaluate_time_condition(_condition) do
    # For now, always true - in production, check if time condition is met
    true
  end

  defp evaluate_balance_condition(_condition) do
    # For now, always true - in production, check account balances
    true
  end

  defp evaluate_event_condition(_condition) do
    # For now, always true - in production, check if event occurred
    true
  end

  defp execute_actions(actions, contract) do
    # Execute actions sequentially
    transaction_ids =
      Enum.reduce_while(actions, [], fn action, acc ->
        case execute_action(action, contract) do
          {:ok, tx_id} when is_binary(tx_id) -> {:cont, [tx_id | acc]}
          {:ok, tx_ids} when is_list(tx_ids) -> {:cont, tx_ids ++ acc}
          {:error, reason} -> {:halt, {:error, reason}}
          _ -> {:cont, acc}
        end
      end)

    case transaction_ids do
      {:error, reason} -> {:error, reason}
      _ -> {:ok, transaction_ids}
    end
  end

  defp execute_action(action, contract) do
    case action["type"] || action[:type] do
      "transfer" -> execute_transfer_action(action, contract)
      "invoice" -> execute_invoice_action(action, contract)
      "loan" -> execute_loan_action(action, contract)
      _ -> {:ok, nil}
    end
  end

  defp execute_transfer_action(action, _contract) do
    # In production, this would call Ledger.Core.transfer
    Logger.info("Executing transfer action: #{inspect(action)}")
    {:ok, generate_id()}
  end

  defp execute_invoice_action(action, _contract) do
    # In production, this would call Business.Transactions.purchase_invoice
    Logger.info("Executing invoice action: #{inspect(action)}")
    {:ok, generate_id()}
  end

  defp execute_loan_action(action, _contract) do
    # In production, this would call Business.Transactions.create_loan
    Logger.info("Executing loan action: #{inspect(action)}")
    {:ok, generate_id()}
  end

  defp record_execution(contract_id, status, transaction_ids, error_message \\ nil) do
    execution_id = generate_id()
    executed_at = System.system_time(:millisecond)

    result =
      :mnesia.transaction(fn ->
        record = {
          Storage.executions_table(),
          execution_id,
          contract_id,
          executed_at,
          status,
          %{transaction_ids: transaction_ids},
          transaction_ids,
          error_message,
          %{}
        }

        :mnesia.write(record)
      end)

    case result do
      {:atomic, _} -> :ok
      {:aborted, reason} -> Logger.error("Failed to record execution: #{inspect(reason)}")
    end
  end

  defp update_last_executed(contract_id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Storage.contracts_table(), contract_id) do
          [{_table, id, name, description, contract_type, business_contract_id, conditions,
            actions, status, created_at, _old_last_executed, metadata}] ->
            now = System.system_time(:millisecond)

            record = {
              Storage.contracts_table(),
              id,
              name,
              description,
              contract_type,
              business_contract_id,
              conditions,
              actions,
              status,
              created_at,
              now,
              metadata
            }

            :mnesia.write(record)

          [] ->
            :mnesia.abort({:error, :not_found})
        end
      end)

    case result do
      {:atomic, _} -> :ok
      {:aborted, _} -> :ok
    end
  end

  defp calculate_next_execution(cron_expression) do
    # Simple implementation - in production, use a proper cron parser
    # For now, assume daily execution
    now = System.system_time(:millisecond)
    now + 24 * 60 * 60 * 1000
  end

  defp fetch_all_contracts do
    :mnesia.foldl(
      fn {_table, id, name, description, contract_type, business_contract_id, conditions, actions,
          status, created_at, last_executed_at, metadata},
         acc ->
        contract = %{
          id: id,
          name: name,
          description: description,
          contract_type: contract_type,
          business_contract_id: business_contract_id,
          conditions: conditions,
          actions: actions,
          status: status,
          created_at: created_at,
          last_executed_at: last_executed_at,
          metadata: metadata
        }

        [contract | acc]
      end,
      [],
      Storage.contracts_table()
    )
  end

  defp apply_filters(contracts, contract_type_filter, status_filter) do
    contracts
    |> filter_by_type(contract_type_filter)
    |> filter_by_status(status_filter)
  end

  defp filter_by_type(contracts, nil), do: contracts
  defp filter_by_type(contracts, type), do: Enum.filter(contracts, &(&1.contract_type == type))

  defp filter_by_status(contracts, nil), do: contracts
  defp filter_by_status(contracts, status), do: Enum.filter(contracts, &(&1.status == status))

  defp sort_and_limit(contracts, limit) do
    contracts
    |> Enum.sort_by(& &1.created_at, :desc)
    |> Enum.take(limit)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end

