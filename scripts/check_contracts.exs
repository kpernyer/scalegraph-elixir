#!/usr/bin/env elixir

# Script to check if smart contracts exist in the database
#
# Usage: mix run scripts/check_contracts.exs [contract_id]

Mix.Task.run("app.start")

alias Scalegraph.SmartContracts.Core

IO.puts("""
═══════════════════════════════════════════════════════════════
  CHECKING SMART CONTRACTS IN DATABASE
═══════════════════════════════════════════════════════════════
""")

# If contract ID provided, check specific contract
if length(System.argv()) > 0 do
  contract_id = List.first(System.argv())
  IO.puts("\n📋 Checking contract: #{contract_id}")
  
  case Core.get_contract(contract_id) do
    {:ok, contract} ->
      IO.puts("✅ Contract found!")
      IO.puts("\nContract Details:")
      IO.puts("  ID: #{contract.id}")
      IO.puts("  Name: #{contract.name}")
      IO.puts("  Type: #{contract.contract_type}")
      IO.puts("  Status: #{contract.status}")
      IO.puts("  Created: #{DateTime.from_unix!(div(contract.created_at, 1000), :millisecond)}")
      
      metadata = contract.metadata || %{}
      if map_size(metadata) > 0 do
        IO.puts("\n  Metadata:")
        Enum.each(metadata, fn {k, v} ->
          IO.puts("    #{k}: #{inspect(v)}")
        end)
      end
      
      if contract.last_executed_at do
        IO.puts("  Last Executed: #{DateTime.from_unix!(div(contract.last_executed_at, 1000), :millisecond)}")
      end
    
    {:error, :not_found} ->
      IO.puts("❌ Contract not found: #{contract_id}")
      System.halt(1)
    
    {:error, reason} ->
      IO.puts("❌ Error: #{inspect(reason)}")
      System.halt(1)
  end
else
  # List all contracts
  IO.puts("\n📋 Listing all contracts...")
  
  case Core.list_contracts(limit: 100) do
    {:ok, contracts} ->
      IO.puts("✅ Found #{length(contracts)} contract(s)\n")
      
      if length(contracts) == 0 do
        IO.puts("  No contracts found in database.")
      else
        Enum.each(contracts, fn contract ->
          IO.puts("  • #{contract.id}")
          IO.puts("    Type: #{contract.contract_type}")
          IO.puts("    Status: #{contract.status}")
          IO.puts("    Name: #{contract.name}")
          IO.puts("")
        end)
      end
    
    {:error, reason} ->
      IO.puts("❌ Error listing contracts: #{inspect(reason)}")
      System.halt(1)
  end
end

IO.puts("\n═══════════════════════════════════════════════════════════════\n")

