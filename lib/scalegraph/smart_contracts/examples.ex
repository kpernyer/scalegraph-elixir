defmodule Scalegraph.SmartContracts.Examples do
  @moduledoc """
  Reusable smart contract examples for common marketplace scenarios.
  
  This module provides pre-configured contract templates that can be used
  as building blocks for marketplace automation.
  """

  require Logger

  alias Scalegraph.SmartContracts.Core
  alias Scalegraph.Participant.Core, as: Participant

  # ============================================================================
  # Marketplace Membership Contract
  # ============================================================================

  @doc """
  Create a marketplace membership contract between all participants and the marketplace owner.
  
  ## Contract Terms
  - **Cost**: 60 EUR per month (6000 cents)
  - **First Payment**: 3 months after joining the marketplace
  - **Payment Schedule**: Monthly for 9 months after first payment (total 10 payments)
  - **Renewal Deadline**: All actors must accept renewal 30 days before contract termination
  
  ## Parameters
  - `marketplace_owner_id` - The Ecosystem Orchestrator's participant ID (e.g., "beauty_hosting")
  - `opts` - Options:
    - `:monthly_fee_cents` - Monthly fee in cents (default: 6000 = 60 EUR)
    - `:grace_period_months` - Months before first payment (default: 3)
    - `:payment_months` - Number of monthly payments after grace period (default: 9)
    - `:renewal_notice_days` - Days before termination to require renewal acceptance (default: 30)
    - `:exclude_participants` - List of participant IDs to exclude (default: [])
    - `:metadata` - Additional metadata map
  
  ## Returns
  - `{:ok, contract_info}` - Contract created successfully
  - `{:error, reason}` - Error creating contract
  
  ## Example
      iex> create_marketplace_membership("beauty_hosting")
      {:ok, %{
        contract_id: "abc123...",
        marketplace_owner: "beauty_hosting",
        participants: ["salon_glamour", "schampo_etc", ...],
        total_payments: 10,
        total_amount: 60000,
        first_payment_date: ~U[2024-06-01 00:00:00Z],
        contract_end_date: ~U[2025-03-01 00:00:00Z],
        renewal_deadline: ~U[2025-02-01 00:00:00Z]
      }}
  """
  def create_marketplace_membership(marketplace_owner_id, opts \\ [])
      when is_binary(marketplace_owner_id) do
    monthly_fee = Keyword.get(opts, :monthly_fee_cents, 6000)
    grace_period_months = Keyword.get(opts, :grace_period_months, 3)
    payment_months = Keyword.get(opts, :payment_months, 9)
    renewal_notice_days = Keyword.get(opts, :renewal_notice_days, 30)
    exclude_participants = Keyword.get(opts, :exclude_participants, [])
    metadata = Keyword.get(opts, :metadata, %{})

    # Get all participants (excluding orchestrator and excluded participants)
    with {:ok, all_participants} <- Participant.list_participants(),
         {:ok, marketplace_owner} <- Participant.get_participant(marketplace_owner_id) do
      # Filter out orchestrator and excluded participants
      member_participants =
        all_participants
        |> Enum.reject(&(&1.id == marketplace_owner_id))
        |> Enum.reject(&(&1.id in exclude_participants))

      if Enum.empty?(member_participants) do
        {:error, :no_participants}
      else
        # Calculate dates
        now = System.system_time(:millisecond)
        grace_period_ms = grace_period_months * 30 * 24 * 60 * 60 * 1000
        payment_period_ms = payment_months * 30 * 24 * 60 * 60 * 1000
        renewal_notice_ms = renewal_notice_days * 24 * 60 * 60 * 1000

        first_payment_date = now + grace_period_ms
        contract_end_date = first_payment_date + payment_period_ms
        renewal_deadline = contract_end_date - renewal_notice_ms

        # Create conditions for the contract
        conditions = [
          %{
            "type" => "time",
            "parameters" => %{
              "first_payment_date" => first_payment_date,
              "payment_interval_ms" => 30 * 24 * 60 * 60 * 1000,
              "total_payments" => payment_months + 1,
              "renewal_deadline" => renewal_deadline,
              "contract_end_date" => contract_end_date
            }
          },
          %{
            "type" => "participant_acceptance",
            "parameters" => %{
              "required_participants" => [marketplace_owner_id | Enum.map(member_participants, & &1.id)],
              "renewal_required_by" => renewal_deadline
            }
          }
        ]

        # Create actions for each participant payment
        actions =
          Enum.flat_map(member_participants, fn participant ->
            [
              %{
                "type" => "transfer",
                "parameters" => %{
                  "from_account" => "#{participant.id}:operating",
                  "to_account" => "#{marketplace_owner_id}:fees",
                  "amount_cents" => monthly_fee,
                  "reference" => "MARKETPLACE_MEMBERSHIP: #{participant.name} (#{participant.id})"
                }
              }
            ]
          end)

        # Enhanced metadata
        enhanced_metadata =
          metadata
          |> Map.put("marketplace_owner_id", marketplace_owner_id)
          |> Map.put("participant_ids", Enum.map(member_participants, & &1.id))
          |> Map.put("monthly_fee_cents", monthly_fee)
          |> Map.put("grace_period_months", grace_period_months)
          |> Map.put("payment_months", payment_months)
          |> Map.put("total_payments", payment_months + 1)
          |> Map.put("first_payment_date", first_payment_date)
          |> Map.put("contract_end_date", contract_end_date)
          |> Map.put("renewal_deadline", renewal_deadline)
          |> Map.put("contract_type", "marketplace_membership")

        # Create the smart contract
        case Core.create_contract(
               "Marketplace Membership Contract",
               "Monthly membership fee for all ecosystem participants. First payment after #{grace_period_months} months, then monthly for #{payment_months} months.",
               :subscription,
               nil,
               conditions,
               actions,
               metadata: enhanced_metadata
             ) do
          {:ok, contract} ->
            # Create a schedule for monthly execution
            # Schedule to check daily, but contract conditions will determine actual execution
            case Core.create_schedule(contract.id, "0 0 * * *", []) do
              {:ok, _schedule} ->
                Logger.info(
                  "Created marketplace membership contract: #{contract.id} for #{length(member_participants)} participants"
                )

                {:ok,
                 %{
                   contract_id: contract.id,
                   marketplace_owner: marketplace_owner_id,
                   marketplace_owner_name: marketplace_owner.name,
                   participants:
                     Enum.map(member_participants, fn p ->
                       %{id: p.id, name: p.name, role: p.role}
                     end),
                   total_participants: length(member_participants),
                   monthly_fee_cents: monthly_fee,
                   total_payments: payment_months + 1,
                   total_amount_cents: monthly_fee * (payment_months + 1) * length(member_participants),
                   first_payment_date: first_payment_date,
                   contract_end_date: contract_end_date,
                   renewal_deadline: renewal_deadline,
                   grace_period_months: grace_period_months,
                   payment_months: payment_months
                 }}

              {:error, schedule_reason} ->
                Logger.warning(
                  "Contract created but schedule creation failed: #{inspect(schedule_reason)}"
                )

                {:ok,
                 %{
                   contract_id: contract.id,
                   marketplace_owner: marketplace_owner_id,
                   participants:
                     Enum.map(member_participants, fn p ->
                       %{id: p.id, name: p.name, role: p.role}
                     end),
                   warning: "Schedule creation failed"
                 }}
            end

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  @doc """
  Get contract information for a marketplace membership contract.
  
  Returns detailed information about the contract including payment schedule.
  """
  def get_marketplace_membership_info(contract_id) when is_binary(contract_id) do
    case Core.get_contract(contract_id) do
      {:ok, contract} ->
        if contract.metadata["contract_type"] == "marketplace_membership" do
          metadata = contract.metadata

          {:ok,
           %{
             contract_id: contract.id,
             status: contract.status,
             created_at: contract.created_at,
             last_executed_at: contract.last_executed_at,
             marketplace_owner_id: metadata["marketplace_owner_id"],
             participant_ids: metadata["participant_ids"] || [],
             monthly_fee_cents: metadata["monthly_fee_cents"],
             total_payments: metadata["total_payments"],
             first_payment_date: metadata["first_payment_date"],
             contract_end_date: metadata["contract_end_date"],
             renewal_deadline: metadata["renewal_deadline"],
             grace_period_months: metadata["grace_period_months"],
             payment_months: metadata["payment_months"]
           }}
        else
          {:error, :not_marketplace_membership}
        end

      error ->
        error
    end
  end

  @doc """
  Calculate the next payment date for a marketplace membership contract.
  
  Returns the timestamp (in milliseconds) when the next payment should occur.
  """
  def calculate_next_payment_date(contract_id) when is_binary(contract_id) do
    case get_marketplace_membership_info(contract_id) do
      {:ok, info} ->
        now = System.system_time(:millisecond)
        first_payment = info.first_payment_date
        payment_interval = 30 * 24 * 60 * 60 * 1000

        if now < first_payment do
          {:ok, first_payment}
        else
          # Calculate which payment number we're on
          payments_elapsed = div(now - first_payment, payment_interval) + 1

          if payments_elapsed <= info.total_payments do
            next_payment = first_payment + (payments_elapsed * payment_interval)
            {:ok, next_payment}
          else
            {:ok, nil} # All payments completed
          end
        end

      error ->
        error
    end
  end

  @doc """
  Check if renewal acceptance is required for a marketplace membership contract.
  
  Returns `{:ok, true}` if renewal is required, `{:ok, false}` if not yet required,
  or `{:error, reason}` if contract not found.
  """
  def check_renewal_required(contract_id) when is_binary(contract_id) do
    case get_marketplace_membership_info(contract_id) do
      {:ok, info} ->
        now = System.system_time(:millisecond)
        renewal_deadline = info.renewal_deadline

        if now >= renewal_deadline and now < info.contract_end_date do
          {:ok, true}
        else
          {:ok, false}
        end

      error ->
        error
    end
  end

  @doc """
  Execute a single payment for the marketplace membership contract.
  
  This function manually triggers a payment for all participants.
  In production, this would be called automatically by the scheduler.
  """
  def execute_membership_payment(contract_id) when is_binary(contract_id) do
    case get_marketplace_membership_info(contract_id) do
      {:ok, info} ->
        now = System.system_time(:millisecond)
        first_payment = info.first_payment_date
        payment_interval = 30 * 24 * 60 * 60 * 1000

        # Check if it's time for a payment
        if now < first_payment do
          {:ok, %{executed: false, reason: "before_first_payment", next_payment: first_payment}}
        else
          payments_elapsed = div(now - first_payment, payment_interval) + 1

          if payments_elapsed > info.total_payments do
            {:ok, %{executed: false, reason: "all_payments_completed"}}
          else
            # Execute the contract (which will trigger the transfer actions)
            case Core.execute_contract(contract_id) do
              {:ok, result} ->
                {:ok, Map.merge(result, %{payment_number: payments_elapsed})}

              error ->
                error
            end
          end
        end

      error ->
        error
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc """
  Format a timestamp (milliseconds) as a readable date string.
  """
  def format_date(timestamp_ms) when is_integer(timestamp_ms) do
    timestamp_ms
    |> div(1000)
    |> DateTime.from_unix!()
    |> DateTime.to_string()
  end

  @doc """
  Format amount in cents as EUR string.
  """
  def format_amount(cents) when is_integer(cents) do
    whole = div(cents, 100)
    frac = rem(abs(cents), 100)
    "#{whole}.#{String.pad_leading(Integer.to_string(frac), 2, "0")} EUR"
  end

  # ============================================================================
  # Ecosystem Partner Membership Contract
  # ============================================================================

  @doc """
  Accept ecosystem rules and add an ecosystem partner to the membership contract.
  
  When a new ecosystem partner accepts the rules of the ecosystem, they are
  automatically added to the existing smart contract for payments with the
  ecosystem orchestrator.
  
  ## Parameters
  - `partner_id` - ID of the ecosystem partner accepting the rules
  - `orchestrator_id` - Optional ID of the ecosystem orchestrator (will be found automatically if not provided)
  - `opts` - Options:
    - `:monthly_fee_cents` - Monthly fee per partner in cents (default: 5000 = 50 EUR)
    - `:grace_period_months` - Months before first payment (default: 1)
    - `:payment_months` - Number of monthly payments after grace period (default: 11)
    - `:metadata` - Additional metadata map
  
  ## Returns
  - `{:ok, contract}` - Partner added successfully to the contract
  - `{:error, reason}` - Error adding partner
  
  ## Example
      iex> accept_ecosystem_rules("new_salon", "beauty_hosting")
      {:ok, %{id: "contract123", ...}}
  """
  def accept_ecosystem_rules(partner_id, orchestrator_id \\ nil, opts \\ []) do
    Core.add_ecosystem_partner_to_membership(partner_id, orchestrator_id, opts)
  end

  @doc """
  Create an ecosystem partner membership contract.
  
  This creates the initial contract between the ecosystem orchestrator and
  ecosystem partners. Partners are added to this contract when they accept
  the rules using `accept_ecosystem_rules/3`.
  
  ## Parameters
  - `orchestrator_id` - ID of the ecosystem orchestrator
  - `opts` - Options (same as `accept_ecosystem_rules/3`)
  
  ## Returns
  - `{:ok, contract}` - Contract created successfully
  - `{:error, reason}` - Error creating contract
  
  ## Example
      iex> create_ecosystem_partner_membership("beauty_hosting")
      {:ok, %{id: "contract123", ...}}
  """
  def create_ecosystem_partner_membership(orchestrator_id, opts \\ []) do
    Core.create_ecosystem_partner_membership_contract(orchestrator_id, opts)
  end
end

