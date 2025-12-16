defmodule Scalegraph.Business.Invoices do
  @moduledoc """
  Invoice management with explicit financial terminology.
  
  This module handles invoice creation, payment tracking, and invoice queries.
  All invoice operations interact with the ledger through the pure ledger API.
  """

  require Logger

  alias Scalegraph.Business.Storage
  alias Scalegraph.Business.Contracts

  @doc """
  Create an invoice with explicit financial terminology.
  
  Creates an invoice contract and records the ledger transaction.
  """
  def create_invoice(supplier_id, buyer_id, amount, reference, opts \\ [])
      when is_binary(supplier_id) and is_binary(buyer_id) and is_integer(amount) and amount > 0 do
    Contracts.create_invoice(supplier_id, buyer_id, amount, nil, reference, opts)
  end

  @doc """
  Get an invoice by ID.
  """
  def get_invoice(invoice_id) when is_binary(invoice_id) do
    Contracts.get_invoice(invoice_id)
  end

  @doc """
  List invoices with filters.
  """
  def list_invoices(opts \\ []) do
    Contracts.list_invoices(opts)
  end

  @doc """
  Mark an invoice as paid.
  """
  def mark_paid(invoice_id, payment_transaction_id)
      when is_binary(invoice_id) and is_binary(payment_transaction_id) do
    Contracts.mark_invoice_paid(invoice_id, payment_transaction_id)
  end
end

