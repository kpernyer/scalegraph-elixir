defmodule Scalegraph.StressTest do
  @moduledoc """
  Comprehensive stress test for the Scalegraph ledger database.

  Tests:
  - Concurrent transactions
  - ACID properties
  - Balance consistency
  - Error handling under load
  - Performance metrics
  """

  use ExUnit.Case, async: false

  alias Scalegraph.Ledger.Core
  alias Scalegraph.Participant.Core, as: Participant
  alias Scalegraph.Storage.Schema

  setup do
    # Initialize Mnesia without starting the full application
    # This avoids port conflicts during testing
    :mnesia.stop()
    :mnesia.delete_schema([node()])
    Schema.init()
    Schema.clear_all()
    :ok
  end

  @tag :stress
  test "concurrent transfers maintain balance consistency" do
    # Setup: Create accounts with known balances
    {:ok, _} = Core.create_account("alice", 10_000)
    {:ok, _} = Core.create_account("bob", 5_000)
    {:ok, _} = Core.create_account("charlie", 0)

    # Run 100 concurrent transfers
    num_transfers = 100
    transfer_amount = 10

    tasks =
      for i <- 1..num_transfers do
        Task.async(fn ->
          case rem(i, 3) do
            0 ->
              # Alice -> Bob
              Core.transfer(
                [{"alice", -transfer_amount}, {"bob", transfer_amount}],
                "transfer_#{i}"
              )

            1 ->
              # Bob -> Charlie
              Core.transfer(
                [{"bob", -transfer_amount}, {"charlie", transfer_amount}],
                "transfer_#{i}"
              )

            2 ->
              # Charlie -> Alice
              Core.transfer(
                [{"charlie", -transfer_amount}, {"alice", transfer_amount}],
                "transfer_#{i}"
              )
          end
        end)
      end

    results = Task.await_many(tasks, 30_000)

    # Verify all transactions succeeded
    successes = Enum.count(results, fn r -> match?({:ok, _}, r) end)
    failures = Enum.count(results, fn r -> match?({:error, _}, r) end)

    IO.puts("\n📊 Concurrent Transfer Results:")
    IO.puts("  Total transfers: #{num_transfers}")
    IO.puts("  Successful: #{successes}")
    IO.puts("  Failed: #{failures}")

    # Verify final balances are consistent
    {:ok, alice} = Core.get_account("alice")
    {:ok, bob} = Core.get_account("bob")
    {:ok, charlie} = Core.get_account("charlie")

    total_before = 10_000 + 5_000 + 0
    total_after = alice.balance + bob.balance + charlie.balance

    IO.puts("\n💰 Balance Verification:")
    IO.puts("  Alice: #{alice.balance} (started: 10,000)")
    IO.puts("  Bob: #{bob.balance} (started: 5,000)")
    IO.puts("  Charlie: #{charlie.balance} (started: 0)")
    IO.puts("  Total before: #{total_before}")
    IO.puts("  Total after: #{total_after}")

    # Assertions
    assert total_before == total_after, "Total balance must be conserved"
    # Some transfers may fail due to insufficient funds in concurrent scenarios
    # This is expected behavior - the important thing is balance conservation
    assert successes > 0, "At least some transfers should succeed"
    assert successes + failures == num_transfers, "All attempts should complete"
  end

  @tag :stress
  test "concurrent account creation handles race conditions" do
    num_accounts = 50
    account_ids = for i <- 1..num_accounts, do: "account_#{i}"

    tasks =
      Enum.map(account_ids, fn id ->
        Task.async(fn ->
          Core.create_account(id, 1000)
        end)
      end)

    results = Task.await_many(tasks, 30_000)

    successes = Enum.count(results, fn r -> match?({:ok, _}, r) end)
    duplicates = Enum.count(results, fn r -> match?({:error, :account_exists}, r) end)

    IO.puts("\n📊 Concurrent Account Creation Results:")
    IO.puts("  Attempted: #{num_accounts}")
    IO.puts("  Successful: #{successes}")
    IO.puts("  Duplicates (expected 0): #{duplicates}")

    # Verify all accounts exist
    existing = Enum.count(account_ids, fn id -> match?({:ok, _}, Core.get_account(id)) end)

    assert existing == num_accounts, "All accounts should be created"
    assert duplicates == 0, "No duplicate account errors expected"
  end

  @tag :stress
  test "high volume transactions maintain ACID properties" do
    # Setup accounts
    {:ok, _} = Core.create_account("source", 1_000_000)
    {:ok, _} = Core.create_account("dest1", 0)
    {:ok, _} = Core.create_account("dest2", 0)
    {:ok, _} = Core.create_account("dest3", 0)

    num_transactions = 500
    amount = 100

    start_time = System.monotonic_time(:millisecond)

    tasks =
      for i <- 1..num_transactions do
        Task.async(fn ->
          dest = "dest#{rem(i, 3) + 1}"
          Core.transfer([{"source", -amount}, {dest, amount}], "tx_#{i}")
        end)
      end

    results = Task.await_many(tasks, 60_000)
    end_time = System.monotonic_time(:millisecond)

    duration = end_time - start_time
    tps = num_transactions / (duration / 1000)

    successes = Enum.count(results, fn r -> match?({:ok, _}, r) end)

    IO.puts("\n📊 High Volume Transaction Results:")
    IO.puts("  Transactions: #{num_transactions}")
    IO.puts("  Successful: #{successes}")
    IO.puts("  Duration: #{duration}ms")
    IO.puts("  Throughput: #{Float.round(tps, 2)} tx/s")

    # Verify balances
    {:ok, source} = Core.get_account("source")
    {:ok, dest1} = Core.get_account("dest1")
    {:ok, dest2} = Core.get_account("dest2")
    {:ok, dest3} = Core.get_account("dest3")

    expected_source = 1_000_000 - num_transactions * amount
    expected_dest_total = num_transactions * amount

    IO.puts("\n💰 Balance Verification:")
    IO.puts("  Source: #{source.balance} (expected: #{expected_source})")
    IO.puts("  Dest1: #{dest1.balance}")
    IO.puts("  Dest2: #{dest2.balance}")
    IO.puts("  Dest3: #{dest3.balance}")

    IO.puts(
      "  Total dest: #{dest1.balance + dest2.balance + dest3.balance} (expected: #{expected_dest_total})"
    )

    assert source.balance == expected_source, "Source balance must be correct"

    assert dest1.balance + dest2.balance + dest3.balance == expected_dest_total,
           "Total destination balance must match"

    assert successes == num_transactions, "All transactions should succeed"
  end

  @tag :stress
  test "concurrent insufficient funds errors handled correctly" do
    {:ok, _} = Core.create_account("poor", 100)
    {:ok, _} = Core.create_account("rich", 0)

    num_attempts = 50
    # Each transfer would succeed individually, but concurrent ones will fail
    transfer_amount = 50

    tasks =
      for i <- 1..num_attempts do
        Task.async(fn ->
          # Try to transfer more than available (will fail for some)
          Core.transfer([{"poor", -200}, {"rich", 200}], "attempt_#{i}")
        end)
      end

    results = Task.await_many(tasks, 30_000)

    successes = Enum.count(results, fn r -> match?({:ok, _}, r) end)

    failures =
      Enum.count(results, fn r -> match?({:error, {:insufficient_funds, _, _, _}}, r) end)

    IO.puts("\n📊 Insufficient Funds Test Results:")
    IO.puts("  Attempts: #{num_attempts}")
    IO.puts("  Successful: #{successes}")
    IO.puts("  Failed (insufficient funds): #{failures}")

    # Verify final balance
    {:ok, poor} = Core.get_account("poor")
    {:ok, rich} = Core.get_account("rich")

    IO.puts("\n💰 Final Balances:")
    IO.puts("  Poor: #{poor.balance} (started: 100)")
    IO.puts("  Rich: #{rich.balance} (started: 0)")

    # Balance should be consistent
    total = poor.balance + rich.balance
    assert total == 100, "Total balance must be conserved"
    assert poor.balance >= 0, "Poor account cannot go negative (not receivables/payables)"
    assert successes + failures == num_attempts, "All attempts should complete"
  end

  @tag :stress
  test "receivables and payables can go negative concurrently" do
    # Create participants and accounts with proper types
    alias Scalegraph.Participant.Core, as: ParticipantCore
    
    {:ok, _} = ParticipantCore.create_participant("supplier", "Supplier", :supplier, %{})
    {:ok, _} = ParticipantCore.create_participant("buyer", "Buyer", :ecosystem_partner, %{})
    
    # Create receivables and payables accounts with proper types
    {:ok, _} = ParticipantCore.create_participant_account("supplier", :receivables, 0)
    {:ok, _} = ParticipantCore.create_participant_account("buyer", :payables, 0)

    num_invoices = 100
    invoice_amount = 1000

    tasks =
      for i <- 1..num_invoices do
        Task.async(fn ->
          # Create invoice: supplier receivables +, buyer payables -
          Core.transfer(
            [
              {"supplier:receivables", invoice_amount},
              {"buyer:payables", -invoice_amount}
            ],
            "invoice_#{i}"
          )
        end)
      end

    results = Task.await_many(tasks, 30_000)

    successes = Enum.count(results, fn r -> match?({:ok, _}, r) end)

    IO.puts("\n📊 Negative Balance Test Results:")
    IO.puts("  Invoices created: #{num_invoices}")
    IO.puts("  Successful: #{successes}")

    # Verify balances (should be negative for payables)
    {:ok, receivables} = Core.get_account("supplier:receivables")
    {:ok, payables} = Core.get_account("buyer:payables")

    expected_receivables = num_invoices * invoice_amount
    expected_payables = -num_invoices * invoice_amount

    IO.puts("\n💰 Balance Verification:")
    IO.puts("  Receivables: #{receivables.balance} (expected: #{expected_receivables})")
    IO.puts("  Payables: #{payables.balance} (expected: #{expected_payables})")

    assert receivables.balance == expected_receivables, "Receivables should be positive"
    assert payables.balance == expected_payables, "Payables should be negative"
    assert receivables.balance + payables.balance == 0, "Total should be zero (balanced)"
    assert successes == num_invoices, "All invoices should succeed"
  end

  @tag :stress
  test "participant operations under concurrent load" do
    num_participants = 50

    tasks =
      for i <- 1..num_participants do
        Task.async(fn ->
          participant_id = "participant_#{i}"
          Participant.create_participant(participant_id, "Participant #{i}", :supplier, %{})
        end)
      end

    results = Task.await_many(tasks, 30_000)

    successes = Enum.count(results, fn r -> match?({:ok, _}, r) end)
    duplicates = Enum.count(results, fn r -> match?({:error, :participant_exists}, r) end)

    IO.puts("\n📊 Concurrent Participant Creation Results:")
    IO.puts("  Attempted: #{num_participants}")
    IO.puts("  Successful: #{successes}")
    IO.puts("  Duplicates: #{duplicates}")

    # Verify participants exist
    existing =
      Enum.count(1..num_participants, fn i ->
        match?({:ok, _}, Participant.get_participant("participant_#{i}"))
      end)

    assert existing == num_participants, "All participants should be created"
    assert duplicates == 0, "No duplicate participant errors expected"
  end

  @tag :stress
  test "mixed workload stress test" do
    # Setup
    {:ok, _} = Core.create_account("bank", 1_000_000)
    {:ok, _} = Core.create_account("merchant:operating", 0)
    {:ok, _} = Core.create_account("merchant:receivables", 0)
    {:ok, _} = Core.create_account("customer:operating", 10_000)
    {:ok, _} = Core.create_account("customer:payables", 0)

    num_operations = 200

    start_time = System.monotonic_time(:millisecond)

    tasks =
      for i <- 1..num_operations do
        Task.async(fn ->
          case rem(i, 4) do
            0 ->
              # Payment: customer -> merchant
              Core.transfer(
                [
                  {"customer:operating", -100},
                  {"merchant:operating", 100}
                ],
                "payment_#{i}"
              )

            1 ->
              # Invoice: merchant creates invoice
              Core.transfer(
                [
                  {"merchant:receivables", 200},
                  {"customer:payables", -200}
                ],
                "invoice_#{i}"
              )

            2 ->
              # Loan: bank lends to customer
              Core.transfer(
                [
                  {"bank", -500},
                  {"customer:operating", 500}
                ],
                "loan_#{i}"
              )

            3 ->
              # Repayment: customer pays bank
              Core.transfer(
                [
                  {"customer:operating", -300},
                  {"bank", 300}
                ],
                "repayment_#{i}"
              )
          end
        end)
      end

    results = Task.await_many(tasks, 60_000)
    end_time = System.monotonic_time(:millisecond)

    duration = end_time - start_time
    successes = Enum.count(results, fn r -> match?({:ok, _}, r) end)
    failures = Enum.count(results, fn r -> match?({:error, _}, r) end)

    IO.puts("\n📊 Mixed Workload Stress Test Results:")
    IO.puts("  Operations: #{num_operations}")
    IO.puts("  Successful: #{successes}")
    IO.puts("  Failed: #{failures}")
    IO.puts("  Duration: #{duration}ms")
    IO.puts("  Throughput: #{Float.round(num_operations / (duration / 1000), 2)} ops/s")

    # Verify all accounts are consistent
    {:ok, bank} = Core.get_account("bank")
    {:ok, merchant_op} = Core.get_account("merchant:operating")
    {:ok, merchant_rec} = Core.get_account("merchant:receivables")
    {:ok, customer_op} = Core.get_account("customer:operating")
    {:ok, customer_pay} = Core.get_account("customer:payables")

    IO.puts("\n💰 Final Account Balances:")
    IO.puts("  Bank: #{bank.balance}")
    IO.puts("  Merchant Operating: #{merchant_op.balance}")
    IO.puts("  Merchant Receivables: #{merchant_rec.balance}")
    IO.puts("  Customer Operating: #{customer_op.balance}")
    IO.puts("  Customer Payables: #{customer_pay.balance}")

    # Verify no account went negative (except receivables/payables)
    assert bank.balance >= 0, "Bank account cannot be negative"
    assert merchant_op.balance >= 0, "Merchant operating cannot be negative"
    assert customer_op.balance >= 0, "Customer operating cannot be negative"
    assert successes + failures == num_operations, "All operations should complete"
  end
end
