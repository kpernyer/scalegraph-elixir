defmodule Scalegraph.Ledger.Core do
  @moduledoc """
  Core ledger operations with atomic Mnesia transactions.

  Accounts are typically created through participants using
  `Scalegraph.Participant.Core.create_participant_account/4`.
  """

  alias Scalegraph.Ledger.Storage

  @doc """
  Create a standalone account (not linked to a participant).

  For participant-linked accounts, use `Scalegraph.Participant.Core.create_participant_account/4`.

  Returns {:ok, account} or {:error, reason}
  """
  def create_account(account_id, initial_balance \\ 0, metadata \\ %{})
      when is_binary(account_id) and is_integer(initial_balance) and initial_balance >= 0 do
    created_at = System.system_time(:millisecond)

    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Storage.accounts_table(), account_id) do
          [] ->
            # Standalone accounts have nil participant_id and :standalone type
            record =
              {Storage.accounts_table(), account_id, nil, :standalone, initial_balance, created_at,
               metadata}

            :mnesia.write(record)

            {:ok,
             %{
               id: account_id,
               participant_id: nil,
               account_type: :standalone,
               balance: initial_balance,
               created_at: created_at,
               metadata: metadata
             }}

          [_existing] ->
            :mnesia.abort({:error, :account_exists})
        end
      end)

    case result do
      {:atomic, {:ok, account}} -> {:ok, account}
      {:aborted, {:error, reason}} -> {:error, reason}
      {:aborted, reason} -> {:error, reason}
    end
  end

  @doc """
  Get an account by ID.
  """
  def get_account(account_id) when is_binary(account_id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Storage.accounts_table(), account_id) do
          [{_table, id, participant_id, account_type, balance, created_at, metadata}] ->
            {:ok,
             %{
               id: id,
               participant_id: participant_id,
               account_type: account_type,
               balance: balance,
               created_at: created_at,
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
  Get account balance.
  """
  def get_balance(account_id) when is_binary(account_id) do
    case get_account(account_id) do
      {:ok, account} -> {:ok, account.balance}
      error -> error
    end
  end

  @doc """
  Credit an account (add funds).

  Note: This is a convenience function that creates a single-entry transfer.
  The type field is informational only - all transactions are generic transfers.
  """
  def credit(account_id, amount, reference \\ "")
      when is_binary(account_id) and is_integer(amount) and amount > 0 do
    execute_single_entry_transaction(account_id, amount, "transfer", reference)
  end

  @doc """
  Debit an account (subtract funds).

  Note: This is a convenience function that creates a single-entry transfer.
  The type field is informational only - all transactions are generic transfers.
  """
  def debit(account_id, amount, reference \\ "")
      when is_binary(account_id) and is_integer(amount) and amount > 0 do
    execute_single_entry_transaction(account_id, -amount, "transfer", reference)
  end

  @doc """
  Execute a multi-party atomic transfer.

  Entries is a list of {account_id, amount} tuples where:
  - positive amount = credit
  - negative amount = debit

  For a valid transfer, the sum of all amounts should typically be zero,
  but this is not enforced to allow for fees, etc.

  All transactions are generic transfers - business semantics (invoice, loan, etc.)
  are stored in the Business/Contract layer, not in the ledger.
  """
  def transfer(entries, reference \\ "") when is_list(entries) do
    tx_id = generate_tx_id()
    timestamp = System.system_time(:millisecond)

    result =
      :mnesia.transaction(fn ->
        # Validate and update all accounts
        Enum.each(entries, fn {account_id, amount} ->
          process_transfer_entry(account_id, amount)
        end)

        # Record the transaction
        tx_entries = build_transaction_entries(entries)

        # Type is informational only - all transactions are generic transfers
        tx_record =
          {Storage.transactions_table(), tx_id, "transfer", tx_entries, timestamp, reference}

        :mnesia.write(tx_record)

        {:ok,
         %{
           id: tx_id,
           type: "transfer",
           entries: tx_entries,
           timestamp: timestamp,
           reference: reference
         }}
      end)

    case result do
      {:atomic, {:ok, tx}} ->
        {:ok, tx}

      {:aborted, {:insufficient_funds, account_id, balance, amount}} ->
        {:error, {:insufficient_funds, account_id, balance, amount}}

      {:aborted, {:account_not_found, account_id}} ->
        {:error, {:not_found, account_id}}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  # Private transfer helpers

  defp process_transfer_entry(account_id, amount) do
    case :mnesia.read(Storage.accounts_table(), account_id) do
      [{_table, ^account_id, participant_id, account_type, balance, created_at, metadata}] ->
        new_balance = balance + amount

        # Validate balance based on account type
        validate_balance_for_account_type(account_type, new_balance, account_id, balance, amount)

        # Update account balance
        record =
          {Storage.accounts_table(), account_id, participant_id, account_type, new_balance,
           created_at, metadata}

        :mnesia.write(record)

      [] ->
        :mnesia.abort({:account_not_found, account_id})
    end
  end

  defp validate_balance_for_account_type(account_type, new_balance, account_id, balance, amount) do
    case account_type do
      :receivables ->
        # Receivables can go negative (e.g., if you owe someone)
        :ok

      :payables ->
        # Payables can go negative (e.g., when you owe money)
        :ok

      _ ->
        # All other account types must maintain non-negative balance
        if new_balance < 0 do
          :mnesia.abort({:insufficient_funds, account_id, balance, amount})
        end
    end
  end

  defp build_transaction_entries(entries) do
    Enum.map(entries, fn {account_id, amount} ->
      %{account_id: account_id, amount: amount}
    end)
  end

  # Private functions

  defp execute_single_entry_transaction(account_id, amount, type, reference) do
    tx_id = generate_tx_id()
    timestamp = System.system_time(:millisecond)

    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Storage.accounts_table(), account_id) do
          [{_table, ^account_id, participant_id, account_type, balance, created_at, metadata}] ->
            new_balance = balance + amount

            # Validate balance based on account type
            validate_balance_for_single_entry(account_type, new_balance, balance, amount)

            # Update account
            account_record =
              {Storage.accounts_table(), account_id, participant_id, account_type, new_balance,
               created_at, metadata}

            :mnesia.write(account_record)

            # Record transaction
            entries = [%{account_id: account_id, amount: amount}]
            tx_record = {Storage.transactions_table(), tx_id, type, entries, timestamp, reference}
            :mnesia.write(tx_record)

            {:ok,
             %{
               id: tx_id,
               type: type,
               entries: entries,
               timestamp: timestamp,
               reference: reference
             }}

          [] ->
            :mnesia.abort(:not_found)
        end
      end)

    case result do
      {:atomic, {:ok, tx}} ->
        {:ok, tx}

      {:aborted, {:insufficient_funds, balance, amount}} ->
        {:error, {:insufficient_funds, balance, amount}}

      {:aborted, :not_found} ->
        {:error, :not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  defp validate_balance_for_single_entry(account_type, new_balance, balance, amount) do
    case account_type do
      :receivables ->
        # Receivables can go negative (e.g., if you owe someone)
        :ok

      :payables ->
        # Payables can go negative (e.g., when you owe money)
        :ok

      _ ->
        # All other account types must maintain non-negative balance
        if new_balance < 0 do
          :mnesia.abort({:insufficient_funds, balance, amount})
        end
    end
  end

  @doc """
  List recent transactions, optionally filtered by account.

  Options:
  - `:limit` - Maximum number of transactions to return (default: 50)
  - `:account_id` - Filter by account ID (returns transactions involving this account)

  Returns {:ok, [transaction]} or {:error, reason}
  """
  def list_transactions(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    account_filter = Keyword.get(opts, :account_id)

    result =
      :mnesia.transaction(fn ->
        all_txs = fetch_all_transactions()
        filtered = apply_account_filter(all_txs, account_filter)
        sort_and_limit_transactions(filtered, limit)
      end)

    case result do
      {:atomic, transactions} -> {:ok, transactions}
      {:aborted, reason} -> {:error, reason}
    end
  end

  # Private transaction listing helpers

  defp fetch_all_transactions do
    :mnesia.foldl(
      fn {_table, id, type, entries, timestamp, reference}, acc ->
        tx = %{
          id: id,
          type: type,
          entries: entries,
          timestamp: timestamp,
          reference: reference
        }

        [tx | acc]
      end,
      [],
      Storage.transactions_table()
    )
  end

  defp apply_account_filter(all_txs, nil), do: all_txs

  defp apply_account_filter(all_txs, account_filter) do
    Enum.filter(all_txs, fn tx ->
      transaction_involves_account?(tx, account_filter)
    end)
  end

  defp transaction_involves_account?(tx, account_filter) do
    Enum.any?(tx.entries, fn entry ->
      entry.account_id == account_filter
    end)
  end

  defp sort_and_limit_transactions(transactions, limit) do
    transactions
    |> Enum.sort_by(& &1.timestamp, :desc)
    |> Enum.take(limit)
  end

  defp generate_tx_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
