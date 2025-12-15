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
      {supplier_receivables, amount},   # Supplier is owed money (+)
      {buyer_payables, -amount}         # Buyer owes money (-)
    ]

    case Ledger.transfer(entries, "INVOICE: #{reference}") do
      {:ok, tx} ->
        Logger.info("Purchase invoice created: #{reference} for #{format_amount(amount)}")
        {:ok, %{
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
      {buyer_operating, -amount},        # Money leaves buyer
      {supplier_operating, amount},      # Money arrives at supplier
      {supplier_receivables, -amount},   # Clear the receivable
      {buyer_payables, amount}           # Clear the payable
    ]

    case Ledger.transfer(entries, "PAYMENT: #{reference}") do
      {:ok, tx} ->
        Logger.info("Invoice paid: #{reference} for #{format_amount(amount)}")
        {:ok, %{
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
      when is_binary(payer_id) and is_binary(access_provider_id) and is_integer(amount) and amount > 0 do

    reference = Keyword.get(opts, :reference, generate_access_ref())
    platform_id = Keyword.get(opts, :platform_id)
    platform_fee = Keyword.get(opts, :platform_fee, 0)

    payer_operating = "#{payer_id}:operating"
    provider_fees = "#{access_provider_id}:fees"

    # Build entries based on whether there's a platform fee
    entries = if platform_id && platform_fee > 0 do
      platform_fees = "#{platform_id}:fees"
      provider_amount = amount - platform_fee

      [
        {payer_operating, -amount},           # Total debit from payer
        {provider_fees, provider_amount},     # Access provider gets their cut
        {platform_fees, platform_fee}         # Platform gets fee
      ]
    else
      [
        {payer_operating, -amount},           # Debit from payer
        {provider_fees, amount}               # Credit to access provider
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

        result = if platform_fee > 0 do
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
        {:error, {:insufficient_funds, "Balance #{format_amount(balance)}, need #{format_amount(amount)}"}}

      {:error, :not_found} ->
        {:error, {:account_not_found, payer_operating}}

      error ->
        error
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

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
