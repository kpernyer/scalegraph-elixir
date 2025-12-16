defmodule Mix.Tasks.Scalegraph.Contract.Load do
  @moduledoc """
  Load a smart contract from a YAML file.
  
  ## Usage
  
      mix scalegraph.contract.load path/to/contract.yaml
  
  ## Options
  
      --variables KEY=VALUE    Set variables for substitution (can be used multiple times)
  
  ## Examples
  
      # Load contract with variables
      mix scalegraph.contract.load examples/contracts/supplier_registration.yaml \\
        --variables supplier_id=supplier_123 \\
        --variables orchestrator_id=beauty_hosting
  
  ## Variable Substitution
  
  Variables can be used in YAML files using ${variable_name} syntax.
  Variables can be provided via --variables flags or will be calculated automatically
  for common variables like created_at and expires_at.
  """
  
  use Mix.Task

  @shortdoc "Load a smart contract from a YAML file"

  @switches [
    variables: :keep
  ]

  @aliases [
    v: :variables
  ]

  def run(args) do
    Mix.Task.run("app.start")

    {opts, args, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    if Enum.empty?(args) do
      Mix.shell().error("""
      Error: YAML file path required

      Usage:
        mix scalegraph.contract.load path/to/contract.yaml [options]

      Options:
        --variables KEY=VALUE    Set variables for substitution
      """)
      System.halt(1)
    end

    yaml_path = List.first(args)
    
    # Parse variables from command line
    variables = parse_variables(opts[:variables] || [])
    
    # Add common variables
    now = System.system_time(:millisecond)
    variables = Map.merge(variables, %{
      "created_at" => Integer.to_string(now),
      "expires_at" => Integer.to_string(now + (365 * 24 * 60 * 60 * 1000))  # 1 year
    })
    
    # Convert string values to proper types where needed
    variables = normalize_variables(variables)

    Mix.shell().info("Loading contract from: #{yaml_path}")
    
    if Map.size(variables) > 0 do
      Mix.shell().info("Variables:")
      Enum.each(variables, fn {key, value} ->
        Mix.shell().info("  #{key} = #{inspect(value)}")
      end)
    end

    alias Scalegraph.SmartContracts.YamlParser

    case YamlParser.parse_file_and_create(yaml_path, variables: variables) do
      {:ok, contract} ->
        Mix.shell().info("""
        
        ✅ Contract created successfully!
        
        Contract Details:
          ID: #{contract.id}
          Name: #{contract.name}
          Type: #{contract.contract_type}
          Status: #{contract.status}
        """)
        
        # Show metadata if available
        metadata = contract.metadata || %{}
        if map_size(metadata) > 0 do
          Mix.shell().info("\nMetadata:")
          Enum.each(metadata, fn {key, value} ->
            if key != "yaml_source" do  # Skip YAML source in output
              Mix.shell().info("  #{key}: #{inspect(value)}")
            end
          end)
        end

      {:error, {:file_read_error, reason}} ->
        Mix.shell().error("❌ Failed to read file: #{inspect(reason)}")
        System.halt(1)

      {:error, {:yaml_parse_error, reason}} ->
        Mix.shell().error("❌ Failed to parse YAML: #{inspect(reason)}")
        System.halt(1)

      {:error, {:validation_error, reason}} ->
        Mix.shell().error("❌ Validation error: #{inspect(reason)}")
        System.halt(1)

      {:error, {:contract_creation_failed, reason}} ->
        Mix.shell().error("❌ Failed to create contract: #{inspect(reason)}")
        System.halt(1)

      {:error, reason} ->
        Mix.shell().error("❌ Error: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp parse_variables(vars) when is_list(vars) do
    Enum.reduce(vars, %{}, fn var_str, acc ->
      case String.split(var_str, "=", parts: 2) do
        [key, value] ->
          Map.put(acc, String.trim(key), String.trim(value))
        
        [key] ->
          # No value provided, use empty string
          Map.put(acc, String.trim(key), "")
      end
    end)
  end

  defp parse_variables(_), do: %{}

  defp normalize_variables(vars) do
    # Keep all as strings for now - the parser will handle conversion
    vars
  end
end

