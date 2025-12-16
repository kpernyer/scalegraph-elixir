defmodule Scalegraph.Business.Contracts do
  @moduledoc """
  Business contract management layer.

  This module manages business contracts (invoices, loans, etc.) that reference
  ledger transactions. The ledger layer only handles generic transfers, while this
  layer adds business semantics and state management.

  ## Contract Types

  - **Invoices**: B2B purchase invoices with due dates and payment status
  - **Loans**: Loan agreements with interest rates and repayment schedules

  Future contract types:
  - Revenue-share contracts
  - Conditional payments
  - Subscription contracts
  """

  require Logger

  alias Scalegraph.Business.Storage

  # ============================================================================
  # Invoice Contracts
  # ============================================================================

  @doc """
  Create an invoice contract.

  This should be called after a ledger transaction has been created for the invoice.
  The contract stores business metadata (due date, status) and references the ledger transaction.

  ## Parameters
  - `supplier_id` - Supplier's participant ID
  - `buyer_id` - Buyer's participant ID
  - `amount` - Invoice amount in cents
  - `ledger_transaction_id` - ID of the ledger transaction that created the invoice
  - `reference` - Invoice reference (e.g., "INV-2024-001")
  - `opts` - Options:
    - `:due_date` - Due date as Unix timestamp in milliseconds (default: 30 days from now)
    - `:metadata` - Additional metadata map

  ## Returns
  - `{:ok, invoice}` - Invoice contract created
  - `{:error, reason}` - Error creating contract
  """
  def create_invoice(supplier_id, buyer_id, amount, ledger_transaction_id, reference, opts \\ [])
      when is_binary(supplier_id) and is_binary(buyer_id) and is_integer(amount) and
             amount > 0 and is_binary(ledger_transaction_id) and is_binary(reference) do
    invoice_id = generate_id()
    created_at = System.system_time(:millisecond)
    due_date = Keyword.get(opts, :due_date, created_at + 30 * 24 * 60 * 60 * 1000)
    metadata = Keyword.get(opts, :metadata, %{})

    invoice = %{
      id: invoice_id,
      supplier_id: supplier_id,
      buyer_id: buyer_id,
      amount: amount,
      due_date: due_date,
      status: :pending,
      ledger_transaction_id: ledger_transaction_id,
      reference: reference,
      created_at: created_at,
      paid_at: nil,
      metadata: metadata
    }

    result =
      :mnesia.transaction(fn ->
        record = {
          Storage.invoices_table(),
          invoice_id,
          supplier_id,
          buyer_id,
          amount,
          due_date,
          :pending,
          ledger_transaction_id,
          reference,
          created_at,
          nil,
          metadata
        }

        :mnesia.write(record)
        invoice
      end)

    case result do
      {:atomic, invoice} ->
        Logger.info("Created invoice contract: #{reference} (#{invoice_id})")
        {:ok, invoice}

      {:aborted, reason} ->
        Logger.error("Failed to create invoice contract: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Mark an invoice as paid.

  Updates the invoice status and records the payment transaction ID.

  ## Parameters
  - `invoice_id` - Invoice contract ID
  - `payment_transaction_id` - ID of the ledger transaction that paid the invoice

  ## Returns
  - `{:ok, invoice}` - Invoice updated
  - `{:error, reason}` - Error updating invoice
  """
  def mark_invoice_paid(invoice_id, payment_transaction_id)
      when is_binary(invoice_id) and is_binary(payment_transaction_id) do
    paid_at = System.system_time(:millisecond)

    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Storage.invoices_table(), invoice_id) do
          [{_table, id, supplier_id, buyer_id, amount, due_date, _status, ledger_tx_id, reference,
            created_at, _paid_at, metadata}] ->
            record = {
              Storage.invoices_table(),
              id,
              supplier_id,
              buyer_id,
              amount,
              due_date,
              :paid,
              ledger_tx_id,
              reference,
              created_at,
              paid_at,
              metadata
            }

            :mnesia.write(record)

            %{
              id: id,
              supplier_id: supplier_id,
              buyer_id: buyer_id,
              amount: amount,
              due_date: due_date,
              status: :paid,
              ledger_transaction_id: ledger_tx_id,
              reference: reference,
              created_at: created_at,
              paid_at: paid_at,
              metadata: metadata
            }

          [] ->
            :mnesia.abort({:error, :not_found})
        end
      end)

    case result do
      {:atomic, invoice} ->
        Logger.info("Marked invoice as paid: #{invoice.reference} (#{invoice_id})")
        {:ok, invoice}

      {:aborted, {:error, :not_found}} ->
        {:error, :not_found}

      {:aborted, reason} ->
        Logger.error("Failed to mark invoice as paid: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get an invoice contract by ID.
  """
  def get_invoice(invoice_id) when is_binary(invoice_id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Storage.invoices_table(), invoice_id) do
          [{_table, id, supplier_id, buyer_id, amount, due_date, status, ledger_tx_id, reference,
            created_at, paid_at, metadata}] ->
            {:ok,
             %{
               id: id,
               supplier_id: supplier_id,
               buyer_id: buyer_id,
               amount: amount,
               due_date: due_date,
               status: status,
               ledger_transaction_id: ledger_tx_id,
               reference: reference,
               created_at: created_at,
               paid_at: paid_at,
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
  List invoices with optional filters.

  ## Options
  - `:supplier_id` - Filter by supplier
  - `:buyer_id` - Filter by buyer
  - `:status` - Filter by status (:pending, :paid, :overdue, :cancelled)
  - `:limit` - Maximum number of results (default: 100)

  ## Returns
  - `{:ok, [invoice]}` - List of invoices
  """
  def list_invoices(opts \\ []) do
    supplier_filter = Keyword.get(opts, :supplier_id)
    buyer_filter = Keyword.get(opts, :buyer_id)
    status_filter = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 100)

    result =
      :mnesia.transaction(fn ->
        all_invoices = fetch_all_invoices()
        filtered = apply_invoice_filters(all_invoices, supplier_filter, buyer_filter, status_filter)
        sort_and_limit_invoices(filtered, limit)
      end)

    case result do
      {:atomic, invoices} -> {:ok, invoices}
      {:aborted, reason} -> {:error, reason}
    end
  end

  # Private invoice helpers

  defp fetch_all_invoices do
    :mnesia.foldl(
      fn {_table, id, supplier_id, buyer_id, amount, due_date, status, ledger_tx_id, reference,
          created_at, paid_at, metadata},
         acc ->
        invoice = %{
          id: id,
          supplier_id: supplier_id,
          buyer_id: buyer_id,
          amount: amount,
          due_date: due_date,
          status: status,
          ledger_transaction_id: ledger_tx_id,
          reference: reference,
          created_at: created_at,
          paid_at: paid_at,
          metadata: metadata
        }

        [invoice | acc]
      end,
      [],
      Storage.invoices_table()
    )
  end

  defp apply_invoice_filters(invoices, supplier_filter, buyer_filter, status_filter) do
    invoices
    |> filter_by_supplier(supplier_filter)
    |> filter_by_buyer(buyer_filter)
    |> filter_by_status(status_filter)
  end

  defp filter_by_supplier(invoices, nil), do: invoices
  defp filter_by_supplier(invoices, supplier_id), do: Enum.filter(invoices, &(&1.supplier_id == supplier_id))

  defp filter_by_buyer(invoices, nil), do: invoices
  defp filter_by_buyer(invoices, buyer_id), do: Enum.filter(invoices, &(&1.buyer_id == buyer_id))

  defp filter_by_status(invoices, nil), do: invoices
  defp filter_by_status(invoices, status), do: Enum.filter(invoices, &(&1.status == status))

  defp sort_and_limit_invoices(invoices, limit) do
    invoices
    |> Enum.sort_by(& &1.created_at, :desc)
    |> Enum.take(limit)
  end

  # ============================================================================
  # Loan Contracts
  # ============================================================================

  @doc """
  Create a loan contract.

  This should be called after a ledger transaction has been created for the loan disbursement.
  The contract stores business metadata (interest rate, repayment schedule) and references
  the ledger transaction.

  ## Parameters
  - `lender_id` - Lender's participant ID
  - `borrower_id` - Borrower's participant ID
  - `principal_amount` - Loan principal amount in cents
  - `disbursement_transaction_id` - ID of the ledger transaction that disbursed the loan
  - `reference` - Loan reference (e.g., "LOAN-2024-001")
  - `opts` - Options:
    - `:interest_rate` - Interest rate as decimal (default: 0.0)
    - `:repayment_schedule` - Repayment schedule map (default: %{})
    - `:metadata` - Additional metadata map

  ## Returns
  - `{:ok, loan}` - Loan contract created
  - `{:error, reason}` - Error creating contract
  """
  def create_loan(lender_id, borrower_id, principal_amount, disbursement_transaction_id, reference,
        opts \\ [])
      when is_binary(lender_id) and is_binary(borrower_id) and is_integer(principal_amount) and
             principal_amount > 0 and is_binary(disbursement_transaction_id) and
             is_binary(reference) do
    loan_id = generate_id()
    created_at = System.system_time(:millisecond)
    interest_rate = Keyword.get(opts, :interest_rate, 0.0)
    repayment_schedule = Keyword.get(opts, :repayment_schedule, %{})
    base_metadata = Keyword.get(opts, :metadata, %{})
    # Store reference in metadata
    metadata = Map.put(base_metadata, "reference", reference)

    loan = %{
      id: loan_id,
      lender_id: lender_id,
      borrower_id: borrower_id,
      principal_amount: principal_amount,
      interest_rate: interest_rate,
      repayment_schedule: repayment_schedule,
      status: :active,
      disbursement_transaction_id: disbursement_transaction_id,
      repayment_transaction_ids: [],
      created_at: created_at,
      reference: reference,
      metadata: metadata
    }

    result =
      :mnesia.transaction(fn ->
        record = {
          Storage.loans_table(),
          loan_id,
          lender_id,
          borrower_id,
          principal_amount,
          interest_rate,
          repayment_schedule,
          :active,
          disbursement_transaction_id,
          [],
          created_at,
          metadata
        }

        :mnesia.write(record)
        loan
      end)

    case result do
      {:atomic, loan} ->
        Logger.info("Created loan contract: #{reference} (#{loan_id})")
        {:ok, loan}

      {:aborted, reason} ->
        Logger.error("Failed to create loan contract: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Add a repayment transaction to a loan.

  Records that a repayment has been made and updates the loan contract.

  ## Parameters
  - `loan_id` - Loan contract ID
  - `repayment_transaction_id` - ID of the ledger transaction that repaid the loan

  ## Returns
  - `{:ok, loan}` - Loan updated
  - `{:error, reason}` - Error updating loan
  """
  def add_loan_repayment(loan_id, repayment_transaction_id)
      when is_binary(loan_id) and is_binary(repayment_transaction_id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Storage.loans_table(), loan_id) do
          [{_table, id, lender_id, borrower_id, principal_amount, interest_rate, repayment_schedule,
            status, disbursement_tx_id, repayment_tx_ids, created_at, metadata}] ->
            updated_repayment_ids = [repayment_transaction_id | repayment_tx_ids]

            record = {
              Storage.loans_table(),
              id,
              lender_id,
              borrower_id,
              principal_amount,
              interest_rate,
              repayment_schedule,
              status,
              disbursement_tx_id,
              updated_repayment_ids,
              created_at,
              metadata
            }

            :mnesia.write(record)

            # Extract reference from metadata
            reference = Map.get(metadata, "reference", "") || Map.get(metadata, :reference, "")
            
            %{
              id: id,
              lender_id: lender_id,
              borrower_id: borrower_id,
              principal_amount: principal_amount,
              interest_rate: interest_rate,
              repayment_schedule: repayment_schedule,
              status: status,
              disbursement_transaction_id: disbursement_tx_id,
              repayment_transaction_ids: updated_repayment_ids,
              created_at: created_at,
              reference: reference,
              metadata: metadata
            }

          [] ->
            :mnesia.abort({:error, :not_found})
        end
      end)

    case result do
      {:atomic, loan} ->
        Logger.info("Added repayment to loan: #{loan_id}")
        {:ok, loan}

      {:aborted, {:error, :not_found}} ->
        {:error, :not_found}

      {:aborted, reason} ->
        Logger.error("Failed to add loan repayment: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get a loan contract by ID.
  """
  def get_loan(loan_id) when is_binary(loan_id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Storage.loans_table(), loan_id) do
          [{_table, id, lender_id, borrower_id, principal_amount, interest_rate, repayment_schedule,
            status, disbursement_tx_id, repayment_tx_ids, created_at, metadata}] ->
            # Extract reference from metadata
            reference = Map.get(metadata, "reference", "") || Map.get(metadata, :reference, "")
            
            {:ok,
             %{
               id: id,
               lender_id: lender_id,
               borrower_id: borrower_id,
               principal_amount: principal_amount,
               interest_rate: interest_rate,
               repayment_schedule: repayment_schedule,
               status: status,
               disbursement_transaction_id: disbursement_tx_id,
               repayment_transaction_ids: repayment_tx_ids,
               created_at: created_at,
               reference: reference,
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
  List loans with optional filters.

  ## Options
  - `:lender_id` - Filter by lender
  - `:borrower_id` - Filter by borrower
  - `:status` - Filter by status (:active, :repaid, :defaulted)
  - `:limit` - Maximum number of results (default: 100)

  ## Returns
  - `{:ok, [loan]}` - List of loans
  """
  def list_loans(opts \\ []) do
    lender_filter = Keyword.get(opts, :lender_id)
    borrower_filter = Keyword.get(opts, :borrower_id)
    status_filter = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 100)

    result =
      :mnesia.transaction(fn ->
        all_loans = fetch_all_loans()
        filtered = apply_loan_filters(all_loans, lender_filter, borrower_filter, status_filter)
        sort_and_limit_loans(filtered, limit)
      end)

    case result do
      {:atomic, loans} -> {:ok, loans}
      {:aborted, reason} -> {:error, reason}
    end
  end

  # Private loan helpers

  defp fetch_all_loans do
    :mnesia.foldl(
      fn {_table, id, lender_id, borrower_id, principal_amount, interest_rate, repayment_schedule,
          status, disbursement_tx_id, repayment_tx_ids, created_at, metadata},
         acc ->
        # Extract reference from metadata if stored there, or use empty string
        reference = Map.get(metadata, "reference", "") || Map.get(metadata, :reference, "")
        
        loan = %{
          id: id,
          lender_id: lender_id,
          borrower_id: borrower_id,
          principal_amount: principal_amount,
          interest_rate: interest_rate,
          repayment_schedule: repayment_schedule,
          status: status,
          disbursement_transaction_id: disbursement_tx_id,
          repayment_transaction_ids: repayment_tx_ids,
          created_at: created_at,
          reference: reference,
          metadata: metadata
        }

        [loan | acc]
      end,
      [],
      Storage.loans_table()
    )
  end

  defp apply_loan_filters(loans, lender_filter, borrower_filter, status_filter) do
    loans
    |> filter_by_lender(lender_filter)
    |> filter_by_borrower(borrower_filter)
    |> filter_loans_by_status(status_filter)
  end

  defp filter_by_lender(loans, nil), do: loans
  defp filter_by_lender(loans, lender_id), do: Enum.filter(loans, &(&1.lender_id == lender_id))

  defp filter_by_borrower(loans, nil), do: loans
  defp filter_by_borrower(loans, borrower_id), do: Enum.filter(loans, &(&1.borrower_id == borrower_id))

  defp filter_loans_by_status(loans, nil), do: loans
  defp filter_loans_by_status(loans, status), do: Enum.filter(loans, &(&1.status == status))

  defp sort_and_limit_loans(loans, limit) do
    loans
    |> Enum.sort_by(& &1.created_at, :desc)
    |> Enum.take(limit)
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end

