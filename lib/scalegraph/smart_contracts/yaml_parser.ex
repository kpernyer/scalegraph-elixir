defmodule Scalegraph.SmartContracts.YamlParser do
  @moduledoc """
  YAML parser for generic smart contracts.
  
  This module parses YAML contract definitions and converts them to contract structures
  that can be stored and executed by the smart contracts system.
  
  ## YAML Contract Format
  
  ```yaml
  name: "Contract Name"
  description: "Contract description"
  type: supplier_registration  # Contract type (atom or string)
  status: active  # active, paused, completed, cancelled
  
  conditions:
    - type: time
      parameters:
        expires_at: 1234567890000  # Unix timestamp in milliseconds
        first_payment_date: 1234567890000
        payment_interval_ms: 2592000000  # 30 days
        total_payments: 12
  
    - type: balance
      parameters:
        account_id: "supplier:operating"
        min_balance: 10000
  
    - type: event
      parameters:
        event_type: "first_provider_usage"
        supplier_id: "supplier_123"
  
  actions:
    - type: transfer
      parameters:
        from_account: "supplier:operating"
        to_account: "orchestrator:fees"
        amount_cents: 5000
        reference: "SUPPLIER_REGISTRATION_FEE"
  
    - type: supplier_monthly_fee
      parameters:
        supplier_id: "supplier_123"
        orchestrator_id: "beauty_hosting"
        monthly_fee_cents: 10000
        orchestrator_share: 0.9
        first_provider_share: 0.1
  
  metadata:
    supplier_id: "supplier_123"
    orchestrator_id: "beauty_hosting"
    registration_fee_cents: 5000
    monthly_fee_cents: 10000
  ```
  """

  require Logger

  alias Scalegraph.SmartContracts.Core

  @doc """
  Parse a YAML contract definition and create a contract.
  
  ## Parameters
  - `yaml_content` - YAML string content
  - `opts` - Options:
    - `:variables` - Map of variables to substitute in YAML (e.g., %{"supplier_id" => "supplier_123"})
  
  ## Returns
  - `{:ok, contract}` - Contract created successfully
  - `{:error, reason}` - Error parsing or creating contract
  """
  def parse_and_create(yaml_content, opts \\ []) do
    variables = Keyword.get(opts, :variables, %{})
    
    case parse_yaml(yaml_content, variables) do
      {:ok, contract_def} ->
        create_from_definition(contract_def, yaml_content)
      
      {:error, reason} ->
        {:error, {:yaml_parse_error, reason}}
    end
  end

  @doc """
  Parse a YAML file and create a contract.
  """
  def parse_file_and_create(file_path, opts \\ []) do
    case File.read(file_path) do
      {:ok, content} ->
        parse_and_create(content, opts)
      
      {:error, reason} ->
        {:error, {:file_read_error, reason}}
    end
  end

  @doc """
  Parse YAML content into a contract definition map.
  """
  def parse_yaml(yaml_content, variables \\ %{}) do
    case YamlElixir.read_from_string(yaml_content) do
      {:ok, data} ->
        # Substitute variables
        substituted = substitute_variables(data, variables)
        
        # Validate and normalize
        case validate_contract_definition(substituted) do
          {:ok, normalized} ->
            {:ok, normalized}
          
          {:error, reason} ->
            {:error, {:validation_error, reason}}
        end
      
      {:error, reason} ->
        {:error, {:yaml_error, reason}}
    end
  end

  # Private functions

  defp substitute_variables(data, variables) when map_size(variables) == 0 do
    data
  end

  defp substitute_variables(data, variables) when is_map(data) do
    Enum.reduce(data, %{}, fn {key, value}, acc ->
      new_value = substitute_variables(value, variables)
      {new_key, _} = substitute_key(key, variables)
      Map.put(acc, new_key, new_value)
    end)
  end

  defp substitute_variables(data, variables) when is_list(data) do
    Enum.map(data, &substitute_variables(&1, variables))
  end

  defp substitute_variables(data, variables) when is_binary(data) do
    # Substitute ${variable} patterns
    Enum.reduce(variables, data, fn {var_name, var_value}, acc ->
      pattern = "${#{var_name}}"
      String.replace(acc, pattern, to_string(var_value))
    end)
  end

  defp substitute_variables(data, _variables) do
    data
  end

  defp substitute_key(key, variables) when is_binary(key) do
    substituted = substitute_variables(key, variables)
    {substituted, true}
  end

  defp substitute_key(key, _variables) do
    {key, false}
  end

  defp validate_contract_definition(data) do
    with :ok <- validate_required_fields(data),
         {:ok, normalized} <- normalize_contract_definition(data) do
      {:ok, normalized}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_required_fields(data) do
    required = ["name", "type"]
    
    missing = Enum.filter(required, &(not Map.has_key?(data, &1)))
    
    if Enum.empty?(missing) do
      :ok
    else
      {:error, "Missing required fields: #{Enum.join(missing, ", ")}"}
    end
  end

  defp normalize_contract_definition(data) do
    # Normalize contract type
    contract_type = normalize_contract_type(data["type"])
    
    # Normalize conditions
    conditions = normalize_conditions(data["conditions"] || [])
    
    # Normalize actions
    actions = normalize_actions(data["actions"] || [])
    
    # Normalize metadata
    metadata = normalize_metadata(data["metadata"] || %{})
    
    # Add YAML source to metadata (optional, for reference)
    metadata = if Map.has_key?(data, "_yaml_source") do
      Map.put(metadata, "yaml_source", data["_yaml_source"])
    else
      metadata
    end
    
    normalized = %{
      "name" => data["name"],
      "description" => data["description"] || "",
      "type" => contract_type,
      "status" => normalize_status(data["status"] || "active"),
      "conditions" => conditions,
      "actions" => actions,
      "metadata" => metadata
    }
    
    {:ok, normalized}
  end

  defp normalize_contract_type(type) when is_atom(type), do: type
  defp normalize_contract_type(type) when is_binary(type) do
    case String.downcase(type) do
      "loan" -> :loan
      "invoice" -> :invoice
      "subscription" -> :subscription
      "revenue_share" -> :revenue_share
      "conditional_payment" -> :conditional_payment
      "supplier_registration" -> :supplier_registration
      "ecosystem_partner_membership" -> :ecosystem_partner_membership
      "generic" -> :generic
      other -> String.to_existing_atom(other)
    rescue
      ArgumentError -> :generic
    end
  end
  defp normalize_contract_type(_), do: :generic

  defp normalize_status(status) when is_atom(status), do: status
  defp normalize_status(status) when is_binary(status) do
    case String.downcase(status) do
      "active" -> :active
      "paused" -> :paused
      "completed" -> :completed
      "cancelled" -> :cancelled
      _ -> :active
    end
  end
  defp normalize_status(_), do: :active

  defp normalize_conditions(conditions) when is_list(conditions) do
    Enum.map(conditions, fn condition ->
      %{
        "type" => condition["type"] || condition[:type] || "custom",
        "parameters" => normalize_parameters(condition["parameters"] || condition[:parameters] || %{})
      }
    end)
  end
  defp normalize_conditions(_), do: []

  defp normalize_actions(actions) when is_list(actions) do
    Enum.map(actions, fn action ->
      %{
        "type" => action["type"] || action[:type] || "custom",
        "parameters" => normalize_parameters(action["parameters"] || action[:parameters] || %{})
      }
    end)
  end
  defp normalize_actions(_), do: []

  defp normalize_parameters(params) when is_map(params) do
    # Convert all parameter values to strings (for storage)
    # Numbers and booleans will be converted back when needed
    Enum.reduce(params, %{}, fn {key, value}, acc ->
      string_key = to_string(key)
      string_value = parameter_value_to_string(value)
      Map.put(acc, string_key, string_value)
    end)
  end
  defp normalize_parameters(_), do: %{}

  defp parameter_value_to_string(value) when is_binary(value), do: value
  defp parameter_value_to_string(value) when is_integer(value), do: Integer.to_string(value)
  defp parameter_value_to_string(value) when is_float(value), do: Float.to_string(value)
  defp parameter_value_to_string(value) when is_boolean(value), do: to_string(value)
  defp parameter_value_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp parameter_value_to_string(value) when is_nil, do: ""
  defp parameter_value_to_string(value), do: inspect(value)

  defp normalize_metadata(metadata) when is_map(metadata) do
    # Ensure all metadata values are strings
    Enum.reduce(metadata, %{}, fn {key, value}, acc ->
      string_key = to_string(key)
      string_value = if is_binary(value), do: value, else: inspect(value)
      Map.put(acc, string_key, string_value)
    end)
  end
  defp normalize_metadata(_), do: %{}

  defp create_from_definition(contract_def, yaml_source) do
    name = contract_def["name"]
    description = contract_def["description"]
    contract_type = contract_def["type"]
    conditions = contract_def["conditions"]
    actions = contract_def["actions"]
    
    # Add YAML source to metadata
    metadata = Map.put(contract_def["metadata"], "yaml_source", yaml_source)
    
    opts = [
      metadata: metadata
    ]
    
    # Create the contract
    case Core.create_contract(name, description, contract_type, nil, conditions, actions, opts) do
      {:ok, contract} ->
        Logger.info("Created contract from YAML: #{name} (#{contract.id})")
        {:ok, contract}
      
      {:error, reason} ->
        {:error, {:contract_creation_failed, reason}}
    end
  end
end

