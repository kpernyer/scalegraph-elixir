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

      {:error, {:not_found, message}} ->
        business_error(:not_found, message)

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

      {:error, {:not_found, message}} ->
        business_error(:not_found, message)

      {:error, {:insufficient_funds, message}} ->
        business_error(:failed_precondition, message)

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

      {:error, {:not_found, message}} ->
        business_error(:not_found, message)

      {:error, {:insufficient_funds, message}} ->
        business_error(:failed_precondition, message)

      {:error, {:account_not_found, account_id}} ->
        business_error(:not_found, "Account not found: #{account_id}")

      {:error, reason} ->
        business_error(:internal, "Access payment failed: #{inspect(reason)}")
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
    {:error, GRPC.RPCError.exception(status: status, message: message)}
  end

  defp format_amount(cents) do
    whole = div(cents, 100)
    frac = rem(abs(cents), 100)
    "#{whole}.#{String.pad_leading(Integer.to_string(frac), 2, "0")}"
  end
end
