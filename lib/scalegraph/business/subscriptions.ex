defmodule Scalegraph.Business.Subscriptions do
  @moduledoc """
  Subscription contract management with explicit financial terminology.
  
  This module handles recurring subscription payments with billing cycles.
  """

  require Logger

  alias Scalegraph.Business.Storage

  @doc """
  Create a subscription contract.
  
  ## Parameters
  - `provider_id` - The provider's participant ID (who provides the service)
  - `subscriber_id` - The subscriber's participant ID (who pays)
  - `amount_cents` - Subscription amount in cents
  - `billing_cycle` - Billing cycle in days (e.g., 30 for monthly)
  - `reference` - Subscription reference
  - `opts` - Options:
    - `:next_billing_date` - Next billing date as Unix timestamp in milliseconds (default: now + billing_cycle)
    - `:metadata` - Additional metadata map
  """
  def create_subscription(provider_id, subscriber_id, amount_cents, billing_cycle, reference,
        opts \\ [])
      when is_binary(provider_id) and is_binary(subscriber_id) and is_integer(amount_cents) and
             amount_cents > 0 and is_integer(billing_cycle) and billing_cycle > 0 do
    subscription_id = generate_id()
    created_at = System.system_time(:millisecond)
    next_billing_date = Keyword.get(opts, :next_billing_date, created_at + billing_cycle * 24 * 60 * 60 * 1000)
    metadata = Keyword.get(opts, :metadata, %{})

    subscription = %{
      id: subscription_id,
      provider_id: provider_id,
      subscriber_id: subscriber_id,
      amount_cents: amount_cents,
      billing_cycle: billing_cycle,
      next_billing_date: next_billing_date,
      status: :active,
      ledger_transaction_ids: [],
      reference: reference,
      created_at: created_at,
      metadata: metadata
    }

    result =
      :mnesia.transaction(fn ->
        record = {
          Storage.subscriptions_table(),
          subscription_id,
          provider_id,
          subscriber_id,
          amount_cents,
          billing_cycle,
          next_billing_date,
          :active,
          [],
          reference,
          created_at,
          metadata
        }

        :mnesia.write(record)
        subscription
      end)

    case result do
      {:atomic, subscription} ->
        Logger.info("Created subscription contract: #{reference} (#{subscription_id})")
        {:ok, subscription}

      {:aborted, reason} ->
        Logger.error("Failed to create subscription contract: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get a subscription contract by ID.
  """
  def get_subscription(subscription_id) when is_binary(subscription_id) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Storage.subscriptions_table(), subscription_id) do
          [{_table, id, provider_id, subscriber_id, amount_cents, billing_cycle,
            next_billing_date, status, ledger_tx_ids, reference, created_at, metadata}] ->
            {:ok,
             %{
               id: id,
               provider_id: provider_id,
               subscriber_id: subscriber_id,
               amount_cents: amount_cents,
               billing_cycle: billing_cycle,
               next_billing_date: next_billing_date,
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
  List subscriptions with filters.
  """
  def list_subscriptions(opts \\ []) do
    provider_filter = Keyword.get(opts, :provider_id)
    subscriber_filter = Keyword.get(opts, :subscriber_id)
    status_filter = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 100)

    result =
      :mnesia.transaction(fn ->
        all_subscriptions = fetch_all_subscriptions()
        filtered =
          apply_filters(all_subscriptions, provider_filter, subscriber_filter, status_filter)
        sort_and_limit(filtered, limit)
      end)

    case result do
      {:atomic, subscriptions} -> {:ok, subscriptions}
      {:aborted, reason} -> {:error, reason}
    end
  end

  @doc """
  Add a billing transaction to a subscription.
  """
  def add_billing(subscription_id, transaction_id, next_billing_date)
      when is_binary(subscription_id) and is_binary(transaction_id) and is_integer(next_billing_date) do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Storage.subscriptions_table(), subscription_id) do
          [{_table, id, provider_id, subscriber_id, amount_cents, billing_cycle, _old_next_date,
            status, ledger_tx_ids, reference, created_at, metadata}] ->
            updated_tx_ids = [transaction_id | ledger_tx_ids]

            record = {
              Storage.subscriptions_table(),
              id,
              provider_id,
              subscriber_id,
              amount_cents,
              billing_cycle,
              next_billing_date,
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
              subscriber_id: subscriber_id,
              amount_cents: amount_cents,
              billing_cycle: billing_cycle,
              next_billing_date: next_billing_date,
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
      {:atomic, subscription} ->
        Logger.info("Added billing to subscription: #{subscription_id}")
        {:ok, subscription}

      {:aborted, {:error, :not_found}} ->
        {:error, :not_found}

      {:aborted, reason} ->
        Logger.error("Failed to add billing to subscription: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Update subscription status.
  """
  def update_status(subscription_id, status)
      when is_binary(subscription_id) and status in [:active, :paused, :cancelled] do
    result =
      :mnesia.transaction(fn ->
        case :mnesia.read(Storage.subscriptions_table(), subscription_id) do
          [{_table, id, provider_id, subscriber_id, amount_cents, billing_cycle, next_billing_date,
            _old_status, ledger_tx_ids, reference, created_at, metadata}] ->
            record = {
              Storage.subscriptions_table(),
              id,
              provider_id,
              subscriber_id,
              amount_cents,
              billing_cycle,
              next_billing_date,
              status,
              ledger_tx_ids,
              reference,
              created_at,
              metadata
            }

            :mnesia.write(record)

            %{
              id: id,
              provider_id: provider_id,
              subscriber_id: subscriber_id,
              amount_cents: amount_cents,
              billing_cycle: billing_cycle,
              next_billing_date: next_billing_date,
              status: status,
              ledger_transaction_ids: ledger_tx_ids,
              reference: reference,
              created_at: created_at,
              metadata: metadata
            }

          [] ->
            :mnesia.abort({:error, :not_found})
        end
      end)

    case result do
      {:atomic, subscription} ->
        Logger.info("Updated subscription status: #{subscription_id} -> #{status}")
        {:ok, subscription}

      {:aborted, {:error, :not_found}} ->
        {:error, :not_found}

      {:aborted, reason} ->
        Logger.error("Failed to update subscription status: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private helpers

  defp fetch_all_subscriptions do
    :mnesia.foldl(
      fn {_table, id, provider_id, subscriber_id, amount_cents, billing_cycle, next_billing_date,
          status, ledger_tx_ids, reference, created_at, metadata},
         acc ->
        subscription = %{
          id: id,
          provider_id: provider_id,
          subscriber_id: subscriber_id,
          amount_cents: amount_cents,
          billing_cycle: billing_cycle,
          next_billing_date: next_billing_date,
          status: status,
          ledger_transaction_ids: ledger_tx_ids,
          reference: reference,
          created_at: created_at,
          metadata: metadata
        }

        [subscription | acc]
      end,
      [],
      Storage.subscriptions_table()
    )
  end

  defp apply_filters(subscriptions, provider_filter, subscriber_filter, status_filter) do
    subscriptions
    |> filter_by_provider(provider_filter)
    |> filter_by_subscriber(subscriber_filter)
    |> filter_by_status(status_filter)
  end

  defp filter_by_provider(subscriptions, nil), do: subscriptions
  defp filter_by_provider(subscriptions, provider_id),
    do: Enum.filter(subscriptions, &(&1.provider_id == provider_id))

  defp filter_by_subscriber(subscriptions, nil), do: subscriptions
  defp filter_by_subscriber(subscriptions, subscriber_id),
    do: Enum.filter(subscriptions, &(&1.subscriber_id == subscriber_id))

  defp filter_by_status(subscriptions, nil), do: subscriptions
  defp filter_by_status(subscriptions, status),
    do: Enum.filter(subscriptions, &(&1.status == status))

  defp sort_and_limit(subscriptions, limit) do
    subscriptions
    |> Enum.sort_by(& &1.created_at, :desc)
    |> Enum.take(limit)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end

