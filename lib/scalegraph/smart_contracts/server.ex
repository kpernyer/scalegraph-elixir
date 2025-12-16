defmodule Scalegraph.SmartContracts.Server do
  @moduledoc """
  gRPC server implementation for the Smart Contracts service.
  
  This server exposes smart contract operations including:
  - Contract creation and management
  - Contract listing and querying
  - Contract execution
  - Status updates
  """

  use GRPC.Server, service: Scalegraph.Smartcontracts.SmartContractService.Service

  require Logger

  alias Scalegraph.SmartContracts.Core
  alias Scalegraph.Smartcontracts

  @doc """
  List all contracts with optional filters.
  """
  def list_contracts(request, _stream) do
    # Convert proto contract type to atom
    contract_type = case request.contract_type do
      0 -> nil  # CONTRACT_TYPE_UNSPECIFIED
      1 -> :loan
      2 -> :invoice
      3 -> :subscription
      4 -> :conditional_payment
      5 -> :revenue_share
      6 -> :supplier_registration
      _ -> nil
    end

    # Convert status string to atom
    status = if request.status != "" do
      case request.status do
        "active" -> :active
        "paused" -> :paused
        "completed" -> :completed
        "cancelled" -> :cancelled
        _ -> nil
      end
    else
      nil
    end

    opts = [
      contract_type: contract_type,
      status: status,
      limit: request.limit
    ]

    case Core.list_contracts(opts) do
      {:ok, contracts} ->
        contract_responses = Enum.map(contracts, &contract_to_proto/1)
        
        %Smartcontracts.ListContractsResponse{
          contracts: contract_responses
        }

      {:error, reason} ->
        Logger.error("Failed to list contracts: #{inspect(reason)}")
        raise GRPC.RPCError, status: :internal, message: "Failed to list contracts: #{inspect(reason)}"
    end
  end

  @doc """
  Get a contract by ID and type.
  """
  def get_contract(request, _stream) do
    case Core.get_contract(request.contract_id) do
      {:ok, contract} ->
        contract_to_proto(contract)

      {:error, :not_found} ->
        raise GRPC.RPCError, status: :not_found, message: "Contract not found: #{request.contract_id}"

      {:error, reason} ->
        Logger.error("Failed to get contract: #{inspect(reason)}")
        raise GRPC.RPCError, status: :internal, message: "Failed to get contract: #{inspect(reason)}"
    end
  end

  @doc """
  Execute a contract.
  """
  def execute_contract(request, _stream) do
    case Core.execute_contract(request.contract_id) do
      {:ok, %{executed: true, transaction_ids: tx_ids}} ->
        %Smartcontracts.ExecuteContractResponse{
          contract_id: request.contract_id,
          executed: true,
          message: "Contract executed successfully",
          transaction_ids: tx_ids || []
        }

      {:ok, %{executed: false, reason: reason}} ->
        %Smartcontracts.ExecuteContractResponse{
          contract_id: request.contract_id,
          executed: false,
          message: "Contract not executed: #{reason}",
          transaction_ids: []
        }

      {:error, :not_found} ->
        raise GRPC.RPCError, status: :not_found, message: "Contract not found: #{request.contract_id}"

      {:error, :contract_not_active} ->
        raise GRPC.RPCError, status: :failed_precondition, message: "Contract is not active: #{request.contract_id}"

      {:error, reason} ->
        Logger.error("Failed to execute contract: #{inspect(reason)}")
        raise GRPC.RPCError, status: :internal, message: "Failed to execute contract: #{inspect(reason)}"
    end
  end

  @doc """
  Update contract status.
  """
  def update_contract_status(request, _stream) do
    # Convert proto status to atom
    status = case request.status do
      0 -> :active  # CONTRACT_STATUS_UNSPECIFIED -> active
      1 -> :active
      2 -> :paused
      3 -> :completed
      4 -> :cancelled
      _ -> :active
    end

    case Core.update_status(request.contract_id, status) do
      {:ok, contract} ->
        contract_to_proto(contract)

      {:error, :not_found} ->
        raise GRPC.RPCError, status: :not_found, message: "Contract not found: #{request.contract_id}"

      {:error, reason} ->
        Logger.error("Failed to update contract status: #{inspect(reason)}")
        raise GRPC.RPCError, status: :internal, message: "Failed to update contract status: #{inspect(reason)}"
    end
  end

  # Placeholder implementations for contract-specific operations
  # These can be implemented later if needed

  def create_invoice_contract(_request, _stream) do
    raise GRPC.RPCError, status: :unimplemented, message: "Not yet implemented"
  end

  def get_invoice_contract(_request, _stream) do
    raise GRPC.RPCError, status: :unimplemented, message: "Not yet implemented"
  end

  def create_subscription_contract(_request, _stream) do
    raise GRPC.RPCError, status: :unimplemented, message: "Not yet implemented"
  end

  def get_subscription_contract(_request, _stream) do
    raise GRPC.RPCError, status: :unimplemented, message: "Not yet implemented"
  end

  def create_conditional_payment(_request, _stream) do
    raise GRPC.RPCError, status: :unimplemented, message: "Not yet implemented"
  end

  def get_conditional_payment(_request, _stream) do
    raise GRPC.RPCError, status: :unimplemented, message: "Not yet implemented"
  end

  def create_revenue_share_contract(_request, _stream) do
    raise GRPC.RPCError, status: :unimplemented, message: "Not yet implemented"
  end

  def get_revenue_share_contract(_request, _stream) do
    raise GRPC.RPCError, status: :unimplemented, message: "Not yet implemented"
  end

  @doc """
  Create a generic contract from YAML definition.
  """
  def create_generic_contract(request, _stream) do
    alias Scalegraph.SmartContracts.YamlParser
    
    yaml_content = cond do
      request.yaml_content != "" -> request.yaml_content
      request.yaml_file_path != "" -> 
        case File.read(request.yaml_file_path) do
          {:ok, content} -> content
          {:error, reason} ->
            raise GRPC.RPCError, status: :not_found, 
              message: "Failed to read YAML file: #{request.yaml_file_path}, reason: #{inspect(reason)}"
        end
      true ->
        raise GRPC.RPCError, status: :invalid_argument, 
          message: "Either yaml_content or yaml_file_path must be provided"
    end
    
    # Convert variables map from proto to Elixir map
    variables = Map.new(request.variables || [])
    
    case YamlParser.parse_and_create(yaml_content, variables: variables) do
      {:ok, contract} ->
        contract_to_generic_proto(contract)
      
      {:error, {:yaml_parse_error, reason}} ->
        Logger.error("Failed to parse YAML: #{inspect(reason)}")
        raise GRPC.RPCError, status: :invalid_argument, 
          message: "Failed to parse YAML: #{inspect(reason)}"
      
      {:error, {:contract_creation_failed, reason}} ->
        Logger.error("Failed to create contract: #{inspect(reason)}")
        raise GRPC.RPCError, status: :internal, 
          message: "Failed to create contract: #{inspect(reason)}"
      
      {:error, reason} ->
        Logger.error("Unexpected error: #{inspect(reason)}")
        raise GRPC.RPCError, status: :internal, 
          message: "Unexpected error: #{inspect(reason)}"
    end
  end

  # Private helpers

  defp contract_to_proto(contract) do
    # Convert internal contract to generic proto contract
    generic_contract = contract_to_generic_proto(contract)
    
    %Smartcontracts.ContractResponse{
      contract: {:generic, generic_contract}
    }
  end

  defp contract_to_generic_proto(contract) do
    # Convert contract type atom to proto enum
    contract_type_enum = case contract.contract_type do
      :loan -> 1
      :invoice -> 2
      :subscription -> 3
      :conditional_payment -> 4
      :revenue_share -> 5
      :supplier_registration -> 6
      :ecosystem_partner_membership -> 7
      :generic -> 0
      _ -> 0
    end
    
    # Convert status atom to proto enum
    status_enum = case contract.status do
      :active -> 1
      :paused -> 2
      :completed -> 3
      :cancelled -> 4
      _ -> 1
    end
    
    # Convert conditions
    conditions = Enum.map(contract.conditions || [], fn condition ->
      %Smartcontracts.Condition{
        type: condition["type"] || condition[:type] || "custom",
        parameters: Map.new(condition["parameters"] || condition[:parameters] || %{})
      }
    end)
    
    # Convert actions
    actions = Enum.map(contract.actions || [], fn action ->
      %Smartcontracts.Action{
        type: action["type"] || action[:type] || "custom",
        parameters: Map.new(action["parameters"] || action[:parameters] || %{})
      }
    end)
    
    # Extract next execution time
    next_execution = extract_execution_time(contract, contract.metadata || %{})
    
    # Get YAML source from metadata
    yaml_source = Map.get(contract.metadata || %{}, "yaml_source", "")
    
    %Smartcontracts.GenericContract{
      id: contract.id,
      name: contract.name,
      description: contract.description || "",
      contract_type: contract_type_enum,
      status: status_enum,
      created_at: contract.created_at,
      last_executed_at: contract.last_executed_at || 0,
      next_execution_at: next_execution,
      conditions: conditions,
      actions: actions,
      metadata: Map.new(contract.metadata || %{}),
      yaml_source: yaml_source
    }
  end

  defp extract_execution_time(contract, metadata) do
    # Try to extract next execution time from various sources
    cond do
      # Check for next_billing_date (subscriptions)
      Map.has_key?(metadata, "next_billing_date") ->
        Map.get(metadata, "next_billing_date")
      
      # Check for due_date (invoices)
      Map.has_key?(metadata, "due_date") ->
        Map.get(metadata, "due_date")
      
      # Check for expires_at
      Map.has_key?(metadata, "expires_at") ->
        Map.get(metadata, "expires_at")
      
      # Check for first_payment_date
      Map.has_key?(metadata, "first_payment_date") ->
        Map.get(metadata, "first_payment_date")
      
      # Check conditions for time-based execution
      is_list(contract.conditions) ->
        extract_time_from_conditions(contract.conditions)
      
      true ->
        0
    end
  end

  defp extract_time_from_conditions(conditions) do
    Enum.reduce(conditions, 0, fn condition, acc ->
      params = condition["parameters"] || condition[:parameters] || %{}
      cond do
        Map.has_key?(params, "expires_at") -> max(acc, Map.get(params, "expires_at", 0))
        Map.has_key?(params, "first_payment_date") -> max(acc, Map.get(params, "first_payment_date", 0))
        Map.has_key?(params, "next_billing_date") -> max(acc, Map.get(params, "next_billing_date", 0))
        true -> acc
      end
    end)
  end
end

