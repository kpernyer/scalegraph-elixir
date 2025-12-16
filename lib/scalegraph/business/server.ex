defmodule Scalegraph.Business.Server do
  @moduledoc """
  gRPC server implementation for the Business service.

  Provides high-level business transaction operations:
  - PurchaseInvoice: B2B goods delivery (creates receivables/payables)
  - PayInvoice: Settle a B2B invoice
  - AccessPayment: Real-time micro-transaction for access control
  """

  use GRPC.Server, service: Scalegraph.Proto.BusinessService.Service

  require Logger

  alias Scalegraph.Business.Transactions
  alias Scalegraph.Proto

  @doc """
  Create a purchase invoice - records debt between buyer and supplier.
  """
  def purchase_invoice(request, _stream) do
    case Transactions.purchase_invoice(
           request.supplier_id,
           request.buyer_id,
           request.amount,
           request.reference
         ) do
      {:ok, result} ->
        %Proto.BusinessTransactionResponse{
          transaction_id: result.transaction_id,
          reference: result.invoice_ref,
          amount: result.amount,
          platform_fee: 0,
          status: "completed",
          message: "Invoice created for #{format_amount(result.amount)}"
        }

      {:error, {:not_found, account_id}} ->
        business_error(:not_found, "Account not found: #{account_id}")

      {:error, reason} ->
        business_error(:internal, "Invoice creation failed: #{inspect(reason)}")
    end
  end

  @doc """
  Pay an invoice - transfers money and clears receivables/payables.
  """
  def pay_invoice(request, _stream) do
    case Transactions.pay_invoice(
           request.supplier_id,
           request.buyer_id,
           request.amount,
           request.reference
         ) do
      {:ok, result} ->
        %Proto.BusinessTransactionResponse{
          transaction_id: result.transaction_id,
          reference: result.payment_ref,
          amount: result.amount,
          platform_fee: 0,
          status: "completed",
          message: "Invoice paid: #{format_amount(result.amount)}"
        }

      {:error, {:not_found, account_id}} ->
        business_error(:not_found, "Account not found: #{account_id}")

      {:error, {:insufficient_funds, account_id, balance, amount}} ->
        business_error(
          :failed_precondition,
          "Account #{account_id} has balance #{format_amount(balance)}, cannot apply #{format_amount(amount)}"
        )

      {:error, reason} ->
        business_error(:internal, "Invoice payment failed: #{inspect(reason)}")
    end
  end

  @doc """
  Process an access payment - real-time micro-transaction.
  """
  def access_payment(request, _stream) do
    opts =
      [reference: request.reference]
      |> maybe_add_platform(request.platform_id, request.platform_fee)

    case Transactions.access_payment(
           request.payer_id,
           request.access_provider_id,
           request.amount,
           opts
         ) do
      {:ok, result} ->
        %Proto.BusinessTransactionResponse{
          transaction_id: result.transaction_id,
          reference: result.reference,
          amount: result.amount,
          platform_fee: Map.get(result, :platform_fee, 0),
          status: "completed",
          message: "Access granted"
        }

      {:error, {:not_found, account_id}} ->
        business_error(:not_found, "Account not found: #{account_id}")

      {:error, {:insufficient_funds, account_id, balance, amount}} ->
        business_error(
          :failed_precondition,
          "Account #{account_id} has balance #{format_amount(balance)}, cannot apply #{format_amount(amount)}"
        )

      {:error, {:account_not_found, account_id}} ->
        business_error(:not_found, "Account not found: #{account_id}")

      {:error, reason} ->
        business_error(:internal, "Access payment failed: #{inspect(reason)}")
    end
  end

  @doc """
  Create a loan - lender provides funds and records obligation.
  """
  def create_loan(request, _stream) do
    case Transactions.create_loan(
           request.lender_id,
           request.borrower_id,
           request.amount,
           request.reference
         ) do
      {:ok, result} ->
        %Proto.BusinessTransactionResponse{
          transaction_id: result.transaction_id,
          reference: result.loan_ref,
          amount: result.amount,
          platform_fee: 0,
          status: "completed",
          message: "Loan created: #{format_amount(result.amount)}"
        }

      {:error, {:not_found, account_id}} ->
        business_error(:not_found, "Account not found: #{account_id}")

      {:error, {:insufficient_funds, account_id, balance, amount}} ->
        business_error(
          :failed_precondition,
          "Account #{account_id} has balance #{format_amount(balance)}, cannot apply #{format_amount(amount)}"
        )

      {:error, reason} ->
        business_error(:internal, "Loan creation failed: #{inspect(reason)}")
    end
  end

  @doc """
  Repay a loan - borrower pays back and clears obligation.
  """
  def repay_loan(request, _stream) do
    case Transactions.repay_loan(
           request.lender_id,
           request.borrower_id,
           request.amount,
           request.reference
         ) do
      {:ok, result} ->
        %Proto.BusinessTransactionResponse{
          transaction_id: result.transaction_id,
          reference: result.repayment_ref,
          amount: result.amount,
          platform_fee: 0,
          status: "completed",
          message: "Loan repaid: #{format_amount(result.amount)}"
        }

      {:error, {:not_found, account_id}} ->
        business_error(:not_found, "Account not found: #{account_id}")

      {:error, {:insufficient_funds, account_id, balance, amount}} ->
        business_error(
          :failed_precondition,
          "Account #{account_id} has balance #{format_amount(balance)}, cannot apply #{format_amount(amount)}"
        )

      {:error, reason} ->
        business_error(:internal, "Loan repayment failed: #{inspect(reason)}")
    end
  end

  @doc """
  Get outstanding loans for a lender.
  """
  def get_outstanding_loans(request, _stream) do
    case Transactions.get_outstanding_loans(request.lender_id) do
      {:ok, total_outstanding} ->
        %Proto.GetOutstandingLoansResponse{
          lender_id: request.lender_id,
          total_outstanding: total_outstanding
        }

      {:error, reason} ->
        business_error(:internal, "Failed to get outstanding loans: #{inspect(reason)}")
    end
  end

  @doc """
  Get total debt for a borrower.
  """
  def get_total_debt(request, _stream) do
    case Transactions.get_total_debt(request.borrower_id) do
      {:ok, total_debt} ->
        %Proto.GetTotalDebtResponse{
          borrower_id: request.borrower_id,
          total_debt: total_debt
        }

      {:error, reason} ->
        business_error(:internal, "Failed to get total debt: #{inspect(reason)}")
    end
  end

  # Private helpers

  defp maybe_add_platform(opts, platform_id, platform_fee)
       when is_binary(platform_id) and platform_id != "" and platform_fee > 0 do
    opts
    |> Keyword.put(:platform_id, platform_id)
    |> Keyword.put(:platform_fee, platform_fee)
  end

  defp maybe_add_platform(opts, _platform_id, _platform_fee), do: opts

  defp business_error(status, message) do
    Logger.info("Business error [#{status}]: #{message}")
    raise GRPC.RPCError, status: status, message: message
  end

  defp format_amount(cents) do
    whole = div(cents, 100)
    frac = rem(abs(cents), 100)
    "#{whole}.#{String.pad_leading(Integer.to_string(frac), 2, "0")}"
  end
end