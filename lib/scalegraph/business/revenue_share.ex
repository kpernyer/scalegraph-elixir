defmodule Scalegraph.Business.RevenueShare do
  @moduledoc """
  Revenue share contract management with explicit financial terminology.
  
  This module handles revenue share agreements where a provider shares
  a percentage of revenue with recipients.
  """

  require Logger

  alias Scalegraph.Business.Storage

  @doc """
  Create a revenue share contract.
  
  ## Parameters
  - `provider_id` - The provider's participant ID (who generates revenue)
  - `recipient_id` - The recipient's participant ID (who receives share)
  - `share_percentage` - Percentage of revenue to share (0.0 to 100.0)
  - `reference` - Contract reference
  - `opts` - Options:
    - `:metadata` - Additional metadata map
  """
  def create_revenue_share(provider_id, recipient_id, share_percentage, reference, opts \\ [])
      when is_binary(provider_id) and is_binary(recipient_id) and
             is_float(share_percentage) and share_percentage >= 0.0 and share_percentage <= 100.0 do
    revenue_share_id = generate_id()
    created_at = System.system_time(:millisecond)
    metadata = Keyword.get(opts, :metadata, %{})

    revenue_share = %{
      id: revenue_share_id,
      provider_id: provider_id,
      recipient_id: recipient_id,
      share_percentage: share_percentage,
      status: :active,
      ledger_transaction_ids: [],
      reference: reference,
      created_at: created_at,
      metadata: metadata
    }

    result =
      :mnesia.transaction(fn ->
        record = {
          Storage.revenue_share_table(),
          revenue_share_id,
          provider_id,
          recipient_id,
          share_percentage,
          :active,
          [],
          reference,
          created_at,
          metadata
        }

        :mnesia.write(record)
        revenue_share
      end)

    case result do
      {:atomic, revenue_share} ->
        Logger.info("Created revenue share contract: #{reference} (#{revenue_share_id})")
        {:ok, revenue_share}

      {:aborted, reason} ->
        Logger.error("Failed to create revenue share contract: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get a revenue share contract by ID.
  """
  def get_revenue_share(revenue_share_id) when is_binary(revenue_share_id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Storage.revenue_share_table(), revenue_share_id) do
          [{_table, id, provider_id, recipient_id, share_percentage, status, ledger_tx_ids,
            reference, created_at, metadata}] ->
            {:ok,
             %{
               id: id,
               provider_id: provider_id,
               recipient_id: recipient_id,
               share_percentage: share_percentage,
               status: status,
               ledger_transaction_ids: ledger_tx_ids,
               reference: reference,
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
  List revenue share contracts with filters.
  """
  def list_revenue_shares(opts \\ []) do
    provider_filter = Keyword.get(opts, :provider_id)
    recipient_filter = Keyword.get(opts, :recipient_id)
    status_filter = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 100)

    result =
      :mnesia.transaction(fn ->
        all_contracts = fetch_all_revenue_shares()
        filtered = apply_filters(all_contracts, provider_filter, recipient_filter, status_filter)
        sort_and_limit(filtered, limit)
      end)

    case result do
      {:atomic, contracts} -> {:ok, contracts}
      {:aborted, reason} -> {:error, reason}
    end
  end

  @doc """
  Add a ledger transaction to a revenue share contract.
  """
  def add_transaction(revenue_share_id, transaction_id)
      when is_binary(revenue_share_id) and is_binary(transaction_id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Storage.revenue_share_table(), revenue_share_id) do
          [{_table, id, provider_id, recipient_id, share_percentage, status, ledger_tx_ids,
            reference, created_at, metadata}] ->
            updated_tx_ids = [transaction_id | ledger_tx_ids]

            record = {
              Storage.revenue_share_table(),
              id,
              provider_id,
              recipient_id,
              share_percentage,
              status,
              updated_tx_ids,
              reference,
              created_at,
              metadata
            }

            :mnesia.write(record)

            %{
              id: id,
              provider_id: provider_id,
              recipient_id: recipient_id,
              share_percentage: share_percentage,
              status: status,
              ledger_transaction_ids: updated_tx_ids,
              reference: reference,
              created_at: created_at,
              metadata: metadata
            }

          [] ->
            :mnesia.abort({:error, :not_found})
        end
      end)

    case result do
      {:atomic, contract} ->
        Logger.info("Added transaction to revenue share: #{revenue_share_id}")
        {:ok, contract}

      {:aborted, {:error, :not_found}} ->
        {:error, :not_found}

      {:aborted, reason} ->
        Logger.error("Failed to add transaction to revenue share: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private helpers

  defp fetch_all_revenue_shares do
    :mnesia.foldl(
      fn {_table, id, provider_id, recipient_id, share_percentage, status, ledger_tx_ids,
          reference, created_at, metadata},
         acc ->
        contract = %{
          id: id,
          provider_id: provider_id,
          recipient_id: recipient_id,
          share_percentage: share_percentage,
          status: status,
          ledger_transaction_ids: ledger_tx_ids,
          reference: reference,
          created_at: created_at,
          metadata: metadata
        }

        [contract | acc]
      end,
      [],
      Storage.revenue_share_table()
    )
  end

  defp apply_filters(contracts, provider_filter, recipient_filter, status_filter) do
    contracts
    |> filter_by_provider(provider_filter)
    |> filter_by_recipient(recipient_filter)
    |> filter_by_status(status_filter)
  end

  defp filter_by_provider(contracts, nil), do: contracts
  defp filter_by_provider(contracts, provider_id),
    do: Enum.filter(contracts, &(&1.provider_id == provider_id))

  defp filter_by_recipient(contracts, nil), do: contracts
  defp filter_by_recipient(contracts, recipient_id),
    do: Enum.filter(contracts, &(&1.recipient_id == recipient_id))

  defp filter_by_status(contracts, nil), do: contracts
  defp filter_by_status(contracts, status), do: Enum.filter(contracts, &(&1.status == status))

  defp sort_and_limit(contracts, limit) do
    contracts
    |> Enum.sort_by(& &1.created_at, :desc)
    |> Enum.take(limit)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end

