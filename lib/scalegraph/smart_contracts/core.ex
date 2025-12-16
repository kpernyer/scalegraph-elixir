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
  alias Scalegraph.Participant.Core, as: ParticipantCore
  alias Scalegraph.Ledger.Core, as: LedgerCore

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
             contract_type in [:loan, :invoice, :subscription, :revenue_share, :conditional_payment, :supplier_registration, :ecosystem_partner_membership, :generic] and
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
    # Evaluate conditions (pass contract for context like last_executed_at)
    conditions_met = evaluate_conditions(contract.conditions, contract)

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

  defp evaluate_conditions(conditions, contract) do
    # Simple condition evaluation - in production, this would be more sophisticated
    Enum.all?(conditions, fn condition ->
      case condition["type"] || condition[:type] do
        "time" -> evaluate_time_condition(condition, contract)
        "balance" -> evaluate_balance_condition(condition)
        "event" -> evaluate_event_condition(condition)
        _ -> true
      end
    end)
  end

  defp evaluate_time_condition(condition, contract) do
    params = condition["parameters"] || condition[:parameters] || %{}
    now = System.system_time(:millisecond)
    last_executed = contract.last_executed_at || 0

    # Check for expiration date
    expires_at = Map.get(params, "expires_at")
    if expires_at && now >= expires_at do
      # Contract has expired
      Logger.info("Contract #{contract.id} has expired")
      # Mark contract as completed
      update_status(contract.id, :completed)
      false
    else
      # Check for first payment date
      first_payment_date = Map.get(params, "first_payment_date")
      payment_interval_ms = Map.get(params, "payment_interval_ms")
      total_payments = Map.get(params, "total_payments")

      if first_payment_date && payment_interval_ms && total_payments do
        # Calculate which payment we should be on
        if now < first_payment_date do
          # Before first payment
          false
        else
          # Calculate payment number (0-indexed)
          payments_elapsed = div(now - first_payment_date, payment_interval_ms)

          if payments_elapsed >= total_payments do
            # All payments completed
            false
          else
            # Check if this payment has already been executed
            # We allow execution if we're past the payment date and haven't executed this payment yet
            payment_due_date = first_payment_date + (payments_elapsed * payment_interval_ms)
            # Allow execution if we're within the payment window (due date to next payment date)
            next_payment_date = first_payment_date + ((payments_elapsed + 1) * payment_interval_ms)

            if now >= payment_due_date && now < next_payment_date do
              # Check if we've already executed this payment
              # Simple check: if last_executed is before this payment's due date, we need to execute
              last_executed < payment_due_date
            else
              false
            end
          end
        end
      else
        # No time parameters, default to true (backward compatibility)
        true
      end
    end
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
      "supplier_monthly_fee" -> execute_supplier_monthly_fee_action(action, contract)
      _ -> {:ok, nil}
    end
  end

  defp execute_transfer_action(action, _contract) do
    alias Scalegraph.Ledger.Core, as: Ledger

    params = action["parameters"] || action[:parameters] || %{}
    from_account = Map.get(params, "from_account") || Map.get(params, :from_account)
    to_account = Map.get(params, "to_account") || Map.get(params, :to_account)
    amount = Map.get(params, "amount_cents") || Map.get(params, :amount_cents) || 0
    reference = Map.get(params, "reference") || Map.get(params, :reference) || "SMART_CONTRACT_TRANSFER"

    if from_account && to_account && amount > 0 do
      entries = [
        {from_account, -amount},
        {to_account, amount}
      ]

      case Ledger.transfer(entries, reference) do
        {:ok, tx} ->
          Logger.info("Executed transfer action: #{from_account} -> #{to_account}, amount: #{amount}")
          {:ok, tx.id}

        {:error, reason} ->
          Logger.error("Failed to execute transfer action: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.error("Invalid transfer action parameters: #{inspect(params)}")
      {:error, :invalid_parameters}
    end
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
  
  defp execute_supplier_monthly_fee_action(action, contract) do
    params = action["parameters"] || action[:parameters] || %{}
    metadata = contract.metadata || %{}
    
    # Check if monthly fee has started
    if Map.get(metadata, "monthly_fee_started", false) do
      # Check if we've already executed this month
      now = System.system_time(:millisecond)
      last_monthly_fee_at = Map.get(metadata, "last_monthly_fee_at", 0)
      
      # One month in milliseconds (approximately 30 days)
      one_month_ms = 30 * 24 * 60 * 60 * 1000
      
      if now - last_monthly_fee_at >= one_month_ms do
        # Execute monthly fee
        case execute_supplier_monthly_fee(contract, metadata) do
          {:ok, tx_id} ->
            # Update last monthly fee execution time
            updated_metadata = Map.put(metadata, "last_monthly_fee_at", now)
            update_contract_metadata(contract.id, updated_metadata)
            {:ok, tx_id}
          
          error ->
            error
        end
      else
        Logger.debug("Monthly fee already executed this month for supplier: #{Map.get(metadata, "supplier_id")}")
        {:ok, nil}
      end
    else
      Logger.debug("Monthly fee not yet started for supplier: #{Map.get(metadata, "supplier_id")}")
      {:ok, nil}
    end
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

  @doc """
  Create a supplier registration contract.
  
  This contract handles:
  - One-time registration fee of 50 euros (5000 cents) to orchestrator
  - Monthly fee of 100 euros (10000 cents) starting when first ecosystem provider uses their service
  - 90% of monthly fee to orchestrator, 10% to first provider
  - Valid for one year from creation
  
  ## Parameters
  - `supplier_id` - ID of the supplier participant
  - `opts` - Options:
    - `:orchestrator_id` - Optional orchestrator ID (will be found automatically if not provided)
  
  ## Returns
  - `{:ok, contract}` - Contract created successfully
  - `{:error, reason}` - Error creating contract
  """
  def create_supplier_registration_contract(supplier_id, opts \\ [])
      when is_binary(supplier_id) do
    # Find ecosystem orchestrator
    orchestrator_id = Keyword.get(opts, :orchestrator_id)
    
    orchestrator_id = if orchestrator_id do
      orchestrator_id
    else
      case find_ecosystem_orchestrator() do
        {:ok, id} -> id
        {:error, reason} -> 
          Logger.error("Failed to find ecosystem orchestrator: #{inspect(reason)}")
          {:error, :orchestrator_not_found}
      end
    end
    
    # Return early if orchestrator not found
    if is_tuple(orchestrator_id) and elem(orchestrator_id, 0) == :error do
      orchestrator_id
    else
    
      # Verify supplier exists
      case ParticipantCore.get_participant(supplier_id) do
        {:ok, supplier} ->
          if supplier.role != :supplier do
            {:error, {:invalid_role, "Participant must be a supplier"}}
          else
            create_supplier_registration_contract_internal(supplier_id, orchestrator_id)
          end
        
        {:error, :not_found} ->
          {:error, :supplier_not_found}
        
        error ->
          error
      end
    end
  end
  
  defp find_ecosystem_orchestrator do
    case ParticipantCore.list_participants(:ecosystem_orchestrator) do
      {:ok, []} ->
        {:error, :orchestrator_not_found}
      
      {:ok, [orchestrator | _]} ->
        {:ok, orchestrator.id}
      
      error ->
        error
    end
  end
  
  defp create_supplier_registration_contract_internal(supplier_id, orchestrator_id) do
    created_at = System.system_time(:millisecond)
    one_year_ms = 365 * 24 * 60 * 60 * 1000
    expires_at = created_at + one_year_ms
    
    # Registration fee: 50 euros = 5000 cents
    registration_fee_cents = 5000
    
    # Monthly fee: 100 euros = 10000 cents
    monthly_fee_cents = 10000
    
    # Get supplier's operating account
    supplier_account_id = "#{supplier_id}:operating"
    
    # Get orchestrator's fees account (or operating if fees doesn't exist)
    orchestrator_account_id = "#{orchestrator_id}:fees"
    
    # Ensure orchestrator has a fees account
    case LedgerCore.get_account(orchestrator_account_id) do
      {:error, :not_found} ->
        # Create fees account if it doesn't exist
        case ParticipantCore.create_participant_account(orchestrator_id, :fees, 0) do
          {:ok, _} -> :ok
          error -> error
        end
      {:ok, _} -> :ok
    end
    
    # Create registration fee action (immediate)
    registration_action = %{
      "type" => "transfer",
      "parameters" => %{
        "from_account" => supplier_account_id,
        "to_account" => orchestrator_account_id,
        "amount_cents" => registration_fee_cents,
        "reference" => "SUPPLIER_REGISTRATION_FEE:#{supplier_id}"
      }
    }
    
    # Create monthly fee action (triggered by first usage)
    # This will be executed monthly after first ecosystem provider uses the service
    monthly_fee_action = %{
      "type" => "supplier_monthly_fee",
      "parameters" => %{
        "supplier_id" => supplier_id,
        "orchestrator_id" => orchestrator_id,
        "monthly_fee_cents" => monthly_fee_cents,
        "orchestrator_share" => 0.9,
        "first_provider_share" => 0.1
      }
    }
    
    # Conditions: contract expires after one year
    conditions = [
      %{
        "type" => "time",
        "parameters" => %{
          "expires_at" => expires_at
        }
      }
    ]
    
    # Actions: registration fee (immediate) and monthly fee (triggered)
    actions = [registration_action, monthly_fee_action]
    
    metadata = %{
      "supplier_id" => supplier_id,
      "orchestrator_id" => orchestrator_id,
      "registration_fee_cents" => registration_fee_cents,
      "monthly_fee_cents" => monthly_fee_cents,
      "created_at" => created_at,
      "expires_at" => expires_at,
      "first_provider_id" => nil,  # Will be set when first provider uses the service
      "monthly_fee_started" => false
    }
    
    # Create the contract
    case create_contract(
      "Supplier Registration: #{supplier_id}",
      "Supplier registration contract with registration fee and monthly fees",
      :supplier_registration,
      nil,
      conditions,
      actions,
      metadata: metadata
    ) do
      {:ok, contract} ->
        # Execute registration fee immediately
        case execute_transfer_action(registration_action, contract) do
          {:ok, tx_id} ->
            Logger.info("Supplier registration fee paid: #{supplier_id} -> #{orchestrator_id}, #{registration_fee_cents} cents")
            
            # Create monthly schedule (will be activated when first provider uses the service)
            # Schedule for 1st of each month at midnight
            case create_schedule(contract.id, "0 0 1 * *", metadata: %{"type" => "supplier_monthly_fee"}) do
              {:ok, _schedule} ->
                Logger.info("Created monthly schedule for supplier registration: #{supplier_id}")
                {:ok, contract}
              
              {:error, reason} ->
                Logger.warning("Failed to create monthly schedule: #{inspect(reason)}, but contract created")
                {:ok, contract}
            end
          
          {:error, reason} ->
            Logger.error("Failed to execute registration fee: #{inspect(reason)}")
            # Contract was created but fee payment failed - this is a problem
            # We could delete the contract or mark it as failed
            {:error, {:registration_fee_failed, reason}}
        end
      
      error ->
        error
    end
  end
  
  @doc """
  Get supplier registration contract for a supplier.
  """
  def get_supplier_registration_contract(supplier_id) when is_binary(supplier_id) do
    find_supplier_registration_contract(supplier_id)
  end
  
  @doc """
  Trigger monthly fee for supplier registration contract.
  
  This should be called when an ecosystem provider first uses a supplier's service.
  It will:
  1. Record the first provider ID
  2. Start monthly fee billing
  3. Execute the first monthly fee payment
  
  ## Parameters
  - `supplier_id` - ID of the supplier
  - `first_provider_id` - ID of the first ecosystem provider to use the service
  """
  def trigger_supplier_monthly_fee(supplier_id, first_provider_id)
      when is_binary(supplier_id) and is_binary(first_provider_id) do
    # Find the supplier registration contract
    case find_supplier_registration_contract(supplier_id) do
      {:ok, contract} ->
        metadata = contract.metadata || %{}
        
        # Check if monthly fee has already started
        if Map.get(metadata, "monthly_fee_started", false) do
          {:ok, :already_started}
        else
          # Update contract metadata with first provider
          now = System.system_time(:millisecond)
          updated_metadata = Map.merge(metadata, %{
            "first_provider_id" => first_provider_id,
            "monthly_fee_started" => true,
            "monthly_fee_started_at" => now,
            "last_monthly_fee_at" => now  # Set initial timestamp for first payment
          })
          
          # Update contract with new metadata
          case update_contract_metadata(contract.id, updated_metadata) do
            {:ok, updated_contract} ->
              # Execute first monthly fee immediately
              case execute_supplier_monthly_fee(updated_contract, updated_metadata) do
                {:ok, tx_id} ->
                  Logger.info("First monthly fee executed for supplier: #{supplier_id}, triggered by provider: #{first_provider_id}")
                  {:ok, :started}
                
                error ->
                  Logger.error("Failed to execute first monthly fee: #{inspect(error)}")
                  error
              end
            
            error ->
              error
          end
        end
      
      {:error, :not_found} ->
        {:error, :contract_not_found}
      
      error ->
        error
    end
  end
  
  defp find_supplier_registration_contract(supplier_id) do
    case list_contracts(contract_type: :supplier_registration) do
      {:ok, contracts} ->
        contract = Enum.find(contracts, fn c ->
          metadata = c.metadata || %{}
          Map.get(metadata, "supplier_id") == supplier_id
        end)
        
        if contract do
          {:ok, contract}
        else
          {:error, :not_found}
        end
      
      error ->
        error
    end
  end
  
  defp update_contract_metadata(contract_id, new_metadata) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Storage.contracts_table(), contract_id) do
          [{_table, id, name, description, contract_type, business_contract_id, conditions,
            actions, status, created_at, last_executed_at, _old_metadata}] ->
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
              new_metadata
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
              metadata: new_metadata
            }
          
          [] ->
            :mnesia.abort({:error, :not_found})
        end
      end)
    
    case result do
      {:atomic, contract} -> {:ok, contract}
      {:aborted, {:error, :not_found}} -> {:error, :not_found}
      {:aborted, reason} -> {:error, reason}
    end
  end
  
  defp execute_supplier_monthly_fee(contract, metadata) do
    supplier_id = Map.get(metadata, "supplier_id")
    orchestrator_id = Map.get(metadata, "orchestrator_id")
    first_provider_id = Map.get(metadata, "first_provider_id")
    monthly_fee_cents = Map.get(metadata, "monthly_fee_cents", 10000)
    orchestrator_share = Map.get(metadata, "orchestrator_share", 0.9)
    first_provider_share = Map.get(metadata, "first_provider_share", 0.1)
    expires_at = Map.get(metadata, "expires_at")
    
    # Check if contract has expired
    now = System.system_time(:millisecond)
    if expires_at && now >= expires_at do
      Logger.info("Supplier registration contract expired: #{supplier_id}")
      update_status(contract.id, :completed)
      {:error, :contract_expired}
    else
      supplier_account_id = "#{supplier_id}:operating"
      orchestrator_account_id = "#{orchestrator_id}:fees"
      first_provider_account_id = "#{first_provider_id}:operating"
      
      orchestrator_amount = round(monthly_fee_cents * orchestrator_share)
      first_provider_amount = round(monthly_fee_cents * first_provider_share)
      
      # Create transfer entries: supplier pays, orchestrator and first provider receive
      entries = [
        {supplier_account_id, -monthly_fee_cents},
        {orchestrator_account_id, orchestrator_amount},
        {first_provider_account_id, first_provider_amount}
      ]
      
      reference = "SUPPLIER_MONTHLY_FEE:#{supplier_id}:#{System.system_time(:millisecond)}"
      
      case LedgerCore.transfer(entries, reference) do
        {:ok, tx} ->
          Logger.info("Supplier monthly fee paid: #{supplier_id} -> orchestrator: #{orchestrator_amount}, first provider: #{first_provider_amount}")
          {:ok, tx.id}
        
        {:error, reason} ->
          Logger.error("Failed to execute supplier monthly fee: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Create an ecosystem partner membership contract.
  
  This contract manages payments between the ecosystem orchestrator and ecosystem partners.
  When a new ecosystem partner accepts the rules, they are automatically added to this contract.
  
  ## Parameters
  - `orchestrator_id` - ID of the ecosystem orchestrator
  - `opts` - Options:
    - `:monthly_fee_cents` - Monthly fee per partner in cents (default: 5000 = 50 EUR)
    - `:grace_period_months` - Months before first payment (default: 1)
    - `:payment_months` - Number of monthly payments after grace period (default: 11, total 12 months)
    - `:metadata` - Additional metadata map
  
  ## Returns
  - `{:ok, contract}` - Contract created successfully
  - `{:error, reason}` - Error creating contract
  """
  def create_ecosystem_partner_membership_contract(orchestrator_id, opts \\ [])
      when is_binary(orchestrator_id) do
    # Verify orchestrator exists and has correct role
    case ParticipantCore.get_participant(orchestrator_id) do
      {:ok, orchestrator} ->
        if orchestrator.role != :ecosystem_orchestrator do
          {:error, {:invalid_role, "Participant must be an ecosystem orchestrator"}}
        else
          create_ecosystem_partner_membership_contract_internal(orchestrator_id, opts)
        end
      
      {:error, :not_found} ->
        {:error, :orchestrator_not_found}
      
      error ->
        error
    end
  end
  
  defp create_ecosystem_partner_membership_contract_internal(orchestrator_id, opts) do
    monthly_fee_cents = Keyword.get(opts, :monthly_fee_cents, 5000)  # 50 EUR default
    grace_period_months = Keyword.get(opts, :grace_period_months, 1)
    payment_months = Keyword.get(opts, :payment_months, 11)  # Total 12 months (1 grace + 11 payments)
    metadata = Keyword.get(opts, :metadata, %{})
    
    created_at = System.system_time(:millisecond)
    
    # Calculate dates
    one_month_ms = 30 * 24 * 60 * 60 * 1000
    grace_period_ms = grace_period_months * one_month_ms
    first_payment_date = created_at + grace_period_ms
    payment_interval_ms = one_month_ms
    total_payments = payment_months
    contract_end_date = first_payment_date + (total_payments * payment_interval_ms)
    
    # Get orchestrator's fees account (or operating if fees doesn't exist)
    orchestrator_account_id = "#{orchestrator_id}:fees"
    
    # Ensure orchestrator has a fees account
    case LedgerCore.get_account(orchestrator_account_id) do
      {:error, :not_found} ->
        case ParticipantCore.create_participant_account(orchestrator_id, :fees, 0) do
          {:ok, _} -> :ok
          error -> error
        end
      {:ok, _} -> :ok
    end
    
    # Conditions: time-based payment schedule
    conditions = [
      %{
        "type" => "time",
        "parameters" => %{
          "first_payment_date" => first_payment_date,
          "payment_interval_ms" => payment_interval_ms,
          "total_payments" => total_payments,
          "expires_at" => contract_end_date
        }
      }
    ]
    
    # Actions will be dynamically generated for each partner
    # For now, create a placeholder action that will be updated as partners are added
    actions = []
    
    contract_metadata = Map.merge(metadata, %{
      "orchestrator_id" => orchestrator_id,
      "orchestrator_account_id" => orchestrator_account_id,
      "monthly_fee_cents" => monthly_fee_cents,
      "grace_period_months" => grace_period_months,
      "payment_months" => payment_months,
      "first_payment_date" => first_payment_date,
      "payment_interval_ms" => payment_interval_ms,
      "total_payments" => total_payments,
      "contract_end_date" => contract_end_date,
      "partner_ids" => [],  # Will be populated as partners accept rules
      "created_at" => created_at
    })
    
    # Create the contract
    case create_contract(
      "Ecosystem Partner Membership: #{orchestrator_id}",
      "Membership contract for ecosystem partners with the orchestrator",
      :ecosystem_partner_membership,
      nil,
      conditions,
      actions,
      metadata: contract_metadata
    ) do
      {:ok, contract} ->
        # Create schedule for monthly payments (1st of each month at midnight)
        case create_schedule(contract.id, "0 0 1 * *", metadata: %{"type" => "ecosystem_partner_membership"}) do
          {:ok, _schedule} ->
            Logger.info("Created ecosystem partner membership contract: #{contract.id}")
            {:ok, contract}
          
          {:error, reason} ->
            Logger.warning("Failed to create schedule: #{inspect(reason)}, but contract created")
            {:ok, contract}
        end
      
      error ->
        error
    end
  end
  
  @doc """
  Get the ecosystem partner membership contract for an orchestrator.
  
  Returns the contract if it exists, or creates a new one if it doesn't.
  """
  def get_or_create_ecosystem_partner_membership_contract(orchestrator_id, opts \\ [])
      when is_binary(orchestrator_id) do
    case find_ecosystem_partner_membership_contract(orchestrator_id) do
      {:ok, contract} ->
        {:ok, contract}
      
      {:error, :not_found} ->
        # Create new contract
        create_ecosystem_partner_membership_contract(orchestrator_id, opts)
      
      error ->
        error
    end
  end
  
  @doc """
  Add an ecosystem partner to the membership contract when they accept the rules.
  
  This function:
  1. Finds or creates the ecosystem partner membership contract
  2. Adds the partner to the contract's participant list
  3. Updates the contract actions to include payments from the new partner
  
  ## Parameters
  - `partner_id` - ID of the ecosystem partner accepting the rules
  - `orchestrator_id` - ID of the ecosystem orchestrator (optional, will be found if not provided)
  - `opts` - Options:
    - `:metadata` - Additional metadata map
  
  ## Returns
  - `{:ok, contract}` - Partner added successfully
  - `{:error, reason}` - Error adding partner
  """
  def add_ecosystem_partner_to_membership(partner_id, orchestrator_id \\ nil, opts \\ [])
      when is_binary(partner_id) do
    # Verify partner exists and has correct role
    case ParticipantCore.get_participant(partner_id) do
      {:ok, partner} ->
        if partner.role != :ecosystem_partner do
          {:error, {:invalid_role, "Participant must be an ecosystem partner"}}
        else
          # Find orchestrator if not provided
          final_orchestrator_id = if orchestrator_id do
            orchestrator_id
          else
            case find_ecosystem_orchestrator() do
              {:ok, id} -> id
              {:error, reason} -> 
                Logger.error("Failed to find ecosystem orchestrator: #{inspect(reason)}")
                {:error, :orchestrator_not_found}
            end
          end
          
          # Return early if orchestrator not found
          if is_tuple(final_orchestrator_id) and elem(final_orchestrator_id, 0) == :error do
            final_orchestrator_id
          else
            # Get or create the contract
            case get_or_create_ecosystem_partner_membership_contract(final_orchestrator_id, opts) do
              {:ok, contract} ->
                add_partner_to_contract(contract, partner_id, final_orchestrator_id)
              
              error ->
                error
            end
          end
        end
      
      {:error, :not_found} ->
        {:error, :partner_not_found}
      
      error ->
        error
    end
  end
  
  defp add_partner_to_contract(contract, partner_id, orchestrator_id) do
    metadata = contract.metadata || %{}
    partner_ids = Map.get(metadata, "partner_ids", [])
    
    # Check if partner is already in the contract
    if partner_id in partner_ids do
      Logger.info("Partner #{partner_id} is already in the ecosystem partner membership contract")
      {:ok, contract}
    else
      # Ensure partner has an operating account
      partner_account_id = "#{partner_id}:operating"
      account_result = case LedgerCore.get_account(partner_account_id) do
        {:error, :not_found} ->
          ParticipantCore.create_participant_account(partner_id, :operating, 0)
        {:ok, _} -> :ok
      end
      
      # Return early if account creation failed
      case account_result do
        {:error, _} = error -> 
          error
        
        :ok ->
          # Add partner to the list
          updated_partner_ids = [partner_id | partner_ids]
          orchestrator_account_id = Map.get(metadata, "orchestrator_account_id", "#{orchestrator_id}:fees")
          monthly_fee_cents = Map.get(metadata, "monthly_fee_cents", 5000)
          
          # Create payment action for this partner
          partner_payment_action = %{
            "type" => "transfer",
            "parameters" => %{
              "from_account" => partner_account_id,
              "to_account" => orchestrator_account_id,
              "amount_cents" => monthly_fee_cents,
              "reference" => "ECOSYSTEM_PARTNER_MEMBERSHIP:#{partner_id}"
            }
          }
          
          # Update contract actions to include this partner's payment
          updated_actions = [partner_payment_action | contract.actions]
          
          # Update metadata
          updated_metadata = Map.merge(metadata, %{
            "partner_ids" => updated_partner_ids,
            "last_partner_added_at" => System.system_time(:millisecond),
            "last_partner_id" => partner_id
          })
          
          # Update the contract
          case update_contract_actions_and_metadata(contract.id, updated_actions, updated_metadata) do
            {:ok, updated_contract} ->
              Logger.info("Added ecosystem partner #{partner_id} to membership contract: #{contract.id}")
              {:ok, updated_contract}
            
            error ->
              error
          end
      end
    end
  end
  
  defp find_ecosystem_partner_membership_contract(orchestrator_id) do
    case list_contracts(contract_type: :ecosystem_partner_membership) do
      {:ok, contracts} ->
        contract = Enum.find(contracts, fn c ->
          metadata = c.metadata || %{}
          Map.get(metadata, "orchestrator_id") == orchestrator_id
        end)
        
        if contract do
          {:ok, contract}
        else
          {:error, :not_found}
        end
      
      error ->
        error
    end
  end
  
  defp update_contract_actions_and_metadata(contract_id, new_actions, new_metadata) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Storage.contracts_table(), contract_id) do
          [{_table, id, name, description, contract_type, business_contract_id, conditions,
            _old_actions, status, created_at, last_executed_at, _old_metadata}] ->
            record = {
              Storage.contracts_table(),
              id,
              name,
              description,
              contract_type,
              business_contract_id,
              conditions,
              new_actions,
              status,
              created_at,
              last_executed_at,
              new_metadata
            }
            
            :mnesia.write(record)
            
            %{
              id: id,
              name: name,
              description: description,
              contract_type: contract_type,
              business_contract_id: business_contract_id,
              conditions: conditions,
              actions: new_actions,
              status: status,
              created_at: created_at,
              last_executed_at: last_executed_at,
              metadata: new_metadata
            }
          
          [] ->
            :mnesia.abort({:error, :not_found})
        end
      end)
    
    case result do
      {:atomic, contract} ->
        Logger.info("Updated contract actions and metadata: #{contract_id}")
        {:ok, contract}
      
      {:aborted, {:error, :not_found}} ->
        {:error, :not_found}
      
      {:aborted, reason} ->
        Logger.error("Failed to update contract actions and metadata: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end

