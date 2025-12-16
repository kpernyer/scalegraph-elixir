#!/usr/bin/env elixir

# Example script demonstrating marketplace membership smart contract creation
#
# This script shows how to:
# 1. Create a marketplace membership contract between all participants
# 2. Set up automatic monthly payments
# 3. Check contract status and payment schedule
#
# Usage:
#   mix run scripts/marketplace_membership_example.exs
#
# Note: This script must be run within the Mix project context.
# The application will be started automatically when run with `mix run`.

# Ensure application is started
Application.ensure_all_started(:scalegraph)

alias Scalegraph.SmartContracts.Examples
alias Scalegraph.Participant.Core, as: Participant

IO.puts("""
═══════════════════════════════════════════════════════════════
  MARKETPLACE MEMBERSHIP CONTRACT EXAMPLE
═══════════════════════════════════════════════════════════════
""")

# Find the ecosystem orchestrator (marketplace owner)
case Participant.list_participants() do
  {:ok, participants} ->
    orchestrator =
      Enum.find(participants, fn p -> p.role == :ecosystem_orchestrator end)

    if orchestrator do
      IO.puts("Found marketplace owner: #{orchestrator.name} (#{orchestrator.id})")
      IO.puts("")

      # Create the marketplace membership contract
      IO.puts("Creating marketplace membership contract...")
      IO.puts("")

      case Examples.create_marketplace_membership(orchestrator.id) do
        {:ok, contract_info} ->
          IO.puts("✅ Contract created successfully!")
          IO.puts("")
          IO.puts("Contract Details:")
          IO.puts("  Contract ID: #{contract_info.contract_id}")
          IO.puts("  Marketplace Owner: #{contract_info.marketplace_owner_name} (#{contract_info.marketplace_owner})")
          IO.puts("  Total Participants: #{contract_info.total_participants}")
          IO.puts("  Monthly Fee: #{Examples.format_amount(contract_info.monthly_fee_cents)}")
          IO.puts("  Total Payments: #{contract_info.total_payments}")
          IO.puts("  Total Amount: #{Examples.format_amount(contract_info.total_amount_cents)}")
          IO.puts("  First Payment Date: #{Examples.format_date(contract_info.first_payment_date)}")
          IO.puts("  Contract End Date: #{Examples.format_date(contract_info.contract_end_date)}")
          IO.puts("  Renewal Deadline: #{Examples.format_date(contract_info.renewal_deadline)}")
          IO.puts("")
          IO.puts("Participants:")
          Enum.each(contract_info.participants, fn p ->
            IO.puts("  - #{p.name} (#{p.id}) - #{p.role}")
          end)
          IO.puts("")

          # Get next payment date
          case Examples.calculate_next_payment_date(contract_info.contract_id) do
            {:ok, next_payment} when not is_nil(next_payment) ->
              IO.puts("Next Payment Date: #{Examples.format_date(next_payment)}")
              IO.puts("")

            {:ok, nil} ->
              IO.puts("All payments have been completed.")
              IO.puts("")

            error ->
              IO.puts("Error calculating next payment: #{inspect(error)}")
              IO.puts("")
          end

          # Check renewal status
          case Examples.check_renewal_required(contract_info.contract_id) do
            {:ok, true} ->
              IO.puts("⚠️  RENEWAL REQUIRED: All participants must accept renewal before the deadline!")
              IO.puts("")

            {:ok, false} ->
              IO.puts("✓ Renewal not yet required.")
              IO.puts("")

            error ->
              IO.puts("Error checking renewal: #{inspect(error)}")
              IO.puts("")
          end

          IO.puts("""
═══════════════════════════════════════════════════════════════
  Contract created successfully!
  
  The contract will automatically execute payments according to:
  - Grace period: #{contract_info.grace_period_months} months
  - Payment schedule: Monthly for #{contract_info.payment_months} months
  - Total: #{contract_info.total_payments} payments per participant
  
  To manually trigger a payment, use:
    Examples.execute_membership_payment("#{contract_info.contract_id}")
  
  To check contract status:
    Examples.get_marketplace_membership_info("#{contract_info.contract_id}")
═══════════════════════════════════════════════════════════════
""")

        {:error, :no_participants} ->
          IO.puts("❌ Error: No participants found in the ecosystem")
          IO.puts("   Please seed the database first with: mix scalegraph.seed")

        {:error, reason} ->
          IO.puts("❌ Error creating contract: #{inspect(reason)}")
      end

    else
      IO.puts("❌ Error: No ecosystem orchestrator found")
      IO.puts("   Please ensure at least one participant has role :ecosystem_orchestrator")
    end

  {:error, reason} ->
    IO.puts("❌ Error listing participants: #{inspect(reason)}")
end

