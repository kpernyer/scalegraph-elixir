#!/usr/bin/env elixir

# Supplier Registration Contract Example
#
# This script demonstrates how to create and use supplier registration contracts.
#
# Run with: mix run scripts/supplier_registration_example.exs

Mix.Task.run("app.start")

alias Scalegraph.SmartContracts.Core
alias Scalegraph.Participant.Core, as: ParticipantCore
alias Scalegraph.Ledger.Core, as: LedgerCore

IO.puts("""
═══════════════════════════════════════════════════════════════
  SUPPLIER REGISTRATION CONTRACT EXAMPLE
═══════════════════════════════════════════════════════════════
""")

# Step 1: Check for ecosystem orchestrator
IO.puts("\n📋 Step 1: Finding ecosystem orchestrator...")
case ParticipantCore.list_participants(:ecosystem_orchestrator) do
  {:ok, []} ->
    IO.puts("❌ Error: No ecosystem orchestrator found")
    IO.puts("   Please ensure at least one participant has role :ecosystem_orchestrator")
    System.halt(1)

  {:ok, [orchestrator | _]} ->
    IO.puts("✅ Found orchestrator: #{orchestrator.id} (#{orchestrator.name})")

  {:error, reason} ->
    IO.puts("❌ Error listing participants: #{inspect(reason)}")
    System.halt(1)
end

# Step 2: Check for suppliers
IO.puts("\n📋 Step 2: Finding suppliers...")
case ParticipantCore.list_participants(:supplier) do
  {:ok, []} ->
    IO.puts("❌ Error: No suppliers found")
    IO.puts("   Please seed the database first with: mix scalegraph.seed")
    System.halt(1)

  {:ok, suppliers} ->
    supplier = List.first(suppliers)
    IO.puts("✅ Found supplier: #{supplier.id} (#{supplier.name})")
    
    # Ensure supplier has operating account with sufficient funds
    supplier_account_id = "#{supplier.id}:operating"
    case LedgerCore.get_account(supplier_account_id) do
      {:error, :not_found} ->
        IO.puts("   Creating operating account for supplier...")
        case ParticipantCore.create_participant_account(supplier.id, :operating, 20000) do
          {:ok, account} ->
            IO.puts("   ✅ Created account with 200 EUR initial balance")
          error ->
            IO.puts("   ❌ Failed to create account: #{inspect(error)}")
            System.halt(1)
        end
      
      {:ok, account} ->
        if account.balance < 15000 do
          IO.puts("   ⚠️  Supplier account balance is low (#{account.balance} cents)")
          IO.puts("   Adding funds...")
          case LedgerCore.credit(supplier_account_id, 20000, "Initial funding") do
            {:ok, _} ->
              IO.puts("   ✅ Added 200 EUR to supplier account")
            error ->
              IO.puts("   ❌ Failed to add funds: #{inspect(error)}")
          end
        else
          IO.puts("   ✅ Supplier account has sufficient balance: #{account.balance} cents")
        end
    end

  {:error, reason} ->
    IO.puts("❌ Error listing suppliers: #{inspect(reason)}")
    System.halt(1)
end

# Step 3: Check for ecosystem providers
IO.puts("\n📋 Step 3: Finding ecosystem providers...")
case ParticipantCore.list_participants(:ecosystem_partner) do
  {:ok, []} ->
    IO.puts("⚠️  Warning: No ecosystem providers found")
    IO.puts("   Monthly fees will not start until a provider uses the service")

  {:ok, [provider | _]} ->
    IO.puts("✅ Found ecosystem provider: #{provider.id} (#{provider.name})")
    
    # Ensure provider has operating account
    provider_account_id = "#{provider.id}:operating"
    case LedgerCore.get_account(provider_account_id) do
      {:error, :not_found} ->
        IO.puts("   Creating operating account for provider...")
        case ParticipantCore.create_participant_account(provider.id, :operating, 0) do
          {:ok, _} ->
            IO.puts("   ✅ Created account")
          error ->
            IO.puts("   ❌ Failed to create account: #{inspect(error)}")
        end
      {:ok, _} ->
        IO.puts("   ✅ Provider account exists")
    end

  {:error, reason} ->
    IO.puts("⚠️  Warning: Error listing providers: #{inspect(reason)}")
end

# Step 4: Create supplier registration contract
IO.puts("\n📋 Step 4: Creating supplier registration contract...")
{:ok, suppliers} = ParticipantCore.list_participants(:supplier)
supplier = List.first(suppliers)

case Core.create_supplier_registration_contract(supplier.id) do
  {:ok, contract} ->
    IO.puts("✅ Supplier registration contract created!")
    IO.puts("   Contract ID: #{contract.id}")
    IO.puts("   Status: #{contract.status}")
    
    metadata = contract.metadata || %{}
    IO.puts("\n   Contract Details:")
    IO.puts("   - Supplier: #{Map.get(metadata, "supplier_id")}")
    IO.puts("   - Orchestrator: #{Map.get(metadata, "orchestrator_id")}")
    IO.puts("   - Registration Fee: #{Map.get(metadata, "registration_fee_cents")} cents (50 EUR)")
    IO.puts("   - Monthly Fee: #{Map.get(metadata, "monthly_fee_cents")} cents (100 EUR)")
    IO.puts("   - Monthly Fee Started: #{Map.get(metadata, "monthly_fee_started", false)}")
    
    # Check account balances
    supplier_account_id = "#{supplier.id}:operating"
    case LedgerCore.get_balance(supplier_account_id) do
      {:ok, balance} ->
        IO.puts("\n   Supplier account balance: #{balance} cents (#{balance / 100} EUR)")
    end
    
    # Step 5: Trigger monthly fee (simulate first provider usage)
    IO.puts("\n📋 Step 5: Simulating first ecosystem provider usage...")
    case ParticipantCore.list_participants(:ecosystem_partner) do
      {:ok, []} ->
        IO.puts("⚠️  No ecosystem providers available to trigger monthly fee")
        IO.puts("   Monthly fees will start automatically when a provider uses the service")
      
      {:ok, [provider | _]} ->
        IO.puts("   Triggering monthly fee with provider: #{provider.id}")
        case Core.trigger_supplier_monthly_fee(supplier.id, provider.id) do
          {:ok, :started} ->
            IO.puts("✅ Monthly fee started!")
            IO.puts("   First provider: #{provider.id}")
            IO.puts("   First monthly fee charged immediately")
            
            # Check balances after monthly fee
            IO.puts("\n   Account Balances After Monthly Fee:")
            case LedgerCore.get_balance(supplier_account_id) do
              {:ok, balance} ->
                IO.puts("   - Supplier: #{balance} cents")
            end
            
            provider_account_id = "#{provider.id}:operating"
            case LedgerCore.get_balance(provider_account_id) do
              {:ok, balance} ->
                IO.puts("   - First Provider (10%): #{balance} cents")
            end
            
            {:ok, orchestrators} = ParticipantCore.list_participants(:ecosystem_orchestrator)
            orchestrator = List.first(orchestrators)
            orchestrator_account_id = "#{orchestrator.id}:fees"
            case LedgerCore.get_balance(orchestrator_account_id) do
              {:ok, balance} ->
                IO.puts("   - Orchestrator Fees (90%): #{balance} cents")
            end
          
          {:ok, :already_started} ->
            IO.puts("✅ Monthly fee already started")
          
          {:error, reason} ->
            IO.puts("❌ Failed to trigger monthly fee: #{inspect(reason)}")
        end
      
      {:error, reason} ->
        IO.puts("⚠️  Error listing providers: #{inspect(reason)}")
    end
    
    # Step 6: Get contract information
    IO.puts("\n📋 Step 6: Contract Information...")
    case Core.get_supplier_registration_contract(supplier.id) do
      {:ok, updated_contract} ->
        updated_metadata = updated_contract.metadata || %{}
        IO.puts("✅ Contract Status:")
        IO.puts("   - Status: #{updated_contract.status}")
        IO.puts("   - Monthly Fee Started: #{Map.get(updated_metadata, "monthly_fee_started", false)}")
        IO.puts("   - First Provider: #{Map.get(updated_metadata, "first_provider_id", "Not set")}")
        
        # Calculate expiration
        expires_at = Map.get(updated_metadata, "expires_at", 0)
        if expires_at > 0 do
          now = System.system_time(:millisecond)
          days_remaining = div(expires_at - now, 24 * 60 * 60 * 1000)
          IO.puts("   - Expires in: #{days_remaining} days")
        end
      
      {:error, reason} ->
        IO.puts("❌ Error getting contract: #{inspect(reason)}")
    end

  {:error, reason} ->
    IO.puts("❌ Error creating contract: #{inspect(reason)}")
    System.halt(1)
end

IO.puts("""

═══════════════════════════════════════════════════════════════
  ✅ EXAMPLE COMPLETE
═══════════════════════════════════════════════════════════════

The supplier registration contract is now active. Monthly fees will
be automatically charged on the 1st of each month via the scheduler.

To check contract status:
  alias Scalegraph.SmartContracts.Core
  {:ok, contract} = Core.get_supplier_registration_contract("supplier_id")

To manually trigger monthly fee (when first provider uses service):
  {:ok, :started} = Core.trigger_supplier_monthly_fee("supplier_id", "provider_id")
""")

