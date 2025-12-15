defmodule Scalegraph.Business.Transactions do
  @moduledoc """
  High-level business transactions that orchestrate ledger entries.

  All transactions are atomic - either all entries succeed or none do.

  ## Transaction Types

  ### Purchase Invoice (B2B)
  When a supplier delivers goods to a buyer:
  - Records the debt in receivables/payables
  - Later paid via `pay_invoice/3`

  ### Access Payment (Micro-transaction)
  Real-time payment for access control (e.g., door unlock):
  - Instant debit from payer
  - Credit to access provider
  - Optional platform fee

  ## Account Conventions

  Account IDs follow the pattern: `{participant_id}:{account_type}`
  - `salon_glamour:operating` - Salon's main account
  - `schampo_etc:receivables` - Money owed to Schampo etc
  """

  require Logger

  alias Scalegraph.Ledger.Core, as: Ledger

  # ============================================================================
  # Purchase / Invoice Transactions
  # ============================================================================

  @doc """
  Create a purchase invoice - records debt between buyer and supplier.

  This is Step 1 of a B2B purchase. The actual payment happens later via `pay_invoice/3`.

  ## Parameters
  - `supplier_id` - The supplier's participant ID (e.g., "schampo_etc")
  - `buyer_id` - The buyer's participant ID (e.g., "salon_glamour")
  - `amount` - Total amount in cents (including VAT, delivery, etc.)
  - `reference` - Invoice reference (e.g., "INV-2024-001")

  ## What happens
  - Supplier's receivables increases (they are owed money)
  - Buyer's payables decreases (they owe money)

  ## Example
      iex> purchase_invoice("schampo_etc", "salon_glamour", 455000, "INV-2024-001 ABC Shine 300x")
      {:ok, %{transaction_id: "abc123", invoice_ref: "INV-2024-001 ABC Shine 300x"}}
  """
  def purchase_invoice(supplier_id, buyer_id, amount, reference)
      when is_binary(supplier_id) and is_binary(buyer_id) and is_integer(amount) and amount > 0 do
    supplier_receivables = "#{supplier_id}:receivables"
    buyer_payables = "#{buyer_id}:payables"

    entries = [
      # Supplier is owed money (+)
      {supplier_receivables, amount},
      # Buyer owes money (-)
      {buyer_payables, -amount}
    ]

    case Ledger.transfer(entries, "INVOICE: #{reference}") do
      {:ok, tx} ->
        Logger.info("Purchase invoice created: #{reference} for #{format_amount(amount)}")

        {:ok,
         %{
           transaction_id: tx.id,
           invoice_ref: reference,
           supplier: supplier_id,
           buyer: buyer_id,
           amount: amount
         }}

      {:error, reason} ->
        Logger.warning("Purchase invoice failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Pay an invoice - transfers money and clears the receivables/payables.

  This is Step 2 of a B2B purchase (after `purchase_invoice/4`).

  ## Parameters
  - `supplier_id` - The supplier's participant ID
  - `buyer_id` - The buyer's participant ID
  - `amount` - Amount to pay in cents
  - `reference` - Payment reference (e.g., "PAY-INV-2024-001")

  ## What happens (all atomic)
  1. Money moves: buyer's operating → supplier's operating
  2. Clear receivables: supplier's receivables decreases
  3. Clear payables: buyer's payables increases (back to zero)

  ## Example
      iex> pay_invoice("schampo_etc", "salon_glamour", 455000, "PAY-INV-2024-001")
      {:ok, %{transaction_id: "def456", ...}}
  """
  def pay_invoice(supplier_id, buyer_id, amount, reference)
      when is_binary(supplier_id) and is_binary(buyer_id) and is_integer(amount) and amount > 0 do
    supplier_operating = "#{supplier_id}:operating"
    supplier_receivables = "#{supplier_id}:receivables"
    buyer_operating = "#{buyer_id}:operating"
    buyer_payables = "#{buyer_id}:payables"

    # All four entries in one atomic transaction
    entries = [
      # Money leaves buyer
      {buyer_operating, -amount},
      # Money arrives at supplier
      {supplier_operating, amount},
      # Clear the receivable
      {supplier_receivables, -amount},
      # Clear the payable
      {buyer_payables, amount}
    ]

    case Ledger.transfer(entries, "PAYMENT: #{reference}") do
      {:ok, tx} ->
        Logger.info("Invoice paid: #{reference} for #{format_amount(amount)}")

        {:ok,
         %{
           transaction_id: tx.id,
           payment_ref: reference,
           supplier: supplier_id,
           buyer: buyer_id,
           amount: amount
         }}

      {:error, reason} ->
        Logger.warning("Invoice payment failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ============================================================================
  # Access / Micro-payment Transactions
  # ============================================================================

  @doc """
  Process an access payment - real-time micro-transaction for access control.

  Used when someone uses a temporary key/access and needs to pay immediately.

  ## Parameters
  - `payer_id` - Who is paying (e.g., "salon_glamour")
  - `access_provider_id` - Access provider (e.g., "assa_abloy")
  - `amount` - Amount in cents (e.g., 800 for 8.00 USD)
  - `opts` - Options:
    - `:reference` - Transaction reference (default: auto-generated)
    - `:platform_id` - Platform to receive fee (e.g., "beauty_hosting")
    - `:platform_fee` - Platform fee in cents (default: 0)

  ## What happens (all atomic)
  - Payer's operating account is debited
  - Access provider's fees account is credited
  - Optional: platform receives a fee

  ## Examples

  Simple access payment:
      iex> access_payment("salon_glamour", "assa_abloy", 800, reference: "DOOR-123")
      {:ok, %{transaction_id: "...", amount: 800}}

  With platform fee:
      iex> access_payment("salon_glamour", "assa_abloy", 800,
      ...>   reference: "DOOR-123",
      ...>   platform_id: "beauty_hosting",
      ...>   platform_fee: 50)
      {:ok, %{transaction_id: "...", amount: 800, platform_fee: 50}}
  """
  def access_payment(payer_id, access_provider_id, amount, opts \\ [])
      when is_binary(payer_id) and is_binary(access_provider_id) and is_integer(amount) and
             amount > 0 do
    reference = Keyword.get(opts, :reference, generate_access_ref())
    platform_id = Keyword.get(opts, :platform_id)
    platform_fee = Keyword.get(opts, :platform_fee, 0)

    payer_operating = "#{payer_id}:operating"
    provider_fees = "#{access_provider_id}:fees"

    # Build entries based on whether there's a platform fee
    entries =
      if platform_id && platform_fee > 0 do
        platform_fees = "#{platform_id}:fees"
        provider_amount = amount - platform_fee

        [
          # Total debit from payer
          {payer_operating, -amount},
          # Access provider gets their cut
          {provider_fees, provider_amount},
          # Platform gets fee
          {platform_fees, platform_fee}
        ]
      else
        [
          # Debit from payer
          {payer_operating, -amount},
          # Credit to access provider
          {provider_fees, amount}
        ]
      end

    case Ledger.transfer(entries, "ACCESS: #{reference}") do
      {:ok, tx} ->
        Logger.info("Access payment: #{reference} for #{format_amount(amount)} from #{payer_id}")

        result = %{
          transaction_id: tx.id,
          reference: reference,
          payer: payer_id,
          access_provider: access_provider_id,
          amount: amount
        }

        result =
          if platform_fee > 0 do
            Map.merge(result, %{platform: platform_id, platform_fee: platform_fee})
          else
            result
          end

        {:ok, result}

      {:error, reason} ->
        Logger.warning("Access payment failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Quick access check and payment - validates balance before attempting payment.

  Returns `{:ok, result}` if payment succeeds, or `{:error, :insufficient_funds}`
  if the payer doesn't have enough balance.

  Useful for real-time access control where you want to check before unlocking.
  """
  def check_and_pay_access(payer_id, access_provider_id, amount, opts \\ []) do
    payer_operating = "#{payer_id}:operating"

    case Ledger.get_balance(payer_operating) do
      {:ok, balance} when balance >= amount ->
        access_payment(payer_id, access_provider_id, amount, opts)

      {:ok, balance} ->
        {:error,
         {:insufficient_funds, "Balance #{format_amount(balance)}, need #{format_amount(amount)}"}}

      {:error, :not_found} ->
        {:error, {:account_not_found, payer_operating}}

      error ->
        error
    end
  end

  # ============================================================================
  # Loan Management
  # ============================================================================

  @doc """
  Create a loan - lender provides funds and records obligation.

  Creates a formal loan obligation using receivables/payables accounts:
  - Lender's receivables increases (they are owed money)
  - Borrower's payables decreases (they owe money)
  - Money moves from lender's operating to borrower's operating

  ## Parameters
  - `lender_id` - The lender's participant ID (e.g., "seb")
  - `borrower_id` - The borrower's participant ID (e.g., "salon_glamour")
  - `amount` - Loan amount in cents
  - `reference` - Loan reference (e.g., "LOAN-2024-001")

  ## What happens (all atomic)
  1. Money moves: lender's operating → borrower's operating
  2. Record obligation: lender's receivables increases (positive = owed)
  3. Record debt: borrower's payables decreases (negative = owes)

  ## Example
      iex> create_loan("seb", "salon_glamour", 150023, "LOAN-2024-001")
      {:ok, %{transaction_id: "...", loan_ref: "LOAN-2024-001"}}
  """
  def create_loan(lender_id, borrower_id, amount, reference)
      when is_binary(lender_id) and is_binary(borrower_id) and is_integer(amount) and amount > 0 do
    alias Scalegraph.Participant.Core, as: Participant
    alias Scalegraph.Ledger.Core, as: Ledger

    lender_operating = "#{lender_id}:operating"
    lender_receivables = "#{lender_id}:receivables"
    borrower_operating = "#{borrower_id}:operating"
    borrower_payables = "#{borrower_id}:payables"

    # Ensure receivables/payables accounts exist
    with {:ok, _} <- ensure_account_exists(lender_id, :receivables),
         {:ok, _} <- ensure_account_exists(borrower_id, :payables) do
      # All four entries in one atomic transaction
      entries = [
        # Money leaves lender
        {lender_operating, -amount},
        # Money arrives at borrower
        {borrower_operating, amount},
        # Record receivable (lender is owed)
        {lender_receivables, amount},
        # Record payable (borrower owes)
        {borrower_payables, -amount}
      ]

      case Ledger.transfer(entries, "LOAN: #{reference}") do
        {:ok, tx} ->
          Logger.info("Loan created: #{reference} for #{format_amount(amount)}")

          {:ok,
           %{
             transaction_id: tx.id,
             loan_ref: reference,
             lender: lender_id,
             borrower: borrower_id,
             amount: amount
           }}

        {:error, reason} ->
          Logger.warning("Loan creation failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Repay a loan - borrower pays back and clears obligation.

  Clears the loan obligation by reversing the receivables/payables entries.

  ## Parameters
  - `lender_id` - The lender's participant ID
  - `borrower_id` - The borrower's participant ID
  - `amount` - Repayment amount in cents
  - `reference` - Repayment reference (e.g., "REPAY-LOAN-2024-001")

  ## What happens (all atomic)
  1. Money moves: borrower's operating → lender's operating
  2. Clear receivable: lender's receivables decreases
  3. Clear payable: borrower's payables increases (back toward zero)

  ## Example
      iex> repay_loan("seb", "salon_glamour", 150023, "REPAY-LOAN-2024-001")
      {:ok, %{transaction_id: "...", repayment_ref: "REPAY-LOAN-2024-001"}}
  """
  def repay_loan(lender_id, borrower_id, amount, reference)
      when is_binary(lender_id) and is_binary(borrower_id) and is_integer(amount) and amount > 0 do
    alias Scalegraph.Ledger.Core, as: Ledger

    lender_operating = "#{lender_id}:operating"
    lender_receivables = "#{lender_id}:receivables"
    borrower_operating = "#{borrower_id}:operating"
    borrower_payables = "#{borrower_id}:payables"

    # All four entries in one atomic transaction
    entries = [
      # Money leaves borrower
      {borrower_operating, -amount},
      # Money arrives at lender
      {lender_operating, amount},
      # Clear the receivable (lender no longer owed)
      {lender_receivables, -amount},
      # Clear the payable (borrower no longer owes)
      {borrower_payables, amount}
    ]

    case Ledger.transfer(entries, "LOAN_REPAYMENT: #{reference}") do
      {:ok, tx} ->
        Logger.info("Loan repaid: #{reference} for #{format_amount(amount)}")

        {:ok,
         %{
           transaction_id: tx.id,
           repayment_ref: reference,
           lender: lender_id,
           borrower: borrower_id,
           amount: amount
         }}

      {:error, reason} ->
        Logger.warning("Loan repayment failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get outstanding loans for a lender.

  Returns all borrowers who owe money to this lender.
  Outstanding loans = positive balance in lender's receivables account.

  ## Parameters
  - `lender_id` - The lender's participant ID

  ## Returns
  - `{:ok, total_outstanding}` - Total amount outstanding in cents
  - `{:ok, 0}` - No outstanding loans (account doesn't exist or has zero balance)
  - `{:error, reason}` - Error getting account

  ## Example
      iex> get_outstanding_loans("seb")
      {:ok, 150023}  # $1,500.23 outstanding
  """
  def get_outstanding_loans(lender_id) when is_binary(lender_id) do
    alias Scalegraph.Ledger.Core, as: Ledger

    receivables_account = "#{lender_id}:receivables"

    case Ledger.get_balance(receivables_account) do
      {:ok, balance} when balance > 0 -> {:ok, balance}
      # Zero or negative = no outstanding loans
      {:ok, _balance} -> {:ok, 0}
      # Account doesn't exist = no loans
      {:error, :not_found} -> {:ok, 0}
      error -> error
    end
  end

  @doc """
  Get total debt for a borrower.

  Returns total amount the borrower owes across all lenders.
  Total debt = absolute value of negative balance in borrower's payables account.

  ## Parameters
  - `borrower_id` - The borrower's participant ID

  ## Returns
  - `{:ok, total_debt}` - Total debt in cents (always positive)
  - `{:ok, 0}` - No debt (account doesn't exist or has zero/positive balance)
  - `{:error, reason}` - Error getting account

  ## Example
      iex> get_total_debt("salon_glamour")
      {:ok, 150023}  # $1,500.23 owed
  """
  def get_total_debt(borrower_id) when is_binary(borrower_id) do
    alias Scalegraph.Ledger.Core, as: Ledger

    payables_account = "#{borrower_id}:payables"

    case Ledger.get_balance(payables_account) do
      # Negative = debt
      {:ok, balance} when balance < 0 -> {:ok, abs(balance)}
      # Zero or positive = no debt
      {:ok, _balance} -> {:ok, 0}
      # Account doesn't exist = no debt
      {:error, :not_found} -> {:ok, 0}
      error -> error
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  # Ensure an account exists, create it if it doesn't
  defp ensure_account_exists(participant_id, account_type) do
    alias Scalegraph.Participant.Core, as: Participant
    alias Scalegraph.Ledger.Core, as: Ledger

    account_id = "#{participant_id}:#{account_type}"

    case Ledger.get_account(account_id) do
      {:ok, _account} ->
        {:ok, :exists}

      {:error, :not_found} ->
        Participant.create_participant_account(participant_id, account_type, 0)

      error ->
        error
    end
  end

  defp format_amount(cents) do
    whole = div(cents, 100)
    frac = rem(abs(cents), 100)
    "#{whole}.#{String.pad_leading(Integer.to_string(frac), 2, "0")}"
  end

  defp generate_access_ref do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "ACC-#{timestamp}-#{random}"
  end
end
