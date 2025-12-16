defmodule Scalegraph.SmartContracts.Scheduler do
  @moduledoc """
  Smart contracts scheduler - cron-based automation and active agent-driven management.
  
  This GenServer periodically checks for contracts that need execution and executes them.
  """

  use GenServer

  require Logger

  alias Scalegraph.SmartContracts.Core

  @check_interval 60_000 # Check every minute

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting Smart Contracts Scheduler")
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_contracts, state) do
    Logger.debug("Checking for due contracts...")

    case Core.get_due_contracts() do
      {:ok, contract_ids} ->
        Enum.each(contract_ids, fn contract_id ->
          Logger.info("Executing due contract: #{contract_id}")
          Task.start(fn -> Core.execute_contract(contract_id) end)
        end)

      {:error, reason} ->
        Logger.error("Failed to get due contracts: #{inspect(reason)}")
    end

    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_contracts, @check_interval)
  end
end

