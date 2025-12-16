defmodule Scalegraph.Business.Loans do
  @moduledoc """
  Loan management with explicit financial terminology.
  
  This module handles loan creation, repayment tracking, and loan queries.
  All loan operations interact with the ledger through the pure ledger API.
  """

  require Logger

  alias Scalegraph.Business.Storage
  alias Scalegraph.Business.Contracts

  @doc """
  Create a loan with explicit financial terminology.
  
  Creates a loan contract and records the ledger transaction.
  """
  def create_loan(lender_id, borrower_id, principal_amount, reference, opts \\ [])
      when is_binary(lender_id) and is_binary(borrower_id) and is_integer(principal_amount) and
             principal_amount > 0 do
    Contracts.create_loan(lender_id, borrower_id, principal_amount, nil, reference, opts)
  end

  @doc """
  Get a loan by ID.
  """
  def get_loan(loan_id) when is_binary(loan_id) do
    Contracts.get_loan(loan_id)
  end

  @doc """
  List loans with filters.
  """
  def list_loans(opts \\ []) do
    Contracts.list_loans(opts)
  end

  @doc """
  Add a repayment to a loan.
  """
  def add_repayment(loan_id, repayment_transaction_id)
      when is_binary(loan_id) and is_binary(repayment_transaction_id) do
    Contracts.add_loan_repayment(loan_id, repayment_transaction_id)
  end
end

