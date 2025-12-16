defmodule Scalegraph.Ledger.Server do
  @moduledoc """
  gRPC server implementation for the Ledger service.

  Business errors (not_found, insufficient_funds, already_exists) are returned
  as gRPC error tuples and logged at info level.

  System errors are raised as exceptions and logged at error level.
  """

  use GRPC.Server, service: Scalegraph.Ledger.LedgerService.Service

  require Logger

  alias Scalegraph.Ledger.Core
  alias Scalegraph.Common
  alias Scalegraph.Ledger, as: LedgerProto

  # Account type mapping
  @reverse_account_type_mapping %{
    standalone: :STANDALONE,
    operating: :OPERATING,
    receivables: :RECEIVABLES,
    payables: :PAYABLES,
    escrow: :ESCROW,
    fees: :FEES,
    usage: :USAGE
  }

  @doc """
  Create a new standalone account.
  """
  def create_account(request, _stream) do
    metadata = Map.new(request.metadata || [])

    case Core.create_account(request.account_id, request.initial_balance, metadata) do
      {:ok, account} ->
        account_to_proto(account)

      {:error, :account_exists} ->
        business_error(:already_exists, "Account already exists: #{request.account_id}")

      {:error, reason} ->
        system_error("Failed to create account", reason)
    end
  end

  @doc """
  Get account details.
  """
  def get_account(request, _stream) do
    case Core.get_account(request.account_id) do
      {:ok, account} ->
        account_to_proto(account)

      {:error, :not_found} ->
        case String.split(request.account_id, ":") do
          [participant_id, account_type] ->
            business_error(
              :not_found,
              "Account not found: #{request.account_id}. The #{account_type} account for participant '#{participant_id}' does not exist. Create it using CreateParticipantAccount with account_type=#{String.upcase(account_type)}."
            )

          _ ->
            business_error(:not_found, "Account not found: #{request.account_id}")
        end

      {:error, reason} ->
        system_error("Failed to get account", reason)
    end
  end

  @doc """
  Get account balance.
  """
  def get_balance(request, _stream) do
    case Core.get_balance(request.account_id) do
      {:ok, balance} ->
        %LedgerProto.GetBalanceResponse{
          account_id: request.account_id,
          balance: balance
        }

      {:error, :not_found} ->
        case String.split(request.account_id, ":") do
          [participant_id, account_type] ->
            business_error(
              :not_found,
              "Account not found: #{request.account_id}. The #{account_type} account for participant '#{participant_id}' does not exist. Create it using CreateParticipantAccount with account_type=#{String.upcase(account_type)}."
            )

          _ ->
            business_error(:not_found, "Account not found: #{request.account_id}")
        end

      {:error, reason} ->
        system_error("Failed to get balance", reason)
    end
  end

  @doc """
  Credit an account.
  """
  def credit(request, _stream) do
    case Core.credit(request.account_id, request.amount, request.reference || "") do
      {:ok, tx} ->
        transaction_to_proto(tx)

      {:error, :not_found} ->
        case String.split(request.account_id, ":") do
          [participant_id, account_type] ->
            business_error(
              :not_found,
              "Account not found: #{request.account_id}. The #{account_type} account for participant '#{participant_id}' does not exist. Create it using CreateParticipantAccount with account_type=#{String.upcase(account_type)}."
            )

          _ ->
            business_error(:not_found, "Account not found: #{request.account_id}")
        end

      {:error, reason} ->
        system_error("Credit failed", reason)
    end
  end

  @doc """
  Debit an account.
  """
  def debit(request, _stream) do
    case Core.debit(request.account_id, request.amount, request.reference || "") do
      {:ok, tx} ->
        transaction_to_proto(tx)

      {:error, :not_found} ->
        case String.split(request.account_id, ":") do
          [participant_id, account_type] ->
            business_error(
              :not_found,
              "Account not found: #{request.account_id}. The #{account_type} account for participant '#{participant_id}' does not exist. Create it using CreateParticipantAccount with account_type=#{String.upcase(account_type)}."
            )

          _ ->
            business_error(:not_found, "Account not found: #{request.account_id}")
        end

      {:error, {:insufficient_funds, balance, amount}} ->
        business_error(
          :failed_precondition,
          "Balance #{balance} insufficient for amount #{amount}"
        )

      {:error, reason} ->
        system_error("Debit failed", reason)
    end
  end

  @doc """
  Execute a multi-party atomic transfer.
  """
  def transfer(request, _stream) do
    entries =
      Enum.map(request.entries, fn entry ->
        {entry.account_id, entry.amount}
      end)

    case Core.transfer(entries, request.reference || "") do
      {:ok, tx} ->
        Logger.info("Transfer completed: #{tx.id}")
        transaction_to_proto(tx)

      {:error, {:not_found, account_id}} ->
        case String.split(account_id, ":") do
          [participant_id, account_type] ->
            business_error(
              :not_found,
              "Account not found: #{account_id}. The #{account_type} account for participant '#{participant_id}' does not exist. Create it using CreateParticipantAccount with account_type=#{String.upcase(account_type)}."
            )

          _ ->
            business_error(:not_found, "Account not found: #{account_id}")
        end

      {:error, {:insufficient_funds, account_id, balance, amount}} ->
        business_error(
          :failed_precondition,
          "Account #{account_id} has balance #{balance}, cannot apply #{amount}"
        )

      {:error, reason} ->
        system_error("Transfer failed", reason)
    end
  end

  @doc """
  List recent transactions.
  """
  def list_transactions(request, _stream) do
    opts = []
    opts = if request.limit > 0, do: [{:limit, request.limit} | opts], else: opts
    opts = if request.account_id != "", do: [{:account_id, request.account_id} | opts], else: opts

    case Core.list_transactions(opts) do
      {:ok, transactions} ->
        %LedgerProto.ListTransactionsResponse{
          transactions: Enum.map(transactions, &transaction_to_proto/1)
        }

      {:error, reason} ->
        system_error("Failed to list transactions", reason)
    end
  end

  # Business errors - expected conditions, logged at info level
  defp business_error(status, message) do
    Logger.info("Business error [#{status}]: #{message}")
    raise GRPC.RPCError, status: status, message: message
  end

  # System errors - unexpected conditions, raised as exceptions (logged at error level)
  defp system_error(context, reason) do
    raise GRPC.RPCError, status: :internal, message: "#{context}: #{inspect(reason)}"
  end

  # Private helpers

  defp transaction_to_proto(tx) do
    entries =
      Enum.map(tx.entries, fn entry ->
        %Common.TransferEntry{
          account_id: entry.account_id,
          amount: entry.amount
        }
      end)

    %Common.Transaction{
      id: tx.id,
      type: tx.type,
      entries: entries,
      timestamp: tx.timestamp,
      reference: tx.reference || ""
    }
  end

  defp account_to_proto(account) do
    %Common.Account{
      id: account.id,
      participant_id: account.participant_id || "",
      account_type:
        Map.get(@reverse_account_type_mapping, account.account_type, :ACCOUNT_TYPE_UNSPECIFIED),
      balance: account.balance,
      created_at: account.created_at,
      metadata: account.metadata || %{}
    }
  end
end
